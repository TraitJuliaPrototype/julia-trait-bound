#!/bin/bash
# Build a Julia tree under the shared host's rule for cores (writeup/record/INDEX.md, "Standing constraints"):
# - the others' load (the 1-minute load average less this build's own running tasks, averaged the
#   way the kernel averages) below half the cores: make -j<half the cores>;
# - at or above half: make -j4. A wide build whose others' load reaches half is stopped and continues
#   at -j4 (make resumes where it stopped) and stays narrow;
# - a narrow build pauses while the whole load is above HI (default 110) and resumes below LO (90).
# Niced; killed below 4 GB available memory. Each output line is time-stamped, so the stages
# (Base, Base.Compiler, the system image) can be timed from the log; the peak RSS of the largest
# process is sampled every 10 s. The log is <tree>/tw-build.log and ends with "BUILD EXIT <rc>".
# A wide build is a spike (its parallel compile phase lasts minutes); builds one after another
# (a bisection) are sustained use and run with WIDE=0.
# The runtime's rules (subtyping, memberships, cells) shape what Base's build compiles, yet Julia's
# make rebuilds the system image only when a file of base/ changes: where a runtime source (src/) is
# newer than the image, base/sysimg.jl is touched so the image is rebuilt (KEEP_IMAGE=1 keeps it).
# Usage: tools-local/build.sh <julia tree> [make target]     (WIDE=0 forces -j4)
# Run from a private copy: bash reads a script as it runs, so an edit to this file would corrupt a running build.
if [ -z "${BUILD_SH_COPY:-}" ]; then t=$(mktemp); cp "$0" "$t"; BUILD_SH_COPY=$t exec bash "$t" "$@"; fi
trap 'rm -f "$BUILD_SH_COPY"' EXIT
TREE=$(cd "$1" && pwd) || exit 2
TARGET=${2:-}
NCPU=$(getconf _NPROCESSORS_ONLN);  # not nproc: it honours OMP_NUM_THREADS, which env.sh sets to 1
 HALF=$((NCPU / 2)); NARROW=4
HI=${HI:-110}; LO=${LO:-90}
LOG=$TREE/tw-build.log
: > "$LOG"
note() { echo "$(date +%T) [build.sh] $*" | tee -a "$LOG"; }

start() {  # $1 = jobs
  setsid nice -n 10 bash -c 'make -C "$1" -j"$2" $3 2>&1 | gawk "{ print strftime(\"%T\"), \$0; fflush() }" >> "$4"; exit ${PIPESTATUS[0]}' \
    _ "$TREE" "$1" "$TARGET" "$LOG" &
  pid=$!
}
own_running() { ps -L -s "$pid" -o stat= 2>/dev/null | grep -c '^[RD]'; }
load1() { awk '{print $1}' /proc/loadavg; }

IMG=$TREE/usr/lib/julia/sys.so
if [ "${KEEP_IMAGE:-0}" != 1 ] && [ -f "$IMG" ] && [ -f "$TREE/base/sysimg.jl" ]; then
  newer=$(find "$TREE/src" -maxdepth 2 \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -newer "$IMG" -print -quit)
  [ -n "$newer" ] && touch "$TREE/base/sysimg.jl" && note "runtime source newer than the system image ($(basename "$newer")): the image is rebuilt"
fi
l=$(load1)
if [ "${WIDE:-1}" = 1 ] && awk -v l="$l" -v h="$HALF" 'BEGIN{exit !(l < h)}'; then jobs=$HALF; else jobs=$NARROW; fi
note "start: load $l, $NCPU cores, make -j$jobs ${TARGET:-(default target)}, git $(git -C "$TREE" rev-parse --short=10 HEAD)"
t0=$(date +%s)
start $jobs
own=0; peak=0; paused=0; narrowed=0
E=$(awk 'BEGIN{print exp(-10/60)}')
while kill -0 $pid 2>/dev/null; do
  sleep 10
  kill -0 $pid 2>/dev/null || break
  avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  if [ "$avail" -lt 4096 ]; then
    note "WATCHDOG: MemAvailable ${avail} MB, killing build"; kill -TERM -$pid; sleep 5; kill -KILL -$pid 2>/dev/null
    echo "BUILD EXIT 99" >> "$LOG"; exit 99
  fi
  rss=$(ps -s $pid -o rss= 2>/dev/null | sort -n | tail -1); [ -n "$rss" ] && [ "$rss" -gt "$peak" ] && peak=$rss
  n=$(own_running)
  own=$(awk -v o="$own" -v n="$n" -v e="$E" 'BEGIN{print o*e + n*(1-e)}')
  l=$(load1)
  others=$(awk -v l="$l" -v o="$own" 'BEGIN{x=l-o; print (x<0?0:x)}')
  if [ $jobs -gt $NARROW ] && awk -v x="$others" -v h="$HALF" 'BEGIN{exit !(x >= h)}'; then
    note "others' load $others reached half the cores: stopping -j$jobs, continuing at -j$NARROW"
    kill -TERM -$pid; sleep 5; kill -KILL -$pid 2>/dev/null; wait $pid 2>/dev/null
    jobs=$NARROW; narrowed=1; start $jobs; own=0; continue
  fi
  if [ $jobs = $NARROW ]; then
    li=${l%.*}
    if [ $paused = 0 ] && [ "$li" -ge "$HI" ]; then kill -STOP -$pid; paused=1; note "load $l: paused"
    elif [ $paused = 1 ] && [ "$li" -le "$LO" ]; then kill -CONT -$pid; paused=0; note "load $l: resumed"; fi
  fi
done
wait $pid; rc=$?
note "done: wall $(( $(date +%s) - t0 )) s, peak RSS of the largest process $((peak / 1024)) MB (sampled), narrowed $narrowed"
echo "BUILD EXIT $rc" >> "$LOG"; exit $rc

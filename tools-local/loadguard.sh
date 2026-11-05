#!/bin/bash
# Pause (SIGSTOP) the build's process group when the shared machine is full; resume when load drops.
# Usage: loadguard.sh <pgid>   (stops when the group is gone)
PG=$1; HI=${HI:-110}; LO=${LO:-90}; paused=0
while pgrep -g "$PG" >/dev/null; do
  l=$(awk '{print int($1)}' /proc/loadavg)
  if [ $paused = 0 ] && [ "$l" -ge "$HI" ]; then kill -STOP -"$PG"; paused=1; echo "$(date +%T) load $l: paused"
  elif [ $paused = 1 ] && [ "$l" -le "$LO" ]; then kill -CONT -"$PG"; paused=0; echo "$(date +%T) load $l: resumed"; fi
  sleep 30
done
echo "$(date +%T) group $PG gone"

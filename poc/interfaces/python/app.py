"""Python baseline for App.main (session 21): the same task with pandas and
matplotlib. Read the CSV into a DataFrame; per column mean, sample standard
deviation, min, max and sum (Stats.weighted with weight 1); a 24-bin histogram
of the first column drawn as bars, with a vertical line at its mean, titled
with the file name, saved as a 1200x800 PNG.

    python app.py <csv> <out.png>        # prints its own phase times to stderr

The environment is not committed:
    uv venv pyenv && VIRTUAL_ENV=pyenv uv pip install pandas matplotlib
"""
import sys
import time

t0 = time.perf_counter()
import os

import numpy as np
import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

t1 = time.perf_counter()


def main(args):
    path = args[0]
    out = args[1] if len(args) > 1 else "report.png"
    ta = time.perf_counter()
    df = pd.read_csv(path)
    tb = time.perf_counter()
    for name in df.columns:
        c = df[name]
        print(f"{name:<6} mean {round(c.mean(), 4)}  std {round(c.std(), 4)}  min {c.min()}  max {c.max()}  weighted {round(c.sum(), 4)}")
    tc = time.perf_counter()
    x = df.iloc[:, 0].to_numpy()
    counts, edges = np.histogram(x, bins=24)
    centers = (edges[:-1] + edges[1:]) / 2
    fig, ax = plt.subplots(figsize=(6, 4), dpi=200)
    ax.bar(centers, counts, width=(edges[1] - edges[0]) * 0.8)
    ax.axvline(x.mean(), color="red")
    ax.set_title(os.path.basename(path))
    ax.set_xlabel(df.columns[0])
    fig.savefig(out)
    td = time.perf_counter()
    return ta, tb, tc, td


if __name__ == "__main__":
    ta, tb, tc, td = main(sys.argv[1:])
    print(f"imports {t1 - t0:.3f} s; read {tb - ta:.3f} s; summarize+print {tc - tb:.3f} s; plot+PNG {td - tc:.3f} s",
          file=sys.stderr)

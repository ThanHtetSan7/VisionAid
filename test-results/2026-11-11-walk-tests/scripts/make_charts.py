"""Report charts from the walk-test tables (light theme, validated categorical slots 1-4)."""
import csv, sys, statistics as st
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = Path(sys.argv[1])
SURFACE, INK, INK2, GRID, MUTED = "#fcfcfb", "#0b0b0b", "#52514e", "#e6e5e1", "#b9b8b2"
FIRST = ("Firstwalk", "First walk · YOLO11m · ultra-wide", "#eda100")
VIDEOS = [("YOLOv11m_ultrawidecamera", "YOLO11m · ultra-wide", "#2a78d6"),
          ("YOLOv11m_maincamera", "YOLO11m · main", "#eb6834"),
          ("YOLOv11s_maincamera", "YOLO11s · main", "#1baf7a")]
plt.rcParams.update({"font.family": "Helvetica Neue", "font.size": 11, "text.color": INK, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2, "axes.edgecolor": MUTED, "figure.facecolor": SURFACE,
                     "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE})
XMAX = 9.8
per = list(csv.DictReader(open(d / "per_second.csv")))
summ = {r["video"]: r for r in csv.DictReader(open(d / "DataSummary.csv"))}

def rolling(xs, ys, window):
    out = []
    for i in range(len(xs)):
        w = [y for x, y in zip(xs, ys) if abs(x - xs[i]) <= window / 2]
        out.append(st.mean(w))
    return out

def end_labels(ax, items, gap):
    """Direct labels at line ends, nudged apart so they never overlap."""
    items = sorted(items, key=lambda i: i[1])
    ys = [y for _, y, _ in items]
    for k in range(1, len(ys)):
        ys[k] = max(ys[k], ys[k - 1] + gap)
    for (x, _, text), y in zip(items, ys):
        ax.text(x, y, text, color=INK, fontsize=9.5, va="center")

def frame(ax, title, sub):
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold", color=INK, pad=24)
    ax.text(0, 1.02, sub, transform=ax.transAxes, fontsize=10.5, color=INK2)
    for s in ("top", "right", "left"): ax.spines[s].set_visible(False)
    ax.grid(axis="y", color=GRID, linewidth=0.8); ax.set_axisbelow(True); ax.tick_params(length=0)

# 1. Inference time over the walk
fig, ax = plt.subplots(figsize=(11, 5.4), dpi=200)
labels = []
for v, name, c in [FIRST] + VIDEOS:
    rows = [(float(r["t_s"]), float(r["inference_ms"])) for r in per if r["video"] == v and r["inference_ms"]]
    xs = [x / 60 for x, _ in rows]; ys = rolling([x for x, _ in rows], [y for _, y in rows], 10)
    ax.plot(xs, ys, color=c, linewidth=2, solid_capstyle="round")
    labels.append((XMAX + 0.08, ys[-1], f"{name}\nmedian {float(summ[v]['ms_median']):g} ms"))
end_labels(ax, labels, 5)
ax.axhline(33.3, color=INK2, linewidth=1, linestyle=(0, (4, 3)))
ax.text(0.05, 34.2, "33 ms budget for 30 FPS", color=INK2, fontsize=9.5)
ax.set_xlabel("Minutes into walk"); ax.set_ylabel("Inference time per frame (ms)")
ax.set_ylim(0, 60); ax.set_xlim(0, XMAX)
frame(ax, "Inference time during each walk", "10-second rolling average, read from the app's on-screen stats once per second")
fig.subplots_adjust(right=0.78, top=0.86, bottom=0.12); fig.savefig(d / "chart_inference_time.png"); plt.close(fig)

# 2. Share of time speaking
fig, ax = plt.subplots(figsize=(11, 5.4), dpi=200)
labels = []
for v, name, c in [FIRST] + VIDEOS:
    rows = [(float(r["t_s"]), float(r["speaking_share"]) * 100) for r in per if r["video"] == v]
    xs = [x / 60 for x, _ in rows]; ys = rolling([x for x, _ in rows], [y for _, y in rows], 60)
    ax.plot(xs, ys, color=c, linewidth=2)
    labels.append((XMAX + 0.08, ys[-1], f"{name}\n{summ[v]['speaking_pct']}% overall"))
end_labels(ax, labels, 10)
ax.set_xlabel("Minutes into walk"); ax.set_ylabel("Time the app was speaking (%)")
ax.set_ylim(0, 100); ax.set_xlim(0, XMAX)
frame(ax, "How much the app talked", "60-second rolling share of time with spoken warnings, from the recording's audio. First walk: before path-only alerts")
fig.subplots_adjust(right=0.78, top=0.86, bottom=0.12); fig.savefig(d / "chart_speaking_time.png"); plt.close(fig)

# 3. Vehicle labels in path vs faded
fig, ax = plt.subplots(figsize=(10, 4.2), dpi=200)
names = [n for _, n, _ in VIDEOS]
for i, (v, name, c) in enumerate(VIDEOS):
    s = float(summ[v]["vehicle_readings_solid_pct"]); n = int(summ[v]["vehicle_readings"])
    ax.barh(i, s, color="#2a78d6", height=0.5, edgecolor=SURFACE, linewidth=2)
    ax.barh(i, 100 - s, left=s, color=MUTED, height=0.5, edgecolor=SURFACE, linewidth=2)
    ax.text(s / 2, i, f"{s:.0f}%", color="white", ha="center", va="center", fontsize=10, fontweight="bold")
    ax.text(101, i, f"n = {n}", color=INK2, va="center", fontsize=9.5)
ax.set_yticks(range(3), names); ax.invert_yaxis(); ax.set_xlim(0, 110); ax.set_xticks([0, 25, 50, 75, 100])
ax.set_xlabel("Share of vehicle label readings (%)")
frame(ax, "How often vehicles were treated as “in path”", "Cars, trucks and buses; solid label = in path, faded = outside the 1.5 m corridor. Not measurable on the first walk")
ax.grid(False); ax.grid(axis="x", color=GRID, linewidth=0.8)
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color="#2a78d6", label="In path (solid)"), Patch(color=MUTED, label="Outside path (faded)")],
          loc="upper center", bbox_to_anchor=(0.45, -0.28), ncol=2, frameon=False, fontsize=9.5)
fig.subplots_adjust(left=0.2, top=0.78, bottom=0.3); fig.savefig(d / "chart_vehicles_in_path.png"); plt.close(fig)
print("ok")

"""Turns the raw screen readings and audio loudness into CSV tables."""
import csv, json, re, sys, statistics as st
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
# (file name, model, camera, walk date, app version). The first walk used the version before
# path-only alerts, which drew every label solid, so its label style isn't recorded.
VIDEOS = [("Firstwalk", "YOLO11m", "ultra-wide", "2026-10-30", "before path-only alerts"),
          ("YOLOv11m_ultrawidecamera", "YOLO11m", "ultra-wide", "2026-11-11", "path-only alerts (85ac0e3)"),
          ("YOLOv11m_maincamera", "YOLO11m", "main", "2026-11-11", "path-only alerts (85ac0e3)"),
          ("YOLOv11s_maincamera", "YOLO11s", "main", "2026-11-11", "path-only alerts (85ac0e3)")]
COCO = set("""person bicycle car motorcycle airplane bus train truck boat|traffic light|fire hydrant|stop sign|parking meter
bench bird cat dog horse sheep cow elephant bear zebra giraffe backpack umbrella handbag tie suitcase frisbee skis snowboard
|sports ball|kite|baseball bat|baseball glove|skateboard surfboard|tennis racket|bottle|wine glass|cup fork knife spoon bowl
banana apple sandwich orange broccoli carrot|hot dog|pizza donut cake chair couch|potted plant|bed|dining table|toilet tv laptop
mouse remote keyboard|cell phone|microwave oven toaster sink refrigerator book clock vase scissors|teddy bear|hair drier|toothbrush"""
    .replace("|", "\n").replace(" ", "\n").split("\n")) | {"traffic light", "fire hydrant", "stop sign", "parking meter",
    "sports ball", "baseball bat", "baseball glove", "tennis racket", "wine glass", "hot dog", "potted plant", "dining table",
    "cell phone", "teddy bear", "hair drier"}
COCO.discard("")
RISK = {"car": 3, "bus": 3, "truck": 3, "motorcycle": 3, "train": 3, "bicycle": 2, "dog": 2, "horse": 2}
LABEL = re.compile(r"^([a-z]+(?: [a-z]+)?) +(?:(\d+(?:\.\d)?)m +)?(-?\d+)°$")

def style(bg):
    """Solid labels are drawn at full opacity (red channel ~255); faded ones at 35%."""
    if not bg: return "unknown"
    return "solid" if bg[0] >= 235 else "faded" if bg[0] < 210 else "unknown"

def speech_segments(rows, gap=0.6, threshold=100):
    """Continuous runs of app audio, merging pauses shorter than `gap` seconds."""
    segs, start, last = [], None, None
    for t, v in rows:
        if v > threshold:
            if start is None: start = t
            elif t - last > gap: segs.append((start, last + 0.1)); start = t
            last = t
    if start is not None: segs.append((start, last + 0.1))
    return segs

per_sec, labels, summary, utter = [], [], [], []
for name, model, camera, date, version in VIDEOS:
    has_path = name != "Firstwalk"
    audio = [(float(r["t"]), float(r["rms"])) for r in csv.DictReader(open(src / f"{name}.audio.csv"))]
    segs = speech_segments(audio)
    for s, e in segs: utter.append({"video": name, "date": date, "start_s": round(s, 1), "end_s": round(e, 1), "length_s": round(e - s, 1)})
    def talking(t0, t1): return sum(max(0, min(e, t1) - max(s, t0)) for s, e in segs) / (t1 - t0)

    rows = [json.loads(l) for l in open(src / f"{name}.jsonl")]
    for r in rows:
        t = r["t"]; stats = " ".join(x["text"] for x in r["stats"])
        fps = re.search(r"(\d+)\s*FPS", stats); ms = re.search(r"(\d+)\s*ms", stats)
        status = [x["text"] for x in r["status"]]
        clock = next((m.group(0) for s in status if (m := re.search(r"\b\d{1,2}:\d{2}\b", s))), "")
        batt = next((int(s) for s in status if re.fullmatch(r"\d{1,3}", s.strip()) and 1 <= int(s) <= 100), None)
        read = []
        for x in r["scene"]:
            m = LABEL.match(x["text"].strip())
            if not m or m.group(1) not in COCO: continue
            read.append(x)
            labels.append({"video": name, "date": date, "model": model, "camera": camera, "t_s": round(t, 1), "object": m.group(1),
                           "distance_m": m.group(2) or "", "angle_deg": m.group(3), "risk": RISK.get(m.group(1), 1),
                           "style": style(x.get("bg")) if has_path else "n/a", "x": round(x["x"], 3), "y": round(x["y"], 3)})
        per_sec.append({"video": name, "date": date, "model": model, "camera": camera, "t_s": round(t, 1), "clock": clock,
                        "battery_pct": batt if batt is not None else "", "fps": fps.group(1) if fps else "",
                        "inference_ms": ms.group(1) if ms else "",
                        "labels_read": len(read), "labels_solid": sum(style(x.get("bg")) == "solid" for x in read) if has_path else "",
                        "speaking_share": round(talking(t - 0.5, t + 0.5), 2)})

    mine = [p for p in per_sec if p["video"] == name]
    # Battery: drop misreadings (e.g. "8" for "86"), keeping values near this video's typical level.
    typical = st.median([p["battery_pct"] for p in mine if p["battery_pct"] != ""])
    for p in mine:
        if p["battery_pct"] != "" and abs(p["battery_pct"] - typical) > 5: p["battery_pct"] = ""
    # FPS 0 means the app was stopped (the last second of a recording), not a slow frame.
    for p in mine:
        if p["fps"] == "0": p["fps"] = p["inference_ms"] = ""
    ms_v = [int(p["inference_ms"]) for p in mine if p["inference_ms"]]
    fps_v = [int(p["fps"]) for p in mine if p["fps"]]
    batt_v = [(p["t_s"], p["battery_pct"]) for p in mine if p["battery_pct"] != ""]
    dur = audio[-1][0] + 0.1
    lab = [l for l in labels if l["video"] == name]
    cars = [l for l in lab if l["object"] in ("car", "truck", "bus")]
    summary.append({
        "video": name, "date": date, "app_version": version, "model": model, "camera": camera, "duration_s": round(dur, 1),
        "clock_start": next((p["clock"] for p in mine if p["clock"]), ""),
        "clock_end": next((p["clock"] for p in reversed(mine) if p["clock"]), ""),
        "seconds_sampled": len(mine), "stats_readable_pct": round(100 * len(ms_v) / len(mine), 1),
        "fps_mean": round(st.mean(fps_v), 1), "fps_min": min(fps_v),
        "ms_mean": round(st.mean(ms_v), 1), "ms_median": st.median(ms_v),
        "ms_p95": sorted(ms_v)[int(0.95 * (len(ms_v) - 1))], "ms_max": max(ms_v),
        "battery_start_pct": batt_v[0][1] if batt_v else "", "battery_end_pct": batt_v[-1][1] if batt_v else "",
        "battery_drop_pct_per_hour": round((batt_v[0][1] - batt_v[-1][1]) / ((batt_v[-1][0] - batt_v[0][0]) / 3600), 1) if len(batt_v) > 1 else "",
        "speaking_pct": round(100 * sum(e - s for s, e in segs) / dur, 1),
        "utterances": len(segs), "utterances_per_min": round(len(segs) / (dur / 60), 1),
        "label_readings": len(lab), "label_readings_solid_pct": round(100 * sum(l["style"] == "solid" for l in lab) / max(1, len(lab)), 1) if has_path else "",
        "vehicle_readings": len(cars), "vehicle_readings_solid_pct": round(100 * sum(l["style"] == "solid" for l in cars) / max(1, len(cars)), 1) if has_path else "",
    })

def write(fn, rows):
    with open(out / fn, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
write("DataSummary.csv", summary); write("per_second.csv", per_sec); write("labels.csv", labels); write("speech.csv", utter)
for s in summary: print(s)

# Walk tests

Four screen recordings of VisionAid running on an iPhone 15 while walking along a residential street. The first walk (30 October 2026, afternoon sun) used the app version before path-only alerts. The other three (11 November 2026, 16:09–16:28, at dusk) used the version with path-only alerts on (commit `85ac0e3`).

| Video | Date | App version | Model | Camera | Length | Clock |
|---|---|---|---|---|---|---|
| `Firstwalk.MP4` | 30 Oct | Before path-only alerts | YOLO11m | Ultra-wide | 9:46 | 15:11–15:21 |
| `YOLOv11m_ultrawidecamera.MP4` | 11 Nov | Path-only alerts | YOLO11m | Ultra-wide | 6:22 | 16:09–16:15 |
| `YOLOv11m_maincamera.MP4` | 11 Nov | Path-only alerts | YOLO11m | Main | 5:49 | 16:16–16:22 |
| `YOLOv11s_maincamera.MP4` | 11 Nov | Path-only alerts | YOLO11s | Main | 6:17 | 16:22–16:28 |

## Results

| | First walk · YOLO11m · ultra-wide | YOLO11m · ultra-wide | YOLO11m · main | YOLO11s · main |
|---|---|---|---|---|
| Inference time, median | 24 ms | 25 ms | 28 ms | **18 ms** |
| Inference time, 95th percentile | 32 ms | 32 ms | 36 ms | **21 ms** |
| Inference time, worst second | 57 ms | 41 ms | 52 ms | **23 ms** |
| FPS, mean (lowest second) | 30.2 (16) | 30.5 (25) | 30.1 (20) | **30.6 (30)** |
| Battery used | 77 → 68% | 89 → 86% | 86 → 81% | 80 → 76% |
| Time spent speaking | 63.1% | 43.3% | 39.5% | **35.5%** |
| Spoken warnings per minute | 8.7 | 6.8 | 7.2 | 7.2 |
| Vehicle labels shown as "in path" | n/a | 66% | 74% | 78% |

- **Path-only alerts and the tighter alert rules cut talking by about a third.** The app spoke for 63% of the first walk, and for 36–43% of the later walks. Warnings per minute fell from 8.7 to 6.8–7.2.
- **YOLO11s was the only setup that never missed the 33 ms budget for 30 FPS.** YOLO11m stayed at 30 FPS on average but had slow bursts. The worst, on the first walk at about minute 6, lasted about 20 seconds (down to 16 FPS) and began as a phone notification arrived (see `chart_inference_time.png`).
- **Most vehicle labels (66–78%) were drawn as "in path" on the later walks**, even though the vehicles were mostly parked on the road beside the pavement. In a frame checked by eye, the camera pointed slightly towards the road, and the corridor follows the camera. This is a likely explanation, not a measured one, and it probably accounts for much of the remaining talk.
- **Cars dominate every walk.** On the first walk 366 of 432 labels read were cars, the same pattern as the later walks.

## Files

| File | Contents |
|---|---|
| `summary.csv` | One row per video: the results above plus counts |
| `per_second.csv` | One row per second of each video: date, clock, battery, FPS, inference ms, labels read, labels shown as in path, share of the second spent speaking |
| `labels.csv` | Every on-screen box label read in full: object, distance (m), angle (°), risk level, solid (in path) or faded, position on screen |
| `speech.csv` | Start, end and length of each spoken warning |
| `TestData.csv` | Detection results for the three 11 November walks: true positives, false positives and false negatives per object class |
| `chart_*.png` | Charts of inference time, speaking time and in-path vehicles |
| `scripts/` | The scripts that produced everything here |

## How the data was collected

1. **Screen reading.** One frame per second was taken from each recording and read with Apple's Vision text recognition (`scripts/read_screen.swift`). This gives the stats bar (model, FPS, ms), the clock, the battery level and the text of each box label. Each label's background colour was also sampled: in the later app version, labels for objects in the walking path are drawn at full opacity, those outside it at 35%.
2. **Speech.** The recordings captured only the app's own audio (it is digitally silent between warnings), so any sound is the app speaking. Loudness was measured every 0.1 s (`scripts/audio_loudness.swift`); sound separated by less than 0.6 s counts as one warning.
3. **Tables and charts** were built with `scripts/build_tables.py` and `scripts/make_charts.py`.

## Limitations

- **The first walk is not a like-for-like comparison.** It used an older app version, was longer, and was done on a different day in bright sun rather than at dusk. Its version drew every label solid, so "in path" could not be measured (shown as n/a or blank).
- **Labels, not objects.** Labels were read once a second, so a car on screen for 5 seconds counts about 5 times. Overlapping or cut-off labels could not be read and are missing: 1,222 labels were read in full across the four videos.
- **Distances are what the app displayed**, not measured ground truth.
- **Battery levels** are whole percentages over 6–10 minutes, so drain rates are rough. On the first walk, sun glare made the battery icon readable in only about a third of seconds. Battery figures should not be compared closely.
- **Conditions changed between runs.** The 11 November tests were done one after another at dusk, so light was fading and the phone may have been warming up. The YOLO11m main-camera slowdowns could be partly heat.
- **Warning counts are approximate.** A warning with a long pause in it counts as two.
- **Reading errors.** The stats bar was read in 98–100% of seconds; it was unreadable while notifications covered it. A few battery readings were misread (for example "8" for "86") and were discarded. The final second of the YOLO11m main-camera recording (0 FPS, the app had been stopped) was excluded.

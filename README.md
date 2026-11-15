# VisionAid

VisionAid is an iOS app that helps blind and visually impaired people avoid obstacles while walking. It uses the iPhone's camera and a YOLO11 object detection model running on the phone to spot objects such as cars, bicycles, people, dogs and benches. It estimates how far away each object is and in which direction, and speaks short warnings such as "Car ahead, 3 metres". Everything runs on the device, so no internet connection is needed.

The app was built as a final-year BSc (Hons) Computer Science project at the University of Portsmouth London.

## Main features

- Real-time object detection with YOLO11 through Core ML, using the Neural Engine.
- Distance and direction for each object, using the camera's field of view and the phone's tilt.
- Spoken warnings, prioritised by risk (vehicles first), with rules to avoid repeating the same warning.
- An option to warn only about objects in the walking path.
- A choice of two models (YOLO11s for speed, YOLO11m for accuracy) and of the main or ultra-wide lens.
- Settings for which objects to detect and the minimum confidence.

## Requirements

- A Mac with **Xcode 26.3** or later.
- An **iPhone running iOS 26.2 or later**. The app needs a real camera, so it does not work in the Simulator. It was tested on an iPhone 15.
- An Apple ID added to Xcode, to sign the app for your iPhone. A free account is enough.

## How to open and run

1. Download the project:
   ```bash
   git clone https://github.com/ThanHtetSan7/VisionAid.git
   ```
   Or use **Code → Download ZIP** on GitHub and unzip it.
2. Open `VisionAId.xcodeproj` in Xcode.
3. Select the **VisionAId** target, open **Signing & Capabilities**, and choose your own **Team**. If Xcode reports that the bundle identifier is taken, change it to something unique, for example `com.yourname.VisionAid`.
4. Connect your iPhone with a cable (or over Wi-Fi), unlock it and select it as the run destination at the top of Xcode.
5. Press **Run** (⌘R).
6. The first time, the iPhone may block the app. Go to **Settings → General → VPN & Device Management**, trust your developer account, and run it again. If asked, turn on **Developer Mode** in **Settings → Privacy & Security**.
7. Allow camera access when the app asks.

To use it, hold the phone upright at chest height with the camera facing forward and press **Start**. The model can be switched on the main screen; other options are in **Settings**.

## Models

The app includes two Core ML models in the `VisionAId` folder:

| File | Model | Size |
|---|---|---|
| `yolo11s.mlpackage` | YOLO11s (small) | 18 MB |
| `yolo11m.mlpackage` | YOLO11m (medium) | 39 MB |

Both are the official **Ultralytics YOLO11** models, pre-trained on the COCO dataset (80 object classes). They were not retrained. They were converted to Core ML with the Ultralytics Python package at 640 × 640 input size, 16-bit precision and with non-maximum suppression built in:

```bash
pip install ultralytics
yolo export model=yolo11m.pt format=coreml imgsz=640 half=True nms=True
yolo export model=yolo11s.pt format=coreml imgsz=640 half=True nms=True
```

Xcode compiles the `.mlpackage` files into the app automatically.

- Ultralytics YOLO11: https://docs.ultralytics.com/models/yolo11/
- COCO dataset: https://cocodataset.org/

## Testing data

The results of the walk tests are in [`test-results/2026-11-11-walk-tests/`](test-results/2026-11-11-walk-tests/). The folder has its own README explaining how the data was collected.

- `DataSummary.csv`, `per_second.csv`, `labels.csv` and `speech.csv`: performance and alert data read from screen recordings of four walks (inference time, FPS, battery, spoken warnings and on-screen labels).
- `TestData.csv`: detection results for the three 11 November walks, with true positives, false positives and false negatives for each object class.
- `chart_*.png`: charts of the results.
- `scripts/`: the scripts used to extract the data and draw the charts.

The screen recordings themselves are not included because of their size.

## Licence

This project is licensed under the **GNU Affero General Public License v3.0** (see [`LICENSE`](LICENSE)), the same licence as Ultralytics YOLO11, whose models it uses.

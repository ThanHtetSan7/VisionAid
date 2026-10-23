import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var vm = DetectionViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: vm.camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            DetectionOverlay(detections: vm.detections, imageSize: vm.imageSize)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack {
                statsBar
                Spacer()
                controls
            }
            .padding()
        }
        .background(Color.black)
        .task { await vm.start() }
        .alert("VisionAid", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var statsBar: some View {
        Text("\(vm.modelSize.title) · \(Int(vm.fps)) FPS · \(Int(vm.inferenceMs)) ms")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Model", selection: $vm.modelSize) {
                ForEach(ObstacleDetector.ModelSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    vm.muted.toggle()
                } label: {
                    Image(systemName: vm.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title2)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .accessibilityLabel(vm.muted ? "Unmute alerts" : "Mute alerts")

                Button {
                    vm.toggle()
                } label: {
                    Text(vm.isRunning ? "Stop" : "Start")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isRunning ? .red : .blue)
                .accessibilityLabel(vm.isRunning ? "Stop detection" : "Start detection")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Live camera feed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Draws boxes over the preview, using the same aspect-fill scaling as the preview layer.
struct DetectionOverlay: View {
    let detections: [Detection]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let scale = max(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let offset = CGPoint(x: (geo.size.width - drawn.width) / 2, y: (geo.size.height - drawn.height) / 2)

            ForEach(detections) { d in
                let rect = CGRect(x: offset.x + d.box.minX * drawn.width,
                                  y: offset.y + d.box.minY * drawn.height,
                                  width: d.box.width * drawn.width,
                                  height: d.box.height * drawn.height)
                let colour = color(for: d.label)

                Rectangle()
                    .stroke(colour, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Text("\(d.label) \(d.distance.map { String(format: "%.1fm", $0) } ?? "") \(Int(d.angle))°")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(colour)
                    .position(x: rect.minX + 50, y: max(rect.minY - 10, 10))
            }
        }
    }

    private func color(for label: String) -> Color {
        switch Obstacles.priority[label] ?? 1 {
        case 3: return .red
        case 2: return .orange
        default: return .yellow
        }
    }
}

import AVFoundation
// Usage: audio_loudness <video> <out.csv>  — loudness (RMS) every 0.1 s of the mono 8 kHz mix.
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let r = try! AVAssetReader(asset: asset)
let o = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .audio).first!, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 8000])
r.add(o); r.startReading()
var out = "t,rms\n"; var acc = 0.0, n = 0, k = 0
while let b = o.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(b) {
  var len = 0; var p: UnsafeMutablePointer<Int8>?
  CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &p)
  p!.withMemoryRebound(to: Int16.self, capacity: len / 2) { s in
    for i in 0..<len / 2 { acc += Double(s[i]) * Double(s[i]); n += 1
      if n == 800 { out += String(format: "%.1f,%.1f\n", Double(k) / 10, (acc / 800).squareRoot()); acc = 0; n = 0; k += 1 } }
  }
}
try! out.write(toFile: a[2], atomically: true, encoding: .utf8)

import AVFoundation
import Vision
import AppKit
// Usage: read_screen <video> <out.jsonl> <stepSeconds> [startSeconds] [sceneEvery]
// Reads the status bar, the stats bar and every text label in the camera area once per step,
// and records the median colour of each label's background (non-white pixels inside its box).
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1])); let dur = CMTimeGetSeconds(asset.duration); let step = Double(a[3])!
let g = AVAssetImageGenerator(asset: asset); g.appliesPreferredTrackTransform = true
g.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600); g.requestedTimeToleranceAfter = g.requestedTimeToleranceBefore
if !FileManager.default.fileExists(atPath: a[2]) { FileManager.default.createFile(atPath: a[2], contents: nil) }
let fh = FileHandle(forWritingAtPath: a[2])!; fh.seekToEndOfFile()
let start = a.count > 4 ? Double(a[4])! : step / 2; let sceneEvery = a.count > 5 ? Int(a[5])! : 1; var i = 0

struct Pixels {
  let w: Int, h: Int, data: [UInt8]
  init(_ img: CGImage) {
    w = img.width; h = img.height; var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); data = buf
  }
  // Median RGB of pixels in a rect (top-left origin) that aren't near-white text.
  func background(_ r: CGRect) -> [Int] {
    var rs: [Int] = [], gs: [Int] = [], bs: [Int] = []
    let x0 = max(0, Int(r.minX)), x1 = min(w - 1, Int(r.maxX)), y0 = max(0, Int(r.minY)), y1 = min(h - 1, Int(r.maxY))
    guard x1 > x0, y1 > y0 else { return [] }
    for y in stride(from: y0, through: y1, by: 2) { for x in stride(from: x0, through: x1, by: 2) {
      let i = (y * w + x) * 4; let R = Int(data[i]), G = Int(data[i+1]), B = Int(data[i+2])
      if min(R, G, B) < 200 { rs.append(R); gs.append(G); bs.append(B) }
    } }
    guard !rs.isEmpty else { return [] }
    func med(_ v: [Int]) -> Int { v.sorted()[v.count / 2] }
    return [med(rs), med(gs), med(bs)]
  }
}
func scaled(_ img: CGImage, _ crop: CGRect, _ k: Int) -> CGImage {
  let c = img.cropping(to: crop)!; if k == 1 { return c }
  let ctx = CGContext(data: nil, width: c.width * k, height: c.height * k, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high; ctx.draw(c, in: CGRect(x: 0, y: 0, width: c.width * k, height: c.height * k)); return ctx.makeImage()!
}
// Returns text with its box in full-frame pixels (top-left origin).
func read(_ img: CGImage, crop: CGRect, k: Int) -> [(String, Float, CGRect)] {
  let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
  try? VNImageRequestHandler(cgImage: scaled(img, crop, k)).perform([r])
  return (r.results ?? []).compactMap { o in
    guard let c = o.topCandidates(1).first else { return nil }
    let b = o.boundingBox
    let rect = CGRect(x: crop.minX + b.minX * crop.width, y: crop.minY + (1 - b.maxY) * crop.height, width: b.width * crop.width, height: b.height * crop.height)
    return (c.string, c.confidence, rect)
  }
}
var t = start
while t < dur {
  if let img = try? g.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
    let W = CGFloat(img.width), H = CGFloat(img.height); let px = Pixels(img)
    func pack(_ items: [(String, Float, CGRect)], colour: Bool) -> [[String: Any]] {
      items.map { s, c, r in
        var d: [String: Any] = ["text": s, "conf": c, "x": Double(r.midX / W), "y": Double(r.midY / H), "w": Double(r.width / W), "h": Double(r.height / H)]
        if colour { d["bg"] = px.background(r) }
        return d
      }
    }
    let rec: [String: Any] = [
      "t": t,
      "status": pack(read(img, crop: CGRect(x: 0, y: 0, width: W, height: H * 0.07), k: 2), colour: false),
      "stats": pack(read(img, crop: CGRect(x: 0, y: H * 0.07, width: W, height: H * 0.08), k: 2), colour: false),
      "scene": i % sceneEvery == 0 ? pack(read(img, crop: CGRect(x: 0, y: H * 0.15, width: W, height: H * 0.60), k: 1), colour: true) : [],
      "scene_read": i % sceneEvery == 0
    ]
    fh.write(try! JSONSerialization.data(withJSONObject: rec)); fh.write("\n".data(using: .utf8)!)
  }
  t += step; i += 1
}

import Foundation
import AVFoundation
import CoreImage
import UIKit
import ImageIO

final class VideoWatermarkProcessor {
  private let queue = DispatchQueue(label: "wm.video", qos: .userInitiated)

  private enum OverlaySource {
    case staticImage(CIImage)
    case animated(AnimatedOverlay)
  }

  private struct AnimatedOverlay {
    let frames: [CIImage]
    let cumulativeDurations: [Double]
    let totalDuration: Double

    func image(at time: Double) -> CIImage? {
      guard !frames.isEmpty else { return nil }
      if totalDuration <= 0 {
        return frames[0]
      }
      let t = time.truncatingRemainder(dividingBy: totalDuration)
      let idx = cumulativeDurations.firstIndex(where: { t < $0 }) ?? (frames.count - 1)
      return frames[idx]
    }
  }

  private final class TaskState {
    var cancelled = false
    let request: ComposeVideoRequest
    let outputURL: URL
    init(request: ComposeVideoRequest, outputURL: URL) {
      self.request = request
      self.outputURL = outputURL
    }
  }

  private var tasks: [String: TaskState] = [:]

  func start(plugin: WatermarkKitPlugin,
             request: ComposeVideoRequest,
             callbacks: WatermarkCallbacks,
             taskId: String,
             onComplete: @escaping (ComposeVideoResult) -> Void,
             onError: @escaping (_ code: String, _ message: String) -> Void) {
    let outputPath: String
    if let out = request.outputVideoPath, !out.isEmpty {
      outputPath = out
    } else {
      let tmp = NSTemporaryDirectory()
      outputPath = (tmp as NSString).appendingPathComponent("wm_\(taskId).mp4")
    }
    let outputURL = URL(fileURLWithPath: outputPath)
    // Remove existing
    try? FileManager.default.removeItem(at: outputURL)

    let state = TaskState(request: request, outputURL: outputURL)
    tasks[taskId] = state

    queue.async { [weak self] in
      guard let self else { return }
      do {
        try self.process(plugin: plugin, state: state, callbacks: callbacks, taskId: taskId, onComplete: onComplete, onError: onError)
      } catch let err {
        callbacks.onVideoError(taskId: taskId, code: "compose_failed", message: err.localizedDescription) { _ in }
        onError("compose_failed", err.localizedDescription)
        self.tasks[taskId] = nil
      }
    }
  }

  func cancel(taskId: String) {
    if let st = tasks[taskId] {
      st.cancelled = true
    }
  }

  private func process(plugin: WatermarkKitPlugin,
                       state: TaskState,
                       callbacks: WatermarkCallbacks,
                       taskId: String,
                       onComplete: @escaping (ComposeVideoResult) -> Void,
                       onError: @escaping (_ code: String, _ message: String) -> Void) throws {
    let request = state.request
    let asset = AVURLAsset(url: URL(fileURLWithPath: request.inputVideoPath))
    let duration = CMTimeGetSeconds(asset.duration)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      throw NSError(domain: "wm", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }

    let natural = videoTrack.naturalSize
    let t = videoTrack.preferredTransform
    let display = CGSize(width: abs(natural.applying(t).width), height: abs(natural.applying(t).height))

    // Prepare overlay source (static or animated)
    let overlaySource: OverlaySource? = try Self.prepareOverlaySource(request: request, plugin: plugin, baseWidth: display.width, baseHeight: display.height)

    let reader = try AVAssetReader(asset: asset)
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    videoReaderOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(videoReaderOutput) else { throw NSError(domain: "wm", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video reader output"]) }
    reader.add(videoReaderOutput)

    // Optional audio passthrough (best-effort)
    let audioTrack = asset.tracks(withMediaType: .audio).first
    var audioReaderOutput: AVAssetReaderOutput? = nil
    if let a = audioTrack {
      let out = AVAssetReaderTrackOutput(track: a, outputSettings: nil) // compressed pass-through
      if reader.canAdd(out) {
        reader.add(out)
        audioReaderOutput = out
      }
    }

    let writer = try AVAssetWriter(outputURL: state.outputURL, fileType: .mp4)
    // Video writer input
    let codec: AVVideoCodecType = (request.codec == .hevc) ? .hevc : .h264
    let defaultBitrate = Int64(Self.estimateBitrate(width: Int(display.width), height: Int(display.height), fps: Float(videoTrack.nominalFrameRate)))
    let bitrate64: Int64 = request.bitrateBps ?? defaultBitrate
    var compression: [String: Any] = [
      AVVideoAverageBitRateKey: NSNumber(value: bitrate64),
    ]
    if codec == .h264 {
      compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
    }
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: codec,
      AVVideoWidthKey: Int(display.width),
      AVVideoHeightKey: Int(display.height),
      AVVideoCompressionPropertiesKey: compression,
    ]
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false
    videoInput.transform = videoTrack.preferredTransform
    guard writer.canAdd(videoInput) else { throw NSError(domain: "wm", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video writer input"]) }
    writer.add(videoInput)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: Int(display.width),
      kCVPixelBufferHeightKey as String: Int(display.height),
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ])

    // Optional audio writer input (pass-through)
    var audioInput: AVAssetWriterInput? = nil
    if audioReaderOutput != nil {
      let ain = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
      ain.expectsMediaDataInRealTime = false
      if writer.canAdd(ain) {
        writer.add(ain)
        audioInput = ain
      }
    }

    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "wm", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"]) }
    let startTime = CMTime.zero
    writer.startSession(atSourceTime: startTime)
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "wm", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"]) }

    let ciContext = plugin.sharedCIContext

    let staticOverlay: CIImage?
    let animatedOverlay: AnimatedOverlay?
    switch overlaySource {
    case .staticImage(let img):
      staticOverlay = img
      animatedOverlay = nil
    case .animated(let anim):
      staticOverlay = nil
      animatedOverlay = anim
    case nil:
      staticOverlay = nil
      animatedOverlay = nil
    }

    // Processing loop
    var lastPTS = CMTime.zero
    var lastTimeSec: Double = -1.0
    var frameIndex: Int64 = 0
    let fallbackFps = max(1.0, Double(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30.0))
    while reader.status == .reading && !state.cancelled {
      autoreleasepool {
        if videoInput.isReadyForMoreMediaData, let sample = videoReaderOutput.copyNextSampleBuffer() {
          let pts = Self.sampleTime(sample, fallbackFps: fallbackFps, frameIndex: frameIndex, lastTimeSeconds: lastTimeSec)
          lastPTS = pts
          let ptsSec = CMTimeGetSeconds(pts)
          if ptsSec.isFinite {
            lastTimeSec = ptsSec
          }
          guard let pool = adaptor.pixelBufferPool else { return }
          var pb: CVPixelBuffer? = nil
          CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
          guard let dst = pb else { return }

          // Create base CIImage from sample
          if let srcPB = CMSampleBufferGetImageBuffer(sample) {
            let base = CIImage(cvPixelBuffer: srcPB)
            let output: CIImage
            let overlay = animatedOverlay?.image(at: CMTimeGetSeconds(pts)) ?? staticOverlay
            if let overlay = overlay {
              // Source-over
              let filter = CIFilter(name: "CISourceOverCompositing")!
              filter.setValue(overlay, forKey: kCIInputImageKey)
              filter.setValue(base, forKey: kCIInputBackgroundImageKey)
              output = filter.outputImage ?? base
            } else {
              output = base
            }
            ciContext.render(output, to: dst, bounds: CGRect(x: 0, y: 0, width: display.width, height: display.height), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            _ = adaptor.append(dst, withPresentationTime: pts)
          }

          // Progress
          let p = max(0.0, min(1.0, CMTimeGetSeconds(pts) / max(0.001, duration)))
          callbacks.onVideoProgress(taskId: taskId, progress: p, etaSec: max(0.0, duration - CMTimeGetSeconds(pts))) { _ in }
          frameIndex += 1
        } else {
          // Back off a little
          usleep(2000)
        }

        // Pump audio opportunistically
        if let aout = audioReaderOutput, let ain = audioInput, ain.isReadyForMoreMediaData {
          if let asample = aout.copyNextSampleBuffer() {
            ain.append(asample)
          }
        }
      }
    }

    if state.cancelled {
      reader.cancelReading()
      videoInput.markAsFinished()
      audioInput?.markAsFinished()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: state.outputURL)
      callbacks.onVideoError(taskId: taskId, code: "cancelled", message: "Cancelled") { _ in }
      onError("cancelled", "Cancelled")
      tasks[taskId] = nil
      return
    }

    // Drain remaining audio
    if let aout = audioReaderOutput, let ain = audioInput {
      while reader.status == .reading || reader.status == .completed {
        if let asample = aout.copyNextSampleBuffer() {
          while !ain.isReadyForMoreMediaData { usleep(2000) }
          ain.append(asample)
        } else { break }
      }
    }

    videoInput.markAsFinished()
    audioInput?.markAsFinished()
    reader.cancelReading()
    writer.finishWriting { [weak self] in
      guard let self else { return }
      if writer.status == .completed {
        let res = ComposeVideoResult(taskId: taskId,
                                     outputVideoPath: state.outputURL.path,
                                     width: Int64(display.width),
                                     height: Int64(display.height),
                                     durationMs: Int64(duration * 1000.0),
                                     codec: request.codec)
        callbacks.onVideoCompleted(result: res) { _ in }
        onComplete(res)
      } else {
        let msg = writer.error?.localizedDescription ?? "Unknown writer error"
        callbacks.onVideoError(taskId: taskId, code: "encode_failed", message: msg) { _ in }
        onError("encode_failed", msg)
      }
      self.tasks[taskId] = nil
    }
  }

  private static func estimateBitrate(width: Int, height: Int, fps: Float) -> Int {
    let bpp: Float = 0.08 // reasonable default for H.264 1080p
    let f = max(24.0, fps > 0 ? fps : 30.0)
    let br = bpp * Float(width * height) * f
    return max(500_000, Int(br))
  }

  private static func prepareOverlaySource(request: ComposeVideoRequest, plugin: WatermarkKitPlugin, baseWidth: CGFloat, baseHeight: CGFloat) throws -> OverlaySource? {
    // Prefer watermarkImage; fallback to text
    if let data = request.watermarkImage?.data, !data.isEmpty {
      if let decoded = decodeAnimatedCIImages(from: data) {
        let targetW = max(1.0, baseWidth * CGFloat(request.widthPercent))
        let refWidth = decoded.canvasWidth ?? decoded.frames.first?.extent.width ?? 1.0
        let scale = targetW / max(1.0, refWidth)
        let prepared = decoded.frames.map { prepareOverlayFrame($0, request: request, baseWidth: baseWidth, baseHeight: baseHeight, scaleOverride: scale) }
        let durations = sanitizeDurations(decoded.durations, count: prepared.count)
        let cumulative = cumulativeDurations(durations)
        let total = cumulative.last ?? 0.0
        if !prepared.isEmpty {
          return .animated(AnimatedOverlay(frames: prepared, cumulativeDurations: cumulative, totalDuration: total))
        }
      }
      guard let src = decodeCIImage(from: data) else { return nil }
      let prepared = prepareOverlayFrame(src, request: request, baseWidth: baseWidth, baseHeight: baseHeight)
      return .staticImage(prepared)
    }
    if let text = request.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let fontFamily = ".SFUI"
      let fontSizePt = 24.0
      let fontWeight = 600
      let colorArgb: UInt32 = 0xFFFFFFFF
      guard let cg = try WatermarkKitPlugin.renderTextCGImage(text: text, fontFamily: fontFamily, fontSizePt: fontSizePt, fontWeight: fontWeight, colorArgb: colorArgb) else {
        return nil
      }
      let png = WatermarkKitPlugin.encodePNG(cgImage: cg) ?? Data()
      guard let src = decodeCIImage(from: png) else { return nil }
      let prepared = prepareOverlayFrame(src, request: request, baseWidth: baseWidth, baseHeight: baseHeight)
      return .staticImage(prepared)
    }
    return nil
  }

  private struct AnimatedDecodeResult {
    let frames: [CIImage]
    let durations: [Double]
    let canvasWidth: CGFloat?
  }

  private static func decodeAnimatedCIImages(from data: Data) -> AnimatedDecodeResult? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    if count <= 1 { return nil }
    var frames: [CIImage] = []
    var durations: [Double] = []
    let srcProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    var canvasWidth: CGFloat? = numberValue(srcProps?[kCGImagePropertyPixelWidth]).map { CGFloat($0) }
    for i in 0..<count {
      let options: [CFString: Any] = [
        kCGImageSourceShouldCache: true,
        kCGImageSourceShouldCacheImmediately: true
      ]
      guard let cg = CGImageSourceCreateImageAtIndex(source, i, options as CFDictionary) else { continue }
      frames.append(CIImage(cgImage: cg, options: [.applyOrientationProperty: true]))
      let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
      if canvasWidth == nil {
        canvasWidth = numberValue(props?[kCGImagePropertyPixelWidth]).map { CGFloat($0) }
      }
      let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      let unclamped = numberValue(gif?[kCGImagePropertyGIFUnclampedDelayTime])
      let delay = unclamped ?? numberValue(gif?[kCGImagePropertyGIFDelayTime])
      durations.append(delay ?? 0.1)
    }
    if frames.count <= 1 { return nil }
    return AnimatedDecodeResult(frames: frames, durations: durations, canvasWidth: canvasWidth)
  }

  private static func numberValue(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let n = value as? NSNumber { return n.doubleValue }
    return nil
  }

  private static func sanitizeDurations(_ durations: [Double], count: Int) -> [Double] {
    let defaultDur = 0.1
    var out: [Double] = []
    out.reserveCapacity(count)
    for i in 0..<count {
      let d = i < durations.count ? durations[i] : defaultDur
      let value = (d.isFinite && d >= 0.02) ? d : defaultDur
      out.append(value)
    }
    return out
  }

  private static func cumulativeDurations(_ durations: [Double]) -> [Double] {
    var total = 0.0
    var out: [Double] = []
    out.reserveCapacity(durations.count)
    for d in durations {
      total += d
      out.append(total)
    }
    return out
  }

  private static func prepareOverlayFrame(_ image: CIImage, request: ComposeVideoRequest, baseWidth: CGFloat, baseHeight: CGFloat, scaleOverride: CGFloat? = nil) -> CIImage {
    // Scale by widthPercent of base width using high-quality Lanczos
    let targetW = max(1.0, baseWidth * CGFloat(request.widthPercent))
    let extent = image.extent
    let scale = scaleOverride ?? (targetW / max(1.0, extent.width))
    let scaled = scaleCIImageHighQuality(image, scale: scale)
    // Apply opacity
    let alphaVec = CIVector(x: 0, y: 0, z: 0, w: CGFloat(request.opacity))
    let withOpacity = scaled.applyingFilter("CIColorMatrix", parameters: ["inputAVector": alphaVec])
    // Compute position
    let baseRect = CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight)
    let wmRect = withOpacity.extent
    let marginX = (request.marginUnit == .percent) ? CGFloat(request.margin) * baseWidth : CGFloat(request.margin)
    let marginY = (request.marginUnit == .percent) ? CGFloat(request.margin) * baseHeight : CGFloat(request.margin)
    var pos = Self.positionRect(base: baseRect, overlay: wmRect, anchor: request.anchor, marginX: marginX, marginY: marginY)
    let dx = (request.offsetUnit == .percent) ? CGFloat(request.offsetX) * baseWidth : CGFloat(request.offsetX)
    let dy = (request.offsetUnit == .percent) ? CGFloat(request.offsetY) * baseHeight : CGFloat(request.offsetY)
    pos.x += dx
    pos.y += dy
    return withOpacity.transformed(by: CGAffineTransform(translationX: floor(pos.x), y: floor(pos.y)))
  }

  private static func sampleTime(_ sample: CMSampleBuffer, fallbackFps: Double, frameIndex: Int64, lastTimeSeconds: Double) -> CMTime {
    let outputPts = CMSampleBufferGetOutputPresentationTimeStamp(sample)
    let candidate = outputPts.isValid ? outputPts : CMSampleBufferGetPresentationTimeStamp(sample)
    let secs = CMTimeGetSeconds(candidate)
    if secs.isFinite && secs >= 0 {
      if frameIndex > 0 && secs <= lastTimeSeconds + 0.000001 {
        let fallback = Double(frameIndex) / max(1.0, fallbackFps)
        return CMTime(seconds: fallback, preferredTimescale: 600)
      }
      return candidate
    }
    let fallback = Double(frameIndex) / max(1.0, fallbackFps)
    return CMTime(seconds: fallback, preferredTimescale: 600)
  }

  private static func scaleCIImageHighQuality(_ image: CIImage, scale: CGFloat) -> CIImage {
    // Use CILanczosScaleTransform for superior quality scaling
    if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
      lanczos.setValue(image, forKey: kCIInputImageKey)
      lanczos.setValue(scale, forKey: kCIInputScaleKey)
      lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
      return lanczos.outputImage ?? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    } else {
      // Fallback to simple transform
      return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
  }

  private static func decodeCIImage(from data: Data) -> CIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
      return nil
    }
    return CIImage(cgImage: cg, options: [.applyOrientationProperty: true])
  }

  private static func positionRect(base: CGRect, overlay: CGRect, anchor: Anchor, marginX: CGFloat, marginY: CGFloat) -> CGPoint {
    let w = overlay.width
    let h = overlay.height
    switch anchor {
    case .topLeft:
      return CGPoint(x: base.minX + marginX, y: base.maxY - marginY - h)
    case .topRight:
      return CGPoint(x: base.maxX - marginX - w, y: base.maxY - marginY - h)
    case .bottomLeft:
      return CGPoint(x: base.minX + marginX, y: base.minY + marginY)
    case .center:
      return CGPoint(x: base.midX - w * 0.5, y: base.midY - h * 0.5)
    default: // bottomRight
      return CGPoint(x: base.maxX - marginX - w, y: base.minY + marginY)
    }
  }
}

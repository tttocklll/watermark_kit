import Foundation
import AVFoundation
import CoreImage
import UIKit

final class VideoWatermarkProcessor {
  private let queue = DispatchQueue(label: "wm.video", qos: .userInitiated)

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
        callbacks.onVideoError(taskId: taskId, code: "compose_failed", message: err.localizedDescription)
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

    // Prepare overlay CIImage once
    let overlayCI: CIImage? = try Self.prepareOverlayCI(request: request, plugin: plugin, baseWidth: display.width, baseHeight: display.height)
    let overlayParams = (anchor: request.anchor, margin: request.margin, marginUnit: request.marginUnit, offsetX: request.offsetX, offsetY: request.offsetY, offsetUnit: request.offsetUnit)

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
    let bitrate = request.bitrateBps ?? Self.estimateBitrate(width: Int(display.width), height: Int(display.height), fps: Float(videoTrack.nominalFrameRate))
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: codec,
      AVVideoWidthKey: Int(display.width),
      AVVideoHeightKey: Int(display.height),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoProfileLevelKey: codec == .h264 ? AVVideoProfileLevelH264HighAutoLevel : AVVideoProfileLevelHEVCMainAutoLevel
      ]
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

    // Precompute overlay with opacity and translation in display coordinates
    let preparedOverlay: CIImage? = {
      guard let ov = overlayCI else { return nil }
      // Apply opacity
      let alphaVec = CIVector(x: 0, y: 0, z: 0, w: CGFloat(request.opacity))
      let withOpacity = ov.applyingFilter("CIColorMatrix", parameters: ["inputAVector": alphaVec])
      // Compute position
      let baseRect = CGRect(x: 0, y: 0, width: display.width, height: display.height)
      let wmRect = withOpacity.extent
      let marginX = (request.marginUnit == .percent) ? CGFloat(request.margin) * display.width : CGFloat(request.margin)
      let marginY = (request.marginUnit == .percent) ? CGFloat(request.margin) * display.height : CGFloat(request.margin)
      var pos = Self.positionRect(base: baseRect, overlay: wmRect, anchor: request.anchor, marginX: marginX, marginY: marginY)
      let dx = (request.offsetUnit == .percent) ? CGFloat(request.offsetX) * display.width : CGFloat(request.offsetX)
      let dy = (request.offsetUnit == .percent) ? CGFloat(request.offsetY) * display.height : CGFloat(request.offsetY)
      pos.x += dx
      pos.y += dy
      return withOpacity.transformed(by: CGAffineTransform(translationX: floor(pos.x), y: floor(pos.y)))
    }()

    // Processing loop
    var lastPTS = CMTime.zero
    while reader.status == .reading && !state.cancelled {
      autoreleasepool {
        if videoInput.isReadyForMoreMediaData, let sample = videoReaderOutput.copyNextSampleBuffer() {
          let pts = CMSampleBufferGetPresentationTimeStamp(sample)
          lastPTS = pts
          guard let pool = adaptor.pixelBufferPool else { return }
          var pb: CVPixelBuffer? = nil
          CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
          guard let dst = pb else { return }

          // Create base CIImage from sample
          if let srcPB = CMSampleBufferGetImageBuffer(sample) {
            let base = CIImage(cvPixelBuffer: srcPB)
            let output: CIImage
            if let overlay = preparedOverlay {
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
          callbacks.onVideoProgress(taskId: taskId, progress: p, etaSec: max(0.0, duration - CMTimeGetSeconds(pts)))
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
      callbacks.onVideoError(taskId: taskId, code: "cancelled", message: "Cancelled")
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
        callbacks.onVideoCompleted(result: res)
        onComplete(res)
      } else {
        let msg = writer.error?.localizedDescription ?? "Unknown writer error"
        callbacks.onVideoError(taskId: taskId, code: "encode_failed", message: msg)
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

  private static func prepareOverlayCI(request: ComposeVideoRequest, plugin: WatermarkKitPlugin, baseWidth: CGFloat, baseHeight: CGFloat) throws -> CIImage? {
    // Prefer watermarkImage; fallback to text
    if let data = request.watermarkImage?.data, !data.isEmpty {
      guard let src = decodeCIImage(from: data) else { return nil }
      // Scale by widthPercent of base width
      let targetW = max(1.0, baseWidth * CGFloat(request.widthPercent))
      let extent = src.extent
      let scale = targetW / max(1.0, extent.width)
      return src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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
      let targetW = max(1.0, baseWidth * CGFloat(request.widthPercent))
      let extent = src.extent
      let scale = targetW / max(1.0, extent.width)
      return src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    return nil
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

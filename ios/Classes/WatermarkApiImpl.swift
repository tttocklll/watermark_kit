import Foundation
import Flutter

// Pigeon generated API is in Messages.g.swift

final class WatermarkApiImpl: WatermarkApi {
  private weak var plugin: WatermarkKitPlugin?
  private let videoProcessor = VideoWatermarkProcessor()

  init(plugin: WatermarkKitPlugin) {
    self.plugin = plugin
  }

  func composeImage(request: ComposeImageRequest, completion: @escaping (Result<ComposeImageResult, Error>) -> Void) {
    guard let plugin = plugin else {
      completion(.failure(PigeonError(code: "plugin_missing", message: "Plugin instance deallocated", details: nil)))
      return
    }
    let anchorStr: String
    switch request.anchor {
    case .topLeft: anchorStr = "topLeft"
    case .topRight: anchorStr = "topRight"
    case .bottomLeft: anchorStr = "bottomLeft"
    case .bottomRight: anchorStr = "bottomRight"
    case .center: anchorStr = "center"
    }
    let formatStr = (request.format == .png) ? "png" : "jpeg"
    do {
      let (bytes, w, h) = try plugin.performCompose(
        baseData: request.baseImage.data,
        wmData: request.watermarkImage.data,
        anchor: anchorStr,
        margin: request.margin,
        widthPercent: request.widthPercent,
        opacity: request.opacity,
        format: formatStr,
        quality: request.quality,
        offsetX: request.offsetX,
        offsetY: request.offsetY,
        marginUnit: (request.marginUnit == .percent ? "percent" : "px"),
        offsetUnit: (request.offsetUnit == .percent ? "percent" : "px")
      )
      let res = ComposeImageResult(imageBytes: FlutterStandardTypedData(bytes: bytes), width: Int64(w), height: Int64(h))
      completion(.success(res))
    } catch let err {
      completion(.failure(PigeonError(code: "compose_failed", message: err.localizedDescription, details: nil)))
    }
  }

  func composeText(request: ComposeTextRequest, completion: @escaping (Result<ComposeImageResult, Error>) -> Void) {
    guard let plugin = plugin else {
      completion(.failure(PigeonError(code: "plugin_missing", message: "Plugin instance deallocated", details: nil)))
      return
    }
    // Map enums to the MethodChannel-compatible strings/units used by plugin helpers
    let anchorStr: String
    switch request.anchor {
    case .topLeft: anchorStr = "topLeft"
    case .topRight: anchorStr = "topRight"
    case .bottomLeft: anchorStr = "bottomLeft"
    case .bottomRight: anchorStr = "bottomRight"
    case .center: anchorStr = "center"
    }
    let formatStr = (request.format == .png) ? "png" : "jpeg"

    do {
      // Render text to CGImage using plugin helper
      guard let cg = try WatermarkKitPlugin.renderTextCGImage(
        text: request.text,
        fontFamily: request.textStyle.fontFamily,
        fontSizePt: request.textStyle.fontSizePt,
        fontWeight: Int(request.textStyle.fontWeight),
        colorArgb: UInt32(bitPattern: Int32(request.textStyle.colorArgb))
      ) else {
        throw PigeonError(code: "render_failed", message: "Failed to render text", details: nil)
      }
      guard let overlayData = WatermarkKitPlugin.encodePNG(cgImage: cg) else {
        throw PigeonError(code: "encode_failed", message: "Failed to encode text PNG", details: nil)
      }

      let (bytes, w, h) = try plugin.performCompose(
        baseData: request.baseImage.data,
        wmData: overlayData,
        anchor: anchorStr,
        margin: request.margin,
        widthPercent: request.widthPercent,
        opacity: request.style.opacity,
        format: formatStr,
        quality: request.quality,
        offsetX: request.offsetX,
        offsetY: request.offsetY,
        marginUnit: (request.marginUnit == .percent ? "percent" : "px"),
        offsetUnit: (request.offsetUnit == .percent ? "percent" : "px")
      )
      let res = ComposeImageResult(imageBytes: FlutterStandardTypedData(bytes: bytes), width: Int64(w), height: Int64(h))
      completion(.success(res))
    } catch let err {
      completion(.failure(PigeonError(code: "compose_text_failed", message: err.localizedDescription, details: nil)))
    }
  }

  // MARK: - Video
  func composeVideo(request: ComposeVideoRequest, completion: @escaping (Result<ComposeVideoResult, Error>) -> Void) {
    guard let plugin = plugin else {
      completion(.failure(PigeonError(code: "plugin_missing", message: "Plugin instance deallocated", details: nil)))
      return
    }
    guard let messenger = plugin.messenger else {
      completion(.failure(PigeonError(code: "messenger_missing", message: "Binary messenger unavailable", details: nil)))
      return
    }
    let callbacks = WatermarkCallbacks(binaryMessenger: messenger)
    let taskId = request.taskId ?? UUID().uuidString
    // Start async processing and fulfill the Pigeon completion via closures.
    videoProcessor.start(
      plugin: plugin,
      request: request,
      callbacks: callbacks,
      taskId: taskId,
      onComplete: { res in
        completion(.success(res))
      },
      onError: { code, message in
        completion(.failure(PigeonError(code: code, message: message, details: nil)))
      }
    )
  }

  func cancel(taskId: String) throws {
    videoProcessor.cancel(taskId: taskId)
  }
}

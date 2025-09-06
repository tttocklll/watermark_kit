import Foundation
import Flutter

// Pigeon generated API is in Messages.g.swift

final class WatermarkApiImpl: WatermarkApi {
  private weak var plugin: WatermarkKitPlugin?

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
}

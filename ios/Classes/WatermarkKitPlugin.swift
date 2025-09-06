import Flutter
import UIKit
import CoreImage
import ImageIO
import MobileCoreServices

public class WatermarkKitPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "watermark_kit", binaryMessenger: registrar.messenger())
    let instance = WatermarkKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Pigeon API setup
    WatermarkApiSetup.setUp(binaryMessenger: registrar.messenger(), api: WatermarkApiImpl(plugin: instance))
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "composeImage":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected map arguments", details: nil))
        return
      }
      composeImage(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private let ciContext: CIContext = {
    if let device = MTLCreateSystemDefaultDevice() {
      return CIContext(mtlDevice: device, options: [CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }
    return CIContext(options: [CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
  }()

  struct ComposeError: Error {
    let code: String
    let message: String
  }

  private func composeImage(args: [String: Any], result: @escaping FlutterResult) {
    guard let baseData = (args["inputImage"] as? FlutterStandardTypedData)?.data,
          let wmData = (args["watermarkImage"] as? FlutterStandardTypedData)?.data else {
      result(FlutterError(code: "invalid_arguments", message: "Missing inputImage or watermarkImage bytes", details: nil))
      return
    }
    let anchor = (args["anchor"] as? String) ?? "bottomRight"
    let margin = (args["margin"] as? NSNumber)?.doubleValue ?? 16.0
    let widthPercent = (args["widthPercent"] as? NSNumber)?.doubleValue ?? 0.18
    let opacity = (args["opacity"] as? NSNumber)?.doubleValue ?? 0.6
    let format = (args["format"] as? String) ?? "jpeg"
    let quality = min(max((args["quality"] as? NSNumber)?.doubleValue ?? 0.9, 0.0), 1.0)
    do {
      let (bytes, _, _) = try performCompose(
        baseData: baseData,
        wmData: wmData,
        anchor: anchor,
        margin: margin,
        widthPercent: widthPercent,
        opacity: opacity,
        format: format,
        quality: quality
      )
      result(FlutterStandardTypedData(bytes: bytes))
    } catch let err as ComposeError {
      result(FlutterError(code: err.code, message: err.message, details: nil))
    } catch {
      result(FlutterError(code: "compose_failed", message: error.localizedDescription, details: nil))
    }
  }

  // Shared composition used by MethodChannel and Pigeon
  func performCompose(baseData: Data, wmData: Data, anchor: String, margin: Double, widthPercent: Double, opacity: Double, format: String, quality: Double) throws -> (Data, Int, Int) {
    guard let baseCI = Self.decodeCIImage(from: baseData),
          let wmCIOriginal = Self.decodeCIImage(from: wmData) else {
      throw ComposeError(code: "decode_failed", message: "Failed to decode input images")
    }

    let baseExtent = baseCI.extent.integral
    let baseW = baseExtent.width
    let baseH = baseExtent.height
    if baseW <= 1 || baseH <= 1 {
      throw ComposeError(code: "invalid_image", message: "Base image too small")
    }

    // Scale watermark to widthPercent * baseWidth
    let targetW = max(1.0, baseW * CGFloat(widthPercent))
    let wmExtent = wmCIOriginal.extent
    let scale = targetW / max(wmExtent.width, 1.0)
    let scaled = wmCIOriginal.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    // Apply opacity using CIColorMatrix on alpha
    let alphaVec = CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
    let wmWithOpacity = scaled.applyingFilter("CIColorMatrix", parameters: ["inputAVector": alphaVec])

    // Compute position by anchor
    let wmRect = wmWithOpacity.extent
    let pos = Self.positionRect(base: baseExtent, overlay: wmRect, anchor: anchor, margin: CGFloat(margin))
    let translated = wmWithOpacity.transformed(by: CGAffineTransform(translationX: floor(pos.x), y: floor(pos.y)))

    // Composite
    guard let filter = CIFilter(name: "CISourceOverCompositing") else {
      throw ComposeError(code: "filter_error", message: "CISourceOverCompositing unavailable")
    }
    filter.setValue(translated, forKey: kCIInputImageKey)
    filter.setValue(baseCI, forKey: kCIInputBackgroundImageKey)
    guard let output = filter.outputImage else {
      throw ComposeError(code: "compose_failed", message: "Failed to compose image")
    }

    // Render to CGImage
    guard let cg = ciContext.createCGImage(output, from: baseExtent) else {
      throw ComposeError(code: "render_failed", message: "Failed to render image")
    }

    // Encode to requested format
    if format.lowercased() == "png" {
      guard let data = Self.encodePNG(cgImage: cg) else {
        throw ComposeError(code: "encode_failed", message: "Failed to encode PNG")
      }
      return (data, Int(baseW), Int(baseH))
    } else {
      guard let data = Self.encodeJPEG(cgImage: cg, quality: quality) else {
        throw ComposeError(code: "encode_failed", message: "Failed to encode JPEG")
      }
      return (data, Int(baseW), Int(baseH))
    }
  }

  private static func decodeCIImage(from data: Data) -> CIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let exif = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    var image: CIImage?
    if let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
      image = CIImage(cgImage: cg)
    } else {
      image = CIImage(data: data)
    }
    guard let base = image else { return nil }
    // Apply EXIF orientation to normalize to .up
    return base.oriented(forExifOrientation: Int32(exif))
  }

  private static func encodeJPEG(cgImage: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }

  private static func encodePNG(cgImage: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, kUTTypePNG, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }

  private static func positionRect(base: CGRect, overlay: CGRect, anchor: String, margin: CGFloat) -> CGPoint {
    let w = overlay.width
    let h = overlay.height
    switch anchor {
    case "topLeft":
      return CGPoint(x: base.minX + margin, y: base.maxY - margin - h)
    case "topRight":
      return CGPoint(x: base.maxX - margin - w, y: base.maxY - margin - h)
    case "bottomLeft":
      return CGPoint(x: base.minX + margin, y: base.minY + margin)
    case "center":
      return CGPoint(x: base.midX - w * 0.5, y: base.midY - h * 0.5)
    default: // bottomRight
      return CGPoint(x: base.maxX - margin - w, y: base.minY + margin)
    }
  }
}

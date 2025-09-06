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
    case "composeText":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected map arguments", details: nil))
        return
      }
      composeText(args: args, result: result)
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
    let offsetX = (args["offsetX"] as? NSNumber)?.doubleValue ?? 0.0
    let offsetY = (args["offsetY"] as? NSNumber)?.doubleValue ?? 0.0
    let marginUnit = (args["marginUnit"] as? String) ?? "px"
    let offsetUnit = (args["offsetUnit"] as? String) ?? "px"
    do {
      let (bytes, _, _) = try performCompose(
        baseData: baseData,
        wmData: wmData,
        anchor: anchor,
        margin: margin,
        widthPercent: widthPercent,
        opacity: opacity,
        format: format,
        quality: quality,
        offsetX: offsetX,
        offsetY: offsetY,
        marginUnit: marginUnit,
        offsetUnit: offsetUnit
      )
      result(FlutterStandardTypedData(bytes: bytes))
    } catch let err as ComposeError {
      result(FlutterError(code: err.code, message: err.message, details: nil))
    } catch {
      result(FlutterError(code: "compose_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func composeText(args: [String: Any], result: @escaping FlutterResult) {
    guard let baseData = (args["inputImage"] as? FlutterStandardTypedData)?.data,
          let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "invalid_arguments", message: "Missing inputImage or empty text", details: nil))
      return
    }
    let anchor = (args["anchor"] as? String) ?? "bottomRight"
    let margin = (args["margin"] as? NSNumber)?.doubleValue ?? 16.0
    let marginUnit = (args["marginUnit"] as? String) ?? "px"
    let offsetX = (args["offsetX"] as? NSNumber)?.doubleValue ?? 0.0
    let offsetY = (args["offsetY"] as? NSNumber)?.doubleValue ?? 0.0
    let offsetUnit = (args["offsetUnit"] as? String) ?? "px"
    let widthPercent = (args["widthPercent"] as? NSNumber)?.doubleValue ?? 0.18
    let opacity = (args["opacity"] as? NSNumber)?.doubleValue ?? 0.6
    let format = (args["format"] as? String) ?? "jpeg"
    let quality = min(max((args["quality"] as? NSNumber)?.doubleValue ?? 0.9, 0.0), 1.0)
    let fontFamily = (args["fontFamily"] as? String) ?? ".SFUI"
    let fontSizePt = (args["fontSizePt"] as? NSNumber)?.doubleValue ?? 24.0
    let fontWeight = (args["fontWeight"] as? NSNumber)?.intValue ?? 600
    let colorArgb = (args["colorArgb"] as? NSNumber)?.uint32Value ?? 0xFFFFFFFF

    do {
      // Render text -> PNG bytes as overlay, then reuse existing compose pipeline
      guard let cg = try Self.renderTextCGImage(text: text, fontFamily: fontFamily, fontSizePt: fontSizePt, fontWeight: fontWeight, colorArgb: colorArgb) else {
        throw ComposeError(code: "render_failed", message: "Failed to render text")
      }
      guard let overlayData = Self.encodePNG(cgImage: cg) else {
        throw ComposeError(code: "encode_failed", message: "Failed to encode text PNG")
      }
      let (bytes, _, _) = try performCompose(
        baseData: baseData,
        wmData: overlayData,
        anchor: anchor,
        margin: margin,
        widthPercent: widthPercent,
        opacity: opacity,
        format: format,
        quality: quality,
        offsetX: offsetX,
        offsetY: offsetY,
        marginUnit: marginUnit,
        offsetUnit: offsetUnit
      )
      result(FlutterStandardTypedData(bytes: bytes))
    } catch let err as ComposeError {
      result(FlutterError(code: err.code, message: err.message, details: nil))
    } catch {
      result(FlutterError(code: "compose_text_failed", message: error.localizedDescription, details: nil))
    }
  }

  // Shared composition used by MethodChannel and Pigeon
  func performCompose(baseData: Data, wmData: Data, anchor: String, margin: Double, widthPercent: Double, opacity: Double, format: String, quality: Double, offsetX: Double, offsetY: Double, marginUnit: String = "px", offsetUnit: String = "px") throws -> (Data, Int, Int) {
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

    // Compute position by anchor with units
    let wmRect = wmWithOpacity.extent
    let marginX = (marginUnit == "percent") ? CGFloat(margin) * baseW : CGFloat(margin)
    let marginY = (marginUnit == "percent") ? CGFloat(margin) * baseH : CGFloat(margin)
    var pos = Self.positionRect(base: baseExtent, overlay: wmRect, anchor: anchor, marginX: marginX, marginY: marginY)
    let dx = (offsetUnit == "percent") ? CGFloat(offsetX) * baseW : CGFloat(offsetX)
    let dy = (offsetUnit == "percent") ? CGFloat(offsetY) * baseH : CGFloat(offsetY)
    pos.x += dx
    pos.y += dy
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
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
      return nil
    }
    // Normalize orientation by creating CIImage from CGImage
    return CIImage(cgImage: cg, options: [.applyOrientationProperty: true])
  }

  // MARK: - Text Rendering (single-line)
  private static func renderTextCGImage(text: String, fontFamily: String, fontSizePt: Double, fontWeight: Int, colorArgb: UInt32) throws -> CGImage? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }

    let weight = Self.uiFontWeight(from: fontWeight)
    let font: UIFont
    if fontFamily == ".SFUI" || fontFamily.isEmpty {
      font = UIFont.systemFont(ofSize: CGFloat(fontSizePt), weight: weight)
    } else if let f = UIFont(name: fontFamily, size: CGFloat(fontSizePt)) {
      font = f
    } else {
      font = UIFont.systemFont(ofSize: CGFloat(fontSizePt), weight: weight)
    }

    let color = Self.uiColorFromARGB(colorArgb)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color
    ]
    let attr = NSAttributedString(string: trimmed, attributes: attrs)

    // Measure using CoreText for accurate ascent/descent
    let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
    let ctAttrs: [NSAttributedString.Key: Any] = [
      .font: ctFont,
      .foregroundColor: color.cgColor
    ]
    let ctAttr = NSAttributedString(string: trimmed, attributes: ctAttrs)
    let line = CTLineCreateWithAttributedString(ctAttr)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let height = ascent + descent
    let padding: CGFloat = 4.0
    let scale: CGFloat = 2.0
    let wPx = max(1, Int(ceil((width + padding * 2) * scale)))
    let hPx = max(1, Int(ceil((height + padding * 2) * scale)))

    guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    guard let ctx = CGContext(data: nil, width: wPx, height: hPx, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setFillColor(UIColor.clear.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(wPx), height: CGFloat(hPx)))

    // Draw with baseline at (pad + descent)
    ctx.saveGState()
    // Work in pixel units, no flip, CoreText expects y-up — so we directly set text matrix to identity.
    ctx.textMatrix = .identity
    ctx.translateBy(x: 0, y: 0)

    // Draw fill text using UIKit shortcut for crisp glyph rasterization at 2x
    UIGraphicsBeginImageContextWithOptions(CGSize(width: CGFloat(wPx) / scale, height: CGFloat(hPx) / scale), false, scale)
    attr.draw(at: CGPoint(x: padding, y: padding))
    let uiImg = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    if let cg = uiImg?.cgImage {
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(wPx), height: CGFloat(hPx)))
    } else {
      // Fallback to CoreText draw at baseline
      ctx.setFillColor(color.cgColor)
      ctx.textPosition = CGPoint(x: padding * scale, y: (padding + descent) * scale)
      CTLineDraw(line, ctx)
    }

    ctx.restoreGState()
    return ctx.makeImage()
  }

  private static func uiFontWeight(from val: Int) -> UIFont.Weight {
    switch val {
    case ..<200: return .ultraLight
    case 200..<300: return .thin
    case 300..<400: return .light
    case 400..<500: return .regular
    case 500..<600: return .medium
    case 600..<700: return .semibold
    case 700..<800: return .bold
    case 800..<900: return .heavy
    default: return .black
    }
  }

  private static func uiColorFromARGB(_ argb: UInt32) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
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

  private static func positionRect(base: CGRect, overlay: CGRect, anchor: String, marginX: CGFloat, marginY: CGFloat) -> CGPoint {
    let w = overlay.width
    let h = overlay.height
    switch anchor {
    case "topLeft":
      return CGPoint(x: base.minX + marginX, y: base.maxY - marginY - h)
    case "topRight":
      return CGPoint(x: base.maxX - marginX - w, y: base.maxY - marginY - h)
    case "bottomLeft":
      return CGPoint(x: base.minX + marginX, y: base.minY + marginY)
    case "center":
      return CGPoint(x: base.midX - w * 0.5, y: base.midY - h * 0.5)
    default: // bottomRight
      return CGPoint(x: base.maxX - marginX - w, y: base.minY + marginY)
    }
  }
}

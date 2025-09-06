package com.tttocklll.watermark_kit

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

internal class WatermarkApiImpl(
  private val context: Context,
  private val messenger: BinaryMessenger,
) : WatermarkApi {

  override fun composeImage(request: ComposeImageRequest, callback: (Result<ComposeImageResult>) -> Unit) {
    try {
      val res = ImageWatermarker.compose(
        baseBytes = request.baseImage,
        wmBytes = request.watermarkImage,
        anchor = request.anchor,
        margin = request.margin,
        marginUnit = request.marginUnit,
        offsetX = request.offsetX,
        offsetY = request.offsetY,
        offsetUnit = request.offsetUnit,
        widthPercent = request.widthPercent,
        opacity = request.opacity,
        format = request.format,
        quality = request.quality,
      )
      callback(Result.success(ComposeImageResult(res.bytes, res.width.toLong(), res.height.toLong())))
    } catch (t: Throwable) {
      callback(Result.failure(t))
    }
  }

  override fun composeText(request: ComposeTextRequest, callback: (Result<ComposeImageResult>) -> Unit) {
    try {
      val targetW = (request.widthPercent * guessBaseWidth(request.baseImage)).toInt().coerceAtLeast(1)
      val overlay = TextRasterizer.rasterizeToPng(
        text = request.text,
        fontFamily = request.textStyle.fontFamily,
        targetWidthPx = targetW,
        fontWeight = request.textStyle.fontWeight.toInt(),
        colorArgb = request.textStyle.colorArgb,
      )
      val res = ImageWatermarker.compose(
        baseBytes = request.baseImage,
        wmBytes = overlay,
        anchor = request.anchor,
        margin = request.margin,
        marginUnit = request.marginUnit,
        offsetX = request.offsetX,
        offsetY = request.offsetY,
        offsetUnit = request.offsetUnit,
        widthPercent = 1.0, // overlay already sized
        opacity = request.style.opacity,
        format = request.format,
        quality = request.quality,
      )
      callback(Result.success(ComposeImageResult(res.bytes, res.width.toLong(), res.height.toLong())))
    } catch (t: Throwable) {
      callback(Result.failure(t))
    }
  }

  override fun composeVideo(request: ComposeVideoRequest, callback: (Result<ComposeVideoResult>) -> Unit) {
    // Not yet implemented on Android. Provide a clear error.
    callback(Result.failure(FlutterError("unimplemented", "Android video watermarking is not implemented yet.", null)))
  }

  override fun cancel(taskId: String) {
    // No-op until video pipeline is implemented.
  }

  private fun guessBaseWidth(baseImageBytes: ByteArray): Double {
    // Fast decode bounds only
    val opts = android.graphics.BitmapFactory.Options()
    opts.inJustDecodeBounds = true
    android.graphics.BitmapFactory.decodeByteArray(baseImageBytes, 0, baseImageBytes.size, opts)
    return (opts.outWidth.takeIf { it > 0 } ?: 1024).toDouble()
  }
}

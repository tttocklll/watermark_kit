package com.tttocklll.watermark_kit

import android.graphics.*
import java.io.ByteArrayOutputStream

internal object ImageWatermarker {
  data class Result(val bytes: ByteArray, val width: Int, val height: Int)

  fun compose(
    baseBytes: ByteArray,
    wmBytes: ByteArray,
    anchor: Anchor,
    margin: Double,
    marginUnit: MeasureUnit,
    offsetX: Double,
    offsetY: Double,
    offsetUnit: MeasureUnit,
    widthPercent: Double,
    opacity: Double,
    format: OutputFormat,
    quality: Double,
  ): Result {
    val base = BitmapFactory.decodeByteArray(baseBytes, 0, baseBytes.size)
      ?: throw FlutterError("decode_failed", "Failed to decode base image", null)
    val wmSrc = BitmapFactory.decodeByteArray(wmBytes, 0, wmBytes.size)
      ?: throw FlutterError("decode_failed", "Failed to decode watermark image", null)

    val targetW = (base.width * widthPercent).coerceAtLeast(1.0).toFloat()
    val scale = targetW / wmSrc.width.coerceAtLeast(1)
    val wmW = (wmSrc.width * scale).toInt().coerceAtLeast(1)
    val wmH = (wmSrc.height * scale).toInt().coerceAtLeast(1)

    val out = Bitmap.createBitmap(base.width, base.height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    canvas.drawBitmap(base, 0f, 0f, null)

    // Use high-quality filtering for scaling and drawing
    val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
    p.alpha = (opacity * 255.0).toInt().coerceIn(0, 255)

    val pos = AnchorUtil.computePosition(
      base.width,
      base.height,
      wmW,
      wmH,
      anchor,
      margin,
      marginUnit,
      offsetX,
      offsetY,
      offsetUnit,
    )

    // Draw watermark with high-quality scaling using Matrix
    val matrix = Matrix()
    matrix.postScale(scale, scale)
    matrix.postTranslate(pos.x, pos.y)
    canvas.drawBitmap(wmSrc, matrix, p)

    val bos = ByteArrayOutputStream()
    val ok = when (format) {
      OutputFormat.PNG -> out.compress(Bitmap.CompressFormat.PNG, 100, bos)
      OutputFormat.JPEG -> out.compress(Bitmap.CompressFormat.JPEG, (quality * 100).toInt().coerceIn(1, 100), bos)
    }
    val resultWidth = base.width
    val resultHeight = base.height
    wmSrc.recycle()
    base.recycle()
    out.recycle()
    if (!ok) throw FlutterError("encode_failed", "Failed to encode output image", null)
    return Result(bos.toByteArray(), resultWidth, resultHeight)
  }
}

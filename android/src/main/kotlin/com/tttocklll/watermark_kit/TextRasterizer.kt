package com.tttocklll.watermark_kit

import android.graphics.*
import java.io.ByteArrayOutputStream

internal object TextRasterizer {
  fun rasterizeToPng(
    text: String,
    fontFamily: String,
    targetWidthPx: Int,
    fontWeight: Int,
    colorArgb: Long,
  ): ByteArray {
    val clean = text.trim()
    if (clean.isEmpty()) return ByteArray(0)

    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    paint.color = argbToColorInt(colorArgb)
    paint.isSubpixelText = true
    paint.textAlign = Paint.Align.LEFT
    paint.typeface = Typeface.create(fontFamily.ifEmpty { Typeface.SANS_SERIF.toString() }, mapWeight(fontWeight))

    // Initial guess for size then scale to fit target width.
    paint.textSize = 48f
    val initW = paint.measureText(clean).coerceAtLeast(1f)
    val scale = targetWidthPx / initW
    paint.textSize = (paint.textSize * scale).coerceIn(6f, 512f)

    val fm = paint.fontMetrics
    val textH = (fm.descent - fm.ascent)
    val pad = 4f
    val outW = targetWidthPx.coerceAtLeast(1)
    val outH = kotlin.math.ceil(textH + pad * 2).toInt().coerceAtLeast(1)

    val bmp = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    c.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
    val baseline = pad - fm.ascent
    c.drawText(clean, 0f, baseline, paint)

    val bos = ByteArrayOutputStream()
    bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
    bmp.recycle()
    return bos.toByteArray()
  }

  private fun argbToColorInt(argb: Long): Int {
    val a = ((argb shr 24) and 0xFF).toInt()
    val r = ((argb shr 16) and 0xFF).toInt()
    val g = ((argb shr 8) and 0xFF).toInt()
    val b = (argb and 0xFF).toInt()
    return Color.argb(a, r, g, b)
  }

  private fun mapWeight(w: Int): Int {
    return when {
      w < 200 -> Typeface.EXTRA_LIGHT
      w < 300 -> Typeface.THIN
      w < 400 -> Typeface.LIGHT
      w < 500 -> Typeface.NORMAL
      w < 600 -> Typeface.MEDIUM
      w < 700 -> Typeface.BOLD
      w < 800 -> Typeface.BOLD
      w < 900 -> Typeface.BLACK
      else -> Typeface.BLACK
    }
  }
}


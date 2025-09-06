package com.tttocklll.watermark_kit

import android.graphics.PointF

internal object AnchorUtil {
  fun computePosition(
    baseW: Int,
    baseH: Int,
    overlayW: Int,
    overlayH: Int,
    anchor: Anchor,
    margin: Double,
    marginUnit: MeasureUnit,
    offsetX: Double,
    offsetY: Double,
    offsetUnit: MeasureUnit,
  ): PointF {
    val bw = baseW.toFloat()
    val bh = baseH.toFloat()
    val ow = overlayW.toFloat()
    val oh = overlayH.toFloat()

    val mx = if (marginUnit == MeasureUnit.PERCENT) (margin * bw).toFloat() else margin.toFloat()
    val my = if (marginUnit == MeasureUnit.PERCENT) (margin * bh).toFloat() else margin.toFloat()

    val dx = if (offsetUnit == MeasureUnit.PERCENT) (offsetX * bw).toFloat() else offsetX.toFloat()
    val dy = if (offsetUnit == MeasureUnit.PERCENT) (offsetY * bh).toFloat() else offsetY.toFloat()

    val p = when (anchor) {
      // Android Canvas is top-left origin (y grows down)
      Anchor.TOP_LEFT -> PointF(mx, my)
      Anchor.TOP_RIGHT -> PointF(bw - mx - ow, my)
      Anchor.BOTTOM_LEFT -> PointF(mx, bh - my - oh)
      Anchor.CENTER -> PointF(bw * 0.5f - ow * 0.5f, bh * 0.5f - oh * 0.5f)
      Anchor.BOTTOM_RIGHT -> PointF(bw - mx - ow, bh - my - oh)
    }
    p.x = kotlin.math.floor(p.x + dx)
    p.y = kotlin.math.floor(p.y + dy)
    return p
  }
}

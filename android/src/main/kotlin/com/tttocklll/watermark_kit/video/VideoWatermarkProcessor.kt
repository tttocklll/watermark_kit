package com.tttocklll.watermark_kit.video

import android.content.Context
import android.graphics.BitmapFactory
import android.media.*
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import com.tttocklll.watermark_kit.*
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

internal class VideoWatermarkProcessor(private val appContext: Context) {
  private val thread = HandlerThread("wm.video").apply { start() }
  private val handler = Handler(thread.looper)
  private val main = Handler(Looper.getMainLooper())

  private data class Task(
    val req: ComposeVideoRequest,
    val outPath: String,
    @Volatile var cancelled: Boolean = false
  )
  private val tasks = ConcurrentHashMap<String, Task>()

  fun start(
    request: ComposeVideoRequest,
    callbacks: WatermarkCallbacks,
    onCompleted: (ComposeVideoResult) -> Unit,
    onError: (String, String) -> Unit
  ) {
    val taskId = request.taskId ?: System.currentTimeMillis().toString()
    val out = request.outputVideoPath?.takeIf { it.isNotEmpty() } ?: run {
      val dir = appContext.getExternalFilesDir(null) ?: appContext.cacheDir
      File(dir, "wm_${taskId}.mp4").absolutePath
    }
    val task = Task(request.copy(taskId = taskId), out)
    tasks[taskId] = task
    handler.post {
      try {
        process(task, callbacks, onCompleted)
      } catch (t: Throwable) {
        Log.e("WM", "Video compose failed", t)
        safeError(callbacks, taskId, "compose_failed", t.message ?: "Unknown error")
        onError("compose_failed", t.message ?: "Unknown error")
      } finally {
        tasks.remove(taskId)
      }
    }
  }

  fun cancel(taskId: String) { tasks[taskId]?.cancelled = true }

  private fun process(task: Task, callbacks: WatermarkCallbacks, onCompleted: (ComposeVideoResult) -> Unit) {
    val req = task.req
    val taskId = req.taskId!!

    val extractor = MediaExtractor()
    extractor.setDataSource(req.inputVideoPath)
    val (videoTrack, audioTrack) = selectTracks(extractor)
    if (videoTrack < 0) throw IllegalArgumentException("No video track")
    extractor.selectTrack(videoTrack)

    val vFmt = extractor.getTrackFormat(videoTrack)
    val rotation = if (vFmt.containsKey(MediaFormat.KEY_ROTATION)) vFmt.getInteger(MediaFormat.KEY_ROTATION) else 0
    val srcW = vFmt.getInteger(MediaFormat.KEY_WIDTH)
    val srcH = vFmt.getInteger(MediaFormat.KEY_HEIGHT)
    val displayW = if (rotation % 180 != 0) srcH else srcW
    val displayH = if (rotation % 180 != 0) srcW else srcH

    val encWH = chooseEncodeSize(displayW, displayH, req.maxLongSide?.toInt())
    val encW = encWH.first; val encH = encWH.second
    val fpsGuess = guessFps(vFmt)
    val bitrate = (req.bitrateBps?.toInt() ?: estimateBitrate(encW, encH, fpsGuess))
    val videoCodec = when (req.codec) {
      VideoCodec.HEVC -> "video/hevc"
      else -> "video/avc"
    }
    if (!isCodecAvailable(videoCodec)) {
      if (req.codec == VideoCodec.HEVC && isCodecAvailable("video/avc")) {
        // fallback to AVC
      } else {
        throw RuntimeException("device_not_supported: $videoCodec")
      }
    }

    val muxer = MediaMuxer(task.outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    // Add audio track if present
    val audioExtractor = MediaExtractor()
    var audioTrackIndexMuxer = -1
    if (audioTrack >= 0) {
      audioExtractor.setDataSource(req.inputVideoPath)
      audioExtractor.selectTrack(audioTrack)
      val aFmt = audioExtractor.getTrackFormat(audioTrack)
      audioTrackIndexMuxer = muxer.addTrack(aFmt)
    }

    // Encoder config
    val encFmt = MediaFormat.createVideoFormat(videoCodec, encW, encH).apply {
      setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
      setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
      setInteger(MediaFormat.KEY_FRAME_RATE, max(1, (req.maxFps ?: fpsGuess).toInt()))
      setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
    }
    val encoder = MediaCodec.createEncoderByType(videoCodec)
    encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    val inputSurface = encoder.createInputSurface()
    encoder.start()

    // GL
    val gl = GlRenderer()
    gl.init()
    gl.setEncoderSurface(inputSurface)
    gl.makeCurrent()

    // Overlay texture
    val overlayInfo = prepareOverlay(req, displayW, displayH)
    val overlayTexId = overlayInfo?.let { bmp ->
      val id = gl.create2DTextureFromBitmap(bmp.bitmap)
      bmp.bitmap.recycle()
      id
    } ?: -1

    // Decoder to Surface
    val decoder = MediaCodec.createDecoderByType(vFmt.getString(MediaFormat.KEY_MIME)!!)
    decoder.configure(vFmt, gl.getDecoderSurface(), null, 0)
    decoder.start()

    var videoTrackIndexMuxer = -1
    var muxerStarted = false

    val startUs = 0L
    var durationUs = extractor.getSampleTimeDurationUs(videoTrack)
    if (durationUs <= 0) durationUs = 1_000_000L

    val info = MediaCodec.BufferInfo()
    var sawInputEOS = false
    var sawOutputEOS = false

    // Prepare to read video
    extractor.unselectAll()
    extractor.selectTrack(videoTrack)

    while (!task.cancelled && !sawOutputEOS) {
      // Feed decoder input
      if (!sawInputEOS) {
        val inIndex = decoder.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
          val buf = decoder.getInputBuffer(inIndex)!!
          val sampleSize = extractor.readSampleData(buf, 0)
          if (sampleSize < 0) {
            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            sawInputEOS = true
          } else {
            val pts = extractor.sampleTime
            decoder.queueInputBuffer(inIndex, 0, sampleSize, max(0, pts), 0)
            extractor.advance()
          }
        }
      }

      // Drain decoder output
      val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
      when {
        outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {}
        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
          // ignore
        }
        outIndex >= 0 -> {
          val render = info.size > 0
          decoder.releaseOutputBuffer(outIndex, render)
          if (render) {
            val stMatrix = gl.updateDecoderTexImage()
            // Draw into encoder surface
            gl.makeCurrent()
            gl.drawVideoFrame(stMatrix, rotation, encW, encH)
            overlayInfo?.let { ov ->
              gl.drawOverlay(ov.posX, ov.posY, ov.wPx, ov.hPx, encW, encH, overlayTexId, req.opacity.toFloat())
            }
            gl.setPresentationTime(info.presentationTimeUs * 1000)

            // Start muxer once encoder has output format
            if (!muxerStarted && videoTrackIndexMuxer == -1) {
              // allow encoder to produce format
            }

            gl.swapBuffers()
          }
        }
      }

      // Drain encoder output
      var encOut = true
      while (encOut) {
        val eIndex = encoder.dequeueOutputBuffer(info, 0)
        when {
          eIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> encOut = false
          eIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
            val newFmt = encoder.outputFormat
            videoTrackIndexMuxer = muxer.addTrack(newFmt)
            if (!muxerStarted) {
              muxer.start()
              muxerStarted = true
              // Start copying audio (best-effort) in background
              if (audioTrackIndexMuxer >= 0) {
                copyAudioAsync(audioExtractor, muxer, audioTrackIndexMuxer)
              }
            }
          }
          eIndex >= 0 -> {
            val outBuf = encoder.getOutputBuffer(eIndex)!!
            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
              info.size = 0
            }
            if (info.size > 0 && muxerStarted) {
              outBuf.position(info.offset)
              outBuf.limit(info.offset + info.size)
              muxer.writeSampleData(videoTrackIndexMuxer, outBuf, info)
              // progress
              val p = info.presentationTimeUs.toDouble() / max(1.0, durationUs.toDouble())
              safeProgress(callbacks, req.taskId!!, p.coerceIn(0.0, 1.0), max(0.0, (durationUs - info.presentationTimeUs) / 1_000_000.0))
            }
            encoder.releaseOutputBuffer(eIndex, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
              sawOutputEOS = true
              encOut = false
            }
          }
        }
      }
    }

    // finalize
    decoder.stop(); decoder.release()
    encoder.signalEndOfInputStream()
    // drain remaining encoder
    var draining = true
    val finInfo = MediaCodec.BufferInfo()
    while (draining) {
      val idx = encoder.dequeueOutputBuffer(finInfo, 10_000)
      when {
        idx == MediaCodec.INFO_TRY_AGAIN_LATER -> draining = false
        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { /* already handled */ }
        idx >= 0 -> {
          val out = encoder.getOutputBuffer(idx)!!
          if (finInfo.size > 0 && muxerStarted) muxer.writeSampleData(videoTrackIndexMuxer, out, finInfo)
          encoder.releaseOutputBuffer(idx, false)
          if (finInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) draining = false
        }
      }
    }
    encoder.stop(); encoder.release()
    if (muxerStarted) muxer.stop()
    muxer.release()
    audioExtractor.release()
    extractor.release()
    gl.release()

    if (task.cancelled) {
      File(task.outPath).delete()
      safeError(callbacks, taskId, "cancelled", "Cancelled")
      return
    }

    val res = ComposeVideoResult(taskId, task.outPath, encW.toLong(), encH.toLong(), max(1, (durationUs / 1000).toInt()).toLong(), req.codec)
    safeCompleted(callbacks, res)
    onCompleted(res)
  }

  private fun selectTracks(extractor: MediaExtractor): Pair<Int, Int> {
    var v = -1; var a = -1
    for (i in 0 until extractor.trackCount) {
      val fmt = extractor.getTrackFormat(i)
      val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
      if (mime.startsWith("video/") && v < 0) v = i
      else if (mime.startsWith("audio/") && a < 0) a = i
    }
    return v to a
  }

  private data class Overlay(val bitmap: android.graphics.Bitmap, val posX: Float, val posY: Float, val wPx: Float, val hPx: Float)

  private fun prepareOverlay(req: ComposeVideoRequest, baseW: Int, baseH: Int): Overlay? {
    val overlayBytes = when {
      req.watermarkImage != null && req.watermarkImage!!.isNotEmpty() -> req.watermarkImage!!
      req.text != null && req.text!!.isNotBlank() -> {
        val targetW = (baseW * req.widthPercent).toInt().coerceAtLeast(1)
        val png = com.tttocklll.watermark_kit.TextRasterizer.rasterizeToPng(
          text = req.text!!,
          fontFamily = ".SFUI",
          targetWidthPx = targetW,
          fontWeight = 600,
          colorArgb = 0xFFFFFFFF,
        )
        png
      }
      else -> null
    } ?: return null
    val bmp = BitmapFactory.decodeByteArray(overlayBytes, 0, overlayBytes.size) ?: return null
    val wTarget = (baseW * req.widthPercent).toFloat().coerceAtLeast(1f)
    val scale = wTarget / max(1, bmp.width)
    val wmW = (bmp.width * scale)
    val wmH = (bmp.height * scale)
    val pos = AnchorUtil.computePosition(baseW, baseH, wmW.toInt(), wmH.toInt(), req.anchor, req.margin, req.marginUnit, req.offsetX, req.offsetY, req.offsetUnit)
    return Overlay(bmp, pos.x, pos.y, wmW, wmH)
  }

  private fun guessFps(fmt: MediaFormat): Double {
    return if (fmt.containsKey(MediaFormat.KEY_FRAME_RATE)) fmt.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble() else 30.0
  }

  private fun estimateBitrate(w: Int, h: Int, fps: Double): Int {
    val bpp = 0.08
    val br = bpp * w * h * max(24.0, fps)
    return max(500_000, br.toInt())
  }

  private fun isCodecAvailable(mime: String): Boolean {
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    return list.codecInfos.any { it.isEncoder && it.supportedTypes.contains(mime) }
  }

  private fun chooseEncodeSize(w: Int, h: Int, maxLongSide: Int?): Pair<Int, Int> {
    if (maxLongSide == null || maxLongSide <= 0) return w to h
    val long = max(w, h).toFloat()
    if (long <= maxLongSide) return w to h
    val scale = maxLongSide / long
    val rw = (w * scale).toInt().coerceAtLeast(1)
    val rh = (h * scale).toInt().coerceAtLeast(1)
    return rw to rh
  }

  private fun safeProgress(cb: WatermarkCallbacks, taskId: String, p: Double, eta: Double) {
    main.post { cb.onVideoProgress(taskId, p, eta) { } }
  }
  private fun safeCompleted(cb: WatermarkCallbacks, res: ComposeVideoResult) {
    main.post { cb.onVideoCompleted(res) { } }
  }
  private fun safeError(cb: WatermarkCallbacks, taskId: String, code: String, message: String) {
    main.post { cb.onVideoError(taskId, code, message) { } }
  }

  private fun MediaExtractor.unselectAll() {
    for (i in 0 until trackCount) try { unselectTrack(i) } catch (_: Throwable) {}
  }

  private fun MediaExtractor.getSampleTimeDurationUs(videoTrack: Int): Long {
    var dur = 0L
    try {
      val fmt = getTrackFormat(videoTrack)
      if (fmt.containsKey(MediaFormat.KEY_DURATION)) dur = fmt.getLong(MediaFormat.KEY_DURATION)
    } catch (_: Throwable) {}
    if (dur > 0) return dur
    // fallback scan (coarse)
    val pos = sampleTime
    var last = 0L
    val tk = videoTrack
    val save = this.sampleTime
    unselectAll(); selectTrack(tk)
    while (true) {
      val size = readSampleData(ByteBuffer.allocate(1), 0)
      if (size < 0) break
      last = sampleTime
      advance()
    }
    unselectAll(); selectTrack(tk)
    seekTo(save, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
    return max(1_000_000L, last)
  }

  private fun copyAudioAsync(audioExtractor: MediaExtractor, muxer: MediaMuxer, trackIndex: Int) {
    Thread {
      val buf = ByteBuffer.allocate(262144)
      val info = MediaCodec.BufferInfo()
      while (true) {
        val size = audioExtractor.readSampleData(buf, 0)
        if (size < 0) break
        info.offset = 0
        info.size = size
        info.presentationTimeUs = max(0, audioExtractor.sampleTime)
        info.flags = if (audioExtractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
        try {
          muxer.writeSampleData(trackIndex, buf, info)
        } catch (_: Throwable) { /* ignore */ }
        audioExtractor.advance()
      }
      audioExtractor.release()
    }.start()
  }
}

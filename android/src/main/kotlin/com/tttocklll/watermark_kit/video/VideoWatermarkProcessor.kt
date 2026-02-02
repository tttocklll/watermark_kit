package com.tttocklll.watermark_kit.video

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import android.graphics.PorterDuff
import android.media.*
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.tttocklll.watermark_kit.WMLog
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
        WMLog.e("Video compose failed", t)
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
    // Normalize decoder format: for DV, strip dv-specific csd and map to HEVC; also strip rotation and handle in GL.
    var inMime = vFmt.getString(MediaFormat.KEY_MIME) ?: "video/avc"
    val hadRotation = vFmt.containsKey(MediaFormat.KEY_ROTATION)
    val rotation = if (hadRotation) vFmt.getInteger(MediaFormat.KEY_ROTATION) else 0
    if (hadRotation) {
      try { vFmt.setInteger(MediaFormat.KEY_ROTATION, 0) } catch (_: Throwable) {}
    }
    if (inMime.contains("dolby-vision", ignoreCase = true)) {
      // Many decoders expect DV to be provided as plain HEVC BL; csd-2 triggers issues.
      try {
        vFmt.setString(MediaFormat.KEY_MIME, "video/hevc")
        if (vFmt.containsKey("csd-2")) vFmt.removeKey("csd-2")
        inMime = "video/hevc"
      } catch (_: Throwable) {}
    }
    WMLog.d("Video in fmt=${vFmt.getString(MediaFormat.KEY_MIME)} size=${vFmt.getInteger(MediaFormat.KEY_WIDTH)}x${vFmt.getInteger(MediaFormat.KEY_HEIGHT)} rot=$rotation")
    val srcW = vFmt.getInteger(MediaFormat.KEY_WIDTH)
    val srcH = vFmt.getInteger(MediaFormat.KEY_HEIGHT)
    val displayW = if (rotation % 180 != 0) srcH else srcW
    val displayH = if (rotation % 180 != 0) srcW else srcH

    val encWH = chooseEncodeSize(displayW, displayH, req.maxLongSide?.toInt())
    var encW = encWH.first
    var encH = encWH.second
    val fpsGuess = guessFps(vFmt)
    val videoCodec = when (req.codec) {
      VideoCodec.HEVC -> "video/hevc"
      else -> "video/avc"
    }
    var bitrate = (req.bitrateBps?.toInt() ?: estimateBitrate(encW, encH, fpsGuess))
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

    // Encoder config (with fallback size if configure fails)
    val targetFps = max(1, (req.maxFps ?: fpsGuess).toInt())
    val candidateSizes = mutableListOf<Pair<Int, Int>>()
    candidateSizes.add(encW to encH)
    for (ls in listOf(1920, 1280, 720)) {
      val sz = chooseEncodeSize(displayW, displayH, ls)
      if (!candidateSizes.contains(sz)) candidateSizes.add(sz)
    }
    var encoder: MediaCodec? = null
    var lastErr: Throwable? = null
    for (sz in candidateSizes) {
      val w = sz.first
      val h = sz.second
      val br = (req.bitrateBps?.toInt() ?: estimateBitrate(w, h, fpsGuess))
      val encFmt = MediaFormat.createVideoFormat(videoCodec, w, h).apply {
        setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        setInteger(MediaFormat.KEY_BIT_RATE, br)
        setInteger(MediaFormat.KEY_FRAME_RATE, targetFps)
        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        try { setInteger("profile", MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline) } catch (_: Throwable) {}
        try { setInteger("level", MediaCodecInfo.CodecProfileLevel.AVCLevel31) } catch (_: Throwable) {}
      }
      val enc = createEncoderPreferSoftware(videoCodec) ?: MediaCodec.createEncoderByType(videoCodec)
      try {
        enc.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder = enc
        encW = w
        encH = h
        bitrate = br
        break
      } catch (t: Throwable) {
        lastErr = t
        try { enc.release() } catch (_: Throwable) {}
      }
    }
    val encoderConfigured = encoder != null
    if (!encoderConfigured) throw lastErr ?: RuntimeException("Encoder configure failed")
    WMLog.d("Encode cfg: $videoCodec ${encW}x${encH} fps=${fpsGuess} br=${bitrate}")
    val inputSurface = encoder.createInputSurface()
    encoder.start()

    // GL
    val gl = GlRenderer()
    gl.init()
    gl.setEncoderSurface(inputSurface)
    gl.makeCurrent()

    // Overlay (static or animated)
    val overlay = prepareOverlay(gl, req, encW, encH)

    // Decoder to Surface
    // Prepare decoder with fallback for Dolby Vision → HEVC when necessary
    var decoderMime = inMime
    if (!isDecoderAvailable(decoderMime)) {
      if (decoderMime.contains("dolby-vision")) {
        decoderMime = "video/hevc"
        // try updating format mime for decoder
        try { vFmt.setString(MediaFormat.KEY_MIME, decoderMime) } catch (_: Throwable) {}
      }
    }
    val decoder = createDecoderPreferSoftware(decoderMime) ?: run {
      if (decoderMime != "video/avc") createDecoderPreferSoftware("video/avc") else null
    } ?: throw RuntimeException("No suitable decoder for $decoderMime")
    WMLog.d("Using decoder name=${decoder.name} mime=$decoderMime")
    var useSurfacePath = true
    try {
      decoder.configure(vFmt, gl.getDecoderSurface(), null, 0)
      decoder.start()
      useSurfacePath = true
    } catch (t: Throwable) {
      WMLog.w("Surface decoder configure failed: ${t.message}")
      useSurfacePath = false
      try { decoder.release() } catch (_: Throwable) {}
    }

    var videoTrackIndexMuxer = -1
    var muxerStarted = false
    var renderedFrames = 0
    var encoderFrames = 0
    val surfaceStartMs = SystemClock.elapsedRealtime()

    val startUs = 0L
    var durationUs = extractor.getSampleTimeDurationUs(videoTrack)
    if (durationUs <= 0) durationUs = 1_000_000L

    val info = MediaCodec.BufferInfo()
    var sawInputEOS = false
    var sawOutputEOS = false
    var signaledEncoderEOS = false

    // Prepare to read video
    extractor.unselectAll()
    extractor.selectTrack(videoTrack)

    if (useSurfacePath) while (!task.cancelled && !sawOutputEOS) {
      // Feed decoder input
      if (!sawInputEOS) {
        val inIndex = decoder.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
          val buf = decoder.getInputBuffer(inIndex)!!
          val sampleSize = extractor.readSampleData(buf, 0)
          if (sampleSize < 0) {
            try {
              decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            } catch (e: Throwable) {
              WMLog.e("queueInputBuffer EOS failed: ${e.message}")
              throw e
            }
            sawInputEOS = true
          } else {
            val pts = extractor.sampleTime
            try {
              decoder.queueInputBuffer(inIndex, 0, sampleSize, max(0, pts), 0)
            } catch (e: Throwable) {
              WMLog.e("queueInputBuffer failed at pts=$pts: ${e.message}")
              throw e
            }
            extractor.advance()
          }
        }
      }

      // Drain decoder output
      val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
      when {
        outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {}
        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
          // Decoder output format change: keep silent unless verbose
          val of = decoder.outputFormat
          WMLog.d("Decoder output format changed: $of")
        }
        outIndex >= 0 -> {
          val isDecEOS = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
          val render = info.size > 0 && !isDecEOS
          decoder.releaseOutputBuffer(outIndex, render)
          if (isDecEOS) {
            // Decoder signaled EOS: propagate to encoder so it can emit EOS
            if (!signaledEncoderEOS) {
              try {
                WMLog.d("Decoder EOS reached, signaling encoder EOS")
                encoder.signalEndOfInputStream()
                signaledEncoderEOS = true
              } catch (t: Throwable) {
                WMLog.w("signalEndOfInputStream failed: ${t.message}")
              }
            }
          }
          if (render) {
            val stMatrix = gl.updateDecoderTexImage()
            // Draw into encoder surface
            gl.makeCurrent()
            gl.drawVideoFrame(stMatrix, rotation, encW, encH)
            overlay?.let { ov ->
              if (ov is OverlaySource.Animated) {
                ov.animator.update(gl, ov.texId, info.presentationTimeUs)
              }
              val info = ov.info
              gl.drawOverlay(info.posX, info.posY, info.wPx, info.hPx, encW, encH, ov.texId, req.opacity.toFloat())
            }
            gl.setPresentationTime(info.presentationTimeUs * 1000)
            renderedFrames++

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
              encoderFrames++
            }
            encoder.releaseOutputBuffer(eIndex, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
              sawOutputEOS = true
              encOut = false
            }
          }
        }
      }

      // Surface path stalled? Fallback after threshold (either frames rendered without encoder start or time-based).
      val elapsed = SystemClock.elapsedRealtime() - surfaceStartMs
      if (!muxerStarted && (renderedFrames >= 60 || elapsed > 3000) && encoderFrames == 0 && !signaledEncoderEOS) {
        WMLog.w("Surface path stalled (rendered=$renderedFrames, encoded=$encoderFrames). Falling back to ByteBuffer decode.")
        if (overlay is OverlaySource.Animated) overlay.animator.recycle()
        try { decoder.stop(); decoder.release() } catch (_: Throwable) {}
        try { encoder.stop(); encoder.release() } catch (_: Throwable) {}
        // Use same muxer (not started yet) and audioExtractor
        // Reuse existing gl
        processByteBuffer(req, callbacks, muxer, audioExtractor, audioTrackIndexMuxer, gl, encW, encH, rotation, videoCodec, bitrate, fpsGuess)
        return
      }
    }

    if (!useSurfacePath && !task.cancelled) {
      // Fallback: ByteBuffer decode path
      processByteBuffer(req, callbacks, muxer, audioExtractor, audioTrackIndexMuxer, gl, encW, encH, rotation, videoCodec, bitrate, fpsGuess)
      // processByteBuffer handles muxer.stop/release etc.
      return
    }

    // finalize
    decoder.stop(); decoder.release()
    if (!signaledEncoderEOS) {
      try {
        WMLog.d("Final signaling encoder EOS")
        encoder.signalEndOfInputStream()
        signaledEncoderEOS = true
      } catch (t: Throwable) {
        WMLog.w("signalEndOfInputStream at finalize failed: ${t.message}")
      }
    }
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
    if (overlay is OverlaySource.Animated) overlay.animator.recycle()
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

  private fun processByteBuffer(
    req: ComposeVideoRequest,
    callbacks: WatermarkCallbacks,
    muxer: MediaMuxer,
    audioExtractor: MediaExtractor,
    audioTrackIndexMuxer: Int,
    gl: GlRenderer,
    encW: Int,
    encH: Int,
    rotation: Int,
    videoCodec: String,
    bitrate: Int,
    fpsGuess: Double
  ) {
    val extractor = MediaExtractor()
    extractor.setDataSource(req.inputVideoPath)
    val (videoTrack, audioTrack) = selectTracks(extractor)
    extractor.selectTrack(videoTrack)
    val vFmt = extractor.getTrackFormat(videoTrack)
    // Configure decoder to ByteBuffer YUV420Flexible
    val fmt = MediaFormat.createVideoFormat(vFmt.getString(MediaFormat.KEY_MIME)!!, vFmt.getInteger(MediaFormat.KEY_WIDTH), vFmt.getInteger(MediaFormat.KEY_HEIGHT))
    fmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
    if (vFmt.containsKey("csd-0")) fmt.setByteBuffer("csd-0", vFmt.getByteBuffer("csd-0"))
    if (vFmt.containsKey("csd-1")) fmt.setByteBuffer("csd-1", vFmt.getByteBuffer("csd-1"))
    val decoder = createDecoderPreferSoftware(fmt.getString(MediaFormat.KEY_MIME)!!) ?: throw RuntimeException("No decoder for ByteBuffer path")
    decoder.configure(fmt, null, null, 0)
    decoder.start()

    // Recreate encoder for safety
    val encoder = createEncoderPreferSoftware(videoCodec) ?: MediaCodec.createEncoderByType(videoCodec)
    val encFmt = MediaFormat.createVideoFormat(videoCodec, encW, encH).apply {
      setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
      setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
      setInteger(MediaFormat.KEY_FRAME_RATE, max(1, fpsGuess.toInt()))
      setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
      try { setInteger("profile", MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline) } catch (_: Throwable) {}
      try { setInteger("level", MediaCodecInfo.CodecProfileLevel.AVCLevel31) } catch (_: Throwable) {}
    }
    encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    val inputSurface = encoder.createInputSurface()
    encoder.start()
    gl.setEncoderSurface(inputSurface)
    gl.makeCurrent()

    var videoTrackIndexMuxer = -1
    var muxerStarted = false
    val info = MediaCodec.BufferInfo()
    var sawInputEOS = false
    var sawOutputEOS = false
    var signaledEncoderEOS = false
    val durationUs = vFmt.getLong(MediaFormat.KEY_DURATION, 1_000_000L)

    // Precompute overlay for output size
    val overlay = prepareOverlay(gl, req, encW, encH)

    while (!sawOutputEOS) {
      if (!sawInputEOS) {
        val inIndex = decoder.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
          val buf = decoder.getInputBuffer(inIndex)!!
          val size = extractor.readSampleData(buf, 0)
          if (size < 0) {
            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            sawInputEOS = true
          } else {
            val pts = extractor.sampleTime
            decoder.queueInputBuffer(inIndex, 0, size, max(0, pts), 0)
            extractor.advance()
          }
        }
      }

      val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
      when {
        outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {}
        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {}
        outIndex >= 0 -> {
          val isDecEOS = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
          val render = info.size > 0 && !isDecEOS
          val image = decoder.getOutputImage(outIndex)
          if (render && image != null) {
            val yPlane = image.planes[0]
            val uPlane = image.planes[1]
            val vPlane = image.planes[2]
            // Handle pixelStride (usually 1 for Y and 2 for UV on some devices)
            val yBuf = packTight(yPlane.buffer, image.width, image.height, yPlane.rowStride, yPlane.pixelStride)
            val uBuf = packTight(uPlane.buffer, image.width / 2, image.height / 2, uPlane.rowStride, uPlane.pixelStride)
            val vBuf = packTight(vPlane.buffer, image.width / 2, image.height / 2, vPlane.rowStride, vPlane.pixelStride)

            gl.drawYuvFrame(yBuf, uBuf, vBuf, image.width, image.width / 2, image.width / 2, image.width, image.height, rotation, encW, encH)
            overlay?.let { ov ->
              if (ov is OverlaySource.Animated) {
                ov.animator.update(gl, ov.texId, info.presentationTimeUs)
              }
              val info = ov.info
              gl.drawOverlay(info.posX, info.posY, info.wPx, info.hPx, encW, encH, ov.texId, req.opacity.toFloat())
            }
            image.close()

            gl.setPresentationTime(info.presentationTimeUs * 1_000)
            gl.swapBuffers()
          }
          // Do not render on EOS
          decoder.releaseOutputBuffer(outIndex, false)
          if (isDecEOS && !signaledEncoderEOS) {
            try {
              WMLog.d("[BB] Decoder EOS reached, signaling encoder EOS")
              encoder.signalEndOfInputStream()
              signaledEncoderEOS = true
            } catch (t: Throwable) {
              WMLog.w("[BB] signalEndOfInputStream failed: ${t.message}")
            }
          }

          // drain encoder
          var enc = true
          while (enc) {
            val ei = encoder.dequeueOutputBuffer(info, 0)
            when {
              ei == MediaCodec.INFO_TRY_AGAIN_LATER -> enc = false
              ei == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                videoTrackIndexMuxer = muxer.addTrack(encoder.outputFormat)
                if (!muxerStarted) {
                  muxer.start()
                  muxerStarted = true
                  if (audioTrackIndexMuxer >= 0) copyAudioAsync(audioExtractor, muxer, audioTrackIndexMuxer)
                }
              }
              ei >= 0 -> {
                val out = encoder.getOutputBuffer(ei)!!
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                if (info.size > 0 && muxerStarted) muxer.writeSampleData(videoTrackIndexMuxer, out, info)
                encoder.releaseOutputBuffer(ei, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) { enc = false; sawOutputEOS = true }
              }
            }
          }

          val p = info.presentationTimeUs.toDouble() / max(1.0, durationUs.toDouble())
          safeProgress(callbacks, req.taskId!!, p.coerceIn(0.0, 1.0), max(0.0, (durationUs - info.presentationTimeUs) / 1_000_000.0))
        }
      }
    }

    decoder.stop(); decoder.release()
    if (!signaledEncoderEOS) {
      try {
        WMLog.d("[BB] Final signaling encoder EOS")
        encoder.signalEndOfInputStream()
        signaledEncoderEOS = true
      } catch (t: Throwable) {
        WMLog.w("[BB] signalEndOfInputStream at finalize failed: ${t.message}")
      }
    }
    encoder.stop(); encoder.release()
    muxer.stop(); muxer.release()
    if (overlay is OverlaySource.Animated) overlay.animator.recycle()

    val res = ComposeVideoResult(req.taskId!!, req.outputVideoPath ?: "", encW.toLong(), encH.toLong(), max(1, (durationUs / 1000).toInt()).toLong(), req.codec)
    safeCompleted(callbacks, res)
  }

  private fun packTight(src: java.nio.ByteBuffer, width: Int, height: Int, rowStride: Int, pixelStride: Int): java.nio.ByteBuffer {
    if (pixelStride == 1 && rowStride == width) {
      val dup = src.duplicate()
      dup.position(0)
      dup.limit(width * height)
      val out = java.nio.ByteBuffer.allocateDirect(width * height)
      out.put(dup)
      out.position(0)
      return out
    }
    val out = java.nio.ByteBuffer.allocateDirect(width * height)
    val base = src.position()
    for (y in 0 until height) {
      var offset = base + y * rowStride
      for (x in 0 until width) {
        out.put(src.get(offset))
        offset += pixelStride
      }
    }
    out.position(0)
    return out
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

  private data class OverlayInfo(val posX: Float, val posY: Float, val wPx: Float, val hPx: Float)

  private sealed class OverlaySource {
    abstract val info: OverlayInfo
    abstract val texId: Int

    data class Static(override val info: OverlayInfo, override val texId: Int) : OverlaySource()
    data class Animated(override val info: OverlayInfo, override val texId: Int, val animator: GifAnimator) : OverlaySource()
  }

  private class GifAnimator(
    val movie: Movie,
    val bitmap: Bitmap,
    val canvas: Canvas,
    val durationMs: Int,
    var lastTimeMs: Int = -1
  ) {
    fun update(gl: GlRenderer, texId: Int, timeUs: Long) {
      val duration = if (durationMs > 0) durationMs else 1000
      val t = ((timeUs / 1000) % duration).toInt()
      if (t == lastTimeMs) return
      lastTimeMs = t
      canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
      movie.setTime(t)
      movie.draw(canvas, 0f, 0f)
      gl.update2DTextureFromBitmap(texId, bitmap)
    }

    fun recycle() {
      if (!bitmap.isRecycled) bitmap.recycle()
    }
  }

  private fun prepareOverlay(gl: GlRenderer, req: ComposeVideoRequest, baseW: Int, baseH: Int): OverlaySource? {
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
    val animated = decodeAnimatedGif(overlayBytes)
    if (animated != null) {
      val info = computeOverlayInfo(baseW, baseH, animated.bitmap.width, animated.bitmap.height, req)
      val texId = gl.create2DTextureFromBitmap(animated.bitmap)
      return OverlaySource.Animated(info, texId, animated)
    }
    val bmp = BitmapFactory.decodeByteArray(overlayBytes, 0, overlayBytes.size) ?: return null
    val info = computeOverlayInfo(baseW, baseH, bmp.width, bmp.height, req)
    val texId = gl.create2DTextureFromBitmap(bmp)
    bmp.recycle()
    return OverlaySource.Static(info, texId)
  }

  private fun computeOverlayInfo(baseW: Int, baseH: Int, srcW: Int, srcH: Int, req: ComposeVideoRequest): OverlayInfo {
    val wTarget = (baseW * req.widthPercent).toFloat().coerceAtLeast(1f)
    val scale = wTarget / max(1, srcW)
    val wmW = (srcW * scale)
    val wmH = (srcH * scale)
    val pos = AnchorUtil.computePosition(baseW, baseH, wmW.toInt(), wmH.toInt(), req.anchor, req.margin, req.marginUnit, req.offsetX, req.offsetY, req.offsetUnit)
    return OverlayInfo(pos.x, pos.y, wmW, wmH)
  }

  private fun decodeAnimatedGif(bytes: ByteArray): GifAnimator? {
    val movie = Movie.decodeByteArray(bytes, 0, bytes.size) ?: return null
    val w = movie.width()
    val h = movie.height()
    if (w <= 0 || h <= 0) return null
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
    movie.setTime(0)
    movie.draw(canvas, 0f, 0f)
    val duration = movie.duration().takeIf { it > 0 } ?: 1000
    return GifAnimator(movie, bitmap, canvas, duration)
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

  private fun isDecoderAvailable(mime: String): Boolean {
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    return list.codecInfos.any { !it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, ignoreCase = true) } }
  }

  private fun createDecoderPreferSoftware(mime: String): MediaCodec? {
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    val candidates = list.codecInfos.filter { !it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, ignoreCase = true) } }
    val sorted = candidates.sortedBy { namePreferenceScore(it.name) }
    for (ci in sorted) {
      try {
        WMLog.d("Trying decoder ${ci.name} for $mime")
        return MediaCodec.createByCodecName(ci.name)
      } catch (t: Throwable) {
        WMLog.w("Decoder ${ci.name} failed to create: ${t.message}")
      }
    }
    return null
  }

  private fun namePreferenceScore(name: String): Int {
    val n = name.lowercase()
    return when {
      n.contains("google") -> 0
      n.startsWith("c2.android") -> 1
      n.startsWith("omx.google") -> 0
      else -> 10
    }
  }

  private fun createEncoderPreferSoftware(mime: String): MediaCodec? {
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    val candidates = list.codecInfos.filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, ignoreCase = true) } }
    val sorted = candidates.sortedBy { namePreferenceScore(it.name) }
    for (ci in sorted) {
      try {
        WMLog.d("Trying encoder ${ci.name} for $mime")
        return MediaCodec.createByCodecName(ci.name)
      } catch (t: Throwable) {
        WMLog.w("Encoder ${ci.name} failed to create: ${t.message}")
      }
    }
    return null
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

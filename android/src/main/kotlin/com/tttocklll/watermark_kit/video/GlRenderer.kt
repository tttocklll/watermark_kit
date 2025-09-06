package com.tttocklll.watermark_kit.video

import android.graphics.SurfaceTexture
import android.opengl.*
import android.view.Surface
import kotlin.math.cos
import kotlin.math.sin

internal class GlRenderer {
  private var display: EGLDisplay? = null
  private var context: EGLContext? = null
  private var encoderSurface: EGLSurface? = null
  private var oesTexId: Int = -1
  private var surfaceTexture: SurfaceTexture? = null
  private var surface: Surface? = null

  private lateinit var progOes: ShaderPrograms.Program
  private lateinit var prog2d: ShaderPrograms.Program

  private val identity = FloatArray(16).apply { Matrix.setIdentityM(this, 0) }

  fun init() {
    display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    val version = IntArray(2)
    EGL14.eglInitialize(display, version, 0, version, 1)

    val attribList = intArrayOf(
      EGL14.EGL_RED_SIZE, 8,
      EGL14.EGL_GREEN_SIZE, 8,
      EGL14.EGL_BLUE_SIZE, 8,
      EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
      EGL14.EGL_NONE
    )
    val configs = arrayOfNulls<EGLConfig>(1)
    val num = IntArray(1)
    EGL14.eglChooseConfig(display, attribList, 0, configs, 0, configs.size, num, 0)

    val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
    context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
    makeNothingCurrent()
  }

  fun getDecoderSurface(): Surface = surface!!

  fun release() {
    surface?.release(); surface = null
    surfaceTexture?.release(); surfaceTexture = null
    if (oesTexId != -1) {
      val arr = intArrayOf(oesTexId)
      GLES20.glDeleteTextures(1, arr, 0)
      oesTexId = -1
    }
    if (encoderSurface != null) {
      EGL14.eglDestroySurface(display, encoderSurface)
      encoderSurface = null
    }
    if (context != null) {
      EGL14.eglDestroyContext(display, context)
      context = null
    }
    if (display != null) {
      EGL14.eglTerminate(display)
      display = null
    }
  }

  fun setEncoderSurface(inputSurface: Surface) {
    val cfgAttribs = intArrayOf(
      EGL14.EGL_RED_SIZE, 8,
      EGL14.EGL_GREEN_SIZE, 8,
      EGL14.EGL_BLUE_SIZE, 8,
      EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
      EGL14.EGL_NONE
    )
    val configs = arrayOfNulls<EGLConfig>(1)
    val num = IntArray(1)
    EGL14.eglChooseConfig(display, cfgAttribs, 0, configs, 0, 1, num, 0)
    val attrs = intArrayOf(EGL14.EGL_NONE)
    encoderSurface = EGL14.eglCreateWindowSurface(display, configs[0], inputSurface, attrs, 0)
    // Make current and lazily build programs and external texture
    makeCurrent()
    progOes = ShaderPrograms.buildExternalOes()
    prog2d = ShaderPrograms.buildTexture2D()
    oesTexId = genExternalTexture()
    surfaceTexture = SurfaceTexture(oesTexId)
    surfaceTexture!!.setDefaultBufferSize(16, 16)
    surface = Surface(surfaceTexture)
  }

  fun makeCurrent() {
    EGL14.eglMakeCurrent(display, encoderSurface, encoderSurface, context)
  }

  fun makeNothingCurrent() {
    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
  }

  fun updateDecoderTexImage(): FloatArray {
    val st = FloatArray(16)
    surfaceTexture!!.updateTexImage()
    surfaceTexture!!.getTransformMatrix(st)
    return st
  }

  fun setPresentationTime(nano: Long) {
    EGLExt.eglPresentationTimeANDROID(display, encoderSurface, nano)
  }

  fun swapBuffers() {
    EGL14.eglSwapBuffers(display, encoderSurface)
  }

  fun drawVideoFrame(stMatrix: FloatArray, rotationDeg: Int, viewW: Int, viewH: Int) {
    GLES20.glViewport(0, 0, viewW, viewH)
    GLES20.glClearColor(0f, 0f, 0f, 1f)
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

    GLES20.glUseProgram(progOes.id)
    val verts = createFullscreenQuad(rotationDeg)
    drawQuad(progOes, verts, stMatrix, oes = true, opacity = 1f)
  }

  fun drawOverlay(xPx: Float, yPx: Float, wPx: Float, hPx: Float, viewW: Int, viewH: Int, textureId: Int, opacity: Float) {
    GLES20.glEnable(GLES20.GL_BLEND)
    GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    GLES20.glUseProgram(prog2d.id)
    val verts = createRectQuad(xPx, yPx, wPx, hPx, viewW, viewH)
    drawQuad2D(prog2d, verts, textureId, opacity)
    GLES20.glDisable(GLES20.GL_BLEND)
  }

  fun create2DTextureFromBitmap(bmp: android.graphics.Bitmap): Int {
    val ids = IntArray(1)
    GLES20.glGenTextures(1, ids, 0)
    val id = ids[0]
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    return id
  }

  private fun genExternalTexture(): Int {
    val tex = IntArray(1)
    GLES20.glGenTextures(1, tex, 0)
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
    GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
    GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    return tex[0]
  }

  private fun drawQuad(program: ShaderPrograms.Program, verts: FloatArray, stMatrix: FloatArray, oes: Boolean, opacity: Float) {
    val bb = java.nio.ByteBuffer.allocateDirect(verts.size * 4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer()
    bb.put(verts).position(0)
    val stride = 4 * 4 // 4 floats per position/texcoord
    bb.position(0)
    GLES20.glVertexAttribPointer(program.attrs["aPosition"]!!, 2, GLES20.GL_FLOAT, false, stride, bb)
    GLES20.glEnableVertexAttribArray(program.attrs["aPosition"]!!)
    bb.position(2)
    GLES20.glVertexAttribPointer(program.attrs["aTexCoord"]!!, 2, GLES20.GL_FLOAT, false, stride, bb)
    GLES20.glEnableVertexAttribArray(program.attrs["aTexCoord"]!!)

    GLES20.glUniformMatrix4fv(program.uniforms["uTexMatrix"]!!, 1, false, stMatrix, 0)
    GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexId)
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
  }

  private fun drawQuad2D(program: ShaderPrograms.Program, verts: FloatArray, texId: Int, opacity: Float) {
    val bb = java.nio.ByteBuffer.allocateDirect(verts.size * 4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer()
    bb.put(verts).position(0)
    val stride = 4 * 4
    bb.position(0)
    GLES20.glVertexAttribPointer(program.attrs["aPosition"]!!, 2, GLES20.GL_FLOAT, false, stride, bb)
    GLES20.glEnableVertexAttribArray(program.attrs["aPosition"]!!)
    bb.position(2)
    GLES20.glVertexAttribPointer(program.attrs["aTexCoord"]!!, 2, GLES20.GL_FLOAT, false, stride, bb)
    GLES20.glEnableVertexAttribArray(program.attrs["aTexCoord"]!!)

    GLES20.glUniform1f(program.uniforms["uOpacity"]!!, opacity)
    GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texId)
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
  }

  private fun createFullscreenQuad(rotationDeg: Int): FloatArray {
    // Positions in NDC and default tex coords (0..1). We'll rotate by swapping coords.
    val base = floatArrayOf(
      -1f, -1f, 0f, 0f,
       1f, -1f, 1f, 0f,
      -1f,  1f, 0f, 1f,
       1f,  1f, 1f, 1f
    )
    if (rotationDeg == 0) return base
    // For 90/180/270 we rotate texture coords
    val rot = when ((rotationDeg % 360 + 360) % 360) {
      90 -> floatArrayOf(
        -1f, -1f, 1f, 0f,
         1f, -1f, 1f, 1f,
        -1f,  1f, 0f, 0f,
         1f,  1f, 0f, 1f
      )
      180 -> floatArrayOf(
        -1f, -1f, 1f, 1f,
         1f, -1f, 0f, 1f,
        -1f,  1f, 1f, 0f,
         1f,  1f, 0f, 0f
      )
      270 -> floatArrayOf(
        -1f, -1f, 0f, 1f,
         1f, -1f, 0f, 0f,
        -1f,  1f, 1f, 1f,
         1f,  1f, 1f, 0f
      )
      else -> base
    }
    return rot
  }

  private fun createRectQuad(xPx: Float, yPx: Float, wPx: Float, hPx: Float, vw: Int, vh: Int): FloatArray {
    // Convert top-left origin (xPx,yPx) to GL NDC with origin at center and y up.
    val x0 = 2f * (xPx / vw) - 1f
    val y0 = 1f - 2f * (yPx / vh) - 2f * (hPx / vh)
    val x1 = 2f * ((xPx + wPx) / vw) - 1f
    val y1 = y0 + 2f * (hPx / vh)
    return floatArrayOf(
      x0, y0, 0f, 0f,
      x1, y0, 1f, 0f,
      x0, y1, 0f, 1f,
      x1, y1, 1f, 1f,
    )
  }
}

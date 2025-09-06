package com.tttocklll.watermark_kit.video

import android.opengl.GLES20
import android.opengl.GLES11Ext

internal object ShaderPrograms {
  data class Program(val id: Int, val attrs: Map<String, Int>, val uniforms: Map<String, Int>)

  fun buildExternalOes(): Program {
    val vs = """
      attribute vec4 aPosition;
      attribute vec4 aTexCoord;
      uniform mat4 uTexMatrix;
      varying vec2 vTexCoord;
      void main() {
        gl_Position = aPosition;
        vTexCoord = (uTexMatrix * aTexCoord).xy;
      }
    """
    val fs = """
      #extension GL_OES_EGL_image_external : require
      precision mediump float;
      uniform samplerExternalOES sTexture;
      varying vec2 vTexCoord;
      void main() {
        gl_FragColor = texture2D(sTexture, vTexCoord);
      }
    """
    val prog = link(vs, fs)
    return Program(
      prog,
      mapOf(
        "aPosition" to GLES20.glGetAttribLocation(prog, "aPosition"),
        "aTexCoord" to GLES20.glGetAttribLocation(prog, "aTexCoord")
      ),
      mapOf(
        "uTexMatrix" to GLES20.glGetUniformLocation(prog, "uTexMatrix"),
        "sTexture" to GLES20.glGetUniformLocation(prog, "sTexture")
      )
    )
  }

  fun buildTexture2D(): Program {
    val vs = """
      attribute vec4 aPosition;
      attribute vec2 aTexCoord;
      varying vec2 vTexCoord;
      void main() {
        gl_Position = aPosition;
        vTexCoord = aTexCoord;
      }
    """
    val fs = """
      precision mediump float;
      uniform sampler2D sTexture;
      uniform float uOpacity;
      varying vec2 vTexCoord;
      void main() {
        vec4 c = texture2D(sTexture, vTexCoord);
        gl_FragColor = vec4(c.rgb, c.a * uOpacity);
      }
    """
    val prog = link(vs, fs)
    return Program(
      prog,
      mapOf(
        "aPosition" to GLES20.glGetAttribLocation(prog, "aPosition"),
        "aTexCoord" to GLES20.glGetAttribLocation(prog, "aTexCoord"),
      ),
      mapOf(
        "sTexture" to GLES20.glGetUniformLocation(prog, "sTexture"),
        "uOpacity" to GLES20.glGetUniformLocation(prog, "uOpacity"),
      )
    )
  }

  private fun compile(type: Int, source: String): Int {
    val shader = GLES20.glCreateShader(type)
    GLES20.glShaderSource(shader, source)
    GLES20.glCompileShader(shader)
    val compiled = IntArray(1)
    GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
    if (compiled[0] == 0) {
      val log = GLES20.glGetShaderInfoLog(shader)
      GLES20.glDeleteShader(shader)
      throw RuntimeException("Shader compile failed: $log")
    }
    return shader
  }

  private fun link(vs: String, fs: String): Int {
    val v = compile(GLES20.GL_VERTEX_SHADER, vs)
    val f = compile(GLES20.GL_FRAGMENT_SHADER, fs)
    val prog = GLES20.glCreateProgram()
    GLES20.glAttachShader(prog, v)
    GLES20.glAttachShader(prog, f)
    GLES20.glLinkProgram(prog)
    val link = IntArray(1)
    GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, link, 0)
    if (link[0] == 0) {
      val log = GLES20.glGetProgramInfoLog(prog)
      GLES20.glDeleteProgram(prog)
      throw RuntimeException("Program link failed: $log")
    }
    GLES20.glDeleteShader(v)
    GLES20.glDeleteShader(f)
    return prog
  }
}


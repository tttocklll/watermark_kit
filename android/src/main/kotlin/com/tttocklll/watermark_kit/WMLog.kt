package com.tttocklll.watermark_kit

import android.util.Log

internal object WMLog {
  // Verbose logs are disabled by default to keep logs clean.
  @Volatile var enabled: Boolean = false

  fun d(msg: String) { if (enabled) Log.d("WM", msg) }
  fun i(msg: String) { if (enabled) Log.i("WM", msg) }
  fun w(msg: String) { Log.w("WM", msg) }
  fun e(msg: String, t: Throwable? = null) {
    if (t != null) Log.e("WM", msg, t) else Log.e("WM", msg)
  }
}


package com.jackwallner.baby

import android.content.Intent

/** Release builds ignore every launch option. */
object DebugLaunchOptions {
    @Suppress("UNUSED_PARAMETER")
    fun apply(graph: AppGraph, intent: Intent?): Int? = null
}

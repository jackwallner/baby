package com.jackwallner.baby

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.baby.data.AppSettings
import com.jackwallner.baby.data.EventStore
import com.jackwallner.baby.data.SharingService
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import org.junit.Assume.assumeTrue

/**
 * The Firebase Local Emulator Suite for connected tests. Run them inside
 * `firebase-tools emulators:exec` and pass the host's address as seen from
 * the device: -Pandroid.testInstrumentationRunnerArguments.firebaseEmulator=10.0.2.2
 * Without it the sharing tests are reported as skipped, never as passed.
 */
object SharingEmulator {
    val host: String? get() = InstrumentationRegistry.getArguments().getString("firebaseEmulator")

    fun require(): String = host.also { assumeTrue("Run inside firebase-tools emulators:exec with firebaseEmulator=<host>", it != null) }!!

    val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext

    /** A second phone in the same process: its own log file, preferences and Firebase app. */
    class Phone(val name: String) {
        val prefs = context.getSharedPreferences("phone-$name", Context.MODE_PRIVATE).also { it.edit().clear().commit() }
        val settings = AppSettings(prefs)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val events = EventStore(File(context.cacheDir, "phone-$name.json").also { it.delete() }, settings, scope)
        val sharing = SharingService(context, prefs, events, appName = "phone-$name").also { it.useEmulator(require(), name) }
        val signIn = sharing.testSignIn!!
    }

    /** Polls until [condition] holds: delivery between phones is asynchronous. */
    suspend fun eventually(what: String, timeoutMs: Long = 20_000, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!condition()) {
            if (System.currentTimeMillis() > end) throw AssertionError("Timed out waiting for: $what")
            delay(100)
        }
    }
}

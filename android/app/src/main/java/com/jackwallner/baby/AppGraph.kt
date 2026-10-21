package com.jackwallner.baby

import android.app.Application
import android.content.Context
import com.jackwallner.baby.data.AppSettings
import com.jackwallner.baby.data.EventStore
import com.jackwallner.baby.data.Reminders
import com.jackwallner.baby.data.StoreService
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Every shared object, built once per process. */
class AppGraph(context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs = context.getSharedPreferences("baby", Context.MODE_PRIVATE)
    val settings = AppSettings(prefs)
    val reminders = Reminders(context.applicationContext, prefs, settings)
    val events = EventStore(File(context.filesDir, "baby-log.json"), settings, scope)
    val store = StoreService(context.applicationContext, settings)

    /** Debug screenshot runs hide the reminder offer and record no impressions. */
    var screenshotMode = false

    init {
        events.onPublish = { summary, child -> reminders.reschedule(summary, child) }
        settings.onChange = { events.refresh() }
        events.refresh()
    }
}

class BabyApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        Reminders.ensureChannel(this)
        graph = AppGraph(this)
    }
}

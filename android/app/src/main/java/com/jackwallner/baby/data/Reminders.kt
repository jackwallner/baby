package com.jackwallner.baby.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import com.jackwallner.baby.BabyApplication
import com.jackwallner.baby.MainActivity
import com.jackwallner.baby.R
import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.ReminderPlan
import java.time.ZoneId

/**
 * Local notifications only, this phone only: the feed reminder and the
 * evening-before checkup note, planned by [ReminderPlan]. Inexact alarms, so
 * no exact-alarm permission or Play declaration is needed; a reminder may
 * arrive a few minutes late, which is fine for a nudge.
 */
class Reminders(private val context: Context, private val prefs: SharedPreferences, private val settings: AppSettings) {
    private var lastPlanned: List<ReminderPlan.Planned>? = null

    fun reschedule(summary: NowSummary, child: Child?, now: Long = System.currentTimeMillis()) {
        val zone = ZoneId.systemDefault()
        val planned = buildList {
            ReminderPlan.feedReminder(summary, settings.feedInterval, now, zone)?.let(::add)
            if (settings.checkupRemindersOn) addAll(ReminderPlan.checkupReminders(child?.birthDate, settings.nextCheckup, now, zone))
        }
        if (planned == lastPlanned) return
        lastPlanned = planned
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val keep = planned.map { it.id }.toSet()
        prefs.getStringSet(KEY_SCHEDULED, emptySet()).orEmpty().filter { it !in keep }.forEach { alarms.cancel(pending(it, null)) }
        for (item in planned) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.date, pending(item.id, item))
        }
        prefs.edit { putStringSet(KEY_SCHEDULED, keep) }
    }

    private fun pending(id: String, item: ReminderPlan.Planned?): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).setAction("com.jackwallner.baby.REMINDER.$id")
        if (item != null) {
            intent.putExtra(EXTRA_ID, item.id).putExtra(EXTRA_TITLE, item.title).putExtra(EXTRA_BODY, item.body).putExtra(EXTRA_ROUTE, item.route)
        }
        return PendingIntent.getBroadcast(context, id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    val canNotify: Boolean
        get() = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    companion object {
        const val CHANNEL = "reminders"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_ROUTE = "route"
        private const val KEY_SCHEDULED = "reminder.scheduled"

        fun ensureChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(Reminders.EXTRA_ID) ?: return
        Reminders.ensureChannel(context)
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(Reminders.EXTRA_ROUTE, intent.getStringExtra(Reminders.EXTRA_ROUTE))
        val tap = PendingIntent.getActivity(context, id.hashCode(), open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, Reminders.CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(intent.getStringExtra(Reminders.EXTRA_TITLE))
            .setContentText(intent.getStringExtra(Reminders.EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(Reminders.EXTRA_BODY)))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        val manager = NotificationManagerCompat.from(context)
        if (manager.areNotificationsEnabled()) {
            try {
                manager.notify(id.hashCode(), notification)
            } catch (_: SecurityException) {
                // Permission withdrawn between the check and the post.
            }
        }
    }
}

/** Alarms do not survive a reboot; building the graph republishes and reschedules them. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) (context.applicationContext as BabyApplication).graph.events.refresh()
    }
}

package com.productivity.and.wellbeing

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import java.time.LocalDate

class StepReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!remindersEnabled(context)) {
            cancel(context)
            return
        }

        if (todaySteps(context) >= minimumSteps(context)) {
            StepCounterService.refreshReminder(context)
        }
        schedule(context)
    }

    companion object {
        private const val REQUEST_CODE = 5100

        private const val KEY_ENABLED = "hourly_step_reminders_enabled"
        private const val KEY_MIN_STEPS = "step_reminder_min_steps"
        private const val KEY_STEPS = "bg_steps"
        private const val KEY_DAY = "bg_day"

        fun schedule(context: Context) {
            if (!remindersEnabled(context)) {
                cancel(context)
                return
            }

            val intervalMillis = AlarmManager.INTERVAL_HOUR
            val triggerAt = SystemClock.elapsedRealtime() + intervalMillis
            val alarmManager = context.getSystemService(AlarmManager::class.java)

            alarmManager.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                intervalMillis,
                pendingIntent(context)
            )
        }

        fun cancel(context: Context) {
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            alarmManager.cancel(pendingIntent(context))
        }

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, StepReminderReceiver::class.java)

            return PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        private fun remindersEnabled(context: Context): Boolean {
            return prefs(context).getBoolean(prefKey(KEY_ENABLED), true)
        }

        private fun todaySteps(context: Context): Int {
            val savedDay = prefs(context).getString(prefKey(KEY_DAY), "") ?: ""
            if (savedDay != LocalDate.now().toString()) return 0

            return readInt(context, KEY_STEPS, 0)
        }

        private fun minimumSteps(context: Context): Int {
            return readInt(context, KEY_MIN_STEPS, 100).coerceAtLeast(100)
        }

        private fun readInt(context: Context, key: String, fallback: Int): Int {
            return (prefs(context).all[prefKey(key)] as? Number)?.toInt() ?: fallback
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        private fun prefKey(key: String) = "flutter.$key"

        private fun immutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        }
    }
}

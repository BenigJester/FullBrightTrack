package com.productivity.and.wellbeing

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class StepReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!remindersEnabled(context)) {
            cancel(context)
            return
        }

        showReminder(context)
        schedule(context)
    }

    companion object {
        private const val CHANNEL_ID = "hourly_steps"
        private const val NOTIFICATION_ID = 100
        private const val REQUEST_CODE = 5100

        private const val KEY_ENABLED = "hourly_step_reminders_enabled"
        private const val KEY_INTERVAL = "step_reminder_interval_hours"
        private const val KEY_STEPS = "bg_steps"
        private const val KEY_DAY = "bg_day"

        fun schedule(context: Context) {
            if (!remindersEnabled(context)) {
                cancel(context)
                return
            }

            val intervalMillis = intervalHours(context) * AlarmManager.INTERVAL_HOUR
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

        private fun showReminder(context: Context) {
            if (!hasNotificationPermission(context)) return

            createNotificationChannel(context)

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle("Step Reminder")
                .setContentText("${todaySteps(context)} steps today 🚶")
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()

            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
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

        private fun intervalHours(context: Context): Long {
            return when (val saved = readInt(context, KEY_INTERVAL, 2)) {
                1, 2, 3 -> saved.toLong()
                else -> 2L
            }
        }

        private fun todaySteps(context: Context): Int {
            val savedDay = prefs(context).getString(prefKey(KEY_DAY), "") ?: ""
            if (savedDay != java.time.LocalDate.now().toString()) return 0

            return readInt(context, KEY_STEPS, 0)
        }

        private fun readInt(context: Context, key: String, fallback: Int): Int {
            return (prefs(context).all[prefKey(key)] as? Number)?.toInt() ?: fallback
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        private fun prefKey(key: String) = "flutter.$key"

        private fun hasNotificationPermission(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }

        private fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hourly Step Reminder",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Hourly wellness reminders"
            }

            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        private fun immutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        }
    }
}

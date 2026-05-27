package com.productivity.and.wellbeing

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StepBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_USER_UNLOCKED -> {
                if (StepCounterService.hasActivityPermission(context)) {
                    StepCounterService.start(context)
                }
                StepReminderReceiver.schedule(context)
            }
        }
    }
}

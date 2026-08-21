package com.example.app_freezer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object AlarmHelper {
    fun scheduleUnfreeze(context: Context, packageName: String, triggerAtEpochMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, UnfreezeReceiver::class.java).apply {
            action = UnfreezeReceiver.ACTION_UNFREEZE
            putExtra(UnfreezeReceiver.EXTRA_PACKAGE, packageName)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            packageName.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtEpochMs, pi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtEpochMs, pi)
        }
    }

    fun cancelUnfreeze(context: Context, packageName: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, UnfreezeReceiver::class.java).apply {
            action = UnfreezeReceiver.ACTION_UNFREEZE
            putExtra(UnfreezeReceiver.EXTRA_PACKAGE, packageName)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            packageName.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.cancel(pi)
    }
}

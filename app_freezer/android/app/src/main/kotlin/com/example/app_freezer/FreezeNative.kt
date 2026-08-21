package com.example.app_freezer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import org.json.JSONArray

/**
 * Fires when a freeze timer expires. Unsuspends the package and updates prefs.
 */
class UnfreezeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.getStringExtra(EXTRA_PACKAGE) ?: return
        FreezeNative.unsuspend(context, listOf(packageName))
        FreezeNative.removeFrozenPref(context, packageName)
    }

    companion object {
        const val EXTRA_PACKAGE = "packageName"
        const val ACTION_UNFREEZE = "com.example.app_freezer.ACTION_UNFREEZE"
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }
        FreezeNative.reconcileExpired(context)
        FreezeNative.reschedulePendingAlarms(context)
    }
}

object FreezeNative {
    private const val PREFS = "frozen_apps_native"
    private const val KEY_JSON = "entries" // JSON array of {packageName, unfreezeAtEpochMs}

    fun dpm(context: Context): DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun admin(context: Context): ComponentName =
        ComponentName(context, DeviceAdminReceiver::class.java)

    fun isDeviceOwner(context: Context): Boolean =
        dpm(context).isDeviceOwnerApp(context.packageName)

    fun suspend(context: Context, packages: List<String>): Boolean {
        if (!isDeviceOwner(context) || packages.isEmpty()) return false
        val result = dpm(context).setPackagesSuspended(admin(context), packages.toTypedArray(), true)
        return result.isEmpty()
    }

    fun unsuspend(context: Context, packages: List<String>): Boolean {
        if (!isDeviceOwner(context) || packages.isEmpty()) return false
        val result = dpm(context).setPackagesSuspended(admin(context), packages.toTypedArray(), false)
        return result.isEmpty()
    }

    fun saveFrozenPref(context: Context, packageName: String, unfreezeAtEpochMs: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY_JSON, "[]"))
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getString("packageName") != packageName) next.put(o)
        }
        next.put(
            org.json.JSONObject()
                .put("packageName", packageName)
                .put("unfreezeAtEpochMs", unfreezeAtEpochMs),
        )
        prefs.edit().putString(KEY_JSON, next.toString()).apply()
    }

    fun removeFrozenPref(context: Context, packageName: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY_JSON, "[]"))
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getString("packageName") != packageName) next.put(o)
        }
        prefs.edit().putString(KEY_JSON, next.toString()).apply()
    }

    fun reconcileExpired(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY_JSON, "[]"))
        val now = System.currentTimeMillis()
        val keep = JSONArray()
        val expired = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val pkg = o.getString("packageName")
            val at = o.getLong("unfreezeAtEpochMs")
            // Very far future = indefinite; skip auto-unfreeze
            if (at > now + 1000L * 60 * 60 * 24 * 365 * 50) {
                keep.put(o)
            } else if (at <= now) {
                expired.add(pkg)
            } else {
                keep.put(o)
            }
        }
        if (expired.isNotEmpty()) {
            unsuspend(context, expired)
        }
        prefs.edit().putString(KEY_JSON, keep.toString()).apply()
    }

    fun reschedulePendingAlarms(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY_JSON, "[]"))
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val pkg = o.getString("packageName")
            val at = o.getLong("unfreezeAtEpochMs")
            if (at > now && at < now + 1000L * 60 * 60 * 24 * 365 * 50) {
                AlarmHelper.scheduleUnfreeze(context, pkg, at)
            }
        }
    }
}

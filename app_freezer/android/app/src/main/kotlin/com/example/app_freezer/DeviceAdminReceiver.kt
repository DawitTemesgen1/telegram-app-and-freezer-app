package com.example.app_freezer

import android.content.Context
import android.content.Intent
import android.widget.Toast

class DeviceAdminReceiver : android.app.admin.DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        Toast.makeText(context, "App Freezer device admin enabled", Toast.LENGTH_SHORT).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Toast.makeText(context, "App Freezer device admin disabled", Toast.LENGTH_SHORT).show()
    }
}

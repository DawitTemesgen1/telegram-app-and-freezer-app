package com.example.app_freezer

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app_freezer/freeze"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceOwner" -> {
                    result.success(FreezeNative.isDeviceOwner(this))
                }
                "getSetupAdbCommand" -> {
                    result.success(
                        "adb shell dpm set-device-owner ${packageName}/.DeviceAdminReceiver",
                    )
                }
                "suspendPackages" -> {
                    if (!FreezeNative.isDeviceOwner(this)) {
                        result.error("NOT_DEVICE_OWNER", "App is not Device Owner", null)
                        return@setMethodCallHandler
                    }
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val unfreezeAt = call.argument<Number>("unfreezeAtEpochMs")?.toLong()
                    val ok = FreezeNative.suspend(this, packages)
                    if (ok && unfreezeAt != null) {
                        for (pkg in packages) {
                            FreezeNative.saveFrozenPref(this, pkg, unfreezeAt)
                            // Skip alarm for "indefinite" (very far future)
                            if (unfreezeAt < System.currentTimeMillis() + 1000L * 60 * 60 * 24 * 365 * 50) {
                                AlarmHelper.scheduleUnfreeze(this, pkg, unfreezeAt)
                            }
                        }
                    }
                    result.success(ok)
                }
                "unsuspendPackages" -> {
                    if (!FreezeNative.isDeviceOwner(this)) {
                        result.error("NOT_DEVICE_OWNER", "App is not Device Owner", null)
                        return@setMethodCallHandler
                    }
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val ok = FreezeNative.unsuspend(this, packages)
                    for (pkg in packages) {
                        AlarmHelper.cancelUnfreeze(this, pkg)
                        FreezeNative.removeFrozenPref(this, pkg)
                    }
                    result.success(ok)
                }
                "reconcileExpired" -> {
                    FreezeNative.reconcileExpired(this)
                    result.success(true)
                }
                "canScheduleExactAlarms" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val am = getSystemService(ALARM_SERVICE) as android.app.AlarmManager
                        result.success(am.canScheduleExactAlarms())
                    } else {
                        result.success(true)
                    }
                }
                "getInstalledApps" -> {
                    try {
                        val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
                        val pm = packageManager
                        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                        val appsList = ArrayList<Map<String, Any>>()
                        val self = packageName
                        for (appInfo in packages) {
                            if (appInfo.packageName == self) continue
                            val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                            val isUpdatedSystemApp =
                                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                            if (!includeSystemApps && isSystemApp && !isUpdatedSystemApp) {
                                continue
                            }
                            val launch = pm.getLaunchIntentForPackage(appInfo.packageName)
                            if (launch == null && !includeSystemApps) continue

                            val map = HashMap<String, Any>()
                            map["appName"] = pm.getApplicationLabel(appInfo).toString()
                            map["packageName"] = appInfo.packageName
                            map["isSystemApp"] = isSystemApp
                            try {
                                val drawable = pm.getApplicationIcon(appInfo)
                                val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
                                val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                val canvas = Canvas(bitmap)
                                drawable.setBounds(0, 0, canvas.width, canvas.height)
                                drawable.draw(canvas)
                                val scaled = Bitmap.createScaledBitmap(bitmap, 96, 96, true)
                                val stream = ByteArrayOutputStream()
                                scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)
                                map["icon"] = stream.toByteArray()
                            } catch (_: Exception) {
                            }
                            appsList.add(map)
                        }
                        result.success(appsList)
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

package com.productivity.and.wellbeing

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    private val channelName = "fullbright_track/step_service"
    private val deviceReadinessChannelName = "fullbright_track/device_readiness"
    private val connectivityChannelName = "fullbright_track/connectivity"
    private var activityPermissionResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    StepCounterService.start(this)
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, StepCounterService::class.java).setAction(StepCounterService.ACTION_STOP))
                    result.success(true)
                }
                "isRunning" -> result.success(StepCounterService.isMarkedRunning(this))
                "getCurrentState" -> result.success(readState())
                "diagnose" -> result.success(readDiagnosis())
                "seedState" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any> ?: emptyMap()
                    StepCounterService.seedState(this, args)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceReadinessChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "permissionDiagnostics" -> result.success(permissionDiagnostics())
                "requestActivityRecognition" -> requestActivityRecognition(result)
                "requestPostNotifications" -> requestPostNotifications(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, connectivityChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(connectivityStatus())
                else -> result.notImplemented()
            }
        }
    }

    private fun requestActivityRecognition(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || hasActivityPermission()) {
            result.success(true)
            return
        }

        if (!canRequestPermission(Manifest.permission.ACTIVITY_RECOGNITION)) {
            Log.w("FullBrightTrack", "Cannot request activity permission: ${permissionDiagnostics()}")
            result.success(false)
            return
        }

        if (activityPermissionResult != null) {
            result.success(false)
            return
        }

        activityPermissionResult = result
        Log.d("FullBrightTrack", "Requesting activity permission: ${permissionDiagnostics()}")
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            ACTIVITY_RECOGNITION_REQUEST_CODE
        )
    }

    private fun requestPostNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || hasNotificationPermission()) {
            result.success(true)
            return
        }

        if (!canRequestPermission(Manifest.permission.POST_NOTIFICATIONS)) {
            Log.w("FullBrightTrack", "Cannot request notification permission: ${permissionDiagnostics()}")
            result.success(false)
            return
        }

        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }

        notificationPermissionResult = result
        Log.d("FullBrightTrack", "Requesting notification permission: ${permissionDiagnostics()}")
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            POST_NOTIFICATIONS_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == ACTIVITY_RECOGNITION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            activityPermissionResult?.success(granted)
            activityPermissionResult = null
        } else if (requestCode == POST_NOTIFICATIONS_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivitySafely(intent)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBatteryOptimizations()) {
            return
        }

        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.data = Uri.parse("package:$packageName")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivityForBatteryRequest(intent)
    }

    private fun startActivitySafely(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(fallback)
        }
    }

    private fun startActivityForBatteryRequest(intent: Intent) {
        try {
            startActivity(intent)
        } catch (error: Exception) {
            Log.w("FullBrightTrack", "Could not open direct battery allow dialog", error)
        }
    }

    private fun readState(): Map<String, Any> {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        fun intValue(key: String): Int {
            return (prefs.all["flutter.$key"] as? Number)?.toInt() ?: 0
        }

        fun stringValue(key: String): String {
            return prefs.getString("flutter.$key", "") ?: ""
        }

        val savedDebug = stringValue("bg_debug")
        val diagnosis = readDiagnosis()
        val debugText = savedDebug.ifEmpty { diagnosis["debugText"] as String }
        val day = stringValue("bg_day").ifEmpty { LocalDate.now().toString() }

        return mapOf(
            "steps" to intValue("bg_steps"),
            "baseline" to intValue("bg_baseline"),
            "initialSteps" to intValue("bg_initial_steps"),
            "lastRawSteps" to intValue("bg_last_raw"),
            "anchorSteps" to intValue("bg_anchor"),
            "day" to day,
            "debugText" to debugText,
            "nativeRunning" to StepCounterService.isMarkedRunning(this),
            "hasActivityPermission" to diagnosis["hasActivityPermission"] as Boolean,
            "hasStepCounter" to diagnosis["hasStepCounter"] as Boolean,
            "hasStepDetector" to diagnosis["hasStepDetector"] as Boolean,
            "androidVersion" to Build.VERSION.SDK_INT
        )
    }

    private fun readDiagnosis(): Map<String, Any> {
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val hasActivityPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
        val hasStepCounter = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
        val hasStepDetector = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null
        val debugText = when {
            !hasActivityPermission -> "Native pedometer blocked: activity permission missing"
            !hasStepCounter && !hasStepDetector -> "Native pedometer failed: no Android step sensor found"
            StepCounterService.isMarkedRunning(this) && hasStepCounter -> "Native pedometer service requested: step counter available"
            StepCounterService.isMarkedRunning(this) && hasStepDetector -> "Native pedometer service requested: detector fallback available"
            hasStepCounter -> "Native pedometer ready but service is not marked running"
            else -> "Native pedometer ready but service is not marked running"
        }

        return mapOf(
            "debugText" to debugText,
            "hasActivityPermission" to hasActivityPermission,
            "hasStepCounter" to hasStepCounter,
            "hasStepDetector" to hasStepDetector,
            "nativeRunning" to StepCounterService.isMarkedRunning(this)
        )
    }

    private fun hasActivityPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun isPermissionDeclared(permission: String): Boolean {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            }
            packageInfo.requestedPermissions?.contains(permission) == true
        } catch (_: Exception) {
            false
        }
    }

    private fun canRequestPermission(permission: String): Boolean {
        return isPermissionDeclared(permission) &&
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
    }

    private fun permissionDiagnostics(): Map<String, Any> {
        val targetSdk = try {
            packageManager.getApplicationInfo(packageName, 0).targetSdkVersion
        } catch (_: Exception) {
            -1
        }

        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "targetSdk" to targetSdk,
            "activityDeclared" to isPermissionDeclared(Manifest.permission.ACTIVITY_RECOGNITION),
            "activityGranted" to hasActivityPermission(),
            "activityCanRequest" to canRequestPermission(Manifest.permission.ACTIVITY_RECOGNITION),
            "activityShouldShowRationale" to shouldShowRequestPermissionRationale(Manifest.permission.ACTIVITY_RECOGNITION),
            "notificationDeclared" to isPermissionDeclared(Manifest.permission.POST_NOTIFICATIONS),
            "notificationGranted" to hasNotificationPermission(),
            "notificationCanRequest" to canRequestPermission(Manifest.permission.POST_NOTIFICATIONS),
            "notificationShouldShowRationale" to shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
        )
    }

    private fun connectivityStatus(): Map<String, Any> {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork
        val capabilities = network?.let { connectivityManager.getNetworkCapabilities(it) }
        val transports = mutableListOf<String>()

        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
            transports.add("wifi")
        }
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) {
            transports.add("cellular")
        }
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) {
            transports.add("ethernet")
        }
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) {
            transports.add("vpn")
        }

        val validated = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        val hasInternetCapability = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val downstreamKbps = capabilities?.linkDownstreamBandwidthKbps ?: 0
        val upstreamKbps = capabilities?.linkUpstreamBandwidthKbps ?: 0
        val airplaneMode = Settings.Global.getInt(
            contentResolver,
            Settings.Global.AIRPLANE_MODE_ON,
            0
        ) == 1

        return mapOf(
            "airplaneMode" to airplaneMode,
            "hasNetwork" to (network != null),
            "hasInternetCapability" to hasInternetCapability,
            "validated" to validated,
            "transports" to transports,
            "downstreamKbps" to downstreamKbps,
            "upstreamKbps" to upstreamKbps
        )
    }

    companion object {
        private const val ACTIVITY_RECOGNITION_REQUEST_CODE = 7104
        private const val POST_NOTIFICATIONS_REQUEST_CODE = 7105
    }
}

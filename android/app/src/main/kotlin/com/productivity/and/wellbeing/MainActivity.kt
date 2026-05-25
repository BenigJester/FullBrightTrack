package com.productivity.and.wellbeing

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    private val channelName = "fullbright_track/step_service"

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
                else -> result.notImplemented()
            }
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
}

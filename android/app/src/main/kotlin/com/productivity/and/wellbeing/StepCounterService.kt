package com.productivity.and.wellbeing

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import kotlin.math.max

class StepCounterService : Service(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var counterRegistered = false
    private var detectorRegistered = false

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTracking()
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_REFRESH_REMINDER) {
            if (!hasActivityPermission()) {
                saveDebug("Native reminder refresh blocked: activity permission missing")
                markRunning(false)
                stopSelf()
                return START_NOT_STICKY
            }

            markRunning(true)
            startForeground(NOTIFICATION_ID, buildNotification(currentNotificationText()))
            if (counterRegistered || detectorRegistered) {
                updateNotification(currentNotificationText())
                return START_REDELIVER_INTENT
            }
            startTracking()
            return START_REDELIVER_INTENT
        }

        try {
            if (!hasActivityPermission()) {
                saveDebug("Native pedometer blocked: activity permission missing")
                markRunning(false)
                stopSelf()
                return START_NOT_STICKY
            }

            markRunning(true)
            startForeground(NOTIFICATION_ID, buildNotification(currentNotificationText()))

            if (counterRegistered || detectorRegistered) {
                saveDebug("Native pedometer already active: ${activeSensorNames()}")
                updateNotification(currentNotificationText())
                return START_REDELIVER_INTENT
            }

            saveDebug("Native pedometer service entered")
            startTracking()
        } catch (error: Exception) {
            saveDebug("Native pedometer crashed while starting: ${error.javaClass.simpleName}: ${error.message}")
            markRunning(false)
            stopSelf()
            return START_NOT_STICKY
        }

        return START_REDELIVER_INTENT
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        saveDebug("Native pedometer task removed: keeping service alive")
        start(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopTracking()
        markRunning(false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> handleCounterEvent(event.values.firstOrNull()?.toInt() ?: return)
            Sensor.TYPE_STEP_DETECTOR -> handleDetectorEvent()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun startTracking() {
        if (counterRegistered || detectorRegistered) {
            saveDebug("Native pedometer already active: ${activeSensorNames()}")
            updateNotification(currentNotificationText())
            return
        }

        val counter = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        val detector = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

        if (counter == null && detector == null) {
            saveDebug("Native pedometer failed: no step sensor on this phone")
            updateNotification("No step sensor found")
            return
        }

        counterRegistered = counter?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 0)
        } ?: false

        detectorRegistered = detector?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 0)
        } ?: false

        if (counterRegistered || detectorRegistered) {
            val notificationStatus = if (hasNotificationPermission()) {
                ""
            } else {
                " (notification permission is off)"
            }
            saveDebug("Native pedometer active: ${activeSensorNames()}$notificationStatus")
            updateNotification(currentNotificationText())
        } else {
            saveDebug("Native pedometer failed: sensor listener rejected")
            updateNotification("Pedometer could not start")
        }
    }

    private fun stopTracking() {
        sensorManager.unregisterListener(this)
        counterRegistered = false
        detectorRegistered = false
        saveDebug("Native pedometer stopped")
    }

    private fun handleCounterEvent(rawSteps: Int) {
        val today = todayKey()
        val savedDay = readString(KEY_DAY)

        if (savedDay != today) {
            val previous = currentState()
            if (previous.day.isNotBlank()) enqueueSave(previous, previous.day)
            writeState(
                StepState(
                    steps = 0,
                    baseline = rawSteps,
                    initialSteps = 0,
                    lastRawSteps = rawSteps,
                    anchorSteps = 0,
                    detectorPendingSteps = 0,
                    day = today,
                    debugText = "Native pedometer active: new day baseline set"
                )
            )
            updateNotification("0 steps today")
            return
        }

        val state = currentState()
        val baselineWasMissing = state.baseline <= 0
        val baseline = if (baselineWasMissing) rawSteps else state.baseline
        val lastRaw = state.lastRawSteps
        val rawJump = rawSteps - lastRaw

        if (lastRaw > 0 && rawJump > MAX_REASONABLE_STEP_JUMP) {
            saveDebug("Native pedometer ignored a large sensor jump: ${rawSteps - lastRaw}")
            return
        }

        val sensorReset = lastRaw > 0 && rawSteps < lastRaw
        val counterDelta = if (lastRaw > 0 && !sensorReset) max(0, rawJump) else 0
        val detectorPending = state.detectorPendingSteps
        val baselineForCalculation = if (sensorReset || detectorPending > 0) rawSteps else baseline
        val anchorSteps = when {
            sensorReset || baselineWasMissing -> state.steps
            else -> state.anchorSteps
        }
        val calculatedSteps = if (detectorPending > 0) {
            state.steps + max(0, counterDelta - detectorPending)
        } else {
            val delta = max(0, rawSteps - baselineForCalculation)
            max(state.steps, anchorSteps + delta)
        }

        val next = StepState(
            steps = calculatedSteps,
            baseline = baselineForCalculation,
            initialSteps = state.initialSteps,
            lastRawSteps = rawSteps,
            anchorSteps = calculatedSteps,
            detectorPendingSteps = 0,
            day = today,
            debugText = "Native pedometer active: $calculatedSteps steps"
        )

        writeState(next)
        enqueueSave(next, today)
        updateNotification("$calculatedSteps steps today")
    }

    private fun handleDetectorEvent() {
        val today = todayKey()
        val savedDay = readString(KEY_DAY)

        if (savedDay != today) {
            val previous = currentState()
            if (previous.day.isNotBlank()) enqueueSave(previous, previous.day)
            writeState(
                StepState(
                    steps = 1,
                    baseline = 0,
                    initialSteps = 0,
                    lastRawSteps = 0,
                    anchorSteps = 1,
                    detectorPendingSteps = 0,
                    day = today,
                    debugText = "Native pedometer active: detector fallback"
                )
            )
            updateNotification("1 step today")
            return
        }

        val state = currentState()
        val nextSteps = state.steps + 1
        val detectorPending = if (counterRegistered) state.detectorPendingSteps + 1 else 0
        val next = state.copy(
            steps = nextSteps,
            anchorSteps = if (counterRegistered) state.anchorSteps else nextSteps,
            detectorPendingSteps = detectorPending,
            debugText = "Native pedometer active: $nextSteps steps"
        )

        writeState(next)
        enqueueSave(next, today)
        updateNotification("$nextSteps steps today")
    }

    private fun currentState(): StepState {
        return StepState(
            steps = readInt(KEY_STEPS),
            baseline = readInt(KEY_BASELINE),
            initialSteps = readInt(KEY_INITIAL_STEPS),
            lastRawSteps = readInt(KEY_LAST_RAW),
            anchorSteps = readInt(KEY_ANCHOR),
            detectorPendingSteps = readInt(KEY_DETECTOR_PENDING),
            day = readString(KEY_DAY),
            debugText = readString(KEY_DEBUG)
        )
    }

    private fun writeState(state: StepState) {
        prefs().edit()
            .putLong(prefKey(KEY_STEPS), state.steps.toLong())
            .putLong(prefKey(KEY_BASELINE), state.baseline.toLong())
            .putLong(prefKey(KEY_INITIAL_STEPS), state.initialSteps.toLong())
            .putLong(prefKey(KEY_LAST_RAW), state.lastRawSteps.toLong())
            .putLong(prefKey(KEY_ANCHOR), state.anchorSteps.toLong())
            .putLong(prefKey(KEY_DETECTOR_PENDING), state.detectorPendingSteps.toLong())
            .putString(prefKey(KEY_DAY), state.day)
            .putString(prefKey(KEY_DEBUG), state.debugText)
            .apply()
    }

    private fun enqueueSave(state: StepState, day: String) {
        if (day.isBlank()) return

        val raw = readString(KEY_QUEUE)
        val queue = if (raw.isNotBlank()) JSONArray(raw) else JSONArray()
        val next = JSONArray()

        for (index in 0 until queue.length()) {
            val item = queue.optJSONObject(index) ?: continue
            if (item.optString("day") != day) next.put(item)
        }

        next.put(
            JSONObject()
                .put("day", day)
                .put("steps", state.steps)
                .put("baseline", state.baseline)
                .put("lastRawSteps", state.lastRawSteps)
                .put("timestamp", System.currentTimeMillis())
        )

        val trimmed = JSONArray()
        val start = max(0, next.length() - 60)
        for (index in start until next.length()) trimmed.put(next.get(index))

        prefs().edit().putString(prefKey(KEY_QUEUE), trimmed.toString()).apply()
    }

    private fun saveDebug(message: String) {
        prefs().edit().putString(prefKey(KEY_DEBUG), message).apply()
    }

    private fun markRunning(running: Boolean) {
        prefs().edit().putBoolean(prefKey(KEY_RUNNING), running).apply()
    }

    private fun readInt(key: String): Int {
        return (prefs().all[prefKey(key)] as? Number)?.toInt() ?: 0
    }

    private fun readString(key: String): String {
        return prefs().getString(prefKey(key), "") ?: ""
    }

    private fun prefs() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun prefKey(key: String) = "flutter.$key"

    private fun todayKey(): String = LocalDate.now().toString()

    private fun hasActivityPermission(): Boolean {
        return hasActivityPermission(this)
    }

    private fun hasNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Steps Reminder",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Live step reminder while FullBrightTrack tracks steps"
        }

        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): android.app.Notification {
        val reminderReady = shouldRefreshReminderNotification()
        val title = if (reminderReady) "Step Reminder" else "Step tracking active"
        val content = if (reminderReady) {
            text
        } else {
            "Reminder starts at ${minimumReminderSteps()} steps"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(content)
            .setOngoing(false)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(text: String) {
        if (!shouldRefreshReminderNotification()) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun shouldRefreshReminderNotification(): Boolean {
        if (!prefs().getBoolean(prefKey(KEY_REMINDERS_ENABLED), true)) return false

        return readInt(KEY_STEPS) >= minimumReminderSteps()
    }

    private fun minimumReminderSteps(): Int {
        return readInt(KEY_MIN_REMINDER_STEPS).coerceAtLeast(100)
    }

    private fun currentNotificationText(): String {
        val steps = readInt(KEY_STEPS)
        return "$steps steps today"
    }

    private fun activeSensorNames(): String {
        return listOfNotNull(
            if (counterRegistered) "step counter" else null,
            if (detectorRegistered) "step detector" else null
        ).joinToString(" + ").ifEmpty { "none" }
    }

    data class StepState(
        val steps: Int,
        val baseline: Int,
        val initialSteps: Int,
        val lastRawSteps: Int,
        val anchorSteps: Int,
        val detectorPendingSteps: Int,
        val day: String,
        val debugText: String
    )

    companion object {
        const val ACTION_START = "com.productivity.and.wellbeing.START_STEPS"
        const val ACTION_STOP = "com.productivity.and.wellbeing.STOP_STEPS"
        const val ACTION_REFRESH_REMINDER = "com.productivity.and.wellbeing.REFRESH_STEP_REMINDER"

        private const val CHANNEL_ID = "hourly_steps"
        private const val NOTIFICATION_ID = 100
        private const val MAX_REASONABLE_STEP_JUMP = 5000

        private const val KEY_STEPS = "bg_steps"
        private const val KEY_BASELINE = "bg_baseline"
        private const val KEY_INITIAL_STEPS = "bg_initial_steps"
        private const val KEY_LAST_RAW = "bg_last_raw"
        private const val KEY_ANCHOR = "bg_anchor"
        private const val KEY_DETECTOR_PENDING = "bg_detector_pending"
        private const val KEY_DAY = "bg_day"
        private const val KEY_DEBUG = "bg_debug"
        private const val KEY_QUEUE = "steps_queue"
        private const val KEY_RUNNING = "bg_native_running"
        private const val KEY_REMINDERS_ENABLED = "hourly_step_reminders_enabled"
        private const val KEY_MIN_REMINDER_STEPS = "step_reminder_min_steps"

        fun start(context: Context) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            if (!hasActivityPermission(context)) {
                prefs.edit()
                    .putString("flutter.$KEY_DEBUG", "Native pedometer waiting for activity permission")
                    .putBoolean("flutter.$KEY_RUNNING", false)
                    .apply()
                return
            }

            val intent = Intent(context, StepCounterService::class.java).setAction(ACTION_START)
            if (!prefs.getBoolean("flutter.$KEY_RUNNING", false)) {
                prefs.edit()
                    .putString("flutter.$KEY_DEBUG", "Native pedometer start requested")
                    .apply()
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit()
                    .putString("flutter.$KEY_DEBUG", "Native pedometer could not start: ${error.message}")
                    .putBoolean("flutter.$KEY_RUNNING", false)
                    .apply()
            }
        }

        fun refreshReminder(context: Context) {
            val intent = Intent(context, StepCounterService::class.java).setAction(ACTION_REFRESH_REMINDER)

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit()
                    .putString("flutter.$KEY_DEBUG", "Native reminder refresh failed: ${error.message}")
                    .apply()
            }
        }

        fun isMarkedRunning(context: Context): Boolean {
            return context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.$KEY_RUNNING", false)
        }

        fun seedState(context: Context, args: Map<String, Any>) {
            fun intArg(key: String): Int {
                return (args[key] as? Number)?.toInt() ?: 0
            }

            val day = args["day"] as? String ?: LocalDate.now().toString()
            val steps = intArg("steps")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val currentDay = prefs.getString("flutter.$KEY_DAY", "") ?: ""
            val currentBaseline = (prefs.all["flutter.$KEY_BASELINE"] as? Number)?.toInt() ?: 0
            val currentSteps = (prefs.all["flutter.$KEY_STEPS"] as? Number)?.toInt() ?: 0

            if (isMarkedRunning(context) && currentDay == day && currentBaseline > 0 && currentSteps >= steps) {
                start(context)
                return
            }

            val baseline = intArg("baseline")
            val anchorSteps = intArg("anchorSteps")

            prefs.edit()
                .putLong("flutter.$KEY_STEPS", steps.toLong())
                .putLong("flutter.$KEY_BASELINE", baseline.toLong())
                .putLong("flutter.$KEY_INITIAL_STEPS", intArg("initialSteps").toLong())
                .putLong("flutter.$KEY_LAST_RAW", intArg("lastRawSteps").toLong())
                .putLong("flutter.$KEY_ANCHOR", anchorSteps.toLong())
                .putLong("flutter.$KEY_DETECTOR_PENDING", 0)
                .putString("flutter.$KEY_DAY", day)
                .putString("flutter.$KEY_DEBUG", "Native state seeded from Firestore: $steps steps")
                .apply()

            start(context)
        }

        fun hasActivityPermission(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED
        }
    }
}

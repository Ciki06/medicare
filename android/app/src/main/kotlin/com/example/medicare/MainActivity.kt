package com.example.medicare

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

// Exposes Android alarm, camera and widget actions to Flutter.
class MainActivity : FlutterActivity() {
    companion object {
        private const val DEEP_LINK_CHANNEL = "medicare/deeplinks"
        private const val CALL_CAMERA_PERMISSION = 35103
    }

    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    private var callActivityResumed = false
    private var cameraPermissionResult: MethodChannel.Result? = null
    private val callHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private data class PendingCallResume(val ready: () -> Unit, val timeout: Runnable, val cancel: () -> Unit)
    private val pendingCallResumes = mutableListOf<PendingCallResume>()

    override fun onResume() {
        super.onResume()
        callActivityResumed = true
        finishCameraPermissionIfReady()
        val waiting = pendingCallResumes.toList()
        pendingCallResumes.clear()
        for (pending in waiting) {
            callHandler.removeCallbacks(pending.timeout)
            pending.ready()
        }
    }

    override fun onPause() {
        callActivityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        cancelPendingCallResumes()
        cameraPermissionResult?.error("camera_permission_cancelled", "The call screen was closed.", null)
        cameraPermissionResult = null
        super.onDestroy()
    }

    private fun cancelPendingCallResumes() {
        val waiting = pendingCallResumes.toList()
        pendingCallResumes.clear()
        for (pending in waiting) {
            callHandler.removeCallbacks(pending.timeout)
            pending.cancel()
        }
    }

    private fun startCallService(result: MethodChannel.Result, camera: Boolean = false) {
        val ready: () -> Unit = {
            if (androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                result.error("call_service_failed", "Allow microphone access before starting a call.", null)
            } else if (!callActivityResumed && (!VoiceCallForegroundService.active || camera)) {
                result.error("call_not_visible", "Return to the call before starting its microphone or camera.", null)
            } else {
                VoiceCallForegroundService.ensureStarted(this) { error ->
                    if (error != null) {
                        result.error("call_service_failed", error.message, null)
                    } else {
                        try {
                            if (camera && !callActivityResumed) {
                                throw IllegalStateException("Return to the call before enabling your camera.")
                            }
                            result.success(if (camera) VoiceCallForegroundService.setCameraEnabled(true) else null)
                        } catch (upgradeError: Exception) {
                            result.error("call_service_failed", upgradeError.message, null)
                        }
                    }
                }
            }
        }
        if (callActivityResumed || VoiceCallForegroundService.active || camera) {
            ready()
        } else {
            // getUserMedia may return a microphone permission grant before the
            // activity resumes. Wait briefly instead of starting a while-in-use
            // service from the background or breaking the first voice call.
            lateinit var pending: PendingCallResume
            val timeout = Runnable {
                if (pendingCallResumes.remove(pending)) {
                    result.error("call_not_visible", "Open MediCare to start or answer the call, then try again.", null)
                }
            }
            pending = PendingCallResume(ready, timeout) {
                result.error("call_service_failed", "The call service start was cancelled.", null)
            }
            pendingCallResumes.add(pending)
            callHandler.postDelayed(timeout, 8000L)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_CAMERA_PERMISSION || cameraPermissionResult == null) return
        if (grantResults.firstOrNull() != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            cameraPermissionResult?.success(false)
            cameraPermissionResult = null
        } else {
            // Permission dialogs pause the activity. Do not let Dart upgrade a
            // camera foreground service until the activity is visible again.
            finishCameraPermissionIfReady()
        }
    }

    private fun finishCameraPermissionIfReady() {
        if (callActivityResumed && androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            cameraPermissionResult?.success(true)
            cameraPermissionResult = null
        }
    }

    private fun requestCallCameraPermission(result: MethodChannel.Result) {
        if (!callActivityResumed) {
            result.error("call_not_visible", "Return to the call before enabling your camera.", null)
        } else if (cameraPermissionResult != null) {
            result.error("permission_in_progress", "A camera permission request is already open.", null)
        } else if (androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            result.success(true)
        } else {
            cameraPermissionResult = result
            try {
                requestPermissions(arrayOf(android.Manifest.permission.CAMERA), CALL_CAMERA_PERMISSION)
            } catch (error: RuntimeException) {
                cameraPermissionResult = null
                result.error("camera_permission_failed", error.message, null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        handleAppointmentOpen(intent)
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medicare/reminder_audio").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "reconcile" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        result.success(ReminderAlarmScheduler.reconcile(this, items,
                            call.argument<String>("group") ?: "main",
                            call.argument<List<Map<String, Any?>>>("retain")))
                    }
                    "cancel" -> { ReminderAlarmScheduler.cancel(this, call.argument<Number>("id")!!.toInt()); result.success(null) }
                    "cancelAll" -> { ReminderAlarmScheduler.cancelAll(this); result.success(null) }
                    "dismissedAppointments" -> result.success(AppointmentAlarmStore.dismissed(this))
                    "stopSpeech" -> {
                        val payload = call.argument<String>("payload")
                        if (payload?.startsWith("appointment:") == true) AppointmentAlarmService.dismiss(this, payload = payload)
                        if (ReminderSpeechService.active) startService(
                            Intent(this, ReminderSpeechService::class.java)
                                .setAction(ReminderSpeechService.CANCEL_PAYLOAD)
                                .putExtra("payload", call.argument<String>("payload")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("reminder_audio_failed", e.message, null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medicare/patient_alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        AppointmentAlarmService.pauseForPriority(this)
                        val alarm = Intent(this, PatientAlarmService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(alarm) else startService(alarm)
                        result.success(null)
                    } catch (e: Exception) { result.error("alarm_failed", e.message, null) }
                }
                "stop" -> { stopService(Intent(this, PatientAlarmService::class.java)); result.success(null) }
                "isActive" -> result.success(PatientAlarmService.active)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medicare/voice_call").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> startCallService(result)
                    "cameraPermission" -> requestCallCameraPermission(result)
                    "camera" -> {
                        val enabled = call.argument<Boolean>("enabled")
                            ?: throw IllegalArgumentException("A camera enabled value is required.")
                        if (enabled && !callActivityResumed) {
                            throw IllegalStateException("Return to the call before enabling your camera.")
                        }
                        if (enabled) startCallService(result, camera = true)
                        else result.success(VoiceCallForegroundService.setCameraEnabled(false))
                    }
                    "stop" -> { cancelPendingCallResumes(); VoiceCallForegroundService.stop(this); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("call_service_failed", e.message, null) }
        }
        pendingDeepLink = intent?.dataString
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeInitialDeepLink" -> {
                        result.success(pendingDeepLink)
                        // Cold-start links are consumed once; warm links use onNewIntent.
                        pendingDeepLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        handleAppointmentOpen(intent)
        super.onNewIntent(intent)
        setIntent(intent)
        val deepLink = intent.dataString ?: return
        pendingDeepLink = deepLink
        deepLinkChannel?.invokeMethod("onDeepLink", deepLink)
    }

    private fun handleAppointmentOpen(intent: Intent?) {
        if (intent?.action != "SELECT_NOTIFICATION") return
        try {
            val occurrence = intent.getStringExtra(AppointmentAlarmService.OPEN_ITEM)?.let(::JSONObject)
            if (occurrence != null) {
                // This launcher activity is exported. Notification extras may
                // acknowledge only an occurrence already owned by our service.
                AppointmentAlarmStore.active(this).firstOrNull {
                    it.optInt("id") == occurrence.optInt("id") &&
                        AppointmentAlarmStore.key(it) == AppointmentAlarmStore.key(occurrence)
                }?.let { AppointmentAlarmService.dismiss(this, occurrence = it) }
            }
            else intent.getStringExtra("payload")?.takeIf { it.startsWith("appointment:") }?.let {
                AppointmentAlarmService.dismiss(this, payload = it)
            }
        } catch (error: Exception) {
            android.util.Log.e("AppointmentAlarm", "Could not stop opened appointment alarm", error)
        }
    }
}

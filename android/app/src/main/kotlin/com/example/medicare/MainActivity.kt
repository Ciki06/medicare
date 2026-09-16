package com.example.medicare

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEEP_LINK_CHANNEL = "medicare/deeplinks"
    }

    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medicare/patient_alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
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
                val service = Intent(this, VoiceCallForegroundService::class.java)
                when (call.method) {
                    "start" -> { if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service); result.success(null) }
                    "stop" -> { stopService(service); result.success(null) }
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
                        pendingDeepLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val deepLink = intent.dataString ?: return
        pendingDeepLink = deepLink
        deepLinkChannel?.invokeMethod("onDeepLink", deepLink)
    }
}

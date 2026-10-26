package com.example.medicare

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Keeps the current WebRTC microphone/camera session visible to Android. */
class VoiceCallForegroundService : Service() {
    companion object {
        private var instance: VoiceCallForegroundService? = null
        private const val START_TOKEN = "call_start_token"
        private const val START_TIMEOUT_MS = 8000L
        private val mainHandler = Handler(Looper.getMainLooper())
        private var nextStartToken = 0
        private var pendingStartToken: Int? = null
        private var startTimeout: Runnable? = null
        private val startCallbacks = mutableListOf<(Exception?) -> Unit>()

        val active: Boolean get() = instance != null

        /** Completes only after Android has accepted the foreground notification/type. */
        fun ensureStarted(context: Context, callback: (Exception?) -> Unit) {
            if (active) {
                callback(null)
                return
            }
            startCallbacks.add(callback)
            if (pendingStartToken != null) return
            val token = ++nextStartToken
            pendingStartToken = token
            val application = context.applicationContext
            val service = Intent(application, VoiceCallForegroundService::class.java)
                .putExtra(START_TOKEN, token)
            startTimeout = Runnable {
                if (pendingStartToken == token) {
                    try {
                        application.stopService(service)
                    } catch (stopError: Exception) {
                        android.util.Log.e("VoiceCall", "Could not clean up timed-out call service", stopError)
                    }
                    finishStart(token, IllegalStateException("The call service did not start. Return to MediCare and try again."))
                }
            }.also { mainHandler.postDelayed(it, START_TIMEOUT_MS) }
            try {
                if (Build.VERSION.SDK_INT >= 26) application.startForegroundService(service)
                else application.startService(service)
            } catch (error: Exception) {
                finishStart(token, error)
            }
        }

        fun stop(context: Context) {
            instance?.cameraEnabled = false
            instance = null
            try {
                context.stopService(Intent(context, VoiceCallForegroundService::class.java))
            } finally {
                pendingStartToken?.let {
                    finishStart(it, IllegalStateException("The call service start was cancelled."))
                }
            }
        }

        private fun finishStart(token: Int, error: Exception?) {
            if (pendingStartToken != token) return
            pendingStartToken = null
            startTimeout?.let(mainHandler::removeCallbacks)
            startTimeout = null
            val callbacks = startCallbacks.toList()
            startCallbacks.clear()
            for (callback in callbacks) {
                try {
                    callback(error)
                } catch (callbackError: Exception) {
                    android.util.Log.e("VoiceCall", "Could not complete call service start", callbackError)
                }
            }
        }

        /** Called on the main thread, before starting or after stopping camera capture. */
        fun setCameraEnabled(enabled: Boolean): Boolean {
            val service = instance ?: if (!enabled) return false else
                throw IllegalStateException("Start a voice call before enabling the camera.")
            if (enabled && ContextCompat.checkSelfPermission(service, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                throw SecurityException("Allow camera access before enabling video.")
            }
            // startForeground is synchronous: callers must not open the camera
            // until Android has accepted the upgraded service type.
            service.showForeground(enabled)
            service.cameraEnabled = enabled
            return true
        }
    }

    private var cameraEnabled = false

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val token = intent?.getIntExtra(START_TOKEN, -1) ?: -1
        if (token != pendingStartToken) {
            // A cancelled/timed-out request must not revive capture or resolve a
            // later call's start. Duplicate starts never demote an active camera.
            if (instance !== this) stopSelfResult(startId)
            return START_NOT_STICKY
        }
        try {
            showForeground(cameraEnabled)
            instance = this
            finishStart(token, null)
        } catch (error: Exception) {
            android.util.Log.e("VoiceCall", "Could not start call foreground service", error)
            if (instance === this) instance = null
            stopSelfResult(startId)
            finishStart(token, error)
        }
        return START_NOT_STICKY
    }

    private fun showForeground(camera: Boolean) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("active_voice_call", "Active voice call", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, "active_voice_call")
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(if (camera) "MediCare video call" else "MediCare voice call")
            .setContentText("Tap to return to your call and end it.").setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true).setCategory(NotificationCompat.CATEGORY_CALL).build()
        when {
            Build.VERSION.SDK_INT >= 30 -> startForeground(735102, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    (if (camera) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0))
            Build.VERSION.SDK_INT >= 29 -> startForeground(735102, notification,
                if (camera) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0)
            else -> startForeground(735102, notification)
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        cameraEnabled = false
        super.onDestroy()
    }
}

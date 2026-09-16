package com.example.medicare

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/** Keeps the microphone session visible while an accepted WebRTC call is active. */
class VoiceCallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("active_voice_call", "Active voice call", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, "active_voice_call")
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle("MediCare voice call")
            .setContentText("Tap to return to your call and end it.").setContentIntent(open)
            .setOngoing(true).setCategory(NotificationCompat.CATEGORY_CALL).build()
        if (Build.VERSION.SDK_INT >= 30) startForeground(735102, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(735102, notification)
        return START_NOT_STICKY
    }
}

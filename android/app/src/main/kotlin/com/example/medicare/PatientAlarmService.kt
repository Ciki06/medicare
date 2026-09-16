package com.example.medicare

import android.app.*
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder

/** Patient locator siren: owned by a service, not the Flutter route. */
class PatientAlarmService : Service() {
    companion object {
        @Volatile var active = false
        const val STOP = "medicare.STOP_PATIENT_ALARM"
        private const val CHANNEL = "patient_locator_alarm_v1"
        private const val ID = 901001
    }
    private var player: MediaPlayer? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Patient SOS locator", NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null)
                description = "Controls the continuous SOS sound on this phone"
            })
        }
        val stop = PendingIntent.getService(this, 0, Intent(this, PatientAlarmService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        startForeground(ID, builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SOS locator alarm is sounding")
            .setContentText("Tap Stop alarm to silence this phone")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop alarm", stop).build()).build())
        if (player == null) {
            try {
                player = MediaPlayer().apply {
                    setWakeMode(applicationContext, android.os.PowerManager.PARTIAL_WAKE_LOCK)
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    resources.openRawResourceFd(R.raw.sos_alarm).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                    isLooping = true
                    setVolume(1f, 1f)
                    prepare()
                    start()
                }
                active = true
            } catch (error: Exception) {
                android.util.Log.e("PatientAlarm", "Unable to play SOS", error)
                stopSelf()
            }
        }
        return START_STICKY
    }
    override fun onDestroy() {
        player?.stop()
        player?.release()
        player = null
        active = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

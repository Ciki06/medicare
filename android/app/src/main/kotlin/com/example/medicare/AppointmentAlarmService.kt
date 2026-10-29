package com.example.medicare

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.*
import android.net.Uri
import android.os.*
import org.json.JSONObject

/** Appointment-only persistent audio; medication speech keeps its own service. */
class AppointmentAlarmService : Service() {
    companion object {
        const val SYNC = "medicare.SYNC_APPOINTMENT_ALARMS"
        const val DISMISS = "medicare.DISMISS_APPOINTMENT_ALARM"
        private const val PRIORITY_PAUSE = "medicare.PAUSE_APPOINTMENT_ALARM_FOR_PRIORITY"
        const val OPEN_ITEM = "medicareAppointmentAlarm"
        const val CHANNEL = "appointment_alarm_service_v1"
        private const val FALLBACK_CHANNEL = "appointment_alarm_fallback_v4"
        private const val SPEECH = "It's time to go to your appointment."
        private const val RETRY_MS = 2000L
        @Volatile var active = false
            private set
        @Volatile var ringing = false
            private set

        private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

        private fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            manager(context).createNotificationChannel(NotificationChannel(
                CHANNEL, "Appointment alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Persistent appointment alarm controls"
                setSound(null, null)
                enableVibration(false)
            })
            manager(context).createNotificationChannel(NotificationChannel(
                FALLBACK_CHANNEL, "Appointment alarms (system fallback)", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Appointment alarms when foreground audio is unavailable"
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), alarmAttributes())
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 600, 250, 600, 250, 900)
            })
        }

        private fun alarmAttributes() = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()

        private fun canNotify(context: Context, channel: String): Boolean =
            manager(context).areNotificationsEnabled() &&
                (Build.VERSION.SDK_INT < 26 || manager(context).getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE)

        private fun notification(context: Context, item: JSONObject, fallback: Boolean = false): Notification {
            channels(context)
            val id = item.getInt("id")
            val at = item.getLong("at")
            val dismiss = PendingIntent.getBroadcast(context, id,
                Intent(context, AppointmentAlarmActionReceiver::class.java).setAction(DISMISS)
                    .setData(Uri.parse("medicare-appointment-stop:$id:$at"))
                    .putExtra("reminder", item.toString()),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(context, id,
                Intent(context, MainActivity::class.java).setAction("SELECT_NOTIFICATION")
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("notificationId", id).putExtra("payload", item.optString("payload"))
                    .putExtra(OPEN_ITEM, item.toString()),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26)
                Notification.Builder(context, if (fallback) FALLBACK_CHANNEL else CHANNEL)
            else Notification.Builder(context)
            val body = item.optString("body").ifBlank { SPEECH }
            builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(item.optString("title").ifBlank { "Appointment Reminder" })
                .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open).setDeleteIntent(dismiss)
                .setOngoing(true).setAutoCancel(false).setOnlyAlertOnce(!fallback)
                .setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PRIVATE)
                .addAction(Notification.Action.Builder(null, "Stop alarm", dismiss).build())
            if (Build.VERSION.SDK_INT < 26 && fallback) {
                @Suppress("DEPRECATION")
                builder.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), AudioManager.STREAM_ALARM)
                    .setVibrate(longArrayOf(0, 600, 250, 600, 250, 900))
            }
            return builder.build().apply { if (fallback) flags = flags or Notification.FLAG_INSISTENT }
        }

        /** Called by the exact-alarm receiver. Never changes medication delivery. */
        fun deliver(context: Context, item: JSONObject) {
            if (!AppointmentAlarmStore.remember(context, item)) return
            try {
                val intent = Intent(context, AppointmentAlarmService::class.java)
                    .putExtra("reminder", item.toString())
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (error: Exception) {
                android.util.Log.w("AppointmentAlarm", "Foreground audio unavailable; using system alarm notification", error)
                postFallback(context, item)
            }
        }

        private fun postFallback(context: Context, item: JSONObject) {
            channels(context)
            if (canNotify(context, FALLBACK_CHANNEL)) {
                manager(context).notify(item.getInt("id"), notification(context, item, fallback = true))
            }
        }

        /** User actions silence first, independently of Flutter/Firebase availability. */
        fun dismiss(context: Context, id: Int? = null, payload: String? = null,
                    at: Long? = null, occurrence: JSONObject? = null) {
            val targets = if (occurrence != null) listOf(occurrence) else
                AppointmentAlarmStore.active(context).filter {
                    (id == null || it.optInt("id") == id) &&
                        (payload == null || it.optString("payload") == payload) &&
                        (at == null || it.optLong("at") == at)
                }
            try {
                if (occurrence != null) AppointmentAlarmStore.dismissItem(context, occurrence)
                else AppointmentAlarmStore.dismiss(context, id, payload, at)
            } catch (error: Exception) {
                // Disk failure must never make a user's Stop action ineffective.
                android.util.Log.e("AppointmentAlarm", "Could not persist alarm dismissal", error)
            } finally {
                targets.forEach { manager(context).cancel(it.getInt("id")) }
                if (active) {
                    val control = Intent(context, AppointmentAlarmService::class.java).setAction(DISMISS)
                    id?.let { control.putExtra("id", it) }
                    payload?.let { control.putExtra("payload", it) }
                    at?.let { control.putExtra("at", it) }
                    occurrence?.let { control.putExtra("reminder", it.toString()) }
                    context.startService(control)
                }
            }
        }

        /** Retained past/unviewed occurrences keep ringing across reconciliation. */
        fun sync(context: Context) {
            if (active) context.startService(Intent(context, AppointmentAlarmService::class.java).setAction(SYNC))
            else AppointmentAlarmStore.active(context).firstOrNull()?.let { deliver(context, it) }
        }

        fun pauseForPriority(context: Context) {
            if (active) context.startService(Intent(context, AppointmentAlarmService::class.java).setAction(PRIORITY_PAUSE))
        }

        fun stopAll(context: Context) {
            val removed = AppointmentAlarmStore.retain(context, emptyList())
            removed.forEach { manager(context).cancel(it.getInt("id")) }
            context.stopService(Intent(context, AppointmentAlarmService::class.java))
        }

        fun restore(context: Context, fromBoot: Boolean) {
            val pending = AppointmentAlarmStore.active(context)
            if (pending.isEmpty()) return
            if (fromBoot && Build.VERSION.SDK_INT >= 35) {
                // Android 15 forbids mediaPlayback FGS starts from BOOT_COMPLETED.
                // Use the platform alarm-notification fallback and its native
                // Stop controls instead of starting a prohibited service.
                pending.forEach { postFallback(context, it) }
            } else sync(context)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val ignored = mutableSetOf<String>()
    private var foregroundId: Int? = null
    private var loop: MediaPlayer? = null
    private var loopPrepared = false
    private var voice: MediaPlayer? = null
    private var voiceItem: JSONObject? = null
    private var focus: AudioFocusRequest? = null
    private var focusGranted = false
    private var wake: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private var destroyed = false
    private var priorityPauseUntil = 0L
    private val completedVoices = mutableSetOf<String>()
    private val retry = Runnable { resumeAudio() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (intent?.action == PRIORITY_PAUSE) priorityPauseUntil = SystemClock.elapsedRealtime() + 3000
            if (intent?.action == DISMISS) {
                val occurrence = intent.getStringExtra("reminder")?.let(::JSONObject)
                AppointmentAlarmStore.active(this).filter {
                    if (occurrence != null) AppointmentAlarmStore.key(it) == AppointmentAlarmStore.key(occurrence)
                    else (!intent.hasExtra("id") || it.optInt("id") == intent.getIntExtra("id", -1)) &&
                        (!intent.hasExtra("payload") || it.optString("payload") == intent.getStringExtra("payload")) &&
                        (!intent.hasExtra("at") || it.optLong("at") == intent.getLongExtra("at", -1))
                }.forEach { ignored.add(AppointmentAlarmStore.key(it)) }
            } else intent?.getStringExtra("reminder")?.let {
                AppointmentAlarmStore.remember(this, JSONObject(it))
            }
            val items = items()
            if (items.isEmpty()) { stopSelf(); return START_NOT_STICKY }
            channels(this)
            if (!canNotify(this, CHANNEL)) {
                // An endless sound needs a visible Stop control. Respect the
                // user's notification/channel settings instead of trapping it.
                stopSelf()
                return START_NOT_STICKY
            }
            active = true
            updateNotifications(items)
            if (wake == null) wake = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "medicare:appointmentAlarm").apply {
                    setReferenceCounted(false); acquire()
                }
            vibrateOnce()
            resumeAudio()
            return START_STICKY
        } catch (error: Exception) {
            android.util.Log.e("AppointmentAlarm", "Could not start appointment alarm", error)
            intent?.getStringExtra("reminder")?.let {
                try { postFallback(this, JSONObject(it)) } catch (_: Exception) { }
            }
            stopSelf()
            return START_NOT_STICKY
        }
    }

    private fun items() = AppointmentAlarmStore.active(this)
        .filter { AppointmentAlarmStore.key(it) !in ignored }

    private fun updateNotifications(items: List<JSONObject>) {
        val primary = items.first()
        val nextId = primary.getInt("id")
        if (foregroundId != nextId) {
            if (foregroundId != null) stopForeground(STOP_FOREGROUND_REMOVE)
            // Cancel a system fallback's insistent sound before replacing it.
            manager(this).cancel(nextId)
            startForeground(nextId, notification(this, primary))
            foregroundId = nextId
        } else manager(this).notify(nextId, notification(this, primary))
        items.drop(1).forEach { manager(this).notify(it.getInt("id"), notification(this, it)) }
    }

    private fun priorityAudioActive(audio: AudioManager): Boolean =
        SystemClock.elapsedRealtime() < priorityPauseUntil ||
            PatientAlarmService.active || ReminderSpeechService.active ||
            audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION ||
            audio.mode == AudioManager.MODE_RINGTONE ||
            manager(this).activeNotifications.any { it.notification.category == Notification.CATEGORY_CALL }

    private fun scheduleRetry() {
        handler.removeCallbacks(retry)
        handler.postDelayed(retry, RETRY_MS)
    }

    private fun resumeAudio() {
        if (destroyed) return
        val items = items()
        if (items.isEmpty()) { stopSelf(); return }
        if (!canNotify(this, CHANNEL)) { stopSelf(); return }
        val audio = getSystemService(AudioManager::class.java)
        if (priorityAudioActive(audio)) { pauseAudio(); scheduleRetry(); return }
        if (!focusGranted) {
            if (Build.VERSION.SDK_INT >= 26) {
                if (focus == null) focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(alarmAttributes()).setOnAudioFocusChangeListener { change ->
                        handler.post {
                            if (destroyed) return@post
                            focusGranted = change == AudioManager.AUDIOFOCUS_GAIN
                            if (focusGranted) resumeAudio() else { pauseAudio(); scheduleRetry() }
                        }
                    }.build()
                focusGranted = audio.requestAudioFocus(focus!!) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                val result = audio.requestAudioFocus(legacyFocus, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                focusGranted = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
            if (!focusGranted) { scheduleRetry(); return }
        }
        handler.removeCallbacks(retry)
        if (voiceItem != null && items.none { AppointmentAlarmStore.key(it) == AppointmentAlarmStore.key(voiceItem!!) }) {
            voice?.release(); voice = null; voiceItem = null
        }
        if (loop == null) startLoop()
        if (voice == null) items.firstOrNull {
            !it.optBoolean("appointmentVoicePlayed", false) && AppointmentAlarmStore.key(it) !in completedVoices
        }?.let { startVoice(it) }
        // Lower the looping alarm while the spoken prompt is playing.
        if (loopPrepared) loop?.setVolume(if (voice == null) 1f else .15f, if (voice == null) 1f else .15f)
        // Also observe SOS/call state and notification permission changes when
        // another component does not participate in Android audio focus.
        scheduleRetry()
    }

    private val legacyFocus = AudioManager.OnAudioFocusChangeListener { change ->
        handler.post {
            if (destroyed) return@post
            focusGranted = change == AudioManager.AUDIOFOCUS_GAIN
            if (focusGranted) resumeAudio() else { pauseAudio(); scheduleRetry() }
        }
    }

    private fun startLoop() {
        try {
            val player = MediaPlayer()
            loop = player
            loopPrepared = false
            player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            player.setAudioAttributes(alarmAttributes())
            player.setDataSource(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            player.isLooping = true
            player.setOnPreparedListener {
                if (loop === it) {
                    loopPrepared = true
                    it.setVolume(if (voice == null) 1f else .15f, if (voice == null) 1f else .15f)
                    it.start()
                    ringing = true
                }
            }
            player.setOnErrorListener { failed, _, _ ->
                if (loop === failed) { loop = null; loopPrepared = false; ringing = false; failed.release(); scheduleRetry() }; true
            }
            player.prepareAsync()
        } catch (error: Exception) {
            loop?.release(); loop = null; loopPrepared = false; ringing = false
            android.util.Log.w("AppointmentAlarm", "Alarm ringtone unavailable", error)
            scheduleRetry()
        }
    }

    private fun startVoice(item: JSONObject) {
        try {
            val player = MediaPlayer()
            voice = player; voiceItem = item
            player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            resources.openRawResourceFd(R.raw.appointment_reminder_voice).use {
                player.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            player.setOnPreparedListener { if (voice === it) it.start() }
            player.setOnCompletionListener { completed ->
                if (voice === completed) {
                    markVoiceCompleted(item)
                    voice = null; voiceItem = null; completed.release(); resumeAudio()
                }
            }
            player.setOnErrorListener { failed, _, _ ->
                if (voice === failed) {
                    markVoiceCompleted(item)
                    voice = null; voiceItem = null; failed.release(); resumeAudio()
                }; true
            }
            player.prepareAsync()
        } catch (error: Exception) {
            voice?.release(); voice = null; voiceItem = null
            // Leave the continuous alarm and visible controls functioning even
            // if the device cannot decode the optional spoken prompt.
            markVoiceCompleted(item)
            android.util.Log.w("AppointmentAlarm", "Appointment voice unavailable", error)
        }
    }

    private fun markVoiceCompleted(item: JSONObject) {
        completedVoices.add(AppointmentAlarmStore.key(item))
        try { AppointmentAlarmStore.markVoicePlayed(this, item) }
        catch (error: Exception) { android.util.Log.w("AppointmentAlarm", "Could not persist spoken prompt state", error) }
    }

    @Suppress("DEPRECATION")
    private fun vibrateOnce() {
        if (vibrator != null) return
        try {
            val device = if (Build.VERSION.SDK_INT >= 31)
                getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
            if (!device.hasVibrator()) return
            vibrator = device
            val effect = longArrayOf(0, 600, 250, 600, 250, 900)
            if (Build.VERSION.SDK_INT >= 33) device.vibrate(VibrationEffect.createWaveform(effect, -1),
                VibrationAttributes.Builder().setUsage(VibrationAttributes.USAGE_ALARM).build())
            else if (Build.VERSION.SDK_INT >= 26) device.vibrate(VibrationEffect.createWaveform(effect, -1), alarmAttributes())
            else device.vibrate(effect, -1, alarmAttributes())
        } catch (error: Exception) {
            android.util.Log.w("AppointmentAlarm", "Appointment vibration unavailable", error)
        }
    }

    private fun pauseAudio() {
        loop?.release(); loop = null; loopPrepared = false
        ringing = false
        voice?.release(); voice = null; voiceItem = null
    }

    override fun onDestroy() {
        destroyed = true
        active = false
        handler.removeCallbacksAndMessages(null)
        pauseAudio()
        vibrator?.cancel(); vibrator = null
        val audio = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
        else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(legacyFocus)
        }
        focus = null; focusGranted = false
        if (wake?.isHeld == true) wake?.release()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

/** Stop/delete actions remain effective when Flutter is closed or offline. */
class AppointmentAlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AppointmentAlarmService.DISMISS) return
        try {
            val item = JSONObject(intent.getStringExtra("reminder") ?: return)
            AppointmentAlarmService.dismiss(context, occurrence = item)
        } catch (error: Exception) {
            android.util.Log.e("AppointmentAlarm", "Unable to dismiss appointment alarm", error)
        }
    }
}

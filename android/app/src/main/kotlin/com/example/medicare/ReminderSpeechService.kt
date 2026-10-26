package com.example.medicare

import android.app.*
import android.content.Intent
import android.media.*
import android.os.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import org.json.JSONObject
import java.util.ArrayDeque
import java.util.Locale

/** Speech and vibration retain alarm usage for Silent-mode reminders. The
 * separately scheduled notification owns the normal message notification tone.
 * Does not modify ringer/DND settings or the user's alarm volume. */
class ReminderSpeechService : Service() {
    companion object {
        const val CANCEL = "medicare.CANCEL_REMINDER_SPEECH"
        const val CANCEL_PAYLOAD = "medicare.CANCEL_REMINDER_PAYLOAD"
        private const val STOP = "medicare.STOP_REMINDER_SPEECH"
        private const val CHANNEL = "spoken_reminder_service_v1"
        private const val ID = 901003
        private const val VOICE_DELAY_MS = 750L
        private const val MEDICATION_SPEECH = "It's time to take your medicine."
        private const val APPOINTMENT_SPEECH = "It's time to go to your appointment."
        @Volatile var active = false
    }
    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<JSONObject>()
    private var current: JSONObject? = null
    private var tts: TextToSpeech? = null
    private var ready = false
    private var fallback: MediaPlayer? = null
    private var wake: PowerManager.WakeLock? = null
    private var focus: AudioFocusRequest? = null
    private var vibrator: Vibrator? = null
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        active = true
        if (intent?.action == STOP) { stopSelf(); return START_NOT_STICKY }
        if (intent?.action == CANCEL) {
            val id = intent.getIntExtra("id", -1)
            queue.removeAll { it.getInt("id") == id }
            if (current?.getInt("id") == id) finishCurrent()
            if (current == null && queue.isEmpty()) stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == CANCEL_PAYLOAD) {
            val payload = intent.getStringExtra("payload") ?: return START_NOT_STICKY
            queue.removeAll { it.optString("payload") == payload }
            if (current?.optString("payload") == payload) {
                getSystemService(NotificationManager::class.java).cancel(current!!.getInt("id"))
                finishCurrent()
            }
            if (current == null && queue.isEmpty()) stopSelf()
            return START_NOT_STICKY
        }
        val json = intent?.getStringExtra("reminder") ?: run { stopSelf(); return START_NOT_STICKY }
        val item = JSONObject(json)
        // Existing persisted alarms may still contain older, detailed speech.
        // Derive the exact current phrase without changing their time/payload.
        item.put("speech", speechFor(item))
        if (current?.optInt("id") == item.optInt("id") ||
            queue.any { it.optInt("id") == item.optInt("id") }) return START_NOT_STICKY
        queue.add(item)
        if (current == null) showNotification(item)
        if (wake == null) wake = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "medicare:reminderSpeech").apply { setReferenceCounted(false); acquire(60000) }
        if (tts == null) {
            tts = TextToSpeech(this) { status -> handler.post {
                if (!active) return@post
                ready = status == TextToSpeech.SUCCESS
                if (ready) {
                    try {
                        // Prefer a high-quality installed English voice. The
                        // bundled recording covers missing or offline engines.
                        tts?.setLanguage(Locale.US)
                        val localEnglish = tts?.voices.orEmpty().filter {
                            it.locale.language == Locale.ENGLISH.language &&
                                !it.isNetworkConnectionRequired &&
                                !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
                        }.sortedWith(compareByDescending<android.speech.tts.Voice> { it.quality }
                            .thenByDescending { it.locale.country == Locale.getDefault().country }
                            .thenByDescending { it.locale == Locale.US }
                            .thenBy { it.name }).firstOrNull()
                        ready = localEnglish != null && tts?.setVoice(localEnglish) == TextToSpeech.SUCCESS
                        tts?.setAudioAttributes(attributes)
                        tts?.setSpeechRate(.82f)
                        tts?.setPitch(1f)
                        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                            override fun onStart(id: String?) {}
                            override fun onDone(id: String?) { handler.post { if (id == current?.getInt("id").toString()) finishCurrent() } }
                            @Deprecated("Deprecated in Java")
                            override fun onError(id: String?) { handler.post { if (id == current?.getInt("id").toString()) playFallback() } }
                        })
                    } catch (error: Exception) {
                        ready = false
                        android.util.Log.w("ReminderSpeech", "English TTS voice unavailable", error)
                    }
                }
            } }
        }
        playNext()
        return START_NOT_STICKY
    }

    private fun speechFor(item: JSONObject) =
        if (item.optBoolean("medication", true)) MEDICATION_SPEECH else APPOINTMENT_SPEECH

    private fun showNotification(item: JSONObject) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Spoken reminders", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
        val open = PendingIntent.getActivity(this, item.getInt("id"),
            Intent(this, MainActivity::class.java).setAction("SELECT_NOTIFICATION")
                .putExtra("notificationId", item.getInt("id"))
                .putExtra("payload", item.optString("payload")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 0, Intent(this, ReminderSpeechService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        startForeground(ID, builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle(item.getString("title"))
            .setContentText(item.getString("speech")).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop voice", stop).build()).build())
    }

    private fun playNext() {
        if (current != null) return
        val item = queue.poll() ?: run { stopSelf(); return }
        current = item
        wake?.acquire(60000)
        showNotification(item)
        vibrateReminder()
        val audio = getSystemService(AudioManager::class.java)
        // Do not mix spoken reminders into a live call or a patient's SOS siren.
        if (audio.mode == AudioManager.MODE_IN_COMMUNICATION || audio.mode == AudioManager.MODE_IN_CALL || PatientAlarmService.active) { finishCurrent(); return }
        // Allow the notification channel's short message chime to sound before
        // taking voice focus. The visual alert and vibration are not delayed.
        handler.postDelayed({ if (current === item) speakCurrent(item) }, VOICE_DELAY_MS)
    }

    private fun speakCurrent(item: JSONObject) {
        val audio = getSystemService(AudioManager::class.java)
        // A call or SOS can start while the notification chime is playing.
        if (audio.mode == AudioManager.MODE_IN_COMMUNICATION || audio.mode == AudioManager.MODE_IN_CALL || PatientAlarmService.active) { finishCurrent(); return }
        if (Build.VERSION.SDK_INT >= 26) {
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener { change ->
                    if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) handler.post { if (current === item) finishCurrent() }
                }.build()
            if (audio.requestAudioFocus(focus!!) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { finishCurrent(); return }
        }
        handler.postDelayed({ if (current === item) finishCurrent() }, 30000)
        val spoken = if (ready) try {
            tts?.speak(speechFor(item), TextToSpeech.QUEUE_FLUSH,
                Bundle().apply { putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_ALARM) },
                item.getInt("id").toString()) == TextToSpeech.SUCCESS
        } catch (error: Exception) {
            android.util.Log.w("ReminderSpeech", "TTS playback unavailable", error)
            false
        } else false
        if (!spoken) playFallback()
    }

    @Suppress("DEPRECATION")
    private fun vibrateReminder() {
        try {
            val device = if (Build.VERSION.SDK_INT >= 31)
                getSystemService(VibratorManager::class.java).defaultVibrator
            else getSystemService(Vibrator::class.java)
            if (!device.hasVibrator()) return
            vibrator = device
            val pattern = longArrayOf(0, 600, 250, 600, 250, 900)
            if (Build.VERSION.SDK_INT >= 33) {
                device.vibrate(VibrationEffect.createWaveform(pattern, -1),
                    VibrationAttributes.Builder().setUsage(VibrationAttributes.USAGE_ALARM).build())
            } else if (Build.VERSION.SDK_INT >= 26) {
                device.vibrate(VibrationEffect.createWaveform(pattern, -1), attributes)
            } else device.vibrate(pattern, -1, attributes)
        } catch (error: Exception) {
            // Hardware, system vibration settings and DND can suppress an
            // alarm. The visible reminder remains available in that case.
            android.util.Log.w("ReminderSpeech", "Reminder vibration unavailable", error)
        }
    }

    private fun playFallback() {
        val item = current ?: return
        if (fallback != null) return
        // No ringtone fallback: a missing/offline TTS engine must still say the
        // same phrase, without introducing another beep or an alarm sound.
        tts?.stop()
        try {
            val player = MediaPlayer()
            fallback = player
            val resource = if (item.optBoolean("medication", true))
                R.raw.medication_voice else R.raw.appointment_reminder_voice
            player.apply {
                setAudioAttributes(attributes)
                resources.openRawResourceFd(resource).use { descriptor ->
                    setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                }
                setOnCompletionListener { if (current === item && fallback === player) finishCurrent() }
                setOnErrorListener { _, _, _ -> if (current === item && fallback === player) finishCurrent(); true }
                prepare(); start()
            }
        } catch (error: Exception) {
            android.util.Log.w("ReminderSpeech", "Spoken reminder unavailable", error)
            if (current === item) finishCurrent()
        }
    }
    private fun finishCurrent() {
        tts?.stop()
        vibrator?.cancel(); vibrator = null
        fallback?.release(); fallback = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        focus = null; current = null
        playNext()
    }
    override fun onDestroy() {
        active = false
        handler.removeCallbacksAndMessages(null)
        queue.clear(); current = null
        tts?.stop(); tts?.shutdown(); tts = null
        vibrator?.cancel(); vibrator = null
        fallback?.release(); fallback = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        if (wake?.isHeld == true) wake?.release()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

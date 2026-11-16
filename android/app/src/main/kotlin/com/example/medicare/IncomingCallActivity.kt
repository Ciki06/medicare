package com.example.medicare

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Source
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import java.util.concurrent.TimeUnit

internal object IncomingCallAlert {
    private const val CHANNEL = "medicare_incoming_calls"
    private const val NOTIFICATION = 1
    val closed = mutableMapOf<String, Long>()
    var pendingAnswer: String? = null
    var onAnswer: (() -> Unit)? = null
    var appVisible = false

    fun validId(id: String?) = id != null && id.matches(Regex("[A-Za-z0-9_-]{1,200}"))

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    fun channel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
        channel.enableVibration(true)
        channel.setSound(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build(),
        )
        manager(context).createNotificationChannel(channel)
    }

    fun permissions(context: Context): Map<String, Boolean> {
        channel(context)
        return mapOf(
            "notifications" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || manager(context).canUseFullScreenIntent()),
            "channelEnabled" to (Build.VERSION.SDK_INT < 26 ||
                manager(context).getNotificationChannel(CHANNEL).importance != NotificationManager.IMPORTANCE_NONE),
        )
    }

    fun openSettings(activity: Activity, fullScreen: Boolean) {
        val intent = if (fullScreen && Build.VERSION.SDK_INT >= 34) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${activity.packageName}"))
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        }
        activity.startActivity(intent)
    }

    fun dismiss(context: Context, id: String) {
        manager(context).cancel(id, NOTIFICATION)
    }

    fun show(context: Context, id: String, name: String, video: Boolean, expiresAt: Long) {
        val remaining = expiresAt - System.currentTimeMillis()
        if (remaining <= 0 || appVisible || closed.containsKey(id)) return
        channel(context)
        fun activity(action: String) = PendingIntent.getActivity(context, 0,
            Intent(context, IncomingCallActivity::class.java)
                .setData(Uri.parse("medicare-call://$action/$id")),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val screen = activity("open")
        val answer = activity("answer")
        val reject = PendingIntent.getBroadcast(context, 0,
            Intent(context, RejectIncomingCallReceiver::class.java)
                .setData(Uri.parse("medicare-call://reject/$id")),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val caller = Person.Builder().setName(name).setImportant(true).build()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, reject, answer).setIsVideo(video))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(screen)
            .setFullScreenIntent(screen, true)
            .setTimeoutAfter(remaining)
            .setOnlyAlertOnce(true)
            .build()
        manager(context).notify(id, NOTIFICATION, notification)
    }

    fun reject(context: Context, id: String, done: (Boolean) -> Unit) {
        FirebaseFunctions.getInstance("asia-southeast1").getHttpsCallable("voiceCall")
            .call(mapOf("action" to "reject", "callId" to id))
            .addOnCompleteListener {
                if (it.isSuccessful) dismiss(context, id)
                done(it.isSuccessful)
            }
    }
}

class IncomingCallMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val id = message.data["callId"] ?: return
        if (!IncomingCallAlert.validId(id)) return
        val main = android.os.Handler(mainLooper)
        when (message.data["type"]) {
            "call_ended" -> main.post {
                val now = System.currentTimeMillis()
                IncomingCallAlert.closed.entries.removeAll { it.value <= now }
                IncomingCallAlert.closed[id] = now + 60_000
                IncomingCallAlert.dismiss(this, id)
            }
            "call" -> {
                val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
                val record = try {
                    val lookup = FirebaseFirestore.getInstance().collection("calls").document(id).get(Source.SERVER)
                    Tasks.await(lookup, 6, TimeUnit.SECONDS)
                } catch (error: Exception) {
                    android.util.Log.w("IncomingCall", "Could not verify incoming call", error)
                    return
                }
                main.post {
                    if (FirebaseAuth.getInstance().currentUser?.uid == uid &&
                            record.getString("calleeId") == uid && record.getString("state") == "ringing"
                    ) {
                        IncomingCallAlert.show(this, id, record.getString("callerName").orEmpty().ifBlank { "MediCare" },
                            record.getString("callType") == "video", record.getLong("expiresAt") ?: 0)
                    }
                }
            }
        }
    }
}

class RejectIncomingCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.data?.lastPathSegment ?: return
        if (!IncomingCallAlert.validId(id)) return
        val result = goAsync()
        val handler = android.os.Handler(context.mainLooper)
        var finished = false
        val finish = Runnable {
            if (!finished) {
                finished = true
                result.finish()
            }
        }
        handler.postDelayed(finish, 8000)
        IncomingCallAlert.reject(context, id) {
            handler.removeCallbacks(finish)
            finish.run()
        }
    }
}

class IncomingCallActivity : Activity() {
    private var listener: ListenerRegistration? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val expire = Runnable { finish() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < 27) {
            @Suppress("DEPRECATION")
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        val id = intent.data?.lastPathSegment
        if (id == null || !IncomingCallAlert.validId(id)) {
            finish()
            return
        }
        val callIcon = ImageView(this).apply { setImageResource(R.drawable.ic_call_phone) }
        val caller = TextView(this).apply {
            text = "MediCare"
            textSize = 28f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
        }
        val status = TextView(this).apply {
            text = "Checking incoming call…"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }
        val answer = callButton("Accept", 0xFF4CAF50.toInt())
        val reject = callButton("Reject", 0xFFD32F2F.toInt())
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            addView(callIcon, LinearLayout.LayoutParams(dp(64), dp(64)))
            addView(caller, spaced(dp(24)))
            addView(status, spaced(dp(16)))
            addView(answer, spaced(dp(24)))
            addView(reject, spaced(dp(16)))
        }
        val screen = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(0xFF142D4E.toInt())
            addView(content)
        }
        ViewCompat.setOnApplyWindowInsetsListener(screen) { view, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        setContentView(screen)
        fun accept() {
            fun openCall() {
                if (isFinishing || isDestroyed) return
                IncomingCallAlert.pendingAnswer = id
                IncomingCallAlert.dismiss(this, id)
                startActivity(Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                finish()
            }
            val keyguard = getSystemService(KeyguardManager::class.java)
            if (Build.VERSION.SDK_INT >= 26 && keyguard.isKeyguardLocked) {
                keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() = openCall()
                })
            } else {
                openCall()
            }
        }
        answer.setOnClickListener { accept() }
        reject.setOnClickListener {
            reject.isEnabled = false
            answer.isEnabled = false
            IncomingCallAlert.reject(this, id) { ok ->
                if (isFinishing || isDestroyed) return@reject
                if (ok) finish() else {
                    status.text = "Could not reject. Try again."
                    reject.isEnabled = true
                    answer.isEnabled = true
                }
            }
        }
        handler.postDelayed(expire, 45_000L)
        listener = FirebaseFirestore.getInstance().collection("calls").document(id).addSnapshotListener { record, error ->
            if (isFinishing || isDestroyed || error != null || record == null || record.metadata.isFromCache) return@addSnapshotListener
            val uid = FirebaseAuth.getInstance().currentUser?.uid
            val remaining = (record.getLong("expiresAt") ?: 0) - System.currentTimeMillis()
            if (uid == null || record.getString("calleeId") != uid ||
                record.getString("state") != "ringing" || remaining <= 0) {
                IncomingCallAlert.dismiss(this, id)
                finish()
                return@addSnapshotListener
            }
            handler.removeCallbacks(expire)
            handler.postDelayed(expire, remaining)
            caller.text = record.getString("callerName").orEmpty().ifBlank { "MediCare" }
            val video = record.getString("callType") == "video"
            callIcon.setImageResource(if (video) R.drawable.ic_call_video else R.drawable.ic_call_phone)
            status.text = if (video) "Incoming video call" else "Incoming voice call"
            answer.isEnabled = true
            reject.isEnabled = true
            if (intent.data?.host == "answer") accept()
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun spaced(top: Int) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = top }

    private fun callButton(label: String, color: Int) = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 16f
        gravity = Gravity.CENTER
        minimumWidth = dp(160)
        minimumHeight = dp(56)
        setPadding(dp(24), dp(12), dp(24), dp(12))
        setTextColor(Color.WHITE)
        background = RippleDrawable(
            ColorStateList.valueOf(0x33FFFFFF),
            GradientDrawable().apply {
                cornerRadius = dp(32).toFloat()
                setColor(ColorStateList(
                    arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
                    intArrayOf(0xFF526580.toInt(), color),
                ))
            },
            null,
        )
        isEnabled = false
    }

    override fun onDestroy() {
        listener?.remove()
        handler.removeCallbacks(expire)
        super.onDestroy()
    }
}

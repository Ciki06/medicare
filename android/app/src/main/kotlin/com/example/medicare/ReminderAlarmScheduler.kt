package com.example.medicare

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId

/** Persisted independently of Flutter so speech survives process death/reboot. */
object ReminderAlarmScheduler {
    private const val STORE = "spoken_reminder_alarms_v1"
    private fun preferences(context: Context) = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
    private fun load(context: Context) = JSONObject(preferences(context).getString("alarms", "{}") ?: "{}")
    private fun save(context: Context, alarms: JSONObject) { preferences(context).edit().putString("alarms", alarms.toString()).commit() }
    private fun pending(context: Context, item: JSONObject): PendingIntent = PendingIntent.getBroadcast(
        context, item.getInt("id"), Intent(context, ReminderAlarmReceiver::class.java)
            .setAction("medicare.SPOKEN_REMINDER").setData(Uri.parse("medicare-reminder:${item.getInt("id")}"))
            .putExtra("id", item.getInt("id")).putExtra("at", item.getLong("at")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun schedule(context: Context, item: JSONObject): Boolean {
        val manager = context.getSystemService(AlarmManager::class.java)
        val exact = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
        if (exact) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("at"), pending(context, item))
        else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("at"), pending(context, item))
        return exact
    }

    @Synchronized fun reconcile(context: Context, items: List<Map<String, Any?>>, group: String = "main",
                               retain: List<Map<String, Any?>>? = null): Boolean {
        val alarms = load(context)
        val manager = context.getSystemService(AlarmManager::class.java)
        alarms.keys().asSequence().toList().forEach { key ->
            val old = alarms.getJSONObject(key)
            if (old.optString("group") == group) { manager.cancel(pending(context, old)); alarms.remove(key) }
        }
        // Persist before registering alarms so a receiver never sees partial data.
        items.forEach { data ->
            val item = JSONObject(data).put("group", group)
            if (item.getLong("at") > System.currentTimeMillis() &&
                (item.optBoolean("medication", true) || !AppointmentAlarmStore.isDismissed(context, item))) {
                alarms.put(item.getInt("id").toString(), item)
            }
        }
        save(context, alarms)
        var exact = true
        items.forEach { data -> alarms.optJSONObject(data["id"].toString())?.let { if (!schedule(context, it)) exact = false } }
        // The future plan is not authoritative for a reminder already ringing.
        // Flutter supplies all valid unviewed appointments, including past ones.
        if (group == "appointments" && retain != null) {
            val removed = AppointmentAlarmStore.retain(context, retain)
            removed.forEach { context.getSystemService(android.app.NotificationManager::class.java).cancel(it.getInt("id")) }
            AppointmentAlarmService.sync(context)
        }
        return exact
    }

    @Synchronized fun cancel(context: Context, id: Int) {
        val alarms = load(context)
        alarms.optJSONObject(id.toString())?.let { context.getSystemService(AlarmManager::class.java).cancel(pending(context, it)) }
        alarms.remove(id.toString()); save(context, alarms)
        if (ReminderSpeechService.active) context.startService(Intent(context, ReminderSpeechService::class.java).setAction(ReminderSpeechService.CANCEL).putExtra("id", id))
        AppointmentAlarmService.dismiss(context, id = id)
    }

    @Synchronized fun cancelAll(context: Context) {
        val alarms = load(context)
        alarms.keys().forEach { key -> context.getSystemService(AlarmManager::class.java).cancel(pending(context, alarms.getJSONObject(key))) }
        save(context, JSONObject())
        context.stopService(Intent(context, ReminderSpeechService::class.java))
        AppointmentAlarmService.stopAll(context)
    }

    private fun advance(item: JSONObject, now: Long): Boolean {
        val repeat = item.optString("repeat")
        if (repeat.isEmpty()) return false
        var next = Instant.ofEpochMilli(item.getLong("at")).atZone(ZoneId.of("Asia/Kuala_Lumpur"))
        val desiredDay = item.optInt("monthDay", next.dayOfMonth)
        item.put("monthDay", desiredDay)
        do {
            next = when (repeat) {
                "time" -> next.plusDays(1)
                "dayOfWeekAndTime" -> next.plusWeeks(1)
                "dayOfMonthAndTime" -> {
                    // Skip months without the original day instead of shifting to month-end.
                    var month = next.withDayOfMonth(1).plusMonths(1)
                    while (month.toLocalDate().lengthOfMonth() < desiredDay) month = month.plusMonths(1)
                    month.withDayOfMonth(desiredDay)
                }
                else -> return false
            }
        } while (next.toInstant().toEpochMilli() <= now)
        item.put("at", next.toInstant().toEpochMilli())
        return true
    }

    @Synchronized fun fire(context: Context, id: Int, expectedAt: Long): JSONObject? {
        val alarms = load(context)
        val item = alarms.optJSONObject(id.toString()) ?: return null
        // A reused alarm ID must not deliver an older scheduled occurrence.
        if (item.getLong("at") != expectedAt) return null
        val delivered = JSONObject(item.toString())
        val now = System.currentTimeMillis()
        if (advance(item, now)) alarms.put(id.toString(), item) else alarms.remove(id.toString())
        save(context, alarms)
        alarms.optJSONObject(id.toString())?.let { schedule(context, it) }
        // Never speak hours-old reminders after a delayed boot or restored backup.
        return if (now - expectedAt in 0..600000L) delivered else null
    }

    @Synchronized fun restore(context: Context) {
        val alarms = load(context)
        val now = System.currentTimeMillis()
        alarms.keys().asSequence().toList().forEach { key ->
            val item = alarms.getJSONObject(key)
            if (item.getLong("at") <= now && !advance(item, now)) alarms.remove(key)
        }
        save(context, alarms)
        alarms.keys().forEach { key -> schedule(context, alarms.getJSONObject(key)) }
    }
}

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action != "medicare.SPOKEN_REMINDER") {
                ReminderAlarmScheduler.restore(context)
                AppointmentAlarmService.restore(context, intent.action == Intent.ACTION_BOOT_COMPLETED)
                return
            }
            val item = ReminderAlarmScheduler.fire(context, intent.getIntExtra("id", -1), intent.getLongExtra("at", 0)) ?: return
            if (!item.optBoolean("medication", true)) {
                AppointmentAlarmService.deliver(context, item)
                return
            }
            val service = Intent(context, ReminderSpeechService::class.java).putExtra("reminder", item.toString())
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
        } catch (error: Exception) {
            // The separately scheduled visible notification still delivers if
            // exact-alarm access or foreground execution was revoked.
            android.util.Log.e("ReminderAlarm", "Unable to play spoken reminder", error)
        }
    }
}

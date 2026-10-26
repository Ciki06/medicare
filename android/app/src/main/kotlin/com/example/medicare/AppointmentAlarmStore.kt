package com.example.medicare

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Durable occurrence state, separate from the future alarm scheduling cache. */
object AppointmentAlarmStore {
    private const val STORE = "appointment_alarm_state_v1"
    private const val STATE = "state"
    private const val ACTIVE = "active"
    private const val DISMISSED = "dismissed"
    private const val VOICE_PLAYED = "appointmentVoicePlayed"

    /** A stable notification id alone cannot distinguish a rescheduled visit. */
    fun key(item: JSONObject): String = JSONArray()
        .put(item.optString("patientId"))
        .put(item.getString("payload"))
        .put(item.optString("scheduleKey"))
        .put(item.getLong("at"))
        .toString()

    private fun load(context: Context): JSONObject {
        val stored = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            .getString(STATE, null)
        val state = try {
            if (stored == null) JSONObject() else JSONObject(stored)
        } catch (_: Exception) {
            JSONObject()
        }
        if (state.optJSONObject(ACTIVE) == null) state.put(ACTIVE, JSONObject())
        if (state.optJSONObject(DISMISSED) == null) state.put(DISMISSED, JSONObject())
        return state
    }

    private fun save(context: Context, state: JSONObject) {
        check(context.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit()
            .putString(STATE, state.toString()).commit()) {
            "Unable to persist appointment alarm state"
        }
    }

    private fun copy(item: JSONObject) = JSONObject(item.toString())

    private fun values(items: JSONObject): List<JSONObject> =
        items.keys().asSequence().toList().mapNotNull { itemKey ->
            items.optJSONObject(itemKey)?.let(::copy)
        }

    private fun acknowledgement(item: JSONObject): JSONObject = JSONObject()
        .put("id", item.getInt("id"))
        .put("at", item.getLong("at"))
        .put("payload", item.getString("payload"))
        .put("patientId", item.optString("patientId"))
        .put("scheduleKey", item.optString("scheduleKey"))

    @Synchronized
    fun active(context: Context): List<JSONObject> =
        values(load(context).getJSONObject(ACTIVE))

    /** Returns false when this exact occurrence was already manually stopped. */
    @Synchronized
    fun remember(context: Context, item: JSONObject): Boolean {
        val state = load(context)
        val itemKey = key(item)
        if (state.getJSONObject(DISMISSED).has(itemKey)) return false
        val active = state.getJSONObject(ACTIVE)
        val previous = active.optJSONObject(itemKey)
        val next = copy(item)
        next.put(VOICE_PLAYED, previous?.optBoolean(VOICE_PLAYED, false)
            ?: item.optBoolean(VOICE_PLAYED, false))
        active.put(itemKey, next)
        save(context, state)
        return true
    }

    @Synchronized
    fun isDismissed(context: Context, item: JSONObject): Boolean =
        load(context).getJSONObject(DISMISSED).has(key(item))

    /** Filters are combined, so an older dismissal need not stop a newer visit. */
    @Synchronized
    fun dismiss(
        context: Context,
        id: Int? = null,
        payload: String? = null,
        at: Long? = null,
    ): List<JSONObject> {
        val state = load(context)
        val active = state.getJSONObject(ACTIVE)
        val dismissed = state.getJSONObject(DISMISSED)
        val removed = mutableListOf<JSONObject>()
        active.keys().asSequence().toList().forEach { itemKey ->
            val item = active.optJSONObject(itemKey) ?: return@forEach
            if ((id == null || item.optInt("id") == id) &&
                (payload == null || item.optString("payload") == payload) &&
                (at == null || item.optLong("at") == at)) {
                removed.add(copy(item))
                dismissed.put(itemKey, acknowledgement(item))
                active.remove(itemKey)
            }
        }
        if (removed.isNotEmpty()) save(context, state)
        return removed
    }

    /** Notification actions can arrive before the service remembers its item. */
    @Synchronized
    fun dismissItem(context: Context, item: JSONObject) {
        val state = load(context)
        val itemKey = key(item)
        state.getJSONObject(ACTIVE).remove(itemKey)
        state.getJSONObject(DISMISSED).put(itemKey, acknowledgement(item))
        save(context, state)
    }

    @Synchronized
    fun dismissAll(context: Context): List<JSONObject> = dismiss(context)

    @Synchronized
    fun markVoicePlayed(context: Context, item: JSONObject) {
        val state = load(context)
        val stored = state.getJSONObject(ACTIVE).optJSONObject(key(item)) ?: return
        if (stored.optBoolean(VOICE_PLAYED, false)) return
        stored.put(VOICE_PLAYED, true)
        save(context, state)
    }

    /** Kept until Flutter applies the matching patient/schedule acknowledgement. */
    @Synchronized
    fun dismissed(context: Context): List<Map<String, Any>> =
        values(load(context).getJSONObject(DISMISSED)).map { item ->
            mapOf(
                "id" to item.getInt("id"),
                "at" to item.getLong("at"),
                "payload" to item.getString("payload"),
                "patientId" to item.optString("patientId"),
                "scheduleKey" to item.optString("scheduleKey"),
            )
        }

    /**
     * The supplied set is authoritative, including an empty set at sign-out.
     * Edit/deletion/completion cleanup does not create a manual-dismissal record.
     */
    @Synchronized
    fun retain(context: Context, items: List<Map<String, Any?>>): List<JSONObject> {
        val retained = items.map { key(JSONObject(it)) }.toSet()
        val state = load(context)
        val active = state.getJSONObject(ACTIVE)
        val removed = mutableListOf<JSONObject>()
        active.keys().asSequence().toList().forEach { itemKey ->
            if (itemKey !in retained) {
                active.optJSONObject(itemKey)?.let { removed.add(copy(it)) }
                active.remove(itemKey)
            }
        }
        if (removed.isNotEmpty()) save(context, state)
        return removed
    }
}

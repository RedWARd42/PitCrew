package com.example.signal_swarm

import android.content.Context

/// SharedPreferences contract between the SMS receiver, the overlay
/// service, and the Flutter side (via MainActivity's channel).
///
///  * `swat_overlay` — whether the patrol is armed, and the most recent
///    incoming message (so a badge tap can scan it on demand).
///  * `swat_blocks` — senders blocked from the overlay's Block & Report,
///    so the in-app Blocked tab can show them too. Entries are
///    unit-separator-joined: sender, snippet, risk, epochMillis.
object SwatPrefs {
    const val OVERLAY_PREFS = "swat_overlay"
    const val KEY_ARMED = "armed"
    const val KEY_LAST_SENDER = "last_sender"
    const val KEY_LAST_BODY = "last_body"
    const val KEY_LAST_AT = "last_at"

    const val BLOCKS_PREFS = "swat_blocks"
    const val KEY_BLOCKED = "blocked_entries"
    const val SEP = "\u001F"

    fun saveLastMessage(context: Context, sender: String, body: String) {
        context.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_SENDER, sender)
            .putString(KEY_LAST_BODY, body)
            .putLong(KEY_LAST_AT, System.currentTimeMillis())
            .apply()
    }

    fun isArmed(context: Context): Boolean =
        context.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ARMED, false)

    fun setArmed(context: Context, armed: Boolean) {
        context.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ARMED, armed).apply()
    }

    fun addBlock(context: Context, sender: String, body: String, risk: Int) {
        val prefs = context.getSharedPreferences(BLOCKS_PREFS, Context.MODE_PRIVATE)
        val current = prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()
        val snippet = body.replace('\n', ' ').take(120)
        val entry = listOf(
            sender, snippet, risk.toString(),
            System.currentTimeMillis().toString(),
        ).joinToString(SEP)
        // StringSet is immutable from prefs — always write back a copy.
        val updated = current.toMutableSet().apply { add(entry) }
        prefs.edit().putStringSet(KEY_BLOCKED, updated).apply()
    }

    fun readBlocks(context: Context): List<Map<String, String>> {
        val prefs = context.getSharedPreferences(BLOCKS_PREFS, Context.MODE_PRIVATE)
        val entries = prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()
        return entries.mapNotNull { raw ->
            val parts = raw.split(SEP)
            if (parts.size < 4) return@mapNotNull null
            mapOf(
                "sender" to parts[0],
                "snippet" to parts[1],
                "risk" to parts[2],
                "at" to parts[3],
            )
        }.sortedByDescending { it["at"]?.toLongOrNull() ?: 0L }
    }
}

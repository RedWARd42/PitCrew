package com.example.signal_swarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/// Wakes the fleet when a text actually arrives.
///
/// The message is read from the broadcast PDUs (and, for the badge-tap
/// path, from the SMS store) — never scraped from another app's screen.
/// If the patrol is armed, the already-running overlay service is told to
/// scan; if it isn't running, the message is just remembered for later.
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return
        val sender = messages.first().originatingAddress ?: "Unknown"
        val body = messages.joinToString("") { it.messageBody ?: "" }
        if (body.isBlank()) return

        SwatPrefs.saveLastMessage(context, sender, body)

        if (SwatPrefs.isArmed(context)) {
            val scan = Intent(context, OverlayService::class.java).apply {
                action = OverlayService.ACTION_SCAN
            }
            // The service is already running (armed == badge is up), so a
            // plain startService reaches it even from the background.
            context.startService(scan)
        }
    }
}

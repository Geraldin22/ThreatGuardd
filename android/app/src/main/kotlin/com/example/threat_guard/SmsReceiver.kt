package com.example.threat_guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Runs when a text arrives, even if the app is closed, and hands it to the
 * user's ThreatGuard server. If the server cannot be reached the message is
 * not lost: the app imports the inbox again the next time it opens, and the
 * server ignores messages it already has.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isNullOrEmpty()) return
        val server = SmsServer.load(context) ?: return // not linked to a server

        // A long text arrives in several parts; join the parts from one sender.
        val bySender = LinkedHashMap<String, StringBuilder>()
        for (p in parts) {
            bySender.getOrPut(p.originatingAddress ?: "Unknown") { StringBuilder() }
                .append(p.messageBody ?: "")
        }
        // The carrier's timestamp, the same value the inbox stores as date_sent,
        // so this and a later inbox import describe the message identically.
        val sentAt = parts[0].timestampMillis

        val pending = goAsync()
        Thread {
            try {
                for ((sender, body) in bySender) {
                    if (body.isNotBlank()) SmsServer.post(server, sender, body.toString(), sentAt)
                }
            } catch (_: Exception) {
                // Server off or unreachable. The next inbox import catches up.
            } finally {
                pending.finish()
            }
        }.start()
    }
}

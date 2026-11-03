package com.example.threat_guard

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** SMS permission state, shared by the activity and the background receiver. */
object SmsAccess {
    fun granted(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
}

/**
 * The ThreatGuard server this phone is linked to. The app saves it here when
 * the user connects, so the receiver can reach the server even when the app
 * itself is not running. Stored in app-private storage.
 */
object SmsServer {
    private const val FILE = "threatguard_native"

    fun save(context: Context, url: String, token: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("url", url.trimEnd('/')).putString("token", token).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun load(context: Context): Pair<String, String>? {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val url = p.getString("url", null) ?: return null
        val token = p.getString("token", null) ?: return null
        return url to token
    }

    /** Sends one received message to the server. Returns true if it was accepted. */
    fun post(server: Pair<String, String>, sender: String, body: String, receivedAtMillis: Long): Boolean {
        val payload = JSONObject()
            .put("sender", sender)
            .put("body", body)
            .put("source", "device")
            .put("receivedAt", java.time.Instant.ofEpochMilli(receivedAtMillis).toString())
        val conn = URL(server.first + "/api/messages").openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer " + server.second)
            conn.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
            conn.responseCode in 200..299
        } finally {
            conn.disconnect()
        }
    }
}

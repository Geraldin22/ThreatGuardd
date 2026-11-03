package com.example.threat_guard

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the app to Android's SMS inbox. Dart side: `lib/services/sms_source.dart`.
 *
 * Channel `threatguard/sms`:
 *  - `status`      -> true if SMS access is granted
 *  - `request`     -> asks for it, returns whether it was granted
 *  - `read`        -> the newest [limit] inbox messages
 *  - `saveServer`  -> remembers the server address and key for the receiver
 *  - `clearServer` -> forgets them
 *  - `openSettings` -> opens this app's page in Android settings
 */
class MainActivity : FlutterActivity() {
    private var pendingRequest: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "threatguard/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(SmsAccess.granted(this))
                    "request" -> requestAccess(result)
                    "read" -> readInbox(call.argument<Int>("limit") ?: 300, result)
                    "saveServer" -> {
                        val url = call.argument<String>("url")
                        val token = call.argument<String>("token")
                        if (url == null || token == null) {
                            result.error("bad_args", "url and token are required", null)
                        } else {
                            SmsServer.save(this, url, token)
                            result.success(null)
                        }
                    }
                    "clearServer" -> {
                        SmsServer.clear(this)
                        result.success(null)
                    }
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", packageName, null)),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (SmsAccess.granted(this)) {
            result.success(true)
            return
        }
        // A second request while the dialog is open just reports the current state.
        pendingRequest?.success(SmsAccess.granted(this))
        pendingRequest = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            REQUEST_SMS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS) {
            pendingRequest?.success(SmsAccess.granted(this))
            pendingRequest = null
        }
    }

    private fun readInbox(limit: Int, result: MethodChannel.Result) {
        if (!SmsAccess.granted(this)) {
            result.error("no_permission", "SMS access has not been allowed.", null)
            return
        }
        val max = limit.coerceIn(1, 1000)
        Thread {
            try {
                val rows = ArrayList<Map<String, Any?>>()
                val columns = arrayOf(
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.DATE_SENT,
                )
                contentResolver.query(
                    Telephony.Sms.Inbox.CONTENT_URI,
                    columns,
                    null,
                    null,
                    "date DESC LIMIT $max",
                )?.use { c ->
                    while (c.moveToNext()) {
                        val received = c.getLong(2)
                        val sent = c.getLong(3)
                        rows.add(
                            mapOf(
                                "sender" to c.getString(0),
                                "body" to c.getString(1),
                                // The carrier timestamp when there is one: it
                                // matches what the live receiver reports.
                                "date" to (if (sent > 0) sent else received),
                            ),
                        )
                    }
                }
                main.post { result.success(rows) }
            } catch (e: Exception) {
                main.post { result.error("read_failed", e.message, null) }
            }
        }.start()
    }

    private companion object {
        const val REQUEST_SMS = 7301
    }
}

# ThreatGuard AI

Check text messages for scams and phishing. A Flutter app (web/PWA, Android, iOS)
plus its own backend server.

```
phone (browser / installed app) ──HTTP──▶ ThreatGuard server ──▶ data/store.json
                                            │  rule engine, auth, history,
                                            └─ settings, block list, serves the web app
```

| Folder | What it is |
|---|---|
| `lib/` | The Flutter app |
| `server/` | The backend (Dart, `shelf`). JSON API + serves the built web app |
| `packages/threatguard_core/` | The detection engine, shared by app and server so they always agree |

## Run it and open it on your phone

You need the Flutter SDK (it includes Dart). From the project root:

```bash
flutter build web --release
```

```bash
cd server
dart pub get
dart run bin/server.dart
```

The server prints something like:

```
Link a phone: open one of these on it, on the same Wi-Fi.
  http://192.168.1.10:8080/?pair=KLWKP73A
```

Open that link in your phone's browser. The code works **once** and expires after
10 minutes; the phone then keeps its own key. Then use *Add to Home Screen* for an
app-like icon.

More phones: *Settings → Server → Manage → Link another phone*. Or restart the server for a new code.

Options: `--port`, `--host`, `--data`, `--web` (also env `PORT`, `HOST`,
`THREATGUARD_DATA`, `THREATGUARD_WEB`). To run without the Dart SDK:
`dart compile exe bin/server.dart -o threatguard-server`.

> **Windows:** the first run asks to allow the server through the firewall. Allow it on
> *Private* networks or the phone cannot connect.

## How messages get in

A website cannot read a phone's SMS inbox, and iOS apps cannot either. Only the Android app
can. So messages arrive in three ways:

1. **Android app: reads your texts.** *Settings → Phone messages → Allow* asks Android for
   SMS access. Then:
   - a scan reads your **newest 300 texts** and sends them to your server (repeat scans add
     nothing twice);
   - every **new text** is passed to the server the moment it arrives, **even when the app is
     closed**, by a small background receiver (`SmsReceiver.kt`);
   - when you reopen the app it catches up on anything the receiver could not deliver (for
     example the server was off).

   Your texts go **only to your own server**, never anywhere else. The app says so before it
   asks. Disconnecting a device stops the receiver. Install the Android build with
   `flutter build apk` (the debug APK is `build/app/outputs/flutter-apk/app-debug.apk`);
   enter the server address and pairing code in the app (*Connect*).
2. **Check a message** in the app (any phone). Paste or type a suspicious text; you get the
   verdict, highlighted signals, and it is kept in your history.
3. **Forwarding**, for automatic monitoring on iPhone or on a phone without the app. Anything
   that can send an HTTP request can feed the server, for example an Android SMS-forwarder
   app or an iOS Shortcuts automation ("When I get a message → Get contents of URL"):

```bash
curl -X POST http://SERVER:8080/api/messages \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"sender":"DHL-NOTICE","body":"Your parcel is held at customs. Pay a fee: bit.ly/x"}'
```

The response says what to do: `"action": "allow" | "flag" | "block"`. The server keeps the
history, the app shows new messages within ~12 seconds. Your API key is in
`server/data/auth.json` (or set `THREATGUARD_TOKEN`, 16+ characters).

## API

All `/api` calls except health and pairing need `Authorization: Bearer <key>` (or `X-Api-Key`).

| | |
|---|---|
| `GET /api/health` | public; identifies a ThreatGuard server |
| `POST /api/pair` `{code}` | trade a one-time code for the key |
| `POST /api/pair/new` | new one-time code (for linking another device) |
| `GET /api/state?rev=` | settings, block list, all messages. Tiny reply if `rev` is unchanged |
| `POST /api/analyze` `{text}` | analyze without storing |
| `POST /api/messages` `{sender?, body, receivedAt?, source?}` | analyze + store. With `receivedAt`, an identical message is stored once (replies `200`, not `201`) |
| `POST /api/messages/import` `{messages:[{sender, body, receivedAt}]}` | bulk load, up to 200 per call, duplicates skipped |
| `DELETE /api/messages[/id]` | delete one / all |
| `POST /api/scan` | re-run the engine over history |
| `GET`/`PUT /api/settings` | `monitoring, autoBlock, linkScanning, alerts, shareIntel, sensitivity` |
| `POST /api/blocked` `{sender, blocked}` | block / unblock a sender |

## What is real, and what is not

- **Detection is rule-based**, not machine learning. It looks for scam phrases, links and
  combinations of them, and is strongest on banking, delivery, one-time-code, crypto,
  government, account-recovery and impersonation scams. It will miss scams that avoid those
  patterns, and can flag odd-but-legitimate messages. It is a second opinion, not a guarantee.
  `confidence` is the strength of the evidence, not a probability.
- **Blocking is a list on the server.** It tells a forwarder what to do (`action: "block"`);
  it cannot delete a text from your phone by itself.
- **Protection score** is how much protection you have switched on (engine 40, monitoring 25,
  auto-block 15, link scanning 10, sensitivity 4–10). It is not a measure of safety.
- **Android SMS has not been run on a device or emulator.** It compiles into a working APK and
  the Dart side is unit-tested against a fake inbox, but the Kotlin (permission dialog, inbox
  query, background receiver) has never executed. Try it on a real phone first. Test with an
  emulator via `adb emu sms send +15551234567 "Verify your account at bit.ly/x"`.
- Android may stop a closed app's receiver on some phones with aggressive battery savers; the
  catch-up on reopening covers that. Texts older than the newest 300 are not read. The same
  text arriving twice within a clock tick may be stored once.
- Google Play restricts apps that request SMS permissions. Installing the APK yourself is fine;
  publishing on Play would need Google's SMS-permission declaration.
- **Not built yet:** push notifications (the *Threat alerts* switch only shows alerts inside
  the app), anonymous threat-intel sharing (the switch is saved, nothing uses it), multiple
  user accounts (one server = one owner), SMS reading on iPhone (not possible).

## Security notes

- Every API call needs the key. Pairing codes are single-use, expire in 10 minutes, and are
  burned after 5 wrong tries. The server never logs message text, keys or codes.
- **Traffic is plain `http` on your home network by default**, so anyone on that Wi-Fi who can
  watch traffic could read it. Fine at home; for anything else put it behind HTTPS (a reverse
  proxy, or a tunnel such as Cloudflare Tunnel) and use the `https://` address.
- Phones only offer true "Install app" and offline caching on **HTTPS** pages (or
  `localhost`). Over plain LAN http you still get *Add to Home Screen*, as a shortcut.
- A page served over `https` cannot call an `http` server (the browser blocks it). Host the app
  and the server at the same address, as above.
- The Android build allows cleartext http so it can reach a LAN server
  (`usesCleartextTraffic` in `AndroidManifest.xml`). Remove it if you only use https.
- Native builds keep the key in `shared_preferences`, not the OS keychain.
- Back up `server/data/`. Keep it out of git (already ignored); it holds your messages and key.

## Develop

```bash
flutter test                              # app
cd server && dart test                    # server
cd packages/threatguard_core && dart test # engine
```

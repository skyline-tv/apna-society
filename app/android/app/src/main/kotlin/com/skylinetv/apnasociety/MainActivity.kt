package com.skylinetv.apnasociety

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        IncomingVisitorCallPlugin.register(flutterEngine, this, this)
        val visitorId = IncomingVisitorCallPlugin.readVisitorId(intent)
        if (!visitorId.isNullOrEmpty()) {
            IncomingVisitorCallManager.launchVisitorId = visitorId
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val visitorId = IncomingVisitorCallPlugin.readVisitorId(intent)
        if (!visitorId.isNullOrEmpty()) {
            IncomingVisitorCallManager.launchVisitorId = visitorId
            IncomingVisitorCallPlugin.dispatchIncoming(mapOf("visitorId" to visitorId))
        }
    }
}

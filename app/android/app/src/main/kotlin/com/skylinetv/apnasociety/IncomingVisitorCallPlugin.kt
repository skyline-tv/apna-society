package com.skylinetv.apnasociety

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter bridge for the native incoming-visitor call service.
 * Events still work if the Dart isolate was not running when FCM arrived.
 */
class IncomingVisitorCallPlugin(
    private val context: Context,
    private val activity: Activity?,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startIncoming" -> {
                val visitorId = call.argument<String>("visitorId").orEmpty()
                if (visitorId.isEmpty()) {
                    result.error("missing_id", "visitorId is required", null)
                    return
                }
                IncomingVisitorCallManager.startService(
                    context,
                    IncomingVisitorCallManager.ACTION_SHOW,
                    visitorId = visitorId,
                    visitorName = call.argument<String>("visitorName").orEmpty(),
                    flatLabel = call.argument<String>("flatLabel").orEmpty(),
                    purpose = call.argument<String>("purpose").orEmpty(),
                    expiresAt = call.argument<String>("expiresAt").orEmpty(),
                )
                result.success(true)
            }
            "stopIncoming" -> {
                IncomingVisitorCallManager.startService(
                    context,
                    IncomingVisitorCallManager.ACTION_STOP,
                    visitorId = call.argument<String>("visitorId").orEmpty(),
                )
                result.success(true)
            }
            "stopAll" -> {
                IncomingVisitorCallManager.startService(
                    context,
                    IncomingVisitorCallManager.ACTION_STOP_ALL,
                    visitorId = IncomingVisitorCallManager.activeVisitorId.orEmpty(),
                )
                result.success(true)
            }
            "consumeLaunchVisitorId" -> {
                val fromIntent = readVisitorId(activity?.intent)
                val pending = fromIntent ?: IncomingVisitorCallManager.consumeLaunchVisitorId()
                if (fromIntent != null) {
                    IncomingVisitorCallManager.launchVisitorId = null
                }
                result.success(pending)
            }
            "canUseFullScreenIntent" ->
                result.success(IncomingVisitorCallManager.canUseFullScreenIntent(context))
            "openFullScreenSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val intent =
                        Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                            data = android.net.Uri.parse("package:${context.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    context.startActivity(intent)
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        plugin = this
    }

    override fun onCancel(arguments: Any?) {
        if (plugin === this) plugin = null
        eventSink = null
    }

    private fun emit(event: Map<String, Any?>) {
        activity?.runOnUiThread { eventSink?.success(event) } ?: eventSink?.success(event)
    }

    companion object {
        const val METHOD_CHANNEL = "com.skylinetv.apnasociety/incoming_visitor_call"
        const val EVENT_CHANNEL = "com.skylinetv.apnasociety/incoming_visitor_call_events"

        @Volatile
        private var plugin: IncomingVisitorCallPlugin? = null

        fun register(engine: FlutterEngine, context: Context, activity: Activity?) {
            val plugin = IncomingVisitorCallPlugin(context.applicationContext, activity)
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                .setMethodCallHandler(plugin)
            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
                .setStreamHandler(plugin)
        }

        fun dispatchIncoming(payload: Map<String, Any?>) {
            val event = HashMap<String, Any?>(payload)
            event["type"] = "incoming"
            plugin?.emit(event)
        }

        fun dispatchStopped(visitorId: String?) {
            plugin?.emit(
                mapOf(
                    "type" to "stopped",
                    "visitorId" to (visitorId ?: ""),
                ),
            )
        }

        fun readVisitorId(intent: Intent?): String? {
            if (intent == null) return null
            val extra = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_VISITOR_ID)
            if (!extra.isNullOrEmpty()) return extra
            val data = intent.data ?: return null
            if (data.scheme != "apnasociety") return null
            if (data.host != "visitor-approval") return null
            return data.pathSegments.firstOrNull()
        }
    }
}

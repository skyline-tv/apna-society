package com.skylinetv.apnasociety

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import com.google.firebase.messaging.RemoteMessage

/**
 * Call-style incoming visitor alerts: notification, looping ringtone, vibration.
 * Started from FCM (background/terminated) and from Flutter (foreground/socket).
 */
object IncomingVisitorCallManager {
    const val CHANNEL_ID = "incoming_visitor_call"
    const val ACTION_SHOW = "com.skylinetv.apnasociety.INCOMING_VISITOR_SHOW"
    const val ACTION_STOP = "com.skylinetv.apnasociety.INCOMING_VISITOR_STOP"
    const val ACTION_STOP_ALL = "com.skylinetv.apnasociety.INCOMING_VISITOR_STOP_ALL"
    const val ACTION_DISMISS = "com.skylinetv.apnasociety.INCOMING_VISITOR_DISMISS"
    const val EXTRA_VISITOR_ID = "visitorId"
    const val EXTRA_VISITOR_NAME = "visitorName"
    const val EXTRA_FLAT_LABEL = "flatLabel"
    const val EXTRA_PURPOSE = "purpose"
    const val EXTRA_EXPIRES_AT = "expiresAt"
    const val EXTRA_OPEN_INCOMING = "openIncomingVisitor"

    private const val TAG = "IncomingVisitorCall"
    private const val NOTIFICATION_ID = 71001

    @Volatile
    var activeVisitorId: String? = null
        private set

    @Volatile
    var launchVisitorId: String? = null

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    fun handleRemoteMessage(context: Context, message: RemoteMessage) {
        val data = message.data
        val type = data["type"].orEmpty()
        val entryMode = data["entryMode"].orEmpty()
        val visitorId = data["relatedEntityId"].orEmpty().ifEmpty { data["requestId"].orEmpty() }
        if (visitorId.isEmpty()) return

        if (type == "VISITOR_REQUEST" && entryMode == "WALK_IN") {
            startService(
                context,
                ACTION_SHOW,
                visitorId = visitorId,
                visitorName = data["visitorName"].orEmpty().ifEmpty { "Visitor" },
                flatLabel = data["flatLabel"].orEmpty(),
                purpose = data["purpose"].orEmpty(),
                expiresAt = data["expiresAt"].orEmpty(),
            )
            return
        }
        val stopCall =
            data["callAction"] == "stop" ||
                (
                    entryMode == "WALK_IN" &&
                        type in setOf("VISITOR_APPROVED", "VISITOR_REJECTED", "VISITOR_EXPIRED")
                    )
        if (stopCall) {
            startService(context, ACTION_STOP, visitorId = visitorId)
        }
    }

    fun startService(
        context: Context,
        action: String,
        visitorId: String,
        visitorName: String = "",
        flatLabel: String = "",
        purpose: String = "",
        expiresAt: String = "",
    ) {
        val intent =
            Intent(context, IncomingVisitorCallService::class.java).apply {
                this.action = action
                putExtra(EXTRA_VISITOR_ID, visitorId)
                putExtra(EXTRA_VISITOR_NAME, visitorName)
                putExtra(EXTRA_FLAT_LABEL, flatLabel)
                putExtra(EXTRA_PURPOSE, purpose)
                putExtra(EXTRA_EXPIRES_AT, expiresAt)
            }
        // STOP must never use startForegroundService. Android kills the app if
        // startForeground() is not called within a few seconds of that API.
        if (action != ACTION_SHOW) {
            stopRingtone()
            notificationManager(context).cancel(NOTIFICATION_ID)
            clearActive(if (action == ACTION_STOP_ALL) null else visitorId)
            try {
                context.stopService(Intent(context, IncomingVisitorCallService::class.java))
            } catch (error: Exception) {
                Log.w(TAG, "Unable to stop incoming-call service: ${error.message}")
            }
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to start incoming-call service: ${error.message}")
            if (action == ACTION_SHOW) {
                ensureChannel(context)
                notificationManager(context)
                    .notify(
                        NOTIFICATION_ID,
                        buildNotification(context, visitorId, visitorName, flatLabel, purpose),
                    )
                startRingtone(context)
            } else {
                stopRingtone()
                notificationManager(context).cancel(NOTIFICATION_ID)
                activeVisitorId = null
            }
        }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager(context)
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val attrs =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Incoming visitors",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Call-style visitor approval requests"
                // Ringtone is played by IncomingVisitorCallService so the
                // notification itself stays silent and does not double-ring.
                setSound(null, attrs)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 400, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(false)
            }
        manager.createNotificationChannel(channel)
    }

    fun buildPlaceholderNotification(context: Context): Notification {
        ensureChannel(context)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("VISITOR AT MAIN GATE")
            .setContentText("Connecting…")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun promoteToForeground(service: Service, notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(
                    SERVICE_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                service.startForeground(SERVICE_NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            Log.w(TAG, "startForeground failed, retrying with a simple notice: ${error.message}")
            try {
                val fallback = buildPlaceholderNotification(service)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    service.startForeground(
                        SERVICE_NOTIFICATION_ID,
                        fallback,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                } else {
                    service.startForeground(SERVICE_NOTIFICATION_ID, fallback)
                }
            } catch (ignored: Exception) {
                Log.e(TAG, "startForeground retry failed: ${ignored.message}")
            }
        }
    }

    fun buildNotification(
        context: Context,
        visitorId: String,
        visitorName: String,
        flatLabel: String,
        purpose: String,
    ): Notification {
        ensureChannel(context)
        val openIntent = activityIntent(context, visitorId)
        val dismissIntent =
            PendingIntent.getBroadcast(
                context,
                visitorId.hashCode(),
                Intent(context, IncomingVisitorCallReceiver::class.java).apply {
                    action = ACTION_DISMISS
                    putExtra(EXTRA_VISITOR_ID, visitorId)
                },
                pendingFlags(),
            )
        val caller = Person.Builder().setName(visitorName).setImportant(true).build()
        val content =
            if (flatLabel.isNotEmpty() && purpose.isNotEmpty()) {
                "$flatLabel · $purpose"
            } else {
                listOf(flatLabel, purpose).filter { it.isNotEmpty() }.joinToString(" · ")
                    .ifEmpty { "Waiting at the main gate" }
            }
        val builder =
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("VISITOR AT MAIN GATE")
                .setContentText("$visitorName · $content")
                .setStyle(
                    NotificationCompat.BigTextStyle()
                        .bigText("$visitorName\n$content"),
                )
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(openIntent)
                .setFullScreenIntent(openIntent, true)
                .setDeleteIntent(dismissIntent)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(0, "APPROVE", openIntent)
                .addAction(0, "REJECT", openIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                builder.setStyle(
                    NotificationCompat.CallStyle.forIncomingCall(caller, dismissIntent, openIntent),
                )
            } catch (error: Exception) {
                Log.w(TAG, "CallStyle unavailable: ${error.message}")
            }
        }
        return builder.build()
    }

    fun startRingtone(context: Context) {
        if (player?.isPlaying == true) return
        stopRingtone()
        try {
            val media = MediaPlayer()
            val uri = android.net.Uri.parse("android.resource://${context.packageName}/raw/incoming_visitor")
            media.setDataSource(context, uri)
            media.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            media.isLooping = true
            media.prepare()
            media.start()
            player = media
        } catch (error: Exception) {
            Log.w(TAG, "Custom ringtone failed, using default: ${error.message}")
            try {
                val fallback = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val media = MediaPlayer()
                media.setDataSource(context, fallback)
                media.isLooping = true
                media.prepare()
                media.start()
                player = media
            } catch (ignored: Exception) {
                Log.w(TAG, "Default ringtone failed: ${ignored.message}")
            }
        }
        startVibration(context)
    }

    fun stopRingtone() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    fun markActive(visitorId: String) {
        activeVisitorId = visitorId
        launchVisitorId = visitorId
    }

    fun clearActive(visitorId: String?) {
        if (visitorId == null || activeVisitorId == visitorId) {
            activeVisitorId = null
        }
        if (visitorId == null || launchVisitorId == visitorId) {
            launchVisitorId = null
        }
        IncomingVisitorCallPlugin.dispatchStopped(visitorId)
    }

    fun consumeLaunchVisitorId(): String? {
        val id = launchVisitorId
        launchVisitorId = null
        return id
    }

    private fun startVibration(context: Context) {
        val vib =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        vibrator = vib
        val pattern = longArrayOf(0, 600, 400, 600, 800)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, 0)
        }
    }

    fun activityIntent(context: Context, visitorId: String): PendingIntent {
        val intent =
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = android.net.Uri.parse("apnasociety://visitor-approval/$visitorId")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_VISITOR_ID, visitorId)
                putExtra(EXTRA_OPEN_INCOMING, true)
            }
        return PendingIntent.getActivity(context, visitorId.hashCode(), intent, pendingFlags())
    }

    fun notificationManager(context: Context): NotificationManager {
        return context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    fun canUseFullScreenIntent(context: Context): Boolean {
        val manager = notificationManager(context)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.canUseFullScreenIntent()
        } else {
            true
        }
    }

    fun pendingFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }

    const val SERVICE_NOTIFICATION_ID = NOTIFICATION_ID
}

class IncomingVisitorCallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        IncomingVisitorCallManager.promoteToForeground(
            this,
            IncomingVisitorCallManager.buildPlaceholderNotification(this),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        IncomingVisitorCallManager.promoteToForeground(
            this,
            IncomingVisitorCallManager.buildPlaceholderNotification(this),
        )
        val action = intent?.action
        if (action == null) {
            stopCallAndSelf(null)
            return START_NOT_STICKY
        }
        val visitorId = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_VISITOR_ID).orEmpty()
        when (action) {
            IncomingVisitorCallManager.ACTION_SHOW -> {
                if (visitorId.isEmpty()) {
                    stopCallAndSelf(null)
                    return START_NOT_STICKY
                }
                val name = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_VISITOR_NAME).orEmpty()
                val flat = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_FLAT_LABEL).orEmpty()
                val purpose = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_PURPOSE).orEmpty()
                IncomingVisitorCallManager.markActive(visitorId)
                val notification =
                    IncomingVisitorCallManager.buildNotification(this, visitorId, name, flat, purpose)
                IncomingVisitorCallManager.promoteToForeground(this, notification)
                IncomingVisitorCallManager.startRingtone(this)
                IncomingVisitorCallPlugin.dispatchIncoming(
                    mapOf(
                        "visitorId" to visitorId,
                        "visitorName" to name,
                        "flatLabel" to flat,
                        "purpose" to purpose,
                    ),
                )
            }
            IncomingVisitorCallManager.ACTION_STOP,
            IncomingVisitorCallManager.ACTION_DISMISS,
            IncomingVisitorCallManager.ACTION_STOP_ALL,
            -> {
                val active = IncomingVisitorCallManager.activeVisitorId
                if (action != IncomingVisitorCallManager.ACTION_STOP_ALL &&
                    visitorId.isNotEmpty() &&
                    active != null &&
                    active != visitorId
                ) {
                    return START_NOT_STICKY
                }
                stopCallAndSelf(
                    if (action == IncomingVisitorCallManager.ACTION_STOP_ALL) {
                        null
                    } else {
                        visitorId.ifEmpty { active }
                    },
                )
            }
        }
        return START_NOT_STICKY
    }

    private fun stopCallAndSelf(visitorId: String?) {
        IncomingVisitorCallManager.stopRingtone()
        IncomingVisitorCallManager.notificationManager(this)
            .cancel(IncomingVisitorCallManager.SERVICE_NOTIFICATION_ID)
        IncomingVisitorCallManager.clearActive(visitorId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        IncomingVisitorCallManager.stopRingtone()
        super.onDestroy()
    }
}

class IncomingVisitorCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == IncomingVisitorCallManager.ACTION_DISMISS) {
            val visitorId = intent.getStringExtra(IncomingVisitorCallManager.EXTRA_VISITOR_ID).orEmpty()
            IncomingVisitorCallManager.startService(
                context.applicationContext,
                IncomingVisitorCallManager.ACTION_STOP,
                visitorId = visitorId,
            )
            return
        }
        val extras = intent.extras ?: return
        try {
            val message = RemoteMessage(extras)
            IncomingVisitorCallManager.handleRemoteMessage(context.applicationContext, message)
        } catch (error: Exception) {
            Log.w("IncomingVisitorCall", "FCM extras were not a RemoteMessage: ${error.message}")
        }
    }
}

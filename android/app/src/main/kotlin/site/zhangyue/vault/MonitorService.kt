package site.zhangyue.vault

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** User-started, visible monitoring. No boot receiver, restart loop or battery exemption. */
internal object MonitorRuntime {
    val gate = MonitorGeneration()
    @Volatile var running = false
    @Volatile var connection: HttpURLConnection? = null
    var started: ((String?) -> Unit)? = null
    var startupGeneration = -1L
    var statusCode = "monitor_stopped"

    fun notificationAllowed(context: Context): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    fun start(context: Context, server: String, bearer: String, reply: (String?) -> Unit) {
        try {
            require(notificationAllowed(context)) { "monitor_permission_required" }
            require(bearer.length in 1..16384 && bearer.none { it.code < 33 || it.code > 126 }) { "monitor_invalid_credential" }
            val configured = context.assets.open("flutter_assets/assets/runtime-config.json").bufferedReader().use { JSONObject(it.readText()).getString("api_base_url") }
            val endpoint = MonitorPolicy.endpoint(server, configured)
            val generation = gate.advance()
            running = false
            connection?.disconnect()
            started?.invoke("monitor_superseded")
            started = null
            MonitorCredentials.save(context, endpoint, bearer)
            startupGeneration = generation
            started = reply
            statusCode = "monitor_starting"
            val intent = Intent(context, MonitorService::class.java).putExtra("generation", generation)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (_: Exception) {
                started = null
                stop(context, generation)
                reply("monitor_start_rejected")
                return
            }
            Handler(Looper.getMainLooper()).postDelayed({
                if (gate.isCurrent(generation) && !running) {
                    val callback = started
                    started = null
                    stop(context, generation)
                    callback?.invoke("monitor_start_timeout")
                }
            }, 5000)
        } catch (error: Exception) {
            // Never forward exception text containing a URL, token or filesystem state.
            reply(if (error is IllegalArgumentException && error.message in setOf("monitor_permission_required", "monitor_invalid_credential", "monitor_invalid_origin", "monitor_origin_mismatch")) error.message else "monitor_start_failed")
        }
    }

    fun stop(context: Context, expected: Long? = null) {
        fun clean() {
            gate.advance()
            running = false
            statusCode = "monitor_stopped"
            connection?.disconnect()
            connection = null
            val callback = started
            started = null
            callback?.invoke("monitor_stopped")
            try { MonitorCredentials.clear(context) } catch (_: Exception) { }
            context.stopService(Intent(context, MonitorService::class.java))
            NotificationManagerCompat.from(context).cancelAll()
        }
        if (expected == null) clean() else gate.runIfCurrent(expected) { clean() }
    }
}

class MonitorService : Service() {
    private var generation = -1L
    private var worker = Executors.newSingleThreadScheduledExecutor()
    private var scheduled: ScheduledFuture<*>? = null
    private var policy = MonitorPolicy()
    private val main = Handler(Looper.getMainLooper())
    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            MonitorRuntime.stop(this)
            return START_NOT_STICKY
        }
        val requested = intent?.getLongExtra("generation", -1L) ?: -1L
        if (!MonitorRuntime.gate.isCurrent(requested)) return START_NOT_STICKY
        generation = requested
        scheduled?.cancel(true)
        policy = MonitorPolicy()
        try {
            require(MonitorRuntime.notificationAllowed(this))
            createChannels()
            val notification = foregroundNotification()
            if (Build.VERSION.SDK_INT >= 34) startForeground(ONGOING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(ONGOING_ID, notification)
            val credentials = MonitorCredentials.load(this)
            MonitorRuntime.running = true
            MonitorRuntime.statusCode = "monitor_running"
            val reply = MonitorRuntime.started
            MonitorRuntime.started = null
            reply?.invoke(null)
            scheduled = worker.scheduleWithFixedDelay({ poll(requested, credentials.first, credentials.second) }, 0, 60, TimeUnit.SECONDS)
        } catch (_: Exception) {
            val reply = MonitorRuntime.started
            MonitorRuntime.started = null
            MonitorRuntime.stop(this, requested)
            reply?.invoke("monitor_start_failed")
        }
        return START_NOT_STICKY
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(ONGOING_CHANNEL, "运行中的状态监测", NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(ALERT_CHANNEL, "额度与服务器提醒", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }
    private fun foregroundNotification(): Notification {
        val stop = PendingIntent.getService(this, 0, Intent(this, MonitorService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, ONGOING_CHANNEL).setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle("乐天助手正在监测").setContentText("每分钟检查状态；可随时停止，受系统省电影响")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止监测", stop).build()
    }

    private fun poll(requested: Long, endpoint: String, bearer: String) {
        if (!MonitorRuntime.gate.isCurrent(requested)) return
        var connection: HttpURLConnection? = null
        try {
            if (!MonitorRuntime.notificationAllowed(this)) {
                main.post { MonitorRuntime.stop(this, requested) }
                return
            }
            connection = URL(endpoint).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.requestMethod = "GET"
            connection.setRequestProperty("Authorization", "Bearer $bearer")
            connection.setRequestProperty("Accept", "application/json")
            connection.useCaches = false
            if (!MonitorRuntime.gate.runIfCurrent(requested) { MonitorRuntime.connection = connection }) return
            val code = connection.responseCode
            if (code == 401 || code == 403) {
                main.post { MonitorRuntime.stop(this, requested) }
                return
            }
            require(code == 200) { "monitor_http_failed" }
            require(connection.contentLengthLong <= MonitorPolicy.MAX_RESPONSE_BYTES) { "monitor_response_too_large" }
            val body = connection.inputStream.use { MonitorPolicy.readBounded(it) }
            val payload = JSONObject(body.toString(Charsets.UTF_8))
            val items = payload.getJSONArray("items")
            require(items.length() <= 1000)
            val settingsObject = payload.getJSONObject("settings")
            val settings = listOf("daily", "quota", "balance", "server", "reset", "recovery").associateWith { settingsObject.opt(it) == true }
            val events = (0 until items.length()).mapNotNull { index ->
                val item = items.optJSONObject(index) ?: return@mapNotNull null
                val id = item.opt("id") as? String ?: return@mapNotNull null
                val sourceTime = (item.opt("source_time") as? Number)?.toDouble() ?: return@mapNotNull null
                val type = item.opt("type") as? String ?: return@mapNotNull null
                val read = item.opt("read") as? Boolean ?: return@mapNotNull null
                MonitorEvent(id, sourceTime, read || !MonitorPolicy.categoryEnabled(type, settings), type)
            }
            MonitorRuntime.gate.runIfCurrent(requested) {
                // Baseline, dedup mutation and posting share the same generation lock.
                for (event in policy.accept(events, System.currentTimeMillis() / 1000.0, true)) postEvent(event.id)
            }
        } catch (_: Exception) {
            // Sampling failure is neither a zero balance nor a recovery. Next attempt
            // remains 60 seconds later and no raw URL/credential/response is logged.
        } finally {
            connection?.disconnect()
            MonitorRuntime.gate.runIfCurrent(requested) { if (MonitorRuntime.connection === connection) MonitorRuntime.connection = null }
        }
    }

    private fun postEvent(id: String) {
        val intent = Intent(this, MainActivity::class.java).putExtra("letian_notification_event_id", id)
            .setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .setData(android.net.Uri.parse("letian-notification://event/$id"))
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("乐天助手").setContentText("状态更新，请打开助手")
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setContentIntent(pending).setAutoCancel(true).build()
        NotificationManagerCompat.from(this).notify("monitor_event_$id", 2, notification)
    }

    override fun onDestroy() {
        scheduled?.cancel(true)
        worker.shutdownNow()
        // A delayed destroy from an old service must not clear a newer session.
        if (MonitorRuntime.gate.isCurrent(generation)) MonitorRuntime.stop(this, generation)
        super.onDestroy()
    }
    companion object {
        private const val ACTION_STOP = "site.zhangyue.vault.STOP_MONITOR"
        private const val ONGOING_CHANNEL = "letian_monitor_running"
        private const val ALERT_CHANNEL = "letian_alerts"
        private const val ONGOING_ID = 41001
    }
}

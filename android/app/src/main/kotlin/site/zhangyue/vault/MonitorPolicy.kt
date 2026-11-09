package site.zhangyue.vault

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URI

internal data class MonitorEvent(val id: String, val sourceTime: Double, val read: Boolean, val type: String)

/** A single lock serializes generation changes and notification side effects. */
internal class MonitorGeneration {
    private var value = 0L
    @Synchronized fun advance(): Long { value += 1; return value }
    @Synchronized fun isCurrent(candidate: Long): Boolean = candidate == value
    @Synchronized fun runIfCurrent(candidate: Long, action: () -> Unit): Boolean {
        if (candidate != value) return false
        action()
        return true
    }
}

internal class MonitorPolicy {
    private var baseline = false
    private val seen = LinkedHashSet<String>()

    fun accept(events: List<MonitorEvent>, now: Double, enabled: Boolean): List<MonitorEvent> {
        val first = !baseline
        baseline = true
        val result = ArrayList<MonitorEvent>()
        for (event in events) {
            if (!safeID(event.id)) continue
            val freshID = seen.add(event.id)
            if (!first && enabled && freshID && !event.read && event.sourceTime.isFinite() &&
                event.sourceTime <= now && now - event.sourceTime <= 300.0) result.add(event)
        }
        while (seen.size > 2000) seen.remove(seen.first())
        return result
    }

    companion object {
        const val MAX_RESPONSE_BYTES = 256 * 1024
        fun categoryEnabled(type: String, settings: Map<String, Boolean>): Boolean {
            val category = when {
                type == "daily_digest" -> "daily"
                type.startsWith("quota_") -> "quota"
                type.startsWith("balance_") -> "balance"
                type.startsWith("server_") || type.startsWith("monitor_") -> "server"
                else -> return false
            }
            return settings[category] == true &&
                (!type.endsWith("_recovered") || settings["recovery"] == true) &&
                (type != "quota_reset" || settings["reset"] == true)
        }
        fun safeID(value: String): Boolean = Regex("[A-Za-z0-9_-]{1,128}").matches(value)
        fun endpoint(server: String, configured: String): String {
            fun origin(value: String): URI {
                val uri = try { URI(value) } catch (_: Exception) { throw IllegalArgumentException("monitor_invalid_origin") }
                require(uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() &&
                    uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
                    (uri.rawPath.isNullOrEmpty() || uri.rawPath == "/") &&
                    (uri.port == -1 || uri.port in 1..65535)) { "monitor_invalid_origin" }
                return uri
            }
            val candidate = origin(server)
            val trusted = origin(configured)
            require(candidate.host.equals(trusted.host, true) &&
                (candidate.port.takeIf { it != -1 } ?: 443) == (trusted.port.takeIf { it != -1 } ?: 443)) { "monitor_origin_mismatch" }
            return URI("https", null, trusted.host.lowercase(), trusted.port.takeIf { it != 443 } ?: -1,
                "/api/hub/notifications", null, null).toASCIIString()
        }
        fun readBounded(input: InputStream, limit: Int = MAX_RESPONSE_BYTES): ByteArray {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= limit) { "monitor_response_too_large" }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        }
    }
}

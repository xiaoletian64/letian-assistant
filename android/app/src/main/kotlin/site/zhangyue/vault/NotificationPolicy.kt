package site.zhangyue.vault

/** Permission and transport capability are deliberately independent. */
internal object NotificationPolicy {
    fun authorization(sdk: Int, enabled: Boolean, requested: Boolean): String = when {
        enabled -> "authorized"
        sdk >= 33 && !requested -> "notDetermined"
        else -> "denied"
    }

    fun status(sdk: Int, enabled: Boolean, requested: Boolean, running: Boolean = false): Map<String, Any?> = mapOf(
        "authorization" to authorization(sdk, enabled, requested),
        "token" to null,
        "background_available" to (enabled && running),
        "mode" to "foreground_monitor",
        "monitor_running" to running,
        "status_code" to if (running) "monitor_running" else "monitor_stopped"
    )
}

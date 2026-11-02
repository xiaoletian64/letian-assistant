package site.zhangyue.vault

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class MonitorPolicyTest {
    @Test fun restrictsCredentialDestinationToConfiguredHttpsOrigin() {
        assertEquals("https://example.org/api/hub/notifications", MonitorPolicy.endpoint("https://example.org/", "https://EXAMPLE.org:443"))
        for (server in listOf("http://example.org", "https://evil.test", "https://example.org@evil.test", "https://example.org/?secret=x", "https://example.org/#x", "https://example.org/path")) {
            try { MonitorPolicy.endpoint(server, "https://example.org"); fail(server) } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun responseLimitIsEnforcedDuringStreaming() {
        assertEquals(3, MonitorPolicy.readBounded(ByteArrayInputStream(ByteArray(3)), 3).size)
        try { MonitorPolicy.readBounded(ByteArrayInputStream(ByteArray(4)), 3); fail() } catch (_: IllegalArgumentException) { }
    }
    @Test fun firstSnapshotIsBaselineThenOnlyFreshUnreadNewIDsNotify() {
        val policy = MonitorPolicy()
        val now = 1000.0
        assertTrue(policy.accept(listOf(MonitorEvent("old", 999.0, false, "quota_low")), now, true).isEmpty())
        val next = listOf(MonitorEvent("old", 999.0, false, "quota_low"), MonitorEvent("fresh", 1001.0, false, "quota_low"),
            MonitorEvent("read", 1001.0, true, "quota_low"), MonitorEvent("expired", 600.0, false, "quota_low"),
            MonitorEvent("future", 2000.0, false, "quota_low"), MonitorEvent("../unsafe", 1001.0, false, "quota_low"))
        assertEquals(listOf("fresh"), policy.accept(next, 1002.0, true).map { it.id })
        assertTrue(policy.accept(next, 1003.0, true).isEmpty())
    }
    @Test fun disabledCategoriesAreNotReplayedAfterEnabling() {
        val policy = MonitorPolicy()
        policy.accept(emptyList(), 1000.0, true)
        assertTrue(policy.accept(listOf(MonitorEvent("muted", 1001.0, false, "quota_low")), 1002.0, false).isEmpty())
        assertTrue(policy.accept(listOf(MonitorEvent("muted", 1001.0, false, "quota_low")), 1003.0, true).isEmpty())
    }
    @Test fun categoriesRequireTheirAdditionalRecoveryAndResetSwitches() {
        val all = mapOf("quota" to true, "balance" to true, "server" to true, "recovery" to true, "reset" to true)
        assertTrue(MonitorPolicy.categoryEnabled("monitor_unreachable", all))
        assertFalse(MonitorPolicy.categoryEnabled("quota_reset", all + ("reset" to false)))
        assertFalse(MonitorPolicy.categoryEnabled("balance_recovered", all + ("recovery" to false)))
        assertFalse(MonitorPolicy.categoryEnabled("server_anomaly", all + ("server" to false)))
        assertFalse(MonitorPolicy.categoryEnabled("unknown", all))
        assertFalse(MonitorPolicy.categoryEnabled("quota_low", emptyMap()))
    }
    @Test fun generationInvalidatesPreviousRequests() {
        val gate = MonitorGeneration()
        val first = gate.advance()
        val second = gate.advance()
        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(second))
        assertFalse(gate.runIfCurrent(first) { fail("old session must never post") })
    }
}

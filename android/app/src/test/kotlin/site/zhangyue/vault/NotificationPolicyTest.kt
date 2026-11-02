package site.zhangyue.vault

import org.junit.Assert.*
import org.junit.Test

class NotificationPolicyTest {
    @Test fun permissionHasNotBeenRequestedIsNotDetermined() {
        assertEquals("notDetermined", NotificationPolicy.authorization(33, false, false))
    }
    @Test fun rejectionAndSystemSwitchAreDenied() {
        assertEquals("denied", NotificationPolicy.authorization(33, false, true))
        assertEquals("denied", NotificationPolicy.authorization(32, false, false))
    }
    @Test fun authorizedDoesNotMeanMonitorIsRunning() {
        val status = NotificationPolicy.status(33, true, true)
        assertEquals("authorized", status["authorization"])
        assertNull(status["token"])
        assertEquals(false, status["background_available"])
        assertEquals("monitor_stopped", status["status_code"])
    }
    @Test fun runningStatusRequiresBothPermissionAndStartedService() {
        assertEquals(true, NotificationPolicy.status(33, true, true, true)["background_available"])
        assertEquals(false, NotificationPolicy.status(33, false, true, true)["background_available"])
        assertEquals("foreground_monitor", NotificationPolicy.status(33, true, true)["mode"])
    }
}

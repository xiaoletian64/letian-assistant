package site.zhangyue.vault

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.ByteArrayInputStream
import java.security.MessageDigest

class TransferPolicyTest {
    @Test fun rejectsUntrustedBackupNames() {
        val dir = java.nio.file.Files.createTempDirectory("backup-test-").toFile()
        try {
            for (name in listOf("../x.minisbak", "/x.minisbak", "a\\x.minisbak", "..minisbak", "x\u0000.minisbak", "x\n.minisbak", "x.apk", "", ".minisbak")) {
                try { TransferPolicy.backupTarget(dir, name); fail(name) } catch (_: IllegalArgumentException) {}
            }
            assertEquals(File(dir, "good.minisbak").canonicalFile, TransferPolicy.backupTarget(dir, "good.minisbak"))
        } finally { dir.deleteRecursively() }
    }
    @Test fun rejectsWrongPackageOldVersionAndSigner() {
        TransferPolicy.validateUpdateIdentity("example.app", "example.app", 2, 1, setOf("signed"), setOf("signed"))
        for ((pkg, version, certs) in listOf(Triple("other.app", 2L, setOf("signed")), Triple("example.app", 1L, setOf("signed")), Triple("example.app", 2L, setOf("wrong")), Triple("example.app", 2L, emptySet<String>()))) {
            try { TransferPolicy.validateUpdateIdentity(pkg, "example.app", version, 1, certs, setOf("signed")); fail() } catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun requiresHttpsShaAndDirectResponse() {
        val sha = "a".repeat(64)
        for ((url, hash) in listOf("http://example.test/update.apk" to sha, "https://user@example.test/a" to sha, "https://example.test/a#fragment" to sha, "https://example.test/a" to "", "https://example.test/a" to "g".repeat(64))) {
            try { TransferPolicy.validateDownload(url, hash); fail(url) } catch (_: IllegalArgumentException) {}
        }
        TransferPolicy.validateDownload("https://example.test/update.apk", sha)
        for (code in listOf(301,302,307,308,404,206)) {
            try { TransferPolicy.requireDownloadResponse(code); fail("$code") } catch (_: IllegalArgumentException) {}
        }
        TransferPolicy.requireDownloadResponse(200)
    }
    @Test fun failedCopyOrValidationPreservesExistingFileAndCleansTemporary() {
        val dir = java.nio.file.Files.createTempDirectory("copy-test-").toFile()
        val target = File(dir, "good.minisbak"); target.writeText("old")
        try {
            try { TransferPolicy.publish(ByteArrayInputStream("too big".toByteArray()), target, 2); fail() } catch (_: IllegalArgumentException) {}
            assertEquals("old", target.readText())
            try { TransferPolicy.publish(ByteArrayInputStream("new".toByteArray()), target, 20) { _, _ -> throw IllegalArgumentException("invalid") }; fail() } catch (_: IllegalArgumentException) {}
            assertEquals("old", target.readText())
            assertEquals(listOf(target.name), dir.list()!!.toList())
            val digest = TransferPolicy.publish(ByteArrayInputStream("new".toByteArray()), target, 20)
            assertEquals("new", target.readText())
            assertEquals(MessageDigest.getInstance("SHA-256").digest("new".toByteArray()).joinToString("") { "%02x".format(it) }, digest)
        } finally { dir.deleteRecursively() }
    }
}

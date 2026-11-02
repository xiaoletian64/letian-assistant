package site.zhangyue.vault

import java.io.File
import java.io.InputStream
import java.net.URI
import java.security.MessageDigest

/** Pure JVM policies shared by backup imports and APK downloads. */
object TransferPolicy {
    const val MAX_BACKUP_BYTES = 256L * 1024 * 1024
    const val MAX_APK_BYTES = 512L * 1024 * 1024

    fun backupTarget(directory: File, name: String): File {
        require(name.length in 10..200 && name.endsWith(".minisbak")) { "无效备份文件名" }
        require(!name.contains("..") && name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }) { "无效备份文件名" }
        require(!File(name).isAbsolute) { "无效备份路径" }
        val root = directory.canonicalFile
        val target = File(root, name).canonicalFile
        require(target.parentFile == root) { "备份路径越界" }
        return target
    }

    fun validateDownload(url: String, sha: String) {
        require(Regex("[a-fA-F0-9]{64}").matches(sha)) { "更新缺少有效 SHA-256" }
        val uri = try { URI(url) } catch (_: Exception) { throw IllegalArgumentException("无效更新地址") }
        require(uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() && uri.rawUserInfo == null && uri.rawFragment == null) { "更新地址必须为不含用户信息或片段的 HTTPS" }
    }
    fun validateUpdateIdentity(candidatePackage: String, installedPackage: String, candidateVersion: Long, installedVersion: Long, candidateSigners: Set<String>, installedSigners: Set<String>) {
        require(candidatePackage == installedPackage) { "安装包应用标识不匹配" }
        require(candidateVersion > installedVersion) { "更新版本必须高于当前版本" }
        require(installedSigners.isNotEmpty() && candidateSigners == installedSigners) { "安装包签名不匹配" }
    }

    fun requireDownloadResponse(code: Int) { require(code == 200) { "更新下载失败或发生重定向" } }

    /** Validation runs on the completed temporary file before atomic publication. */
    fun publish(input: InputStream, target: File, maxBytes: Long, validate: (File, String) -> Unit = { _, _ -> }): String {
        val directory = requireNotNull(target.parentFile)
        require(directory.isDirectory || directory.mkdirs()) { "无法创建传输目录" }
        val temporary = File.createTempFile(".transfer-", ".part", directory)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            temporary.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    total += count
                    require(total <= maxBytes) { "文件超过大小限制" }
                    digest.update(buffer, 0, count)
                    output.write(buffer, 0, count)
                }
                output.fd.sync()
            }
            require(total > 0) { "文件为空" }
            val sha = digest.digest().joinToString("") { "%02x".format(it) }
            validate(temporary, sha)
            // Same-directory rename is atomic on Android's app files filesystem.
            // Do not delete the previous target before rename; failures retain it.
            require(temporary.renameTo(target)) { "无法发布文件" }
            return sha
        } finally { temporary.delete() }
    }
}

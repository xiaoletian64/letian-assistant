package site.zhangyue.vault

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val pendingTokens = HashMap<String, PendingWrite>()
    private var photoResult: MethodChannel.Result? = null
    private var photoUri: Uri? = null
    private var unlockResult: MethodChannel.Result? = null
    private val PICK_PHOTO = 4202
    private val TAKE_PHOTO = 4203
    private val UNLOCK = 4204
    private val SAVE_PRIVATE_FILE = 4205
    private var fileOperationBusy = false
    private var fileSaveResult: MethodChannel.Result? = null
    private var fileToSave: File? = null
    private val PICK_DIR = 4201
    private var dirResult: MethodChannel.Result? = null
    private var treeUri: Uri? = null

    data class PendingWrite(val displayName: String, val mime: String)

    override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "site.zhangyue.vault/install").setMethodCallHandler { call, result ->
            when (call.method) {
                "installFromUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    val sha = call.argument<String>("sha") ?: ""
                    Thread { try { installFromUrl(url, sha); runOnUiThread { result.success(true) } }
                    catch (e: Exception) { runOnUiThread { result.error("E", e.message, null) } } }.start()
                }
                "installApk" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    try { installApk(requireNotNull(bytes) { "没有安装文件" }); result.success(true) }
                    catch (e: Exception) { result.error("E", e.message, null) }
                }
                "lockEnabled" -> result.success(prefs().getBoolean("app_lock", false))
                "setLock" -> { prefs().edit().putBoolean("app_lock", call.argument<Boolean>("off") != true).apply(); result.success(true) }
                "bioAuth" -> {
                    val manager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
                    val intent = manager.createConfirmDeviceCredentialIntent("解锁乐天助手", "请使用手机锁屏密码或系统身份验证")
                    if (intent == null) result.success(false)
                    else if (unlockResult != null) result.error("busy", "正在验证", null)
                    else { unlockResult = result; startActivityForResult(intent, UNLOCK) }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "site.zhangyue.vault/sys").setMethodCallHandler { call, result ->
            try { when(call.method) {
                "openUrl" -> { val uri=Uri.parse(call.argument<String>("url") ?: ""); require(uri.scheme in setOf("https","http","weixin","snssdk1128","dianping")); startActivity(Intent(Intent.ACTION_VIEW,uri)); result.success(true) }
                "openPrivateFile" -> {
                    if (fileOperationBusy) { result.error("busy", "请先完成当前文件的下载或保存", null); return@setMethodCallHandler }
                    val url = call.argument<String>("url") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    val name = File(call.argument<String>("name") ?: "download").name
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    require(trustedService(url))
                    fileOperationBusy = true
                    Thread {
                        try {
                            val conn = URL(url).openConnection() as HttpURLConnection
                            conn.instanceFollowRedirects = false
                            conn.connectTimeout = 15000; conn.readTimeout = 60000
                            conn.setRequestProperty("Authorization", "Bearer $token")
                            try {
                                require(conn.responseCode == 200) { "文件下载失败" }
                                val f = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), name)
                                conn.inputStream.use { input -> f.outputStream().use { input.copyTo(it) } }
                                runOnUiThread {
                                    try {
                                        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
                                        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        if (view.resolveActivity(packageManager) != null) {
                                            startActivity(Intent.createChooser(view, "打开文件"))
                                            fileOperationBusy = false
                                            result.success(true)
                                        } else {
                                            val save = Intent(Intent.ACTION_CREATE_DOCUMENT)
                                                .addCategory(Intent.CATEGORY_OPENABLE)
                                                .setType(mime)
                                                .putExtra(Intent.EXTRA_TITLE, name)
                                            fileSaveResult = result
                                            fileToSave = f
                                            startActivityForResult(save, SAVE_PRIVATE_FILE)
                                        }
                                    } catch (e: Exception) {
                                        fileOperationBusy = false; fileSaveResult = null; fileToSave = null
                                        result.error("file", "无法打开或保存文件，请安装文件管理应用后重试", null)
                                    }
                                }
                            } finally { conn.disconnect() }
                        } catch (e: Exception) { runOnUiThread { fileOperationBusy = false; result.error("file", "文件下载失败，请重试", null) } }
                    }.start()
                }
                "openInstallSettings" -> { if(Build.VERSION.SDK_INT>=26) startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:$packageName"))); result.success(true) }
                else -> result.notImplemented()
            } } catch(e:Exception) { result.error("open", "无法打开系统页面",null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "site.zhangyue.vault/camera").setMethodCallHandler { call, result ->
            if (photoResult != null) { result.error("busy", "请先完成当前照片选择", null); return@setMethodCallHandler }
            try {
                when (call.method) {
                    "takePhoto" -> {
                        val f = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "camera-capture.jpg")
                        photoUri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
                        val intent = Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
                            .putExtra(android.provider.MediaStore.EXTRA_OUTPUT, photoUri)
                            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        photoResult = result; startActivityForResult(intent, TAKE_PHOTO)
                    }
                    "pickPhoto" -> {
                        photoResult = result
                        startActivityForResult(Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE), PICK_PHOTO)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { photoResult = null; result.error("camera", "无法打开相机或相册", null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "site.zhangyue.vault/minis").setMethodCallHandler { call, result ->
            val launch = packageManager.getLaunchIntentForPackage("site.zhangyue.minis")
            when(call.method) {
                "download" -> {
                    val uri = Uri.parse(runtimeConfig().optString("minis_download_url"))
                    require(uri.scheme == "https" && uri.host != null && uri.userInfo == null)
                    startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(true)
                }
                "installed" -> result.success(launch != null)
                "launch" -> { if(launch == null) result.success(false) else { launch.putExtra("letian.sync.settings",true); startActivity(launch); result.success(true) } }
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "site.zhangyue.vault/sync").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> {
                    dirResult = result
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    i.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    startActivityForResult(i, PICK_DIR)
                }
                "getTreeName" -> {
                    val saved = prefs().getString("sync_tree", null)
                    result.success(saved ?: "")
                }
                "syncBackup" -> {
                    val server = call.argument<String>("server") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    Thread { result.success(syncBackup(server, token)) }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runtimeConfig(): JSONObject {
        val key = io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/runtime-config.json")
        return assets.open(key).bufferedReader().use { JSONObject(it.readText()) }
    }
    private fun trustedService(url: String): Boolean {
        val candidate = Uri.parse(url)
        val base = Uri.parse(runtimeConfig().optString("api_base_url"))
        return base.scheme == "https" && base.host != "example.invalid" &&
            candidate.scheme == "https" && candidate.host == base.host && candidate.port == base.port &&
            candidate.userInfo == null
    }
    private fun prefs() = getSharedPreferences("sync_native", Context.MODE_PRIVATE)

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_PRIVATE_FILE) {
            val result = fileSaveResult ?: return
            val file = fileToSave
            fileSaveResult = null; fileToSave = null
            val destination = data?.data
            if (resultCode != Activity.RESULT_OK || destination == null || file == null) {
                fileOperationBusy = false; result.success(false); return
            }
            Thread {
                try {
                    val output = contentResolver.openOutputStream(destination)
                        ?: throw IllegalStateException("无法写入所选位置")
                    output.use { target -> file.inputStream().use { input -> input.copyTo(target) } }
                    runOnUiThread { fileOperationBusy = false; result.success(true) }
                } catch (e: Exception) {
                    runOnUiThread { fileOperationBusy = false; result.error("file", "保存未完成，请选择其他位置重试", null) }
                }
            }.start()
            return
        }
        if (requestCode == UNLOCK) {
            unlockResult?.success(resultCode == Activity.RESULT_OK); unlockResult = null; return
        }
        if (requestCode == PICK_PHOTO || requestCode == TAKE_PHOTO) {
            val result = photoResult ?: return
            photoResult = null
            if (resultCode != Activity.RESULT_OK) { result.success(null); return }
            val uri = if (requestCode == TAKE_PHOTO) photoUri else data?.data
            if (uri == null) { result.error("camera", "未读取到图片", null); return }
            Thread {
                try {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(65536)
                        var count = input.read(buffer)
                        while (count != -1) {
                            if (out.size() + count > 15 * 1024 * 1024) throw Exception("图片超过 15 MB，请选择较小图片")
                            out.write(buffer, 0, count); count = input.read(buffer)
                        }
                        out.toByteArray()
                    } ?: throw Exception("图片无法读取")
                    val mime = if (requestCode == TAKE_PHOTO) "image/jpeg" else contentResolver.getType(uri) ?: "image/jpeg"
                    val encoded = "data:$mime;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
                    runOnUiThread { result.success(mapOf("dataUrl" to encoded)) }
                } catch (e: Exception) { runOnUiThread { result.error("camera", e.message, null) } }
            }.start()
            return
        }

        if (requestCode == PICK_DIR) {
            val r = dirResult; dirResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                treeUri = data.data
                contentResolver.takePersistableUriPermission(treeUri!!,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                val name = treeName(treeUri!!)
                prefs().edit().putString("sync_tree", treeUri!!.toString()).putString("sync_tree_name", name).apply()
                r?.success(mapOf("uri" to treeUri!!.toString(), "name" to name))
            } else r?.success(null)
        }
    }

    private fun treeName(uri: Uri): String {
        val docId = try { DocumentsContract.getTreeDocumentId(uri) } catch (e: Exception) { null }
        return if (docId != null) docId.split(":").lastOrNull { it.isNotEmpty() } ?: uri.toString() else uri.lastPathSegment ?: "dir"
    }

    private fun listTree(): List<Pair<Uri, String>> {
        val u = treeUri ?: return emptyList()
        val rootId = try { DocumentsContract.getTreeDocumentId(u) } catch (e: Exception) { return emptyList() }
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(u, rootId)
        val out = mutableListOf<Pair<Uri, String>>()
        val c: Cursor? = contentResolver.query(childrenUri, null, null, null, null)
        c?.use {
            while (it.moveToNext()) {
                val name = it.getString(it.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))
                val mime = it.getString(it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE))
                if (name.endsWith(".minisbak") && !name.endsWith(".enc")) {
                    val docId2 = it.getString(it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
                    out.add(DocumentsContract.buildDocumentUriUsingTree(u, docId2) to name)
                }
            }
        }
        return out
    }

    private fun syncBackup(server: String, token: String): Map<String, Any> {
        require(trustedService(server))
        var uploaded = 0; var failed = 0
        for ((uri, name) in listTree()) {
            try {
                val inStream = contentResolver.openInputStream(uri) ?: continue
                val bytes = inStream.readBytes(); inStream.close()
                val url = URL("$server/api/sync/upload?name=" + java.net.URLEncoder.encode(name, "UTF-8"))
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"; conn.doOutput = true; conn.instanceFollowRedirects = false
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.connectTimeout = 20000; conn.readTimeout = 60000
                conn.outputStream.use { it.write(bytes) }
                val code = conn.responseCode
                if (code in 200..299) { uploaded++ } else failed++
            } catch (e: Exception) { failed++ }
        }
        return mapOf("uploaded" to uploaded, "failed" to failed, "skippedEnc" to 0)
    }

    private fun sha256hex(b: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    @Synchronized
    private fun installFromUrl(urlStr: String, expectedSha: String) {
        TransferPolicy.validateDownload(urlStr, expectedSha)
        val target = File(requireNotNull(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)) { "下载目录不可用" }, "ota-update.apk")
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 20000
            conn.readTimeout = 120000
            conn.instanceFollowRedirects = false
            // Public download endpoint: never attach the account Bearer credential.
            TransferPolicy.requireDownloadResponse(conn.responseCode)
            require((conn.getHeaderField("Content-Length")?.toLongOrNull() ?: -1L) <= TransferPolicy.MAX_APK_BYTES) { "安装文件过大" }
            conn.inputStream.use { input ->
                TransferPolicy.publish(input, target, TransferPolicy.MAX_APK_BYTES) { temporary, actual ->
                    require(actual.equals(expectedSha, ignoreCase = true)) { "更新文件校验失败" }
                    validateUpdateArchive(temporary)
                }
            }
        } finally { conn.disconnect() }
        launchInstaller(target)
    }

    @Suppress("DEPRECATION")
    private fun validateUpdateArchive(file: File) {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = requireNotNull(packageManager.getPackageArchiveInfo(file.absolutePath, flags)) { "无法验证安装包" }
        val installed = packageManager.getPackageInfo(packageName, flags)
        val nextVersion = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val currentVersion = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        fun signatures(info: android.content.pm.PackageInfo): Set<String> {
            val certs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
            return certs?.map { sha256hex(it.toByteArray()) }?.toSet() ?: emptySet()
        }
        TransferPolicy.validateUpdateIdentity(archive.packageName, packageName, nextVersion, currentVersion, signatures(archive), signatures(installed))
    }

    private fun launchInstaller(file: File) {
        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val canInstall = if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true
        if (!canInstall) {
            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            throw IllegalStateException("请允许安装未知应用后重试")
        }
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    @Synchronized
    private fun installApk(bytes: ByteArray) {
        require(bytes.size.toLong() in 1..TransferPolicy.MAX_APK_BYTES) { "无效安装文件大小" }
        val target = File(requireNotNull(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)) { "下载目录不可用" }, "ota-update.apk")
        bytes.inputStream().use { input ->
            TransferPolicy.publish(input, target, TransferPolicy.MAX_APK_BYTES) { temporary, _ -> validateUpdateArchive(temporary) }
        }
        launchInstaller(target)
    }
}

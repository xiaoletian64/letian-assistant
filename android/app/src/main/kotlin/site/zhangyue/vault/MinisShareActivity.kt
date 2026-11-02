package site.zhangyue.vault

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.io.File

class MinisShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        var saved = 0
        if (uri != null) {
            try {
                val name = contentResolver.query(uri, null, null, null, null)?.use { c ->
                    require(c.moveToFirst()) { "无法读取文件名" }
                    c.getString(c.getColumnIndexOrThrow(android.provider.OpenableColumns.DISPLAY_NAME))
                } ?: ("shared-" + System.currentTimeMillis() + ".minisbak")
                val dir = File(filesDir, "minisbackup")
                require(dir.isDirectory || dir.mkdirs())
                val target = TransferPolicy.backupTarget(dir, name)
                val input = requireNotNull(contentResolver.openInputStream(uri)) { "无法读取备份" }
                input.use { TransferPolicy.publish(it, target, TransferPolicy.MAX_BACKUP_BYTES) }
                saved = 1
            } catch (e: Exception) { }
        }
        val r = Intent()
        r.putExtra("saved", saved)
        setResult(if (saved == 1) RESULT_OK else RESULT_CANCELED, r)
        finish()
    }
}

package com.musicx.musicx

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新所需的两个原生能力:
 *  - getVersionName:Flutter 侧读不到安卓包版本(Info.plist 那套只适用 macOS),
 *    否则版本号恒为 0.0.0、每次启动都误报「有新版本」。
 *  - installApk:把下载好的 APK 通过 FileProvider 以 content:// 交给系统安装器。
 *    Android 8+ 需要用户在系统提示里授予「安装未知应用」权限。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "musicx/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionName" -> result.success(versionName())
                    "getVersionCode" -> result.success(versionCode())
                    "apkVersionCode" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            if (path.isNullOrEmpty()) null else apkVersionCode(path)
                        )
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        result.success(if (path.isNullOrEmpty()) false else installApk(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun versionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: ""
    } catch (e: Exception) {
        ""
    }

    /** 已安装应用的 versionCode(安装前比较版本用)。 */
    private fun versionCode(): Int = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }
    } catch (e: Exception) {
        -1
    }

    /** 读取 APK 文件的 versionCode:交给安装器之前核对,避免同版本/旧包被系统拒绝。 */
    private fun apkVersionCode(path: String): Int = try {
        val info = packageManager.getPackageArchiveInfo(path, 0)
        if (info == null) {
            -1
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }
    } catch (e: Exception) {
        -1
    }

    private fun installApk(path: String): Boolean = try {
        val file = File(path)
        if (!file.exists()) return false
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        true
    } catch (e: Exception) {
        // 未授权「安装未知应用」时部分 ROM 会抛异常,这里回落去设置页引导用户。
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            }
        } catch (_: Exception) {
        }
        false
    }
}

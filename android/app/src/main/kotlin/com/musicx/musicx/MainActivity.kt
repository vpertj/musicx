package com.musicx.musicx

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Build
import kotlin.system.exitProcess
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * 应用内更新所需的两个原生能力:
 *  - getVersionName:Flutter 侧读不到安卓包版本(Info.plist 那套只适用 macOS),
 *    否则版本号恒为 0.0.0、每次启动都误报「有新版本」。
 *  - installApk:把下载好的 APK 通过 FileProvider 以 content:// 交给系统安装器。
 *    Android 8+ 需要用户在系统提示里授予「安装未知应用」权限。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "musicx/installer"

    /** 版本号变化时由 Flutter 侧调用:重启应用以加载新版本代码。 */
    private fun restartApp() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            finishAffinity()
            Runtime.getRuntime().exit(0)
        } catch (_: Exception) {
        }
    }

    /** 每次回到前台通知 Flutter:用于检测安装完成后自动重启。 */
    override fun onResume() {
        super.onResume()
        try {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, channelName)
                    .invokeMethod("onResume", null)
            }
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionName" -> result.success(versionName())
                    "getVersionCode" -> result.success(versionCode())
                    "apkPackageName" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            if (path.isNullOrEmpty()) null else apkPackageName(path)
                        )
                    }
                    "apkVersionName" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            if (path.isNullOrEmpty()) null else apkVersionName(path)
                        )
                    }
                    "apkVersionCode" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            if (path.isNullOrEmpty()) null else apkVersionCode(path)
                        )
                    }
                    // 是否允许安装未知来源应用(Android 8+ 必需,否则安装静默失败)
                    "canInstallPackages" -> {
                        result.success(canInstallPackages())
                    }
                    // 签名指纹:升级的硬前提,交接前自检用
                    "installedSignatureSha256" -> {
                        result.success(installedSignatureSha256())
                    }
                    "apkSignatureSha256" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            if (path.isNullOrEmpty()) null else apkSignatureSha256(path)
                        )
                    }
                    // 本应用已安装 APK 的路径:用于自检(把自己当作「下载到的包」
                    // 验证签名读取链路),也是排查升级问题的有用信息。
                    "installedApkPath" -> {
                        result.success(installedApkPath())
                    }
                    // 跳到「安装未知应用」授权页
                    "openInstallPermissionSettings" -> {
                        openInstallPermissionSettings()
                        result.success(true)
                    }
                    // 回到前台:Flutter 侧据此检测「应用是否已被新版本替换」
                    "restartApp" -> {
                        restartApp()
                        result.success(true)
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

    /** 是否允许本应用安装 APK(API 26+ 需要用户在设置里单独授权)。 */
    private fun canInstallPackages(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    } catch (_: Exception) {
        true
    }

    /** 打开「安装未知应用」授权页,让用户一步到位授予权限。 */
    private fun openInstallPermissionSettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        } catch (_: Exception) {
        }
    }

    /** 读取 APK 文件的包名(核对「下到的是不是本应用」)。 */
    private fun apkPackageName(path: String): String? = try {
        packageManager.getPackageArchiveInfo(path, 0)?.packageName
    } catch (_: Exception) {
        null
    }

    /** 读取 APK 文件的 versionName(核对「下到的是不是目标版本」)。 */
    private fun apkVersionName(path: String): String? = try {
        val info = packageManager.getPackageArchiveInfo(path, 0)
        info?.versionName
    } catch (_: Exception) {
        null
    }

    /**
     * 已安装应用的签名证书 SHA-256 指纹(小写十六进制)。
     *
     * 为什么必须比对:系统安装器在「签名不一致」时给出的是含糊的失败提示,
     * 用户与应用都无法区分「签名不一致」和「已是最新版本」。签名是升级能否
     * 成功的**硬前提**,必须在交接前自检并给出可读原因。
     */
    private fun installedSignatureSha256(): String? = try {
        @Suppress("DEPRECATION")
        val info: PackageInfo = packageManager.getPackageInfo(
            packageName,
            PackageManager.GET_SIGNATURES,
        )
        info.signatures?.firstOrNull()?.let { sha256OfSignature(it) }
    } catch (_: Exception) {
        null
    }

    /** 读取 APK 文件的签名证书 SHA-256 指纹(小写十六进制)。 */
    private fun apkSignatureSha256(path: String): String? = try {
        @Suppress("DEPRECATION")
        val info: PackageInfo? = packageManager.getPackageArchiveInfo(
            path,
            PackageManager.GET_SIGNATURES,
        )
        info?.signatures?.firstOrNull()?.let { sha256OfSignature(it) }
    } catch (_: Exception) {
        null
    }

    /** 证书字节的 SHA-256,输出小写十六进制(与 apksigner 的 SHA-256 digest 同口径)。 */
    private fun sha256OfSignature(sig: Signature): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    /** 本应用已安装 APK 的绝对路径(applicationInfo.sourceDir)。 */
    private fun installedApkPath(): String? = try {
        packageManager.getApplicationInfo(packageName, 0).sourceDir
    } catch (_: Exception) {
        null
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
        // 关键:启动安装器后**主动退出应用**。
        // 参考成熟应用的做法:安装期间本进程不该继续占着前台与文件句柄,
        // 否则部分 ROM(以及旧进程仍显示旧界面)会让用户以为更新失败。
        // 装完后用户重新打开应用即为新版本。
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                finishAffinity()
            } catch (_: Exception) {
            }
            exitProcess(0)
        }, 900)
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

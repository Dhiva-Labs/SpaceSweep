package com.dhivalabs.space_sweep

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Android storage services for the Flutter side (channel `space_sweep/storage`).
 *
 * Android 6+ reserves clearing other apps' caches for system apps, so cache
 * cleaning here is limited to what a normal app may do: ask the system to trim
 * caches (allocateBytes), launch the Android 11+ "clear app cache" system
 * dialog, and open each app's info page so the user can clear it there.
 */
class StorageChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "space_sweep/storage"
        private const val REQ_CLEAR_CACHE = 7301
        private const val REQ_STORAGE_PERMISSION = 7302
        private const val ICON_SIZE = 96
    }

    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var pendingClear: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    private val pm: PackageManager get() = activity.packageManager
    private val stats: StorageStatsManager
        get() = activity.getSystemService(StorageStatsManager::class.java)
    private val storage: StorageManager
        get() = activity.getSystemService(StorageManager::class.java)

    init {
        MethodChannel(messenger, NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "storageRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "storageInfo" -> background(result) { storageInfo() }
            "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
            "requestAllFilesAccess" -> requestAllFilesAccess(result)
            "hasUsageAccess" -> result.success(hasUsageAccess())
            "openUsageAccessSettings" -> {
                openUsageAccessSettings()
                result.success(null)
            }
            "appCaches" -> background(result) { appCaches() }
            "appIcon" -> {
                val pkg = call.argument<String>("package")!!
                background(result) { appIcon(pkg) }
            }
            "openAppDetails" -> {
                val pkg = call.argument<String>("package")!!
                tryStart(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))
                result.success(null)
            }
            "trimCaches" -> background(result) { trimCaches() }
            "clearExternalAppCaches" -> clearExternalAppCaches(result)
            "clearOwnCache" -> background(result) { clearOwnCache() }
            "mediaScan" -> {
                val paths = call.argument<List<String>>("paths").orEmpty()
                MediaScannerConnection.scanFile(activity, paths.toTypedArray(), null, null)
                result.success(null)
            }
            "apkInfo" -> {
                val paths = call.argument<List<String>>("paths").orEmpty()
                background(result) { apkInfo(paths) }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQ_CLEAR_CACHE) return false
        val outcome = when (resultCode) {
            Activity.RESULT_OK -> "cleared"
            Activity.RESULT_CANCELED -> "cancelled"
            else -> "failed"
        }
        pendingClear?.success(outcome)
        pendingClear = null
        return true
    }

    fun onPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQ_STORAGE_PERMISSION) return false
        pendingPermission?.success(null)
        pendingPermission = null
        return true
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun tryStart(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    /** Space actually free right now; excludes cache the system could clear. */
    private fun freeBytes(): Long = StatFs(Environment.getDataDirectory().path).availableBytes

    private fun storageInfo(): Map<String, Any?> {
        val uuid = StorageManager.UUID_DEFAULT
        val info = mutableMapOf<String, Any?>(
            "total" to stats.getTotalBytes(uuid),
            "free" to freeBytes(),
        )
        if (hasUsageAccess()) {
            try {
                val media = stats.queryExternalStatsForUser(uuid, Process.myUserHandle())
                info["images"] = media.imageBytes
                info["video"] = media.videoBytes
                info["audio"] = media.audioBytes
            } catch (_: Exception) {
                // Media totals are a nice-to-have.
            }
        }
        return info
    }

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val forThisApp = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${activity.packageName}"),
            )
            if (!tryStart(forThisApp)) tryStart(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            result.success(null)
            return
        }
        pendingPermission?.success(null)
        pendingPermission = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            REQ_STORAGE_PERMISSION,
        )
    }

    private fun hasUsageAccess(): Boolean {
        val ops = activity.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), activity.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), activity.packageName)
        }
        return if (mode == AppOpsManager.MODE_DEFAULT) {
            activity.checkSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    }

    private fun openUsageAccessSettings() {
        val forThisApp = Intent(
            Settings.ACTION_USAGE_ACCESS_SETTINGS,
            Uri.parse("package:${activity.packageName}"),
        )
        if (!tryStart(forThisApp)) tryStart(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }

    @Suppress("DEPRECATION")
    private fun installedApps(): List<ApplicationInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            pm.getInstalledApplications(0)
        }

    private fun appCaches(): List<Map<String, Any>> {
        val user = Process.myUserHandle()
        return installedApps().mapNotNull { app ->
            try {
                val s = stats.queryStatsForPackage(app.storageUuid, app.packageName, user)
                mapOf(
                    "package" to app.packageName,
                    "label" to app.loadLabel(pm).toString(),
                    "cache" to s.cacheBytes,
                    "data" to s.dataBytes,
                    "app" to s.appBytes,
                    "system" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun appIcon(pkg: String): ByteArray? = try {
        val drawable = pm.getApplicationIcon(pkg)
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(Canvas(bitmap))
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /**
     * Requests every byte the system is willing to hand out, which makes it
     * delete other apps' cached files beyond its cache reserve.
     */
    private fun trimCaches(): Map<String, Any?> {
        val uuid = StorageManager.UUID_DEFAULT
        val before = freeBytes()
        var error: String? = null
        try {
            storage.allocateBytes(uuid, storage.getAllocatableBytes(uuid))
        } catch (e: IOException) {
            error = e.message ?: "Android declined the request"
        }
        return mapOf("freed" to maxOf(0L, freeBytes() - before), "error" to error)
    }

    private fun clearExternalAppCaches(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success("unsupported")
            return
        }
        if (!Environment.isExternalStorageManager()) {
            result.success("failed")
            return
        }
        pendingClear?.success("cancelled")
        pendingClear = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(Intent(StorageManager.ACTION_CLEAR_APP_CACHE), REQ_CLEAR_CACHE)
        } catch (_: ActivityNotFoundException) {
            pendingClear = null
            result.success("unsupported")
        }
    }

    private fun clearOwnCache(): Long {
        var freed = 0L
        for (dir in listOfNotNull(activity.cacheDir, activity.externalCacheDir)) {
            dir.listFiles()?.forEach { child ->
                val size = child.walkTopDown().filter(File::isFile).sumOf(File::length)
                if (child.deleteRecursively()) freed += size
            }
        }
        return freed
    }

    private fun apkInfo(paths: List<String>): Map<String, Map<String, Any?>> {
        val out = mutableMapOf<String, Map<String, Any?>>()
        for (path in paths) {
            if (!path.endsWith(".apk", ignoreCase = true)) continue
            val info = archiveInfo(path) ?: continue
            val app = info.applicationInfo ?: continue
            app.sourceDir = path
            app.publicSourceDir = path
            out[path] = mapOf(
                "package" to info.packageName,
                "label" to app.loadLabel(pm).toString(),
                "versionName" to info.versionName,
                "versionCode" to versionCode(info),
                "installedVersionCode" to installedVersion(info.packageName),
            )
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun archiveInfo(path: String): PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(0))
        } else {
            pm.getPackageArchiveInfo(path, 0)
        }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun installedVersion(pkg: String): Long? = try {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            pm.getPackageInfo(pkg, 0)
        }
        versionCode(info)
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }
}

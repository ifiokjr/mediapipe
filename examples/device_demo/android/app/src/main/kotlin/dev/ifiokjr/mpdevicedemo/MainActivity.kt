package dev.ifiokjr.mpdevicedemo

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Requests the camera permission the demo needs before starting its image stream.
 *
 * The `camera` plugin surfaces a permission denial as an initialization failure,
 * which is hard to distinguish from a hardware problem. A two-line channel keeps
 * the demo dependency-free and reports the outcome explicitly.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                when (call.method) {
                    "ensureCameraPermission" -> ensureCameraPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureCameraPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)

            return
        }

        if (pendingResult != null) {
            result.success(false)

            return
        }

        pendingResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_CAMERA) return
        val result = pendingResult ?: return
        pendingResult = null
        result.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    private companion object {
        const val CHANNEL = "dev.ifiokjr.mp_device_demo/permissions"
        const val REQUEST_CAMERA = 9101
    }
}

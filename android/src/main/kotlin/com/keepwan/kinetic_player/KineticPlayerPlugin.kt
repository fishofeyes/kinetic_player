package com.keepwan.kinetic_player

import android.app.Activity
import android.content.res.Configuration
import android.os.Build
import com.keepwan.kinetic_player.gsy.GsyPlatformViewRegistry
import com.keepwan.kinetic_player.gsy.GsyPlayerDefaults
import com.keepwan.kinetic_player.gsy.GsyPlayerLifecycleRegistry
import com.keepwan.kinetic_player.gsy.GsyVideoViewFactory
import com.keepwan.kinetic_player.gsy.GsyVideoSessions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class KineticPlayerPlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null
    private var sessions: GsyVideoSessions? = null
    private var controllerChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        GsyPlayerDefaults.applyPluginDefaults()
        val messenger = binding.binaryMessenger
        GsyPlatformViewRegistry.attach(messenger)
        val registry = GsyVideoSessions(messenger)
        sessions = registry
        controllerChannel = MethodChannel(messenger, "com.example.player/gsy").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "create" -> {
                            val context = activity ?: binding.applicationContext
                            @Suppress("UNCHECKED_CAST")
                            val params = call.arguments as? Map<String, Any?> ?: emptyMap()
                            result.success(mapOf("viewId" to registry.create(context, params)))
                        }
                        "reset" -> {
                            registry.dispose()
                            result.success(null)
                        }
                        "destroy" -> {
                            registry.destroy(call.argument<Number>("viewId")?.toInt() ?: 0)
                            result.success(null)
                        }
                        "resolveAsset" -> {
                            val asset = call.argument<String>("asset") ?: ""
                            val pkg = call.argument<String>("package")
                            val key = if (pkg == null) {
                                binding.flutterAssets.getAssetFilePathByName(asset)
                            } else {
                                binding.flutterAssets.getAssetFilePathByName(asset, pkg)
                            }
                            // IJK's RawDataSourceProvider expects the complete asset key
                            // in one URI path segment (including nested Flutter paths).
                            result.success("assets:///${android.net.Uri.encode(key)}")
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("KineticPlayer", error.message, null)
                }
            }
        }
        binding.platformViewRegistry.registerViewFactory(
            PlayerConstants.GSY_VIEW_TYPE,
            GsyVideoViewFactory(registry),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        controllerChannel?.setMethodCallHandler(null)
        controllerChannel = null
        sessions?.dispose()
        sessions = null
        activity = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    companion object {
        /** Forward from host Activity.onConfigurationChanged for GSY orientation fullscreen. */
        @JvmStatic
        fun handleConfigurationChanged(
            activity: Activity,
            newConfig: Configuration,
        ) {
            GsyPlayerLifecycleRegistry.onConfigurationChanged(activity, newConfig)
        }

        /** Forward from host Activity.onBackPressed for GSY window fullscreen exit. */
        @JvmStatic
        fun handleBackPressed(activity: Activity): Boolean =
            GsyPlayerLifecycleRegistry.onBackPressed(activity)

        /** Forward from host Activity.onUserLeaveHint for automatic PiP (Android 8+). */
        @JvmStatic
        fun handleUserLeaveHint(activity: Activity) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            GsyPlayerLifecycleRegistry.onUserLeaveHint(activity)
        }
    }
}

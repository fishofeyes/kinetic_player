package com.keepwan.kinetic_player.gsy

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class GsyVideoViewFactory(private val sessions: GsyVideoSessions) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val sessionId = (params?.get("sessionId") as? Number)?.toInt()
        if (sessionId != null) return sessions.attach(context, sessionId)
        return GsyVideoPlatformView(
            context,
            viewId,
            GsyPlatformViewRegistry.messenger,
            params,
        )
    }
}

object GsyPlatformViewRegistry {
    lateinit var messenger: io.flutter.plugin.common.BinaryMessenger
        private set

    fun attach(messenger: io.flutter.plugin.common.BinaryMessenger) {
        this.messenger = messenger
    }
}

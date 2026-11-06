package com.keepwan.kinetic_player.gsy

import android.content.Context
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView

/** Controller lifetime is independent of the platform view lifetime. */
class GsyVideoSessions(private val messenger: BinaryMessenger) {
    private val players = mutableMapOf<Int, GsyVideoPlatformView>()
    private var nextId = 1_000_000_000

    fun create(context: Context, params: Map<String, Any?>): Int {
        val id = nextId++
        players[id] = GsyVideoPlatformView(
            context, id, messenger, params + ("controllerOwned" to true),
        )
        return id
    }

    fun attach(context: Context, id: Int): PlatformView {
        return GsyVideoAttachment(context, players[id])
    }

    fun destroy(id: Int) {
        players.remove(id)?.dispose()
    }

    fun dispose() {
        val current = players.values.toList()
        players.clear()
        current.forEach { it.dispose() }
    }
}

private class GsyVideoAttachment(context: Context, player: GsyVideoPlatformView?) : PlatformView {
    private val container = FrameLayout(context)
    private val surface = player?.view

    init {
        if (surface != null) {
            (surface.parent as? ViewGroup)?.removeView(surface)
            container.addView(surface, FrameLayout.LayoutParams(-1, -1))
        }
    }

    override fun getView() = container

    override fun dispose() {
        // An old attachment may be removed after a new one has mounted.
        if (surface?.parent === container) container.removeView(surface)
    }
}

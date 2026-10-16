package com.keepwan.kinetic_player.gsy

import com.shuyu.gsyvideoplayer.GSYVideoManager
import com.shuyu.gsyvideoplayer.model.VideoOptionModel
import com.shuyu.gsyvideoplayer.player.IjkPlayerManager
import com.shuyu.gsyvideoplayer.player.PlayerFactory
import tv.danmaku.ijk.media.exo2.ExoSourceManager
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/** Global GSY defaults applied when the Flutter plugin attaches. */
object GsyPlayerDefaults {
    /** GSY prepare watchdog (default in GSY is 8s — too short for large remote MKV). */
    private const val PREPARE_TIMEOUT_MS = 60_000

    /** Exo / Media3 HTTP timeouts for large progressive downloads. */
    private const val EXO_HTTP_TIMEOUT_MS = 60_000

    /** IJK FFmpeg format timeouts (microseconds). */
    private const val IJK_TIMEOUT_US = 60_000_000

    fun applyPluginDefaults(ijkEnableAccurateSeek: Boolean = true) {
        PlayerFactory.setPlayManager(IjkPlayerManager::class.java)
        GSYVideoManager.instance().setTimeOut(PREPARE_TIMEOUT_MS, true)
        ExoSourceManager.setHttpConnectTimeout(EXO_HTTP_TIMEOUT_MS)
        ExoSourceManager.setHttpReadTimeout(EXO_HTTP_TIMEOUT_MS)
        applyIjkOptions(ijkEnableAccurateSeek)
    }

    /** IJK-only FFmpeg options; ignored by Exo / System cores. */
    fun applyIjkOptions(enableAccurateSeek: Boolean) {
        val options =
            mutableListOf(
                // GSY 14 software time stretching supports 0.25x–4x across devices.
                VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "soundtouch", 1),
                // Network / demuxer timeouts for large remote progressive files.
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_FORMAT,
                    "timeout",
                    IJK_TIMEOUT_US,
                ),
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_FORMAT,
                    "connect_timeout",
                    IJK_TIMEOUT_US,
                ),
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_FORMAT,
                    "rw_timeout",
                    IJK_TIMEOUT_US,
                ),
                // Help probe complex MKV (HEVC 10-bit + multi-track) over HTTP.
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_FORMAT,
                    "analyzeduration",
                    100_000_000,
                ),
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_FORMAT,
                    "probesize",
                    10 * 1024 * 1024,
                ),
            )
        if (enableAccurateSeek) {
            options.add(
                VideoOptionModel(
                    IjkMediaPlayer.OPT_CATEGORY_PLAYER,
                    "enable-accurate-seek",
                    1,
                ),
            )
        }
        GSYVideoManager.instance().setOptionModelList(options)
    }
}

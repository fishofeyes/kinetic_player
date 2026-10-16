package com.keepwan.kinetic_player.gsy

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.View
import android.widget.FrameLayout
import kotlin.math.roundToInt
import com.keepwan.kinetic_player.CommonPlayerState
import com.keepwan.kinetic_player.ThrottledProgressReporter
import com.shuyu.gsyvideoplayer.GSYVideoManager
import com.shuyu.gsyvideoplayer.builder.GSYVideoOptionBuilder
import com.shuyu.gsyvideoplayer.listener.GSYSampleCallBack
import com.shuyu.gsyvideoplayer.listener.GSYVideoGifSaveListener
import com.shuyu.gsyvideoplayer.listener.GSYVideoShotListener
import com.shuyu.gsyvideoplayer.listener.GSYVideoShotSaveListener
import com.shuyu.gsyvideoplayer.player.IjkPlayerManager
import com.shuyu.gsyvideoplayer.player.PlayerFactory
import com.shuyu.gsyvideoplayer.player.SystemPlayerManager
import com.shuyu.gsyvideoplayer.utils.CommonUtil
import com.shuyu.gsyvideoplayer.utils.GSYVideoType
import com.shuyu.gsyvideoplayer.utils.GifCreateHelper
import tv.danmaku.ijk.media.exo2.Exo2PlayerManager
import com.shuyu.gsyvideoplayer.video.base.GSYVideoView
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

interface GsyPlayerCallbacks {
    fun onPlayerStateChanged(state: CommonPlayerState)
    fun onPositionChanged(positionMs: Long, durationMs: Long)
    fun onScreenshotCaptured(bytes: ByteArray?)
}

class GsyNativePlayer(
    context: Context,
    private val callbacks: GsyPlayerCallbacks,
    initialUiConfig: GsyUiConfig = GsyUiConfig(),
    private val playTag: String = "kinetic_${UUID.randomUUID()}",
) {
    private val appContext = context.applicationContext
    private val container = FrameLayout(context)
    private val playerView = KineticPreViewGSYVideoPlayer(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cacheDir = File(appContext.cacheDir, "kinetic_player").apply { mkdirs() }

    private var uiConfig = initialUiConfig
    private var midRollQueue = mutableListOf<MidRollAd>()
    private var isPlaying = false
    private var currentUrl: String? = null
    private var playlist: List<String> = emptyList()
    private var playlistIndex = 0
    private var pendingContentUrl: String? = null
    private var pendingContentPositionMs: Long = 0L
    private var adMode = AdMode.NONE
    private var adSkipAfterMs = 5_000L
    private var gifHelper: GifCreateHelper? = null
    private var gifResultCallback: ((String?) -> Unit)? = null
    private var renderRotation = 0
    private var mirrorHorizontal = false
    private var mirrorVertical = false
    private var effectFilterName = "none"
    private var subtitleUrl: String? = null
    private var subtitleMime: String? = null
    private var subtitleEnabled = true
    private var activeRenderType: Int? = null
    private var savedVolume = 1f
    private var muted = false
    /** When true and playlist has next item, auto-advance on complete. */
    private var autoPlayNext = true
    private var httpUserAgent: String? = null
    private var httpHeaders: Map<String, String> = emptyMap()

    private data class MidRollAd(
        val atMs: Long,
        val adUrl: String,
        val contentUrl: String?,
    )

    private enum class AdMode {
        NONE,
        PRE_ROLL,
        MID_ROLL,
    }

    private val progressReporter = ThrottledProgressReporter { positionMs, durationMs ->
        callbacks.onPositionChanged(positionMs, durationMs)
    }

    private val progressRunnable =
        object : Runnable {
            override fun run() {
                if (isPlaying) {
                    reportProgress()
                }
                mainHandler.postDelayed(this, 250L)
            }
        }

    private val videoCallback =
        object : GSYSampleCallBack() {
            override fun onPlayError(url: String?, vararg objects: Any?) {
                isPlaying = false
                callbacks.onPlayerStateChanged(CommonPlayerState.ERROR)
            }

            override fun onAutoComplete(url: String?, vararg objects: Any?) {
                isPlaying = false
                when {
                    adMode != AdMode.NONE && pendingContentUrl != null -> {
                        finishAdAndResumeContent()
                    }
                    autoPlayNext && playlist.size > 1 && playlistIndex < playlist.lastIndex -> {
                        playlistIndex++
                        setUrl(playlist[playlistIndex])
                        startPlayLogic()
                    }
                    else -> {
                        activePlayer().getOverlayDanmaku()?.onPlaybackComplete()
                        callbacks.onPlayerStateChanged(CommonPlayerState.COMPLETED)
                        reportProgress(force = true)
                    }
                }
            }

            override fun onPrepared(url: String?, vararg objects: Any?) {
                callbacks.onPlayerStateChanged(CommonPlayerState.READY)
                applyRenderTransform()
                applySavedVolume()
                playerView.fixControlOverlayLayering()
                activePlayer().getOverlayDanmaku()?.onPrepared()
                if (adMode != AdMode.NONE) {
                    activePlayer().showAdChrome(adSkipAfterMs) { skipAd() }
                } else {
                    activePlayer().hideAdChrome()
                }
                reportProgress(force = true)
                syncPictureInPictureParams()
                playerView.refreshQualityToolbar()
                activePlayer().refreshQualityToolbar()
            }
        }

    init {
        playerView.uiConfig = initialUiConfig
        playerView.onDanmakuPlaybackStart = {
            activePlayer().getOverlayDanmaku()?.onPlaybackStart()
            applySavedVolume()
            onPlaybackStarted()
        }
        playerView.onDanmakuPlaybackPause = {
            activePlayer().getOverlayDanmaku()?.onPause()
            onPlaybackPaused()
        }
        playerView.onDanmakuPlaybackComplete = {
            activePlayer().getOverlayDanmaku()?.onPlaybackComplete()
            onPlaybackPaused()
        }
        container.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        playerView.onVolumeChanged = { setVolume(it) }
        playerView.onMuteToggle = { setMute(it) }
        playerView.onRequestAudioTracks = { listAudioTracks() }
        playerView.onAudioTrackSelected = { selectAudioTrack(it) }
        playerView.onRequestVideoTracks = { listExoVideoTracks() }
        playerView.onVideoTrackSelected = { selectExoVideoTrack(it) }
        playerView.onMirrorHorizontalChanged = { setMirrorHorizontal(it) }
        playerView.onLoopingChanged = {
            uiConfig = uiConfig.copy(looping = it)
            setLooping(it)
        }
        playerView.onStartAfterPreparedChanged = {
            uiConfig = uiConfig.copy(startAfterPrepared = it)
        }
        playerView.onAutoPlayNextChanged = { autoPlayNext = it }
        playerView.onShowTypeChanged = { setGsyShowType(it) }
        playerView.onSubtitleEnabledChanged = { setSubtitleEnabled(it) }
        playerView.onDanmakuVisibleChanged = { toggleDanmaku(it) }
        playerView.onDanmakuSend = { /* live danmaku already drawn; optional host hook */ }
        playerView.onCaptureScreenshot = { callback ->
            takeScreenshot(withView = false, high = true) { bytes ->
                callback(bytes)
                callbacks.onScreenshotCaptured(bytes)
            }
        }
        playerView.onStartGifRecording = { startGifRecording() }
        playerView.onStopGifRecording = { callback -> stopGifRecording(callback) }
        playerView.isGifRecording = { isGifRecording() }
        playerView.syncVolumeToolbar(savedVolume, muted)
        mainHandler.post(progressRunnable)
        GsyPlayerDefaults.applyIjkOptions(initialUiConfig.ijkEnableAccurateSeek)
        GsyPlayerLifecycleRegistry.register(this)
    }

    fun getView(): View = container

    fun onConfigurationChanged(
        activity: Activity,
        newConfig: Configuration,
    ) {
        playerView.dispatchConfigurationChanged(activity, newConfig)
    }

    fun applyUiConfig(config: GsyUiConfig) {
        uiConfig = config
        playerView.uiConfig = config
        GsyPlayerDefaults.applyIjkOptions(config.ijkEnableAccurateSeek)
        config.previewVttUrl?.let { playerView.setPreviewVttUrl(it) }
        currentUrl?.let { setUrl(it) }
        syncPictureInPictureParams()
    }

    fun applyChromeLocale(strings: Map<String, String>) {
        playerView.applyChromeLocale(strings)
    }

    fun setKeepLastFrameWhenComplete(enabled: Boolean) {
        uiConfig = uiConfig.copy(keepLastFrameWhenComplete = enabled)
        playerView.setKeepLastFrameWhenComplete(enabled)
    }

    fun setCoverUrl(url: String?) {
        uiConfig = uiConfig.copy(coverUrl = url)
        playerView.setCoverUrl(url)
    }

    fun setPreviewVttUrl(url: String?) {
        uiConfig = uiConfig.copy(previewVttUrl = url)
        playerView.setPreviewVttUrl(url)
    }

    fun startFullscreen() = playerView.toggleWindowFullscreen()

    fun setSpeed(speed: Float) {
        uiConfig = uiConfig.copy(speed = speed)
        activePlayer().setSpeedPlaying(speed, true)
    }

    fun setLooping(looping: Boolean) {
        uiConfig = uiConfig.copy(looping = looping)
        playerView.isLooping = looping
    }

    fun setUrl(videoUrl: String) {
        currentUrl = videoUrl
        buildVideoOptions()
            .setUrl(videoUrl)
            .setPlayTag(playTag)
            .build(playerView)
        uiConfig.previewVttUrl?.let { playerView.setPreviewVttUrl(it) }
        callbacks.onPlayerStateChanged(CommonPlayerState.IDLE)
    }

    fun setPlaylist(urls: List<String>, startIndex: Int = 0) {
        playlist = urls
        playlistIndex = startIndex.coerceIn(0, (urls.size - 1).coerceAtLeast(0))
        if (urls.isNotEmpty()) {
            setUrl(urls[playlistIndex])
        }
    }

    fun playNextInPlaylist(): Boolean {
        if (playlistIndex >= playlist.lastIndex) return false
        playlistIndex++
        setUrl(playlist[playlistIndex])
        startPlayLogic()
        return true
    }

    fun playWithPreRollAd(
        adUrl: String,
        contentUrl: String,
        skipAfterMs: Long = 5_000L,
    ) {
        if (adUrl.isEmpty() || contentUrl.isEmpty()) return
        adMode = AdMode.PRE_ROLL
        adSkipAfterMs = skipAfterMs.coerceAtLeast(0L)
        pendingContentUrl = contentUrl
        pendingContentPositionMs = 0L
        setUrl(adUrl)
        startPlayLogic()
        activePlayer().showAdChrome(adSkipAfterMs) { skipAd() }
    }

    fun skipAd() {
        if (adMode == AdMode.NONE) return
        finishAdAndResumeContent()
    }

    private fun finishAdAndResumeContent() {
        val content = pendingContentUrl ?: return
        val resumeAt = pendingContentPositionMs
        pendingContentUrl = null
        pendingContentPositionMs = 0L
        adMode = AdMode.NONE
        activePlayer().hideAdChrome()
        playerView.hideAdChrome()
        setUrl(content)
        startPlayLogic()
        if (resumeAt > 0) {
            mainHandler.postDelayed({
                seekTo(resumeAt.toInt())
            }, 400L)
        }
    }

    fun setPurePlayMode(enabled: Boolean) {
        applyUiConfig(
            uiConfig.copy(
                enableNativeControls = !enabled,
                enableNativeControlsFullscreen = !enabled,
                showFullscreenButton = !enabled,
                showLockButton = !enabled,
                showVolumeToolbar = !enabled,
                showSettingsButton = !enabled,
                videoTitle = if (enabled) "" else uiConfig.videoTitle,
            ),
        )
    }

    private fun buildVideoOptions(): GSYVideoOptionBuilder {
        val builder =
            GSYVideoOptionBuilder()
                .setVideoTitle(uiConfig.videoTitle)
                .setIsTouchWiget(uiConfig.enableNativeControls)
                .setIsTouchWigetFull(uiConfig.enableNativeControlsFullscreen)
                .setRotateViewAuto(uiConfig.rotateViewAuto)
                .setRotateWithSystem(uiConfig.rotateWithSystem)
                .setLockLand(uiConfig.lockLand)
                .setNeedOrientationUtils(uiConfig.needOrientationUtils)
                .setShowFullAnimation(uiConfig.showFullAnimation)
                .setHideKey(uiConfig.hideVirtualKey)
                .setShowPauseCover(uiConfig.showPauseCover)
                .setNeedShowWifiTip(uiConfig.needShowWifiTip)
                .setSurfaceErrorPlay(uiConfig.surfaceErrorPlay)
                .setReleaseWhenLossAudio(uiConfig.releaseWhenLossAudio)
                .setShowDragProgressTextOnSeekBar(uiConfig.showDragProgressTextOnSeekBar)
                .setDismissControlTime(uiConfig.dismissControlTime)
                .setSeekRatio(uiConfig.seekRatio)
                .setSpeed(uiConfig.speed)
                .setSoundTouch(true)
                .setLooping(uiConfig.looping)
                .setAutoFullWithSize(uiConfig.autoFullWithSize)
                .setNeedLockFull(uiConfig.showLockButton)
                .setCacheWithPlay(uiConfig.cacheWithPlay)
                .setStartAfterPrepared(uiConfig.startAfterPrepared)
                .setVideoAllCallBack(videoCallback)
        if (uiConfig.seekOnStartMs >= 0) {
            builder.setSeekOnStart(uiConfig.seekOnStartMs)
        }
        val headData = linkedMapOf<String, String>()
        headData.putAll(httpHeaders)
        val ua = httpUserAgent
        if (!ua.isNullOrEmpty()) {
            headData["User-Agent"] = ua
        }
        if (headData.isNotEmpty()) {
            builder.setMapHeadData(headData)
        }
        return builder
    }

    fun setHttpRequestOptions(userAgent: String?, headers: Map<String, String>?) {
        httpUserAgent = userAgent?.takeIf { it.isNotEmpty() }
        httpHeaders = headers?.filterKeys { it.isNotEmpty() } ?: emptyMap()
    }

    fun startPlayLogic() {
        if (playerView.currentState == GSYVideoView.CURRENT_STATE_AUTO_COMPLETE) {
            GSYVideoManager.instance().seekTo(0)
        }
        playerView.startPlayLogic()
        onPlaybackStarted()
        applySavedVolume()
        emitMappedState(GSYVideoView.CURRENT_STATE_PLAYING)
        reportProgress(force = true)
    }

    fun onVideoPause() {
        playerView.onVideoPause()
        onPlaybackPaused()
        emitMappedState(GSYVideoView.CURRENT_STATE_PAUSE)
    }

    fun stop() {
        isPlaying = false
        adMode = AdMode.NONE
        pendingContentUrl = null
        activePlayer().hideAdChrome()
        playerView.onVideoReset()
        activePlayer().getOverlayDanmaku()?.onPlaybackComplete()
        callbacks.onPlayerStateChanged(CommonPlayerState.IDLE)
        reportProgress(force = true)
        syncPictureInPictureParams()
    }

    fun setVolume(volume: Float) {
        val clamped = volume.coerceIn(0f, 1f)
        if (clamped > 0f && muted) {
            muted = false
        }
        savedVolume = clamped
        applySavedVolume()
    }

    fun setMute(muted: Boolean) {
        this.muted = muted
        applySavedVolume()
    }

    private fun applySavedVolume() {
        val manager = GSYVideoManager.instance().curPlayerManager
        if (muted) {
            manager?.setNeedMute(true)
        } else {
            manager?.setNeedMute(false)
            manager?.setVolume(savedVolume, savedVolume)
        }
        playerView.syncVolumeToolbar(savedVolume, muted)
    }

    fun switchVideoSource(
        url: String,
        autoPlay: Boolean,
    ) {
        val idx = playlist.indexOf(url)
        if (idx >= 0) {
            playlistIndex = idx
        }
        setUrl(url)
        if (autoPlay) {
            startPlayLogic()
        }
    }

    fun getVideoSize(): Map<String, Int>? {
        val width = GSYVideoManager.instance().currentVideoWidth
        val height = GSYVideoManager.instance().currentVideoHeight
        if (width <= 0 || height <= 0) return null
        return mapOf("width" to width, "height" to height)
    }

    fun listAudioTracks(): List<Map<String, Any?>> =
        GsyAudioTrackHelper.listAudioTracks().map {
            mapOf(
                "index" to it.index,
                "label" to it.label,
                "language" to it.language,
                "selected" to it.selected,
            )
        }

    fun selectAudioTrack(index: Int): Boolean = GsyAudioTrackHelper.selectAudioTrack(index)

    fun seekTo(positionMs: Int) {
        GSYVideoManager.instance().seekTo(positionMs.toLong())
        activePlayer().getOverlayDanmaku()?.onSeek(positionMs.toLong())
        reportProgress(force = true)
    }

    /** CommonScaleMode: 0=fit, 1=fill, 2=stretch */
    fun setScaleMode(commonMode: Int) {
        val gsyMode =
            when (commonMode) {
                0 -> GSYVideoType.SCREEN_TYPE_DEFAULT
                1 -> GSYVideoType.SCREEN_TYPE_FULL
                2 -> GSYVideoType.SCREEN_MATCH_FULL
                else -> GSYVideoType.SCREEN_TYPE_DEFAULT
            }
        GSYVideoType.setShowType(gsyMode)
    }

    fun setGsyShowType(mode: Int) {
        GSYVideoType.setShowType(GsyScaleModeMapper.toGsyShowType(mode))
    }

    fun setRenderType(renderType: Int) {
        if (activeRenderType == renderType) return
        activeRenderType = renderType
        GSYVideoType.setRenderType(renderType)
        currentUrl?.let { setUrl(it) }
        scheduleControlOverlayFix()
    }

    fun setEffectFilter(name: String) {
        effectFilterName = name
        playerView.setOverlayEffectName(name)
        activePlayer().setOverlayEffectName(name)
        scheduleControlOverlayFix()
    }

    private fun scheduleControlOverlayFix() {
        playerView.post { playerView.fixControlOverlayLayering() }
        playerView.postDelayed({ playerView.fixControlOverlayLayering() }, 100)
        playerView.postDelayed({ playerView.fixControlOverlayLayering() }, 400)
    }

    fun setRenderRotation(degrees: Int) {
        renderRotation = ((degrees % 360) + 360) % 360
        applyRenderTransform()
    }

    fun setMirrorHorizontal(enabled: Boolean) {
        mirrorHorizontal = enabled
        applyRenderTransform()
    }

    fun setMirrorVertical(enabled: Boolean) {
        mirrorVertical = enabled
        applyRenderTransform()
    }

    private fun applyRenderTransform() {
        playerView.setOverlayRenderTransform(renderRotation, mirrorHorizontal, mirrorVertical)
        activePlayer().setOverlayRenderTransform(renderRotation, mirrorHorizontal, mirrorVertical)
    }

    fun getNetSpeedBytesPerSecond(): Long = playerView.getNetSpeed()

    fun getNetSpeedText(): String = playerView.getNetSpeedText()

    fun changeRenderCore(core: Int): Boolean =
        when (core) {
            0 -> {
                PlayerFactory.setPlayManager(IjkPlayerManager::class.java)
                GSYVideoManager.instance().releaseMediaPlayer()
                true
            }
            1 -> {
                PlayerFactory.setPlayManager(Exo2PlayerManager::class.java)
                GSYVideoManager.instance().releaseMediaPlayer()
                true
            }
            2 -> {
                PlayerFactory.setPlayManager(SystemPlayerManager::class.java)
                GSYVideoManager.instance().releaseMediaPlayer()
                true
            }
            else -> false
        }

    fun setSubtitleUrl(
        url: String,
        mimeType: String?,
    ) {
        subtitleUrl = url
        subtitleMime = mimeType
        subtitleEnabled = true
        playerView.setOverlaySubtitle(url, mimeType, true)
        activePlayer().setOverlaySubtitle(url, mimeType, true)
    }

    fun setSubtitleEnabled(enabled: Boolean) {
        subtitleEnabled = enabled
        playerView.setOverlaySubtitle(subtitleUrl, subtitleMime, enabled)
        activePlayer().setOverlaySubtitle(subtitleUrl, subtitleMime, enabled)
    }

    fun setEmbeddedSubtitleText(text: String?) {
        if (text.isNullOrEmpty()) {
            activePlayer().clearSubtitleTextFromPlayer()
            playerView.clearSubtitleTextFromPlayer()
        } else {
            activePlayer().setSubtitleTextFromPlayer(text)
            playerView.setSubtitleTextFromPlayer(text)
        }
    }

    fun takeScreenshot(
        withView: Boolean,
        high: Boolean,
        callback: (ByteArray?) -> Unit,
    ) {
        val target = activePlayer()
        val listener =
            object : GSYVideoShotListener {
                override fun getBitmap(bitmap: Bitmap?) {
                    if (bitmap == null) {
                        mainHandler.post { callback(null) }
                        return
                    }
                    try {
                        val stream = ByteArrayOutputStream()
                        val ok = bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        mainHandler.post { callback(if (ok) stream.toByteArray() else null) }
                    } catch (_: Exception) {
                        mainHandler.post { callback(null) }
                    }
                }
            }
        if (withView) {
            target.taskShotPicWithView(listener, high)
        } else {
            target.taskShotPic(listener, high)
        }
    }

    fun saveScreenshot(
        withView: Boolean,
        high: Boolean,
        callback: (String?) -> Unit,
    ) {
        val target = activePlayer()
        val output = File(cacheDir, "frame_${System.currentTimeMillis()}.png")
        val listener =
            GSYVideoShotSaveListener { success, _ ->
                mainHandler.post {
                    callback(if (success) output.absolutePath else null)
                }
            }
        if (withView) {
            target.saveFrameWithView(output, high, listener)
        } else {
            target.saveFrame(output, high, listener)
        }
    }

    fun isGifRecording(): Boolean = gifHelper != null

    fun startGifRecording() {
        stopGifRecordingInternal(save = false)
        val target = activePlayer()
        gifHelper =
            GifCreateHelper(
                target,
                object : GSYVideoGifSaveListener {
                    override fun process(
                        curPosition: Int,
                        total: Int,
                    ) = Unit

                    override fun result(
                        success: Boolean,
                        file: File?,
                    ) {
                        mainHandler.post {
                            gifResultCallback?.invoke(if (success) file?.absolutePath else null)
                            gifResultCallback = null
                        }
                    }
                },
            )
        gifHelper?.startGif(File(cacheDir, "gif_tmp"))
    }

    fun stopGifRecording(callback: (String?) -> Unit) {
        val helper = gifHelper
        if (helper == null) {
            callback(null)
            return
        }
        gifResultCallback = callback
        helper.stopGif(File(cacheDir, "video_${System.currentTimeMillis()}.gif"))
        gifHelper = null
    }

    private fun stopGifRecordingInternal(save: Boolean) {
        gifHelper?.cancelTask()
        if (!save) {
            gifHelper = null
        }
    }

    fun toggleDanmaku(enabled: Boolean) {
        playerView.setOverlayDanmakuVisible(enabled)
        activePlayer().setOverlayDanmakuVisible(enabled)
    }

    fun setDanmakuUrl(url: String?) {
        playerView.setOverlayDanmakuUrl(url)
        if (activePlayer() !== playerView) {
            activePlayer().setOverlayDanmakuUrl(url)
        }
    }

    fun setMidRollAds(ads: List<Map<String, Any>>) {
        midRollQueue.clear()
        for (ad in ads) {
            val atMs =
                (ad["positionMs"] as? Number)?.toLong()
                    ?: (ad["atMs"] as? Number)?.toLong()
                    ?: continue
            val url =
                ad["adUrl"] as? String
                    ?: ad["url"] as? String
                    ?: continue
            val contentUrl = ad["contentUrl"] as? String
            midRollQueue.add(MidRollAd(atMs = atMs, adUrl = url, contentUrl = contentUrl))
        }
        midRollQueue.sortBy { it.atMs }
    }

    fun listExoVideoTracks(): List<Map<String, Any>> =
        GsyExoTrackHelper.listVideoTracks().map {
            mapOf(
                "index" to it.index,
                "label" to it.label,
                "width" to it.width,
                "height" to it.height,
                "bitrate" to it.bitrate,
                "selected" to it.selected,
            )
        }

    fun selectExoVideoTrack(index: Int): Boolean = GsyExoTrackHelper.selectVideoTrack(index)

    fun setWatermarkUrl(url: String?) {
        playerView.setOverlayWatermarkUrl(url)
        activePlayer().setOverlayWatermarkUrl(url)
    }

    /** Prefer the window-fullscreen clone when present so overlays / GIF / shots follow it. */
    private fun activePlayer(): KineticGSYVideoPlayer {
        val full =
            runCatching {
                playerView.javaClass.getMethod("getFullWindowPlayer").invoke(playerView)
            }.getOrNull() as? KineticGSYVideoPlayer
        return full ?: playerView
    }

    fun enterPictureInPicture(): Boolean {
        val activity = CommonUtil.scanForActivity(playerView.context) as? Activity ?: return false
        return enterPictureInPicture(activity)
    }

    fun enterPictureInPicture(activity: Activity): Boolean {
        if (!uiConfig.pictureInPictureEnabled || !isPictureInPictureSupported()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode) {
            return true
        }
        val params = buildPictureInPictureParams(autoEnter = false)
        return activity.enterPictureInPictureMode(params)
    }

    fun isHostedBy(activity: Activity): Boolean =
        CommonUtil.scanForActivity(playerView.context) === activity

    fun shouldAutoEnterPictureInPicture(): Boolean =
        uiConfig.pictureInPictureEnabled &&
            isPictureInPictureSupported() &&
            !currentUrl.isNullOrEmpty() &&
            isPlaybackActive()

    fun syncPictureInPictureParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!isPictureInPictureSupported() || !uiConfig.pictureInPictureEnabled) return
        val activity = CommonUtil.scanForActivity(playerView.context) as? Activity ?: return
        try {
            activity.setPictureInPictureParams(buildPictureInPictureParams(autoEnter = true))
        } catch (_: IllegalArgumentException) {
            // OEM may reject aspect ratio even after clamping; must not crash onPrepared.
        }
    }

    private fun buildPictureInPictureParams(autoEnter: Boolean): PictureInPictureParams {
        val width = GSYVideoManager.instance().currentVideoWidth
        val height = GSYVideoManager.instance().currentVideoHeight
        val aspectRatio = pictureInPictureAspectRatio(width, height)
        val builder =
            PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(
                autoEnter && uiConfig.pictureInPictureEnabled && isPlaybackActive(),
            )
        }
        return builder.build()
    }

    /**
     * PiP aspect ratio must stay within platform bounds (~0.418–2.39).
     * Ultra-wide sources (e.g. 3840×1600 ≈ 2.4) otherwise crash [Activity.setPictureInPictureParams].
     */
    private fun pictureInPictureAspectRatio(
        videoWidth: Int,
        videoHeight: Int,
    ): Rational {
        if (videoWidth <= 0 || videoHeight <= 0) {
            return Rational(16, 9)
        }
        var w = videoWidth
        var h = videoHeight
        val ratio = w.toDouble() / h
        when {
            ratio > PIP_ASPECT_RATIO_MAX ->
                w = (h * PIP_ASPECT_RATIO_MAX).roundToInt().coerceAtLeast(1)
            ratio < PIP_ASPECT_RATIO_MIN ->
                h = (w / PIP_ASPECT_RATIO_MIN).roundToInt().coerceAtLeast(1)
        }
        return Rational(w, h)
    }

    private fun onPlaybackStarted() {
        isPlaying = true
        syncPictureInPictureParams()
    }

    private fun onPlaybackPaused() {
        isPlaying = false
        syncPictureInPictureParams()
    }

    private fun isPlaybackActive(): Boolean {
        if (isPlaying) return true
        return when (playerView.currentState) {
            GSYVideoView.CURRENT_STATE_PLAYING,
            GSYVideoView.CURRENT_STATE_PLAYING_BUFFERING_START,
            -> true
            else -> false
        }
    }

    private fun isPictureInPictureSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    fun releaseAllVideos() {
        GSYVideoManager.releaseAllVideos()
    }

    private fun emitMappedState(rawState: Int) {
        val mapped =
            when (rawState) {
                GSYVideoView.CURRENT_STATE_PLAYING -> CommonPlayerState.PLAYING
                GSYVideoView.CURRENT_STATE_PLAYING_BUFFERING_START -> CommonPlayerState.BUFFERING
                GSYVideoView.CURRENT_STATE_PAUSE -> CommonPlayerState.PAUSED
                GSYVideoView.CURRENT_STATE_AUTO_COMPLETE -> CommonPlayerState.COMPLETED
                GSYVideoView.CURRENT_STATE_ERROR -> CommonPlayerState.ERROR
                GSYVideoView.CURRENT_STATE_PREPAREING -> CommonPlayerState.BUFFERING
                else -> CommonPlayerState.IDLE
            }
        callbacks.onPlayerStateChanged(mapped)
    }

    private fun reportProgress(force: Boolean = false) {
        val positionMs = GSYVideoManager.instance().currentPosition
        val durationMs = playerView.duration.coerceAtLeast(0L)
        checkMidRoll(positionMs)
        progressReporter.report(positionMs, durationMs, force)
    }

    private fun checkMidRoll(positionMs: Long) {
        if (adMode != AdMode.NONE || midRollQueue.isEmpty()) return
        val next = midRollQueue.first()
        if (positionMs >= next.atMs) {
            midRollQueue.removeAt(0)
            val content = next.contentUrl ?: currentUrl ?: return
            adMode = AdMode.MID_ROLL
            adSkipAfterMs = 5_000L
            pendingContentUrl = content
            pendingContentPositionMs = positionMs
            setUrl(next.adUrl)
            startPlayLogic()
            activePlayer().showAdChrome(adSkipAfterMs) { skipAd() }
        }
    }

    fun release() {
        isPlaying = false
        mainHandler.removeCallbacks(progressRunnable)
        stopGifRecordingInternal(save = false)
        playerView.getOverlayDanmaku()?.release()
        activePlayer().hideAdChrome()
        GsyPlayerLifecycleRegistry.unregister(this)
        playerView.release()
        progressReporter.reset()
    }

    private companion object {
        /** Matches Android [Activity.setPictureInPictureParams] validation (API 31+). */
        const val PIP_ASPECT_RATIO_MIN = 0.418410
        const val PIP_ASPECT_RATIO_MAX = 2.390000
    }
}

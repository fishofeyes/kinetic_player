#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
import ObjectiveC
#endif

final class SgVideoPlatformView: NSObject, SgPlayerChromeDelegate {
#if os(iOS)
    private let container = UIView()
#elseif os(macOS)
    private let container = NSView()
#endif
    private let player: SgNativePlayer
    private let channel: FlutterMethodChannel
    private let chrome: SgPlayerChromeView
    private let coverOverlay = SgCoverOverlayView()
    private let fullscreenPresenter = SgFullscreenPresenter()
    private let channelCallbacks: SgChannelCallbacks
    private var isPlaying = false
    private var keepLastFrameWhenComplete = false
    private var latestState: CommonPlayerState = .idle
    private var playlist: [String] = []
    private var playlistIndex = 0
    private var autoPlayNext = true
    private var disposed = false

    init(
        frame: CGRect,
        viewId: Int64,
        messenger: FlutterBinaryMessenger,
        args: Any?,
    ) {
        let params = args as? [String: Any]
        let uiConfig = SgUiConfig.fromCreationParams(params)
        keepLastFrameWhenComplete = uiConfig.keepLastFrameWhenComplete

        channel = FlutterMethodChannel(
            name: PlayerConstants.sgChannelName(viewId: Int(viewId)),
            binaryMessenger: messenger,
        )
        channelCallbacks = SgChannelCallbacks(channel: channel)
        KineticPlayerColors.applyAccent(argb: uiConfig.accentColor)
        chrome = SgPlayerChromeView(config: uiConfig)
        player = SgNativePlayer(callbacks: channelCallbacks)
        super.init()

        channelCallbacks.attach(host: self)

        container.frame = frame
#if os(iOS)
        container.backgroundColor = .black
        container.clipsToBounds = true
#elseif os(macOS)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.masksToBounds = true
#endif

        player.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(player.view)

        coverOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(coverOverlay)
        coverOverlay.onCoverImageUpdated = { [weak self] in
            self?.syncCoverVisibility()
        }
        coverOverlay.setCoverUrl(uiConfig.coverUrl)

        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.delegate = self
        container.addSubview(chrome)

        NSLayoutConstraint.activate([
            player.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            player.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            player.view.topAnchor.constraint(equalTo: container.topAnchor),
            player.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            coverOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            coverOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            coverOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            coverOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: container.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let playlistArgs = (params?["playlist"] as? [String]) ?? []
        let startIndex = params?["playlistStartIndex"] as? Int ?? 0
        applyHttpFromCreationParams(params)
        if !playlistArgs.isEmpty {
            setPlaylist(playlistArgs, startIndex: startIndex, autoPlay: false)
        } else if let url = params?["url"] as? String, !url.isEmpty {
            player.switchVideoSource(url, autoPlay: false)
        }
        player.setLooping(uiConfig.looping)
        if abs(uiConfig.speed - 1) > 0.001 {
            player.setRate(Double(uiConfig.speed))
        }
        syncCoverVisibility()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

#if os(iOS)
    func view() -> UIView { container }
#elseif os(macOS)
    func view() -> NSView { container }
#endif

    /// UIView.layoutIfNeeded() / NSView.layoutSubtreeIfNeeded() equivalent.
    private func forceContainerLayout() {
#if os(iOS)
        container.layoutIfNeeded()
#elseif os(macOS)
        container.layoutSubtreeIfNeeded()
#endif
    }

    func onProgressChanged(positionMs: Int64, durationMs: Int64, bufferedMs: Int64) {
        chrome.updateProgress(positionMs: positionMs, durationMs: durationMs)
        _ = bufferedMs
    }

    func onPlayerError(message: String?, code: Int) {
        _ = message
        _ = code
    }

    func onPlayerStateChanged(_ state: CommonPlayerState) {
        latestState = state
        isPlaying = state == .playing
        chrome.updatePlayState(isPlaying: isPlaying)
        if state == .playing {
            chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
        }
        if state == .paused || state == .completed || state == .idle {
            chrome.setControlsVisible(true, animated: true)
        }
        if state == .completed {
            maybePlayNextInPlaylist()
        }
        syncCoverVisibility()
    }

    private func setPlaylist(_ urls: [String], startIndex: Int, autoPlay: Bool) {
        playlist = urls.filter { !$0.isEmpty }
        guard !playlist.isEmpty else { return }
        playlistIndex = min(max(0, startIndex), playlist.count - 1)
        player.switchVideoSource(playlist[playlistIndex], autoPlay: autoPlay)
    }

    private func applyHttpFromCreationParams(_ params: [String: Any]?) {
        guard let params else { return }
        var options: [String: Any] = [:]
        if let userAgent = params["userAgent"] as? String, !userAgent.isEmpty {
            options["userAgent"] = userAgent
        }
        if let headers = params["headers"] as? [String: Any], !headers.isEmpty {
            options["headers"] = headers
        }
        guard !options.isEmpty else { return }
        player.setHttpRequestOptions(options)
    }

    @discardableResult
    private func playNextInPlaylist() -> Bool {
        guard playlist.count > 1, playlistIndex < playlist.count - 1 else { return false }
        playlistIndex += 1
        player.switchVideoSource(playlist[playlistIndex], autoPlay: true)
        return true
    }

    private func maybePlayNextInPlaylist() {
        guard autoPlayNext else { return }
        _ = playNextInPlaylist()
    }

    private func syncCoverVisibility() {
        let show: Bool
        switch latestState {
        case .playing, .buffering, .paused:
            show = false
        case .completed:
            // Keep last frame: hide cover. Otherwise show cover (or black fallback).
            show = !keepLastFrameWhenComplete
        case .idle, .ready, .error:
            show = coverOverlay.hasCover
        }
        coverOverlay.isHidden = !show
        if show, !coverOverlay.hasCoverImage {
#if os(iOS)
            coverOverlay.backgroundColor = .black
#elseif os(macOS)
            coverOverlay.layer?.backgroundColor = NSColor.black.cgColor
#endif
        }
    }

    // MARK: - SgPlayerChromeDelegate

    func chromeDidTapPlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func chromeDidSeek(toMs: Int) {
        player.seek(positionMs: toMs)
    }

    func chromeDidTapFullscreen() {
        fullscreenPresenter.toggleFullscreen(container: container)
        chrome.updateFullscreenIcon(isFullscreen: fullscreenPresenter.isFullscreen)
        chrome.setFullscreenActive(fullscreenPresenter.isFullscreen)
        forceContainerLayout()
        player.applyRenderTransform()
    }

    func chromeDidChangeVolume(_ volume: Double) {
        player.setVolume(volume)
        chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
    }

    func chromeDidToggleMute(_ muted: Bool) {
        player.setMute(muted)
        chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
    }

    func chromeDidRequestAudioTracks() -> [[String: Any]] {
        player.getAudioTracks()
    }

    func chromeDidSelectAudioTrack(index: Int) {
        _ = player.selectAudioTrack(index)
        chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
    }

    func chromeDidChangeRate(_ rate: Double) {
        player.setRate(rate)
    }

    func chromeDidChangeMirror(_ enabled: Bool) {
        player.setMirrorHorizontal(enabled: enabled)
    }

    func chromeDidChangeLooping(_ looping: Bool) {
        player.setLooping(looping)
    }

    func chromeDidChangeAutoPlayNext(_ enabled: Bool) {
        autoPlayNext = enabled
    }

    func chromeDidChangeScaleMode(_ mode: Int) {
        // Chrome modes: 0 auto, 1 16:9, 2 4:3, 3 fill/hide bars.
        // SG renderer maps to ResizeAspect / ResizeAspectFill / Resize.
        switch mode {
        case 3:
            player.setRenderMode(1) // aspect fill
        case 1, 2:
            // Forced 16:9 / 4:3 not available on SG; keep letterbox fit.
            player.setRenderMode(0)
        default:
            player.setRenderMode(0) // auto / aspect fit
        }
    }

    func chromeDidChangeBlackout(_ enabled: Bool) {
        // Blackout overlay is owned by chrome; no player-side work.
        _ = enabled
    }

    func chromeDidRequestScreenshot() {
        let data = player.captureFrame()
        var args: [String: Any] = [:]
        if let data = data {
            args["bytes"] = FlutterStandardTypedData(bytes: data)
        }
        channel.invokeMethod("onScreenshotCaptured", arguments: args)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            player.play()
            result(nil)
        case "pause":
            player.pause()
            result(nil)
        case "stop":
            player.stop()
            result(nil)
        case "seekTo":
            let args = call.arguments as? [String: Any]
            let position = args?["position"] as? Int ?? 0
            player.seek(positionMs: position)
            result(nil)
        case "setScaleMode":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? Int ?? 0
            player.setRenderMode(mode)
            result(nil)
        case "setRate":
            let args = call.arguments as? [String: Any]
            let rate = args?["rate"] as? Double ?? 1.0
            player.setRate(rate)
            result(nil)
        case "setVolume":
            let args = call.arguments as? [String: Any]
            let volume = args?["volume"] as? Double ?? 1.0
            player.setVolume(volume)
            chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
            result(nil)
        case "setMute":
            let args = call.arguments as? [String: Any]
            let muted = args?["muted"] as? Bool ?? false
            player.setMute(muted)
            chrome.syncVolume(volume: player.currentVolume(), muted: player.isMuted())
            result(nil)
        case "switchVideoSource":
            let args = call.arguments as? [String: Any]
            let url = args?["url"] as? String ?? ""
            let autoPlay = args?["autoPlay"] as? Bool ?? true
            if let idx = playlist.firstIndex(of: url) {
                playlistIndex = idx
            }
            player.switchVideoSource(url, autoPlay: autoPlay)
            latestState = .idle
            syncCoverVisibility()
            result(nil)
        case "gsySetPlaylist":
            let args = call.arguments as? [String: Any]
            let urls = args?["urls"] as? [String] ?? []
            let startIndex = args?["startIndex"] as? Int ?? 0
            setPlaylist(urls, startIndex: startIndex, autoPlay: false)
            result(nil)
        case "gsyPlayNextInPlaylist":
            result(playNextInPlaylist())
        case "getAudioTracks":
            result(player.getAudioTracks())
        case "selectAudioTrack":
            let args = call.arguments as? [String: Any]
            let index = args?["index"] as? Int ?? 0
            if player.selectAudioTrack(index) {
                result(nil)
            } else {
                result(FlutterError(code: "TRACK", message: "Audio track not found", details: nil))
            }
        case "getVideoSize":
            result(player.getVideoSize())
        case "getVideoMetadata":
            let size = player.getVideoSize()
            result([
                "width": size?["width"] ?? 0,
                "height": size?["height"] ?? 0,
                "duration": max(0, player.durationMs()),
            ] as [String: Any])
        case "setLooping":
            let args = call.arguments as? [String: Any]
            let looping = args?["looping"] as? Bool ?? false
            player.setLooping(looping)
            result(nil)
        case "captureFrame":
            if let data = player.captureFrame() {
                result(FlutterStandardTypedData(bytes: data))
            } else {
                result(nil)
            }
        case "sgStartFullscreen":
            if !fullscreenPresenter.isFullscreen {
                fullscreenPresenter.enterFullscreen(container: container)
                chrome.updateFullscreenIcon(isFullscreen: true)
                chrome.setFullscreenActive(true)
                forceContainerLayout()
                player.applyRenderTransform()
            }
            result(nil)
        case "sgExitFullscreen":
            if fullscreenPresenter.isFullscreen {
                fullscreenPresenter.exitFullscreen()
                chrome.updateFullscreenIcon(isFullscreen: false)
                chrome.setFullscreenActive(false)
                forceContainerLayout()
                player.applyRenderTransform()
            }
            result(nil)
        case "sgIsFullscreen":
            result(fullscreenPresenter.isFullscreen)
        case "sgSetVRMode":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            player.setSgVRMode(enabled: enabled)
            result(nil)
        case "sgSetDisplayMode":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? Int ?? 0
            player.setDisplayMode(mode)
            result(nil)
        case "sgGetDisplayMode":
            result(player.displayMode())
        case "sgSetVrViewport":
            let args = call.arguments as? [String: Any] ?? [:]
            player.setVrViewport(args)
            result(nil)
        case "sgGetVrViewport":
            result(player.vrViewport())
        case "sgSetPitch":
            let args = call.arguments as? [String: Any]
            let pitch = args?["pitch"] as? Double ?? 1.0
            player.setPitch(pitch)
            result(nil)
        case "sgGetPitch":
            result(player.currentPitch())
        case "sgGetVideoTracks":
            result(player.getVideoTracks())
        case "sgSelectVideoTrack":
            let args = call.arguments as? [String: Any]
            let index = args?["index"] as? Int ?? 0
            if player.selectVideoTrack(index) {
                result(nil)
            } else {
                result(FlutterError(code: "TRACK", message: "Video track not found", details: nil))
            }
        case "sgSetDemuxerOptions":
            let args = call.arguments as? [String: Any] ?? [:]
            player.setDemuxerOptions(args)
            result(nil)
        case "sgReplaceWithSegments":
            let args = call.arguments as? [String: Any]
            let segments = args?["segments"] as? [[String: Any]] ?? []
            let autoPlay = args?["autoPlay"] as? Bool ?? true
            let ok = player.replaceWithSegments(segments, autoPlay: autoPlay)
            latestState = .idle
            syncCoverVisibility()
            result(ok)
        case "sgSetBackgroundPlaybackPolicy":
            let args = call.arguments as? [String: Any] ?? [:]
            player.setBackgroundPlaybackPolicy(args)
            result(nil)
        case "sgGetBackgroundPlaybackPolicy":
            result(player.backgroundPlaybackPolicy())
        case "sgGetBufferedPosition":
            result(player.bufferedPositionMs())
        case "sgGetLastError":
            result([
                "message": player.lastErrorMessage() as Any,
                "code": player.lastErrorCode(),
            ])
        case "sgIsSeekable":
            result(player.isSeekable())
        case "sgSetRenderRotation":
            let args = call.arguments as? [String: Any]
            let degrees = args?["degrees"] as? Int ?? 0
            player.setRenderRotation(degrees: degrees)
            result(nil)
        case "sgSetMirrorHorizontal":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            player.setMirrorHorizontal(enabled: enabled)
            result(nil)
        case "sgSetMirrorVertical":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            player.setMirrorVertical(enabled: enabled)
            result(nil)
        case "sgSetKeepLastFrameWhenComplete":
            let args = call.arguments as? [String: Any]
            keepLastFrameWhenComplete = args?["enabled"] as? Bool ?? false
            syncCoverVisibility()
            result(nil)
        case "sgSetCoverUrl":
            let args = call.arguments as? [String: Any]
            coverOverlay.setCoverUrl(args?["url"] as? String)
            syncCoverVisibility()
            result(nil)
        case "setLocale":
            let args = call.arguments as? [String: Any]
            let locale = args?["locale"] as? String ?? "zh"
            let strings = SgUiConfig.parseStrings(args?["strings"])
            chrome.applyChromeLocale(locale: locale, strings: strings)
            result(nil)
        case "setHttpRequestOptions":
            let args = call.arguments as? [String: Any] ?? [:]
            player.setHttpRequestOptions(args)
            result(nil)
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        if fullscreenPresenter.isFullscreen { fullscreenPresenter.exitFullscreen() }
        chrome.restoreBrightnessIfNeeded()
        channel.setMethodCallHandler(nil)
        player.release()
        container.removeFromSuperview()
    }
}

private final class SgChannelCallbacks: SgPlayerCallbacks {
    private let channel: FlutterMethodChannel
    private weak var host: SgVideoPlatformView?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func attach(host: SgVideoPlatformView) {
        self.host = host
    }

    func onPlayerStateChanged(_ state: CommonPlayerState) {
        host?.onPlayerStateChanged(state)
        channel.invokeMethod("onPlayerStateChanged", arguments: ["state": state.rawValue])
    }

    func onPositionChanged(positionMs: Int64, durationMs: Int64, bufferedMs: Int64) {
        host?.onProgressChanged(positionMs: positionMs, durationMs: durationMs, bufferedMs: bufferedMs)
        channel.invokeMethod(
            "onPositionChanged",
            arguments: [
                "position": positionMs,
                "duration": durationMs,
                "buffered": bufferedMs,
            ],
        )
    }

    func onPlayerError(message: String?, code: Int) {
        host?.onPlayerError(message: message, code: code)
        channel.invokeMethod(
            "onPlayerError",
            arguments: [
                "message": message as Any,
                "code": code,
            ],
        )
    }
}

#if os(iOS)
extension SgVideoPlatformView: FlutterPlatformView {}
#endif

final class SgVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let sessions: SgVideoSessions

    init(messenger: FlutterBinaryMessenger, sessions: SgVideoSessions) {
        self.messenger = messenger
        self.sessions = sessions
    }

#if os(iOS)
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
    ) -> FlutterPlatformView {
        if let params = args as? [String: Any], let id = params["sessionId"] as? NSNumber {
            return SgVideoAttachment(sessions.attach(id.int64Value, frame: frame))
        }
        return SgVideoPlatformView(frame: frame, viewId: viewId, messenger: messenger, args: args)
    }
#elseif os(macOS)
    // macOS factory returns NSView directly (no FlutterPlatformView protocol).
    // Retain the controller on the view so channel handlers stay alive.
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        if let params = args as? [String: Any], let id = params["sessionId"] as? NSNumber {
            return sessions.attach(id.int64Value)
        }
        let platformView = SgVideoPlatformView(
            frame: .zero,
            viewId: viewId,
            messenger: messenger,
            args: args,
        )
        let view = platformView.view()
        objc_setAssociatedObject(
            view,
            &SgVideoPlatformViewAssociationKey,
            platformView,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        return view
    }
#endif

#if os(iOS)
    // iOS headers use NS_ASSUME_NONNULL: implemented createArgsCodec must be non-optional.
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
#elseif os(macOS)
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }
#endif
}

#if os(macOS)
private var SgVideoPlatformViewAssociationKey: UInt8 = 0
#endif

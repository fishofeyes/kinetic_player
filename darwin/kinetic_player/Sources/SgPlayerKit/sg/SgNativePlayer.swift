#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
// SwiftPM builds the bridge as a separate target. CocoaPods includes its public
// header in kinetic_player's own module, so there is no separate module to import.
#if SWIFT_PACKAGE
import SgNativePlayerBridge
#endif

protocol SgPlayerCallbacks: AnyObject {
    func onPlayerStateChanged(_ state: CommonPlayerState)
    func onPositionChanged(positionMs: Int64, durationMs: Int64, bufferedMs: Int64)
    func onPlayerError(message: String?, code: Int)
}

/// SGPlayer master bridge (wanwenfeng4798/SGPlayer).
final class SgNativePlayer: NSObject {
    private let bridge: SgNativePlayerBridge
    private weak var callbacks: SgPlayerCallbacks?
    private let transformHost = SgTransformHostView()
    private var renderRotationDegrees = 0
    private var mirrorHorizontal = false
    private var mirrorVertical = false

    init(callbacks: SgPlayerCallbacks) {
        self.callbacks = callbacks
        bridge = SgNativePlayerBridge(
            stateHandler: { [weak callbacks] stateIndex in
                guard let callbacks,
                      stateIndex >= 0,
                      stateIndex < CommonPlayerState.allCases.count else { return }
                callbacks.onPlayerStateChanged(CommonPlayerState.allCases[stateIndex])
            },
            progressHandler: { [weak callbacks] positionMs, durationMs, bufferedMs in
                callbacks?.onPositionChanged(
                    positionMs: positionMs,
                    durationMs: durationMs,
                    bufferedMs: bufferedMs,
                )
            },
            errorHandler: { [weak callbacks] message, code in
                callbacks?.onPlayerError(message: message, code: Int(code))
            },
        )
        super.init()

        let renderView = bridge.view
        renderView.translatesAutoresizingMaskIntoConstraints = false
        transformHost.contentView.addSubview(renderView)
        NSLayoutConstraint.activate([
            renderView.leadingAnchor.constraint(equalTo: transformHost.contentView.leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: transformHost.contentView.trailingAnchor),
            renderView.topAnchor.constraint(equalTo: transformHost.contentView.topAnchor),
            renderView.bottomAnchor.constraint(equalTo: transformHost.contentView.bottomAnchor),
        ])
    }

#if os(iOS)
    var view: UIView { transformHost }
#elseif os(macOS)
    var view: NSView { transformHost }
#endif

    func play() { bridge.play() }
    func pause() { bridge.pause() }
    func stop() { bridge.stop() }
    func seek(positionMs: Int) { bridge.seek(toMs: positionMs) }
    func setRate(_ rate: Double) { bridge.setRate(rate) }
    func setVolume(_ volume: Double) { bridge.setVolume(volume) }
    func setMute(_ muted: Bool) { bridge.setMuted(muted) }
    func setPitch(_ pitch: Double) { bridge.setPitch(pitch) }
    func currentPitch() -> Double { bridge.currentPitch() }

    func switchVideoSource(_ urlString: String, autoPlay: Bool) {
        bridge.switchVideoSource(urlString, autoPlay: autoPlay)
    }

    @discardableResult
    func replaceWithSegments(_ segments: [[String: Any]], autoPlay: Bool) -> Bool {
        bridge.replace(withSegments: segments, autoPlay: autoPlay)
    }

    func getAudioTracks() -> [[String: Any]] {
        bridge.getAudioTracks() as? [[String: Any]] ?? []
    }

    func selectAudioTrack(_ index: Int) -> Bool {
        bridge.selectAudioTrack(index)
    }

    func getVideoTracks() -> [[String: Any]] {
        bridge.getVideoTracks() as? [[String: Any]] ?? []
    }

    func selectVideoTrack(_ index: Int) -> Bool {
        bridge.selectVideoTrack(index)
    }

    func getVideoSize() -> [String: Int]? {
        guard let map = bridge.getVideoSize() as? [String: NSNumber] else { return nil }
        let width = map["width"]?.intValue ?? 0
        let height = map["height"]?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        return ["width": width, "height": height]
    }

    func setLooping(_ looping: Bool) { bridge.setLooping(looping) }
    func durationMs() -> Int64 { bridge.getDurationMs() }
    func captureFrame() -> Data? { bridge.captureFrame() }
    func currentVolume() -> Double { bridge.currentVolume() }
    func isMuted() -> Bool { bridge.isMuted() }
    func setRenderMode(_ mode: Int) { bridge.setRenderMode(mode) }

    func setDisplayMode(_ mode: Int) { bridge.setDisplayMode(mode) }
    func displayMode() -> Int { Int(bridge.displayMode()) }

    func setSgVRMode(enabled: Bool) { bridge.setVrModeEnabled(enabled) }

    func setVrViewport(_ viewport: [String: Any]) {
        bridge.setVrViewport(viewport)
    }

    func vrViewport() -> [String: Any] {
        bridge.vrViewport() as? [String: Any] ?? [:]
    }

    func setDemuxerOptions(_ options: [String: Any]) {
        bridge.setDemuxerOptions(options)
    }

    func setHttpRequestOptions(_ options: [String: Any]) {
        bridge.setHttpRequestOptions(options)
    }

    func setBackgroundPlaybackPolicy(_ policy: [String: Any]) {
        bridge.setBackgroundPlaybackPolicy(policy)
    }

    func backgroundPlaybackPolicy() -> [String: Any] {
        bridge.backgroundPlaybackPolicy() as? [String: Any] ?? [:]
    }

    func lastErrorMessage() -> String? { bridge.lastErrorMessage() }
    func lastErrorCode() -> Int { Int(bridge.lastErrorCode()) }
    func bufferedPositionMs() -> Int64 { bridge.bufferedPositionMs() }
    func isSeekable() -> Bool { bridge.isSeekable() }

    func setRenderRotation(degrees: Int) {
        let normalized = ((degrees % 360) + 360) % 360
        renderRotationDegrees = normalized
        applyRenderTransform()
    }

    func setMirrorHorizontal(enabled: Bool) {
        mirrorHorizontal = enabled
        applyRenderTransform()
    }

    func setMirrorVertical(enabled: Bool) {
        mirrorVertical = enabled
        applyRenderTransform()
    }

    func applyRenderTransform() {
        transformHost.setRenderTransform(
            rotationDegrees: renderRotationDegrees,
            mirrorHorizontal: mirrorHorizontal,
            mirrorVertical: mirrorVertical,
        )
    }

    func release() {
        transformHost.setRenderTransform(
            rotationDegrees: 0,
            mirrorHorizontal: false,
            mirrorVertical: false,
        )
        bridge.releasePlayer()
    }
}

private extension CommonPlayerState {
    static var allCases: [CommonPlayerState] {
        [.idle, .buffering, .ready, .playing, .paused, .completed, .error]
    }
}

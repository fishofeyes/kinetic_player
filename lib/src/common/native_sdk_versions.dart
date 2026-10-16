/// Pinned native SDK versions for the dual-core player plugin.
abstract final class NativeSdkVersions {
  /// Android GSYVideoPlayer (Maven Central).
  static const String gsyVideoPlayer = '14.0.0';

  /// iOS SGPlayer git branch (source builds).
  static const String sgPlayerBranch = 'master';

  /// SGPlayer source repository (see darwin/sgplayer/manifest.*.json).
  static const String sgPlayerRepository =
      'https://github.com/wanwenfeng4798/SGPlayer';

  /// iOS / macOS prebuilt binary manifest version (see darwin/sgplayer/manifest.*.json).
  static const String sgPlayerBinary = '1.0.0';

  /// macOS prebuilt binary manifest version.
  static const String sgPlayerBinaryMacOS = '1.0.0';

  /// Windows prebuilt libmpv (zhongfly LGPL; see windows/mpv/manifest.json).
  /// Client headers are mpv v0.41.0; the bundled DLL tracks the latest winbuild.
  static const String libmpvWindows = '0.41.0';

  /// Linux system libmpv (pkg-config). Documented minimum; 0.41+ recommended.
  static const String libmpvLinux = '0.35.0';
}

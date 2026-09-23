#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'kinetic_player'
  s.version          = '2.1.1'
  s.summary          = 'Dual-core video player: SGPlayer on iOS and macOS.'
  s.description      = <<-DESC
Flutter video player plugin. iOS / macOS use wanwenfeng4798/SGPlayer master; Android uses GSYVideoPlayer 13.1.0.
SGPlayer.xcframework via SPM remote binaryTarget (Package.swift) and/or
CocoaPods prepare_command → ensure_sgplayer.sh (30-60 min only if local build).
                       DESC
  s.homepage         = 'https://github.com/wanwenfeng4798/kinetic_player'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'wanwenfeng4798' => 'https://github.com/wanwenfeng4798' }
  s.source           = { :path => '.' }
  s.swift_version    = '5.0'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'

  # CocoaPods prepare: SGPlayer ensure + align FlutterGeneratedPluginSwiftPackage OS mins.
  # SPM: remote binaryTarget in Package.swift; wrapper OS sync on `flutter run` / `flutter build`
  # when host MACOSX_DEPLOYMENT_TARGET >= 11.0 (Flutter updateMinimumDeployment).
  s.prepare_command = <<-CMD
    set -e
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    bash scripts/sgplayer/sync_flutter_spm_wrapper.sh || true
    bash scripts/sgplayer/ensure_sgplayer.sh ios
    bash scripts/sgplayer/ensure_sgplayer.sh macos
  CMD

  s.ios.vendored_frameworks = 'Frameworks/ios/SGPlayer.xcframework'
  s.osx.vendored_frameworks = 'Frameworks/macos/SGPlayer.xcframework'

  s.source_files = 'kinetic_player/Sources/**/*.{swift,h,m}'
  s.public_header_files = 'kinetic_player/Sources/SgNativePlayerBridge/include/*.h'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'VideoToolbox', 'CoreMedia', 'Metal', 'MetalKit'
  s.libraries = 'iconv', 'bz2', 'z'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.resource_bundles = {
    'kinetic_player_privacy' => ['kinetic_player/Sources/kinetic_player/PrivacyInfo.xcprivacy']
  }
end

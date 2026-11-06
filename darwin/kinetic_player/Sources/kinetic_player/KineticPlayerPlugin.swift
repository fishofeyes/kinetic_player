#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

public class KineticPlayerPlugin: NSObject, FlutterPlugin {
  private var sessions: SgVideoSessions?
  private var assetLookup: ((String, String?) -> String)?

  public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
    let messenger = registrar.messenger()
#elseif os(macOS)
    let messenger = registrar.messenger
#endif
    let sessions = SgVideoSessions(messenger: messenger)
    let plugin = KineticPlayerPlugin()
    plugin.sessions = sessions
    plugin.assetLookup = { asset, package in
      let key: String
      if let package {
        key = registrar.lookupKey(forAsset: asset, fromPackage: package)
      } else {
        key = registrar.lookupKey(forAsset: asset)
      }
#if os(iOS)
      let path = Bundle.main.path(forResource: key, ofType: nil) ??
        Bundle.main.bundleURL.appendingPathComponent(key).path
      return URL(fileURLWithPath: path).absoluteString
#elseif os(macOS)
      let path = Bundle.main.path(forResource: key, ofType: nil) ??
        URL(string: key, relativeTo: Bundle.main.bundleURL)?.path ?? key
      return URL(fileURLWithPath: path).absoluteString
#endif
    }
    let channel = FlutterMethodChannel(name: "com.example.player/sg", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(
      SgVideoViewFactory(messenger: messenger, sessions: sessions),
      withId: PlayerConstants.sgViewType
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "create":
      guard let sessions else {
        result(FlutterError(code: "KineticPlayer", message: "Plugin is detached", details: nil))
        return
      }
      result(["viewId": sessions.create(args: call.arguments)])
    case "reset":
      sessions?.dispose()
      result(nil)
    case "destroy":
      if let id = args?["viewId"] as? NSNumber { sessions?.destroy(id.int64Value) }
      result(nil)
    case "resolveAsset":
      result(assetLookup?(args?["asset"] as? String ?? "", args?["package"] as? String))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    sessions?.dispose()
    sessions = nil
    assetLookup = nil
  }
}

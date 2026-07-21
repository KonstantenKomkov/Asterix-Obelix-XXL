import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var gameControllerInput: GameControllerInput?
  private var windowChannel: FlutterMethodChannel?
  private var assetsChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let registrar = flutterViewController.registrar(forPlugin: "AsterixMetalViewport")
    registrar.register(
      MetalViewportFactory(messenger: registrar.messenger),
      withId: MetalViewportFactory.viewType
    )
    gameControllerInput = GameControllerInput(messenger: registrar.messenger)
    let channel = FlutterMethodChannel(name: "asterix/window", binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setFullscreen", let requested = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else { result(nil); return }
      let active = self.styleMask.contains(.fullScreen)
      if active != requested { self.toggleFullScreen(nil) }
      result(nil)
    }
    windowChannel = channel
    let assets = FlutterMethodChannel(name: "asterix/assets", binaryMessenger: registrar.messenger)
    assets.setMethodCallHandler { [weak self] call, result in
      if call.method == "resolveAssetPackage" {
        if let preferred = call.arguments as? String,
           !preferred.isEmpty,
           FileManager.default.fileExists(atPath: preferred) {
          result(preferred)
          return
        }
        let support = FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first
        let package = support?
          .appendingPathComponent("AsterixXXL", isDirectory: true)
          .appendingPathComponent("gaul-stage-1.astpak")
        result(package.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil })
        return
      }
      guard call.method == "selectAssetPackage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let panel = NSOpenPanel()
      panel.title = "Пакет уровня Gaul Stage 1"
      panel.message = "Выберите gaul-stage-1.astpak или сначала запустите scripts/install_slice_assets.sh"
      panel.allowedFileTypes = ["astpak"]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      if let self {
        panel.beginSheetModal(for: self) { response in
          result(response == .OK ? panel.url?.path : nil)
        }
      } else {
        result(nil)
      }
    }
    assetsChannel = assets

    super.awakeFromNib()
  }
}

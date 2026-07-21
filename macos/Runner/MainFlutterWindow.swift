import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var gameControllerInput: GameControllerInput?
  private var windowChannel: FlutterMethodChannel?
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

    super.awakeFromNib()
  }
}

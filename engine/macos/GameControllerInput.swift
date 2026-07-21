import FlutterMacOS
import GameController

@MainActor
final class GameControllerInput: NSObject, FlutterStreamHandler {
  static let channel = "asterix/controller-events"
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterEventChannel(name: Self.channel, binaryMessenger: messenger).setStreamHandler(self)
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
        guard let controller = note.object as? GCController else { return }
        self?.configure(controller)
        self?.sink?(["type": "connected", "name": controller.vendorName ?? "Controller"])
      },
      center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
        self?.sink?(["type": "disconnected"])
      },
    ]
    GCController.startWirelessControllerDiscovery(completionHandler: nil)
    GCController.controllers().forEach(configure)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    for controller in GCController.controllers() {
      configure(controller)
      events(["type": "connected", "name": controller.vendorName ?? "Controller"])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  private func emit(_ control: String, _ value: Float) {
    sink?(["type": "control", "control": control, "value": Double(value)])
  }

  private func configure(_ controller: GCController) {
    guard let pad = controller.extendedGamepad else { return }
    pad.leftThumbstick.xAxis.valueChangedHandler = { [weak self] _, value in self?.emit("leftX", value) }
    pad.leftThumbstick.yAxis.valueChangedHandler = { [weak self] _, value in self?.emit("leftY", value) }
    pad.buttonA.valueChangedHandler = { [weak self] _, value, _ in self?.emit("buttonA", value) }
    pad.buttonX.valueChangedHandler = { [weak self] _, value, _ in self?.emit("buttonX", value) }
    pad.buttonMenu.valueChangedHandler = { [weak self] _, value, _ in self?.emit("menu", value) }
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

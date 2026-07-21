import AppKit
import FlutterMacOS
import MetalKit

final class MetalViewportFactory: NSObject, FlutterPlatformViewFactory, FlutterStreamHandler {
  static let viewType = "asterix/metal-viewport"
  static let statsChannel = "asterix/metal-stats"
  static let debugChannel = "asterix/metal-debug"
  static let inputChannel = "asterix/game-input"
  private weak var viewport: MetalViewportView?
  private var eventSink: FlutterEventSink?
  private var timer: Timer?
  private var debugMethodChannel: FlutterMethodChannel?
  private var inputMethodChannel: FlutterMethodChannel?
  private var latestInput: [String: Double] = [:]
  private var pendingGameplayState: [String: Any]?

  override init() {
    super.init()
  }

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterEventChannel(name: Self.statsChannel, binaryMessenger: messenger)
      .setStreamHandler(self)
    let channel = FlutterMethodChannel(name: Self.debugChannel, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setOptions", let options = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.viewport?.debugOptions = UInt32(truncatingIfNeeded: options)
      result(nil)
    }
    debugMethodChannel = channel
    let input = FlutterMethodChannel(name: Self.inputChannel, binaryMessenger: messenger)
    input.setMethodCallHandler { [weak self] call, result in
      if call.method == "setSnapshot", let values = call.arguments as? [String: NSNumber] {
        self?.latestInput = values.mapValues(\.doubleValue)
        self?.viewport?.setInput(values)
        result(nil)
      } else if call.method == "setPaused", let paused = call.arguments as? Bool {
        self?.viewport?.setGameplayPaused(paused)
        result(nil)
      } else if call.method == "captureState" {
        result(self?.viewport?.gameplaySaveState ?? [:])
      } else if call.method == "restoreState", let state = call.arguments as? [String: Any] {
        self?.pendingGameplayState = state
        self?.viewport?.restoreGameplaySaveState(state)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    inputMethodChannel = input
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withViewIdentifier viewIdentifier: Int64,
    arguments args: Any?
  ) -> NSView {
    let view = MetalViewportView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    let values = args as? NSDictionary
    let path = values?["assetPackagePath"] as? String ?? ""
    if !path.isEmpty {
      view.loadAssetPackage(at: URL(fileURLWithPath: path))
    } else {
      view.reportSceneConfigurationError("ASTERIX_ASSET_PACKAGE is not configured")
    }
    viewport = view
    if let state = pendingGameplayState { view.restoreGameplaySaveState(state) }
    return view
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self, var stats = self.viewport?.statistics else { return }
      stats["input"] = self.latestInput
      self.eventSink?(stats)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    timer?.invalidate()
    timer = nil
    eventSink = nil
    return nil
  }

  deinit { timer?.invalidate() }
}

final class MetalViewportView: MTKView {
  private var renderer: AsterixMetalRenderer?
  private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
  private var pendingGameplayState: [String: Any]?

  var statistics: [String: Any] {
    guard let renderer else { return [:] }
    return [
      "fps": renderer.framesPerSecond,
      "cpuMs": renderer.cpuFrameTimeMilliseconds,
      "gpuMs": renderer.gpuFrameTimeMilliseconds,
      "allocatedBytes": renderer.allocatedMemoryBytes,
      "frameCount": renderer.frameCount,
      "sceneReady": renderer.isSceneReady,
      "sceneMeshCount": renderer.sceneMeshCount,
      "visibleMeshCount": renderer.visibleMeshCount,
      "drawBatchCount": renderer.drawBatchCount,
      "residentSectionCount": renderer.residentSectionCount,
      "collisionTriangleCount": renderer.collisionTriangleCount,
      "debugOptions": renderer.debugOptions,
      "sceneError": renderer.sceneError ?? "",
      "playerState": renderer.playerState,
      "playerHealth": renderer.playerHealth,
      "playerMaximumHealth": renderer.playerMaximumHealth,
      "playerPosition": [renderer.playerPosition.x, renderer.playerPosition.y, renderer.playerPosition.z],
      "enemyState": renderer.enemyState,
      "enemyHealth": renderer.enemyHealth,
      "enemyPosition": [renderer.enemyPosition.x, renderer.enemyPosition.y, renderer.enemyPosition.z],
      "rewardCount": renderer.rewardCount,
      "activeCheckpoint": renderer.activeCheckpoint,
      "leverActivated": renderer.leverActivated,
      "destructibleDestroyed": renderer.destructibleDestroyed,
      "interactionHint": renderer.interactionHint,
      "cameraFov": renderer.cameraFieldOfView,
      "cameraCollisionLimited": renderer.cameraCollisionLimited,
      "combatActive": renderer.combatActive,
      "comboStage": renderer.comboStage,
      "combatHitWindow": renderer.combatHitWindow,
    ]
  }

  var debugOptions: UInt32 {
    get { renderer?.debugOptions ?? 0 }
    set { renderer?.setDebugOptions(newValue) }
  }

  func setInput(_ values: [String: NSNumber]) {
    let x = (values["moveRight"]?.floatValue ?? 0) - (values["moveLeft"]?.floatValue ?? 0)
    let z = (values["moveForward"]?.floatValue ?? 0) - (values["moveBackward"]?.floatValue ?? 0)
    renderer?.setInputMoveX(x, moveZ: z, jump: (values["jump"]?.doubleValue ?? 0) > 0.5,
                           attack: (values["attack"]?.doubleValue ?? 0) > 0.5,
                           interact: (values["interact"]?.doubleValue ?? 0) > 0.5)
  }

  func setGameplayPaused(_ paused: Bool) {
    if paused { renderer?.suspend() } else { renderer?.resume() }
  }

  var gameplaySaveState: [String: Any] {
    renderer?.gameplaySaveState() as? [String: Any] ?? [:]
  }

  func restoreGameplaySaveState(_ state: [String: Any]) {
    pendingGameplayState = state
    if renderer?.restoreGameplaySaveState(state) == true {
      pendingGameplayState = nil
    }
  }

  func loadAssetPackage(at url: URL) {
    // Package parsing and buffer preparation must never stall the UI/render loop.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let loaded = self.renderer?.loadAssetPackage(at: url) == true
      DispatchQueue.main.async { [weak self] in
        guard loaded, let self, let state = self.pendingGameplayState else { return }
        self.restoreGameplaySaveState(state)
      }
    }
  }

  func reportSceneConfigurationError(_ message: String) {
    renderer?.reportSceneError(message)
  }

  override init(frame frameRect: NSRect, device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    super.init(frame: frameRect, device: device)
    autoresizingMask = [.width, .height]
    autoResizeDrawable = false
    preferredFramesPerSecond = 60
    framebufferOnly = true
    colorPixelFormat = .bgra8Unorm
    clearColor = MTLClearColor(red: 0.035, green: 0.075, blue: 0.12, alpha: 1)
    renderer = AsterixMetalRenderer(view: self)
    observeApplicationLifecycle()
    updateDrawableSize()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    lifecycleObservers.forEach { center, token in
      center.removeObserver(token)
    }
    renderer?.stop()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    updateDrawableSize()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateDrawableSize()
    if window == nil || !NSApp.isActive {
      renderer?.suspend()
    } else {
      renderer?.resume()
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.window != nil, NSApp.isActive else { return }
      self.renderer?.resume()
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateDrawableSize()
  }

  private func updateDrawableSize() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    drawableSize = Self.drawablePixelSize(for: bounds.size, scale: scale)
    renderer?.resize(toDrawableSize: drawableSize)
  }

  private func observeApplicationLifecycle() {
    let center = NotificationCenter.default
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    lifecycleObservers = [
      (
        center,
        center.addObserver(
          forName: NSApplication.didResignActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.renderer?.suspend() }
      ),
      (
        center,
        center.addObserver(
          forName: NSApplication.didBecomeActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.resumeIfVisible() }
      ),
      (
        center,
        center.addObserver(
          forName: NSWindow.didChangeOcclusionStateNotification,
          object: nil,
          queue: .main
        ) { [weak self] notification in
          guard
            let self,
            let changedWindow = notification.object as? NSWindow,
            changedWindow === self.window
          else { return }
          self.resumeIfVisible()
        }
      ),
      (
        workspaceCenter,
        workspaceCenter.addObserver(
          forName: NSWorkspace.willSleepNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.renderer?.suspend() }
      ),
      (
        workspaceCenter,
        workspaceCenter.addObserver(
          forName: NSWorkspace.didWakeNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.resumeIfVisible() }
      ),
    ]
  }

  private func resumeIfVisible() {
    guard
      NSApp.isActive,
      let window,
      window.occlusionState.contains(.visible)
    else {
      renderer?.suspend()
      return
    }
    renderer?.resume()
  }

  static func drawablePixelSize(for logicalSize: CGSize, scale: CGFloat) -> CGSize {
    CGSize(
      width: max(0, (logicalSize.width * scale).rounded(.up)),
      height: max(0, (logicalSize.height * scale).rounded(.up))
    )
  }
}

import AppKit
import FlutterMacOS
import MetalKit

final class MetalViewportFactory: NSObject, FlutterPlatformViewFactory, FlutterStreamHandler {
  static let viewType = "asterix/metal-viewport"
  static let statsChannel = "asterix/metal-stats"
  static let debugChannel = "asterix/metal-debug"
  private weak var viewport: MetalViewportView?
  private var eventSink: FlutterEventSink?
  private var timer: Timer?
  private var debugMethodChannel: FlutterMethodChannel?

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
    return view
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let stats = self?.viewport?.statistics else { return }
      self?.eventSink?(stats)
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
    ]
  }

  var debugOptions: UInt32 {
    get { renderer?.debugOptions ?? 0 }
    set { renderer?.setDebugOptions(newValue) }
  }

  func loadAssetPackage(at url: URL) {
    // Package parsing and buffer preparation must never stall the UI/render loop.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.renderer?.loadAssetPackage(at: url)
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

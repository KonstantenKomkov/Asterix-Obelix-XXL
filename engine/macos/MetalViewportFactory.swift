import AppKit
import FlutterMacOS
import MetalKit

final class MetalViewportFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "asterix/metal-viewport"

  func create(
    withViewIdentifier viewIdentifier: Int64,
    arguments args: Any?
  ) -> NSView {
    MetalViewportView(frame: .zero)
  }
}

final class MetalViewportView: MTKView {
  private var renderer: AsterixMetalRenderer?
  private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []

  override init(frame frameRect: NSRect, device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    super.init(frame: frameRect, device: device)
    autoresizingMask = [.width, .height]
    autoResizeDrawable = false
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

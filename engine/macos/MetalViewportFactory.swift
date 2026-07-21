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
  override init(frame frameRect: NSRect, device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    super.init(frame: frameRect, device: device)
    autoresizingMask = [.width, .height]
    autoResizeDrawable = false
    framebufferOnly = true
    colorPixelFormat = .bgra8Unorm
    clearColor = MTLClearColor(red: 0.035, green: 0.075, blue: 0.12, alpha: 1)
    updateDrawableSize()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    updateDrawableSize()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateDrawableSize()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateDrawableSize()
  }

  private func updateDrawableSize() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    drawableSize = Self.drawablePixelSize(for: bounds.size, scale: scale)
  }

  static func drawablePixelSize(for logicalSize: CGSize, scale: CGFloat) -> CGSize {
    CGSize(
      width: max(0, (logicalSize.width * scale).rounded(.up)),
      height: max(0, (logicalSize.height * scale).rounded(.up))
    )
  }
}

import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  @MainActor
  func testRendererLifecycleIsIdempotent() {
    let view = MTKView(frame: .zero, device: nil)
    let renderer = AsterixMetalRenderer(view: view)

    XCTAssertEqual(renderer.state.rawValue, 0)
    renderer.resize(toDrawableSize: CGSize(width: 1280, height: 720))
    XCTAssertEqual(renderer.drawableSize, CGSize(width: 1280, height: 720))

    renderer.suspend()
    renderer.suspend()
    XCTAssertEqual(renderer.state.rawValue, 1)
    XCTAssertTrue(view.isPaused)

    renderer.resume()
    XCTAssertEqual(renderer.state.rawValue, 0)
    renderer.stop()
    renderer.stop()
    XCTAssertEqual(renderer.state.rawValue, 2)
    XCTAssertNil(view.delegate)
  }

  @MainActor
  func testStoppedRendererIsReleased() {
    weak var weakRenderer: AsterixMetalRenderer?

    for _ in 0..<100 {
      autoreleasepool {
        let view = MTKView(frame: .zero, device: nil)
        var renderer: AsterixMetalRenderer? = AsterixMetalRenderer(view: view)
        weakRenderer = renderer
        renderer?.stop()
        renderer = nil
      }
      XCTAssertNil(weakRenderer)
    }
  }

  @MainActor
  func testFactoryCreatesMetalViewport() {
    let factory = MetalViewportFactory()
    let view = factory.create(withViewIdentifier: 7, arguments: nil)

    guard let metalView = view as? MetalViewportView else {
      return XCTFail("Factory must create MetalViewportView")
    }
    XCTAssertEqual(metalView.autoResizeDrawable, false)
    XCTAssertEqual(metalView.colorPixelFormat, .bgra8Unorm)
  }

  func testMetalDrawableSizeUsesRetinaScale() {
    let size = MetalViewportView.drawablePixelSize(
      for: CGSize(width: 640, height: 360),
      scale: 2
    )

    XCTAssertEqual(size, CGSize(width: 1280, height: 720))
  }

  func testMetalDrawableSizeRoundsUpFractionalPixels() {
    let size = MetalViewportView.drawablePixelSize(
      for: CGSize(width: 100.25, height: 50.25),
      scale: 2
    )

    XCTAssertEqual(size, CGSize(width: 201, height: 101))
  }
}

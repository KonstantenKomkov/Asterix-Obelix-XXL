import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
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

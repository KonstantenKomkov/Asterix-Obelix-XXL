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
    let systemDevice = MTLCreateSystemDefaultDevice()
    let factory = MetalViewportFactory()
    let view = factory.create(withViewIdentifier: 7, arguments: nil)

    guard let metalView = view as? MetalViewportView else {
      return XCTFail("Factory must create MetalViewportView")
    }
    XCTAssertEqual(metalView.autoResizeDrawable, false)
    XCTAssertEqual(metalView.colorPixelFormat, .bgra8Unorm)
    XCTAssertEqual(metalView.preferredFramesPerSecond, 60)
    XCTAssertEqual(metalView.statistics["frameCount"] as? UInt64, 0)
    XCTAssertEqual(metalView.device == nil, systemDevice == nil)
    if systemDevice != nil {
      XCTAssertEqual(
        metalView.statistics["sceneReady"] as? Bool,
        true,
        metalView.statistics["sceneError"] as? String ?? "missing shader diagnostic"
      )
    }
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

  @MainActor
  func testDebugModesSwitchWithoutRecreatingViewport() {
    let view = MetalViewportView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    view.debugOptions = 0xffff_ffff
    XCTAssertEqual(view.debugOptions, 31)
    XCTAssertEqual(view.statistics["debugOptions"] as? UInt32, 31)
    view.debugOptions = 0
    XCTAssertEqual(view.debugOptions, 0)
  }

  @MainActor
  func testViewportAcceptsBoundedGameplayInput() {
    let view = MetalViewportView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    view.setInput(["moveLeft": 1, "moveRight": 0, "jump": 1, "attack": 0])
    XCTAssertEqual(view.statistics["playerState"] as? String, "unavailable")
    XCTAssertEqual(view.statistics["playerHealth"] as? Int, 0)
  }

  func testMovementSnapshotMapsToBoundedNativeAxesAndButtons() {
    let input = MetalViewportView.gameplayInput(from: [
      "moveLeft": 1, "moveRight": 0, "moveForward": 1,
      "moveBackward": 0, "jump": 1, "attack": 0, "interact": 1,
    ])
    XCTAssertEqual(input.x, -1)
    XCTAssertEqual(input.z, 1)
    XCTAssertTrue(input.jump)
    XCTAssertFalse(input.attack)
    XCTAssertTrue(input.interact)

    let bounded = MetalViewportView.gameplayInput(from: [
      "moveRight": 4, "moveBackward": 3,
    ])
    XCTAssertEqual(bounded.x, 1)
    XCTAssertEqual(bounded.z, -1)
  }

  func testMacOSArrowKeyCodesMapToMovementActions() {
    XCTAssertEqual(MetalViewportView.keyboardAction(keyCode: 123), "moveLeft")
    XCTAssertEqual(MetalViewportView.keyboardAction(keyCode: 124), "moveRight")
    XCTAssertEqual(MetalViewportView.keyboardAction(keyCode: 125), "moveBackward")
    XCTAssertEqual(MetalViewportView.keyboardAction(keyCode: 126), "moveForward")
    XCTAssertNil(MetalViewportView.keyboardAction(keyCode: 49))
  }
}

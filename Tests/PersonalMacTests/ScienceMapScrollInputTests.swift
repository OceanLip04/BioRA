import AppKit
import XCTest
@testable import PersonalMac

final class ScienceMapScrollInputTests: XCTestCase {
    @MainActor func testPointerOutsideCanvasNeverOwnsScrollEvenWithOversizedNativeBounds() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bridge = NSView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(bridge)
        XCTAssertFalse(ScienceMapInputMonitor.Coordinator.ownsScroll(bridge, windowPoint: NSPoint(x: 400, y: 600), pointerInsideCanvas: false))
        XCTAssertTrue(ScienceMapInputMonitor.Coordinator.ownsScroll(bridge, windowPoint: NSPoint(x: 400, y: 300), pointerInsideCanvas: true))
    }

    @MainActor func testCanvasBoundsExcludeToolbarInspectorAndSurroundingPage() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let canvas = NSView(frame: NSRect(x: 100, y: 120, width: 450, height: 300))
        window.contentView!.addSubview(canvas)
        for point in [NSPoint(x: 110, y: 130), NSPoint(x: 500, y: 400)] {
            XCTAssertTrue(ScienceMapInputMonitor.Coordinator.ownsScroll(canvas, windowPoint: point, pointerInsideCanvas: true))
        }
        for point in [NSPoint(x: 110, y: 450), NSPoint(x: 600, y: 300), NSPoint(x: 50, y: 300), NSPoint(x: 110, y: 100)] {
            XCTAssertFalse(ScienceMapInputMonitor.Coordinator.ownsScroll(canvas, windowPoint: point, pointerInsideCanvas: true))
        }
        canvas.isHidden = true
        XCTAssertFalse(ScienceMapInputMonitor.Coordinator.ownsScroll(canvas, windowPoint: NSPoint(x: 110, y: 130), pointerInsideCanvas: true))
    }

    @MainActor func testClippedOffPartOfCanvasCannotSwallowPageScroll() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let clip = NSClipView(frame: NSRect(x: 100, y: 200, width: 450, height: 180))
        window.contentView!.addSubview(clip)
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 550))
        clip.documentView = canvas
        XCTAssertTrue(ScienceMapInputMonitor.Coordinator.ownsScroll(canvas, windowPoint: NSPoint(x: 110, y: 250), pointerInsideCanvas: true))
        XCTAssertFalse(ScienceMapInputMonitor.Coordinator.ownsScroll(canvas, windowPoint: NSPoint(x: 110, y: 450), pointerInsideCanvas: true))
    }

    func testMagicMousePreciseVerticalAndHorizontalPanInScreenPoints() {
        XCTAssertEqual(action(0, 12.5), .pan(CGSize(width: 0, height: 12.5)))
        XCTAssertEqual(action(-8.25, 0), .pan(CGSize(width: -8.25, height: 0)))
        XCTAssertEqual(action(7, -9), .pan(CGSize(width: 7, height: -9)))
    }

    func testSmallMomentumDeltasAndEndEventAreNotDroppedOrRounded() {
        XCTAssertEqual(action(0.08, -0.04), .pan(CGSize(width: 0.08, height: -0.04)))
        XCTAssertEqual(action(0, 0), .pan(.zero))
    }

    func testBothNaturalScrollingDirectionsUseAlreadyAdjustedAppKitDeltas() {
        XCTAssertEqual(action(4, 6), .pan(CGSize(width: 4, height: 6)))
        XCTAssertEqual(action(-4, -6), .pan(CGSize(width: -4, height: -6)))
    }

    func testConventionalWheelScalesLineUnitsAndShiftOffersHorizontalPan() {
        XCTAssertEqual(action(0, -2, precise: false), .pan(CGSize(width: 0, height: -36)))
        XCTAssertEqual(action(0, -2, precise: false, modifiers: .shift), .pan(CGSize(width: -36, height: 0)))
        XCTAssertEqual(action(9, 0, modifiers: .shift), .pan(CGSize(width: 9, height: 0)))
    }

    func testCommandScrollZoomsInsteadOfPanningAndRetainsSensitivity() {
        XCTAssertEqual(action(7, 10, modifiers: .command), .zoom(exp(10 * 0.008)))
        XCTAssertEqual(action(0, -2, precise: false, modifiers: .command), .zoom(exp(-2 * 0.075)))
        XCTAssertEqual(action(8, 0, modifiers: .command), .zoom(1))
    }

    func testExtremeCommandDeltasAreBounded() {
        XCTAssertEqual(action(0, 1000, modifiers: .command), .zoom(exp(24 * 0.008)))
        XCTAssertEqual(action(0, -1000, modifiers: .command), .zoom(exp(-24 * 0.008)))
    }

    func testReservedModifiersAndInvalidDeltasDoNotConsumeEvents() {
        XCTAssertNil(action(2, 3, modifiers: .control))
        XCTAssertNil(action(2, 3, modifiers: [.command, .option]))
        XCTAssertNil(action(.nan, 1))
        XCTAssertNil(action(0, .infinity))
    }

    private func action(_ x: CGFloat, _ y: CGFloat, precise: Bool = true,
                        modifiers: NSEvent.ModifierFlags = []) -> ScienceMapScrollInput.Action? {
        ScienceMapScrollInput.action(deltaX: x, deltaY: y, precise: precise, modifiers: modifiers)
    }
}

import AppKit
import SwiftUI

/// Watches only this map's window and viewport; the view itself never intercepts mouse clicks.
struct ScienceMapInputMonitor: NSViewRepresentable {
    var pointerInsideCanvas: Bool
    var scrollToPan: (CGSize) -> Void
    var scrollToZoom: (CGFloat, CGPoint, Bool) -> Void
    var keyZoom: (CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(pointerInsideCanvas: pointerInsideCanvas, scrollToPan: scrollToPan, scrollToZoom: scrollToZoom, keyZoom: keyZoom) }

    func makeNSView(context: Context) -> NSView {
        let view = PassiveMonitorView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    /// The local event monitors observe input; this view must never take a click from the map.
    private final class PassiveMonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.pointerInsideCanvas = pointerInsideCanvas
        context.coordinator.scrollToPan = scrollToPan
        context.coordinator.scrollToZoom = scrollToZoom
        context.coordinator.keyZoom = keyZoom
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor final class Coordinator {
        weak var view: NSView?
        var pointerInsideCanvas: Bool
        var scrollToPan: (CGSize) -> Void
        var scrollToZoom: (CGFloat, CGPoint, Bool) -> Void
        var keyZoom: (CGFloat, Bool) -> Void
        private var scrollMonitor: Any?
        private var keyMonitor: Any?

        init(pointerInsideCanvas: Bool, scrollToPan: @escaping (CGSize) -> Void,
             scrollToZoom: @escaping (CGFloat, CGPoint, Bool) -> Void,
             keyZoom: @escaping (CGFloat, Bool) -> Void) {
            self.pointerInsideCanvas = pointerInsideCanvas
            self.scrollToPan = scrollToPan
            self.scrollToZoom = scrollToZoom
            self.keyZoom = keyZoom
        }

        func start() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
                return consumed ? nil : event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
                return consumed ? nil : event
            }
        }

        private func handleScroll(_ event: NSEvent) -> Bool {
            guard pointerInsideCanvas, let view, let window = view.window,
                  event.window === window, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty
            else { return false }
            let local = view.convert(event.locationInWindow, from: nil)
            // Only the visible canvas owns scrolling: not the inspector, toolbar,
            // other window, or a clipped-off region inside the reading page.
            guard Self.ownsScroll(view, windowPoint: event.locationInWindow, pointerInsideCanvas: pointerInsideCanvas),
                  let action = ScienceMapScrollInput.action(deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                    modifiers: event.modifierFlags) else { return false }
            switch action {
            case .pan(let delta):
                // AppKit already applies the user's Natural Scrolling preference.
                // Include momentum events unchanged; do not animate or scale by zoom.
                scrollToPan(delta)
            case .zoom(let factor):
                scrollToZoom(factor, CGPoint(x: local.x, y: view.bounds.height - local.y),
                             event.hasPreciseScrollingDeltas)
            }
            return true
        }

        /// SwiftUI hover limits the event to the actual canvas, not a bridge view
        /// whose native bounds may include adjacent page content. Explicitly clip
        /// through every ancestor so an offscreen map cannot swallow page scroll.
        static func ownsScroll(_ view: NSView, windowPoint: NSPoint, pointerInsideCanvas: Bool) -> Bool {
            guard pointerInsideCanvas, view.window != nil, !view.isHiddenOrHasHiddenAncestor,
                  view.visibleRect.contains(view.convert(windowPoint, from: nil)) else { return false }
            var ancestor: NSView? = view
            while let current = ancestor {
                guard current.bounds.contains(current.convert(windowPoint, from: nil)) else { return false }
                ancestor = current.superview
            }
            return true
        }

        private func handleKey(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window,
                  event.window === window, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty,
                  event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control)
            else { return false }
            let direction: CGFloat
            switch event.keyCode {
            case 24, 69: direction = 1 // =/+ and keypad +
            case 27, 78: direction = -1 // - and keypad -
            default: return false
            }
            keyZoom(direction, event.isARepeat)
            return true
        }

        func stop() {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }
    }
}

/// Pure mapping shared by real AppKit events and device-independent regression tests.
enum ScienceMapScrollInput {
    enum Action: Equatable {
        case pan(CGSize)
        case zoom(CGFloat)
    }

    static func action(deltaX: CGFloat, deltaY: CGFloat, precise: Bool,
                       modifiers: NSEvent.ModifierFlags) -> Action? {
        guard deltaX.isFinite, deltaY.isFinite,
              !modifiers.contains(.option), !modifiers.contains(.control) else { return nil }
        if modifiers.contains(.command) {
            let delta = max(-24, min(24, deltaY))
            return .zoom(exp(delta * (precise ? 0.008 : 0.075)))
        }
        // Magic Mouse / trackpad deltas are screen points. Conventional mouse
        // wheels are line units; Shift + a vertical wheel offers horizontal pan.
        let unit: CGFloat = precise ? 1 : 18
        if modifiers.contains(.shift), deltaX == 0 {
            return .pan(CGSize(width: deltaY * unit, height: 0))
        }
        return .pan(CGSize(width: deltaX * unit, height: deltaY * unit))
    }
}

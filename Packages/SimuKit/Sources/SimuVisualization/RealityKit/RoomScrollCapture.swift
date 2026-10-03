#if os(macOS)
import SwiftUI
import AppKit

/// Window- and viewport-scoped wheel handling; dismantle removes the sole local monitor.
@MainActor
struct RoomScrollCapture: NSViewRepresentable {
    let isActive: Bool
    let onScroll: @MainActor (Double) -> Void
    func makeNSView(context: Context) -> ScrollRegion { let view = ScrollRegion(); view.onScroll = onScroll; view.active = isActive; return view }
    func updateNSView(_ nsView: ScrollRegion, context: Context) { nsView.onScroll = onScroll; nsView.active = isActive }
    static func dismantleNSView(_ nsView: ScrollRegion, coordinator: ()) { nsView.stop(); nsView.onScroll = nil }
    @MainActor final class ScrollRegion: NSView {
        var onScroll: (@MainActor (Double) -> Void)?
        var active = true
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.active, let window = self.window, event.window === window,
                          self.bounds.contains(self.convert(event.locationInWindow,from: nil)) else { return false }
                    self.onScroll?(Double(event.scrollingDeltaY)); return true
                }
                return consumed ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
#endif

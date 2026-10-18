import AppKit
import SwiftUI

enum NotchMotion {
    static let headerHeight: CGFloat = 42
    static let duration: TimeInterval = 0.24

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

/// Reveals the surface from the camera's lower edge without resizing its text or editor.
struct NotchReveal: Shape {
    var progress: CGFloat
    let compactWidth: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = min(1, max(0, progress))
        let width = compactWidth + (rect.width - compactWidth) * fraction
        let height = 10 + (rect.height - 10) * fraction
        let radius = 9 + 15 * fraction
        let reveal = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
            .path(in: reveal)
    }
}

/// Keep the hosting view at its expanded size, top-aligned even inside the compact window.
/// Only the window's hit area changes at transition boundaries; animation never reflows text.
final class NotchContainer: NSView {
    let host: NSHostingView<NotchView>
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    var surfaceSize = CGSize(width: 500, height: 430) {
        didSet { needsLayout = true }
    }

    init(host: NSHostingView<NotchView>) {
        self.host = host
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(host)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag]
        if let window {
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            if visibleRect.contains(point) { options.insert(.assumeInside) }
        }
        let tracking = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func layout() {
        super.layout()
        host.frame = CGRect(x: bounds.midX - surfaceSize.width / 2,
                            y: bounds.maxY - surfaceSize.height,
                            width: surfaceSize.width, height: surfaceSize.height)
    }
}

import AppKit

nonisolated struct PanelGeometry {
    let screen: CGRect
    let safeTop: CGFloat
    let notchWidth: CGFloat

    var compactWidth: CGFloat { max(100, notchWidth + 12) }

    func frame(expanded: Bool) -> CGRect {
        let width = expanded ? min(500, screen.width - 32) : compactWidth
        let height: CGFloat = expanded ? min(430, screen.height - safeTop - 40) : 10
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - safeTop - height,
                      width: width, height: height)
    }

    @MainActor init(screen: NSScreen) {
        self.screen = screen.frame
        safeTop = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else {
            notchWidth = 0
        }
    }

    init(screen: CGRect, safeTop: CGFloat, notchWidth: CGFloat) {
        self.screen = screen
        self.safeTop = safeTop
        self.notchWidth = notchWidth
    }
}

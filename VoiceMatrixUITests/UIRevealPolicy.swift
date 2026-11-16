import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Test harness only. Short, non-flinging gestures avoid jumping from below the
// safe viewport to above it and then back, as full-screen swipes can do.
enum UIRevealPolicy {
    static func offset(target: CGRect, viewport: CGRect) -> CGFloat {
        if target.minY > viewport.minY && target.maxY < viewport.maxY { return 0 }
        return min(120, max(-120, target.midY - viewport.midY))
    }
}

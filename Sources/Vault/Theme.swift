import SwiftUI

/// Design tokens. Visual fixes go here, not in the views.
enum Theme {
    static let gap: CGFloat = 12
    static let padding: CGFloat = 24
    static let radius: CGFloat = 8

    static let lockWidth: CGFloat = 280
    static let lockIcon = Font.system(size: 40, weight: .light)
    static let title = Font.title3.weight(.semibold)
    static let caption = Font.callout

    static let thumbRange: ClosedRange<Double> = 80...240
    static let thumbDefault: Double = 128
    static let thumbPixels: CGFloat = 480 // max thumbnail side, 2x the largest slider size
    static let thumbMemory = 200 << 20   // NSCache cost limit in bytes

    static let selection = Color.accentColor.opacity(0.22)
    static let error = Color.red
    static let viewerBackground = Color.black
}

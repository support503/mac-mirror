import CoreGraphics
import Foundation

public struct DisplaySignature: Codable, Hashable, Identifiable, Sendable {
    public var id: String { stableIdentifier }

    public let stableIdentifier: String
    public let displayID: UInt32
    public let localizedName: String
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double
    public let isPrimary: Bool

    public init(
        stableIdentifier: String,
        displayID: UInt32,
        localizedName: String,
        originX: Double,
        originY: Double,
        width: Double,
        height: Double,
        isPrimary: Bool
    ) {
        self.stableIdentifier = stableIdentifier
        self.displayID = displayID
        self.localizedName = localizedName
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.isPrimary = isPrimary
    }

    public var rect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }
}

public struct DisplayMapping: Hashable, Sendable {
    public let saved: DisplaySignature
    public let current: DisplaySignature
    public let usedFallback: Bool

    public init(saved: DisplaySignature, current: DisplaySignature, usedFallback: Bool) {
        self.saved = saved
        self.current = current
        self.usedFallback = usedFallback
    }
}

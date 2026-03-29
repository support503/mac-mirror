import Foundation

public struct RunningApplicationInfo: Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier ?? executablePath ?? displayName }

    public let pid: Int32
    public let bundleIdentifier: String?
    public let displayName: String
    public let executablePath: String?
    public let isHidden: Bool
    public let isActive: Bool

    public init(
        pid: Int32,
        bundleIdentifier: String?,
        displayName: String,
        executablePath: String?,
        isHidden: Bool,
        isActive: Bool
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.executablePath = executablePath
        self.isHidden = isHidden
        self.isActive = isActive
    }
}

public struct DiscoveredWindow: Hashable, Identifiable, Sendable {
    public var id: Int { windowNumber }

    public let pid: Int32
    public let windowNumber: Int
    public let ownerName: String
    public let windowTitle: String?
    public let frame: WindowGeometry
    public let layer: Int
    public let isOnscreen: Bool
    public let displayID: String?
    public let displayName: String?
    public let spaceIndex: Int?

    public init(
        pid: Int32,
        windowNumber: Int,
        ownerName: String,
        windowTitle: String?,
        frame: WindowGeometry,
        layer: Int,
        isOnscreen: Bool,
        displayID: String?,
        displayName: String?,
        spaceIndex: Int?
    ) {
        self.pid = pid
        self.windowNumber = windowNumber
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.frame = frame
        self.layer = layer
        self.isOnscreen = isOnscreen
        self.displayID = displayID
        self.displayName = displayName
        self.spaceIndex = spaceIndex
    }
}

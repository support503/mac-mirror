import Foundation

public struct Snapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let machineIdentifier: String
    public var createdAt: Date
    public var updatedAt: Date
    public var displaySignatures: [DisplaySignature]
    public var windowTargets: [WindowTarget]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        machineIdentifier: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        displaySignatures: [DisplaySignature],
        windowTargets: [WindowTarget],
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.machineIdentifier = machineIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displaySignatures = displaySignatures
        self.windowTargets = windowTargets
        self.notes = notes
    }
}

public enum WindowTargetKind: String, Codable, Hashable, Sendable {
    case chromeProfile
    case applicationWindow
}

public struct WindowGeometry: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var maximized: Bool

    public init(x: Double, y: Double, width: Double, height: Double, maximized: Bool = false) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.maximized = maximized
    }
}

public struct WindowTarget: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var kind: WindowTargetKind
    public var applicationName: String
    public var bundleIdentifier: String
    public var executablePath: String?
    public var chromeProfileID: String?
    public var chromeProfileName: String?
    public var windowTitle: String?
    public var launchOrder: Int
    public var geometry: WindowGeometry
    public var targetDisplayID: String
    public var targetDisplayName: String
    public var targetSpaceIndex: Int
    public var isHidden: Bool
    public var isMinimized: Bool

    public init(
        id: UUID = UUID(),
        kind: WindowTargetKind,
        applicationName: String,
        bundleIdentifier: String,
        executablePath: String?,
        chromeProfileID: String?,
        chromeProfileName: String?,
        windowTitle: String?,
        launchOrder: Int,
        geometry: WindowGeometry,
        targetDisplayID: String,
        targetDisplayName: String,
        targetSpaceIndex: Int,
        isHidden: Bool,
        isMinimized: Bool
    ) {
        self.id = id
        self.kind = kind
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.chromeProfileID = chromeProfileID
        self.chromeProfileName = chromeProfileName
        self.windowTitle = windowTitle
        self.launchOrder = launchOrder
        self.geometry = geometry
        self.targetDisplayID = targetDisplayID
        self.targetDisplayName = targetDisplayName
        self.targetSpaceIndex = targetSpaceIndex
        self.isHidden = isHidden
        self.isMinimized = isMinimized
    }
}

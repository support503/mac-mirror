import Foundation

public struct AppSelection: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }

    public let bundleIdentifier: String
    public var displayName: String
    public var executablePath: String?

    public init(bundleIdentifier: String, displayName: String, executablePath: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.executablePath = executablePath
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var selectedApplications: [AppSelection]
    public var pinnedSnapshotID: UUID?
    public var launchAtLoginEnabled: Bool
    public var lastSavedSnapshotID: UUID?

    public init(
        selectedApplications: [AppSelection] = [],
        pinnedSnapshotID: UUID? = nil,
        launchAtLoginEnabled: Bool = false,
        lastSavedSnapshotID: UUID? = nil
    ) {
        self.selectedApplications = selectedApplications
        self.pinnedSnapshotID = pinnedSnapshotID
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.lastSavedSnapshotID = lastSavedSnapshotID
    }
}

import Foundation

public final class SnapshotStore: Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func listSnapshots() throws -> [Snapshot] {
        try AppSupportPaths.ensureDirectoriesExist()
        let files = try FileManager.default.contentsOfDirectory(
            at: AppSupportPaths.snapshotsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return try files.map(loadSnapshot(at:)).sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func saveSnapshot(_ snapshot: Snapshot) throws {
        try AppSupportPaths.ensureDirectoriesExist()
        let url = AppSupportPaths.snapshotsDirectory.appendingPathComponent("\(snapshot.id.uuidString).json")
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func loadSnapshot(idOrName: String) throws -> Snapshot {
        let snapshots = try listSnapshots()
        if let uuid = UUID(uuidString: idOrName),
           let snapshot = snapshots.first(where: { $0.id == uuid }) {
            return snapshot
        }

        if let snapshot = snapshots.first(where: { $0.name.caseInsensitiveCompare(idOrName) == .orderedSame }) {
            return snapshot
        }

        throw MacMirrorError.snapshotNotFound(idOrName)
    }

    public func loadPinnedSnapshot() throws -> Snapshot {
        let settings = try loadSettings()
        guard let pinnedSnapshotID = settings.pinnedSnapshotID else {
            throw MacMirrorError.noPinnedSnapshot
        }
        return try loadSnapshot(idOrName: pinnedSnapshotID.uuidString)
    }

    public func deleteSnapshot(idOrName: String) throws {
        let snapshot = try loadSnapshot(idOrName: idOrName)
        let url = AppSupportPaths.snapshotsDirectory.appendingPathComponent("\(snapshot.id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }

    public func pinSnapshot(idOrName: String) throws {
        let snapshot = try loadSnapshot(idOrName: idOrName)
        var settings = try loadSettings()
        settings.pinnedSnapshotID = snapshot.id
        try saveSettings(settings)
    }

    public func exportSnapshot(idOrName: String, to destination: URL) throws {
        let snapshot = try loadSnapshot(idOrName: idOrName)
        let data = try encoder.encode(snapshot)
        try data.write(to: destination, options: .atomic)
    }

    public func importSnapshot(from source: URL) throws -> Snapshot {
        let data = try Data(contentsOf: source)
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        try saveSnapshot(snapshot)
        return snapshot
    }

    public func loadSettings() throws -> AppSettings {
        try AppSupportPaths.ensureDirectoriesExist()
        guard FileManager.default.fileExists(atPath: AppSupportPaths.settingsFile.path) else {
            return AppSettings()
        }
        let data = try Data(contentsOf: AppSupportPaths.settingsFile)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try AppSupportPaths.ensureDirectoriesExist()
        let data = try encoder.encode(settings)
        try data.write(to: AppSupportPaths.settingsFile, options: .atomic)
    }

    private func loadSnapshot(at url: URL) throws -> Snapshot {
        let data = try Data(contentsOf: url)
        return try decoder.decode(Snapshot.self, from: data)
    }
}

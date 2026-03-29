import Foundation

public struct ChromeSessionWindowMetadata: Hashable, Sendable {
    public let profileDirectory: String
    public let windowNumber: Int
    public let windowTitle: String?
    public let frame: WindowGeometry?
    public let workspaceUUID: String?
    public let screenLayoutUUID: String?

    public init(
        profileDirectory: String,
        windowNumber: Int,
        windowTitle: String?,
        frame: WindowGeometry?,
        workspaceUUID: String?,
        screenLayoutUUID: String?
    ) {
        self.profileDirectory = profileDirectory
        self.windowNumber = windowNumber
        self.windowTitle = windowTitle
        self.frame = frame
        self.workspaceUUID = workspaceUUID
        self.screenLayoutUUID = screenLayoutUUID
    }
}

public final class ChromeSessionMetadataService: Sendable {
    private let chromeSupportDirectory: URL

    public init(
        chromeSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    ) {
        self.chromeSupportDirectory = chromeSupportDirectory
    }

    public func discoverWindowMetadata(profileDirectories: [String]) -> [ChromeSessionWindowMetadata] {
        profileDirectories.compactMap { profileDirectory in
            do {
                return try loadWindowMetadata(profileDirectory: profileDirectory)
            } catch {
                Logger.log("Chrome session metadata parse failed for \(profileDirectory): \(error.localizedDescription)")
                return nil
            }
        }
    }

    public func loadWindowMetadata(profileDirectory: String) throws -> ChromeSessionWindowMetadata? {
        guard let sessionURL = try latestSessionURL(for: profileDirectory) else {
            return nil
        }
        let data = try Data(contentsOf: sessionURL)
        return try parseSessionData(data, profileDirectory: profileDirectory)
    }

    func parseSessionData(_ data: Data, profileDirectory: String) throws -> ChromeSessionWindowMetadata? {
        for archivedData in extractArchivedPlistCandidates(from: data) {
            guard
                let plist = try? PropertyListSerialization.propertyList(from: archivedData, format: nil),
                let metadata = parseArchivedPlist(plist, profileDirectory: profileDirectory)
            else {
                continue
            }
            return metadata
        }
        return nil
    }

    private func latestSessionURL(for profileDirectory: String) throws -> URL? {
        let sessionsDirectory = chromeSupportDirectory
            .appendingPathComponent(profileDirectory, isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)

        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
            return nil
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix("Session_") }

        return try urls.max { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private func extractArchivedPlistCandidates(from data: Data) -> [Data] {
        let text = String(decoding: data, as: UTF8.self)
        let regex = try? NSRegularExpression(pattern: "YnBsaXN0MDD[A-Za-z0-9+/=]+")
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let matches = regex?.matches(in: text, range: fullRange) ?? []

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return Data(base64Encoded: String(text[range]))
        }
    }

    private func parseArchivedPlist(_ plist: Any, profileDirectory: String) -> ChromeSessionWindowMetadata? {
        guard
            let dictionary = plist as? [String: Any],
            let reader = KeyedArchiveReader(dictionary: dictionary),
            let windowNumber = reader.top["NSWindowNumber"] as? NSNumber
        else {
            return nil
        }

        let primaryLayout = readLayoutPair(reader: reader, topKey: "_NSWindowLastUserWindowLayouts")
            ?? readLayoutPair(reader: reader, topKey: "_NSWindowLayouts")

        return ChromeSessionWindowMetadata(
            profileDirectory: profileDirectory,
            windowNumber: windowNumber.intValue,
            windowTitle: reader.string(forTopKey: "NSTitle"),
            frame: primaryLayout?.frame,
            workspaceUUID: reader.normalizedString(forTopKey: "NSWindowWorkspaceID"),
            screenLayoutUUID: primaryLayout?.screenLayoutUUID
        )
    }

    private func readLayoutPair(reader: KeyedArchiveReader, topKey: String) -> (frame: WindowGeometry?, screenLayoutUUID: String?)? {
        let pairs = reader.dictionaryPairs(fromTopKey: topKey)
        for pair in pairs {
            let frame = parseWindowFrame(from: reader.normalizedString(from: pair.value["NSWindowLayoutWindowFrame"]))
            let screenLayoutUUID = reader.normalizedString(from: pair.key["NSScreenLayoutUUIDString"])
            if frame != nil || screenLayoutUUID != nil {
                return (frame, screenLayoutUUID)
            }
        }
        return nil
    }

    private func parseWindowFrame(from value: String?) -> WindowGeometry? {
        guard let value else {
            return nil
        }

        let pattern = #"\{\{\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\},\s*\{\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\}\}"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)),
            let x = Double(value.nsRange(match.range(at: 1))),
            let y = Double(value.nsRange(match.range(at: 2))),
            let width = Double(value.nsRange(match.range(at: 3))),
            let height = Double(value.nsRange(match.range(at: 4)))
        else {
            return nil
        }

        return WindowGeometry(x: x, y: y, width: width, height: height)
    }
}

private struct KeyedArchiveReader {
    let top: [String: Any]
    let objects: [Any]

    init?(dictionary: [String: Any]) {
        guard
            let top = dictionary["$top"] as? [String: Any],
            let objects = dictionary["$objects"] as? [Any]
        else {
            return nil
        }
        self.top = top
        self.objects = objects
    }

    func string(forTopKey key: String) -> String? {
        normalizedString(from: top[key])
    }

    func normalizedString(forTopKey key: String) -> String? {
        normalizedString(from: top[key])
    }

    func normalizedString(from rawValue: Any?) -> String? {
        guard let value = dereference(rawValue) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func dictionaryPairs(fromTopKey key: String) -> [(key: [String: Any], value: [String: Any])] {
        dictionaryPairs(from: top[key])
    }

    func dictionaryPairs(from rawValue: Any?) -> [(key: [String: Any], value: [String: Any])] {
        guard let dictionary = dereference(rawValue) as? [String: Any] else {
            return []
        }

        let keys = dictionary["NS.keys"] as? [Any] ?? []
        let values = dictionary["NS.objects"] as? [Any] ?? []
        return zip(keys, values).compactMap { keyValue, objectValue in
            guard
                let keyDictionary = dereference(keyValue) as? [String: Any],
                let valueDictionary = dereference(objectValue) as? [String: Any]
            else {
                return nil
            }
            return (keyDictionary, valueDictionary)
        }
    }

    func dereference(_ rawValue: Any?) -> Any? {
        guard let rawValue else {
            return nil
        }
        guard let index = uidIndex(from: rawValue) else {
            return rawValue
        }
        guard objects.indices.contains(index) else {
            return nil
        }
        return objects[index]
    }

    private func uidIndex(from value: Any) -> Int? {
        let description = String(describing: value)
        guard description.contains("CFKeyedArchiverUID") else {
            return nil
        }

        let pattern = #"value = (\d+)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: description, range: NSRange(location: 0, length: description.utf16.count))
        else {
            return nil
        }

        return Int(description.nsRange(match.range(at: 1)))
    }
}

private extension String {
    func nsRange(_ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: self) else {
            return ""
        }
        return String(self[swiftRange])
    }
}

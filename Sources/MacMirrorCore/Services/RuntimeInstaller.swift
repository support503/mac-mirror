import Foundation

public struct InstalledRuntime: Sendable {
    public let cliURL: URL?
    public let loginHelperURL: URL?
}

public final class RuntimeInstaller: Sendable {
    public init() {}

    public func installSiblingToolsIfAvailable(from executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])) throws -> InstalledRuntime {
        try AppSupportPaths.ensureDirectoriesExist()
        let sourceDirectory = executableURL.deletingLastPathComponent()

        let cliURL = try copyIfPresent(named: "mac-mirror", from: sourceDirectory)
        let loginURL = try copyIfPresent(named: "mac-mirror-login", from: sourceDirectory)
        return InstalledRuntime(cliURL: cliURL, loginHelperURL: loginURL)
    }

    private func copyIfPresent(named binaryName: String, from directory: URL) throws -> URL? {
        let source = directory.appendingPathComponent(binaryName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return nil
        }

        let destination = AppSupportPaths.binDirectory.appendingPathComponent(binaryName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }
}

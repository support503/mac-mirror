import Foundation

public enum AppMetadata {
    public static let repositoryOwner = "support503"
    public static let repositoryName = "mac-mirror"
    public static let repositoryURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    public static let releasesURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases")!

    public static var version: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           version.isEmpty == false {
            return version
        }
        if let version = ProcessInfo.processInfo.environment["MAC_MIRROR_VERSION"], version.isEmpty == false {
            return version
        }
        return "dev"
    }

    public static var build: String {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           build.isEmpty == false {
            return build
        }
        if let build = ProcessInfo.processInfo.environment["MAC_MIRROR_BUILD"], build.isEmpty == false {
            return build
        }
        return "0"
    }

    public static var versionDescription: String {
        "\(version) (\(build))"
    }
}

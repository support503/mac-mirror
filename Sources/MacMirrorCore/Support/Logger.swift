import Foundation

public enum Logger {
    public static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: .now))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try AppSupportPaths.ensureDirectoriesExist()
            if FileManager.default.fileExists(atPath: AppSupportPaths.runtimeLogFile.path) == false {
                FileManager.default.createFile(atPath: AppSupportPaths.runtimeLogFile.path, contents: data)
            } else {
                let handle = try FileHandle(forWritingTo: AppSupportPaths.runtimeLogFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
        } catch {
            fputs("MacMirror log failure: \(error)\n", stderr)
        }
    }
}

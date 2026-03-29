import Foundation

public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum Shell {
    @discardableResult
    public static func run(
        _ launchPath: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> ShellResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

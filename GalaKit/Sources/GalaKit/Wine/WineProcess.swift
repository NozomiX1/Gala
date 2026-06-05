import Foundation

public final class WineProcess: ObservableObject, @unchecked Sendable {
    private var process: Process?

    @Published public var isRunning = false
    @Published public var lastOutput: String = ""

    public init() {}

    public func launch(
        game: Game,
        wineBinary: URL,
        mediaFoundationRuntime: MediaFoundationRuntime? = nil,
        onTermination: @escaping @Sendable (TimeInterval, Int32, String) -> Void
    ) throws {
        guard !isRunning else { return }

        let launchConfig = try WineLaunchConfig.resolve(game: game)

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = launchConfig.arguments
        if let workingDir = launchConfig.workingDirectory {
            process.currentDirectoryURL = workingDir
        }

        process.environment = WineLaunchConfig.buildEnvironment(
            game: game,
            wineBinary: wineBinary,
            mediaFoundationRuntime: mediaFoundationRuntime
        )

        // Write process output to a temp file instead of inheriting stdout/stderr
        // or using a Pipe. Wine and MoltenVK can produce very large logs; inheriting
        // stdout floods the host app console, and pipes can deadlock on full buffers.
        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gala-wine-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputFile)
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        let startTime = Date()

        process.terminationHandler = { [weak self] proc in
            Self.waitForWineDescendants(wineBinary: wineBinary, environment: process.environment)

            let duration = Date().timeIntervalSince(startTime)
            let terminationStatus = proc.terminationStatus
            outputHandle.closeFile()

            let tail = Self.logTail(from: outputFile, limit: 500)
            if !tail.isEmpty {
                DispatchQueue.main.async {
                    self?.lastOutput = tail
                }
            }
            try? FileManager.default.removeItem(at: outputFile)
            DispatchQueue.main.async {
                self?.isRunning = false
            }
            onTermination(duration, terminationStatus, tail)
        }

        try process.run()
        self.process = process

        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func launchNative(
        path: String,
        onTermination: @escaping @Sendable (TimeInterval, Int32, String) -> Void
    ) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", path]

        let startTime = Date()

        process.terminationHandler = { [weak self] proc in
            let duration = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self?.isRunning = false
            }
            onTermination(duration, proc.terminationStatus, "")
        }

        try process.run()
        self.process = process

        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func terminate() {
        process?.terminate()
    }

    public static func wineserverURL(for wineBinary: URL) -> URL? {
        let url = wineBinary
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public static func logTail(from url: URL, limit: Int) -> String {
        guard limit > 0,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(UInt64(limit), fileSize)
        try? handle.seek(toOffset: fileSize - readSize)

        let data = handle.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return ""
        }
        return String(output.suffix(limit))
    }

    private static func waitForWineDescendants(wineBinary: URL, environment: [String: String]?) {
        guard let wineserver = wineserverURL(for: wineBinary) else { return }

        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-w"]
        process.environment = environment

        if let null = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null")) {
            process.standardOutput = null
            process.standardError = null
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}

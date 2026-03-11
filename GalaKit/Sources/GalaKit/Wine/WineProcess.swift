import Foundation

public final class WineProcess: ObservableObject, @unchecked Sendable {
    private var process: Process?

    @Published public var isRunning = false
    @Published public var lastOutput: String = ""

    public init() {}

    public func launch(
        game: Game,
        wineBinary: URL,
        onTermination: @escaping @Sendable (TimeInterval) -> Void
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
            game: game, wineBinary: wineBinary
        )

        // Write stderr to a temp file instead of a Pipe to avoid deadlocks.
        // Pipes have a 64KB buffer; when Wine + child processes fill it, they block.
        // Files have no such limit.
        let stderrFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gala-wine-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrFile)
        process.standardError = stderrHandle

        let startTime = Date()

        process.terminationHandler = { [weak self] proc in
            let duration = Date().timeIntervalSince(startTime)
            stderrHandle.closeFile()
            // Read last 500 chars of stderr for diagnostics
            if let data = try? Data(contentsOf: stderrFile),
               let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let tail = String(output.suffix(500))
                DispatchQueue.main.async {
                    self?.lastOutput = tail
                }
            }
            try? FileManager.default.removeItem(at: stderrFile)
            DispatchQueue.main.async {
                self?.isRunning = false
            }
            onTermination(duration)
        }

        try process.run()
        self.process = process

        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func launchNative(
        path: String,
        onTermination: @escaping @Sendable (TimeInterval) -> Void
    ) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", path]

        let startTime = Date()

        process.terminationHandler = { [weak self] _ in
            let duration = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self?.isRunning = false
            }
            onTermination(duration)
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
}

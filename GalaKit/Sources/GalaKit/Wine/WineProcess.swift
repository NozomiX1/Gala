import Foundation

public final class WineProcess: ObservableObject, @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?

    @Published public var isRunning = false
    @Published public var lastOutput: String = ""

    public init() {}

    public func launch(
        game: Game,
        wineBinary: URL,
        onTermination: @escaping @Sendable (TimeInterval) -> Void
    ) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = game.bottleConfig.launchArguments + [game.executablePath]
        process.currentDirectoryURL = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()

        var env: [String: String] = [
            "WINEPREFIX": game.bottleConfig.prefixPath,
            "LANG": game.bottleConfig.locale,
            "LC_ALL": game.bottleConfig.locale,
        ]
        // Merge DLL overrides into WINEDLLOVERRIDES env var
        if !game.bottleConfig.dllOverrides.isEmpty {
            let overrides = game.bottleConfig.dllOverrides.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            env["WINEDLLOVERRIDES"] = overrides
        }
        for (key, value) in game.bottleConfig.environment {
            env[key] = value
        }
        process.environment = env

        // Capture stderr for diagnostics
        let pipe = Pipe()
        process.standardError = pipe
        self.outputPipe = pipe

        let startTime = Date()

        process.terminationHandler = { [weak self] proc in
            let duration = Date().timeIntervalSince(startTime)
            // Read output for diagnostics
            if let data = try? pipe.fileHandleForReading.availableData,
               let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self?.lastOutput = output
                }
            }
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

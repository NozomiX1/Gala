# Gala Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS-native galgame launcher that wraps GPTK Wine with automatic Japanese environment setup, engine detection, VNDB integration, and play time tracking.

**Architecture:** SwiftUI app (Gala) + Swift Package (GalaKit). MVVM pattern. GalaKit contains all core logic (Wine management, engine detection, VNDB client, persistence). The app layer is pure UI. JSON file persistence via Codable.

**Tech Stack:** Swift, SwiftUI (macOS 14+), Foundation.Process, URLSession, JSONEncoder/Decoder

**Design doc:** `docs/plans/2026-03-11-gala-design.md`

---

## Task 1: Xcode Project + GalaKit Package Scaffold

**Files:**
- Create: Xcode project `Gala.xcodeproj` with SwiftUI app target (macOS 14+)
- Create: `GalaKit/Package.swift`
- Create: `GalaKit/Sources/GalaKit/GalaKit.swift` (placeholder export)
- Create: `GalaKit/Tests/GalaKitTests/GalaKitTests.swift`

**Step 1: Create Xcode project**

Use `swift package init` for GalaKit, then create the Xcode project.

```bash
cd /Users/nozomi/Downloads/lab/Gala
mkdir -p GalaKit/Sources/GalaKit
mkdir -p GalaKit/Tests/GalaKitTests
```

**Step 2: Create GalaKit Package.swift**

```swift
// GalaKit/Package.swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GalaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GalaKit", targets: ["GalaKit"]),
    ],
    targets: [
        .target(name: "GalaKit"),
        .testTarget(name: "GalaKitTests", dependencies: ["GalaKit"]),
    ]
)
```

**Step 3: Create Xcode project with SwiftUI app**

Create the Xcode project via Xcode or manually. The app target must:
- Set deployment target to macOS 14.0
- Add GalaKit as a local Swift Package dependency
- Use SwiftUI App lifecycle

Create minimal `Gala/GalaApp.swift`:

```swift
import SwiftUI

@main
struct GalaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Create minimal `Gala/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Gala")
            .frame(minWidth: 800, minHeight: 500)
    }
}
```

**Step 4: Verify build**

Run: `xcodebuild -project Gala.xcodeproj -scheme Gala build` or build in Xcode.
Expected: Clean build, app launches showing "Gala" text.

**Step 5: Run GalaKit tests**

Run: `cd GalaKit && swift test`
Expected: 0 tests, build succeeds.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold Xcode project and GalaKit package"
```

---

## Task 2: Data Models

**Files:**
- Create: `GalaKit/Sources/GalaKit/Models/Game.swift`
- Create: `GalaKit/Sources/GalaKit/Models/BottleConfig.swift`
- Create: `GalaKit/Sources/GalaKit/Models/Engine.swift`
- Create: `GalaKit/Tests/GalaKitTests/ModelsTests.swift`

**Step 1: Write tests for model serialization**

```swift
// GalaKit/Tests/GalaKitTests/ModelsTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func gameRoundTripsJSON() throws {
    let game = Game(
        title: "Fate/stay night",
        originalTitle: "Fate/stay night",
        executablePath: "/path/to/fate.exe"
    )

    let data = try JSONEncoder().encode(game)
    let decoded = try JSONDecoder().decode(Game.self, from: data)

    #expect(decoded.title == "Fate/stay night")
    #expect(decoded.originalTitle == "Fate/stay night")
    #expect(decoded.executablePath == "/path/to/fate.exe")
    #expect(decoded.totalPlayTime == 0)
    #expect(decoded.status == .backlog)
    #expect(decoded.engine == nil)
    #expect(decoded.bottleConfig.locale == "ja_JP.UTF-8")
}

@Test func engineHasPreset() {
    let preset = Engine.kirikiri.preset
    #expect(preset.components.contains("quartz"))
    #expect(preset.components.contains("lavfilters"))
    #expect(preset.dllOverrides["quartz"] == "native")
}

@Test func enginePresetForUnknownIsBaseOnly() {
    let preset = Engine.unknown.preset
    #expect(preset.components.isEmpty)
    #expect(preset.dllOverrides.isEmpty)
}

@Test func bottleConfigDefaults() {
    let config = BottleConfig(prefixPath: "/tmp/test")
    #expect(config.locale == "ja_JP.UTF-8")
    #expect(config.windowsVersion == .win10)
    #expect(config.dllOverrides.isEmpty)
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`
Expected: Compilation errors (types not defined yet).

**Step 3: Implement Engine**

```swift
// GalaKit/Sources/GalaKit/Models/Engine.swift
import Foundation

public enum Engine: String, Codable, CaseIterable, Sendable {
    case kirikiri, nscripter, renpy, rpgMaker, unity
    case bgi, catSystem2, siglusEngine, artemis, yuris
    case majiro, advHD, realLive, qlie, unknown
}

public struct EnginePreset: Sendable {
    public let components: [String]
    public let dllOverrides: [String: String]

    public static let empty = EnginePreset(components: [], dllOverrides: [:])
}

extension Engine {
    public var preset: EnginePreset {
        switch self {
        case .kirikiri:
            return EnginePreset(
                components: ["quartz", "amstream", "lavfilters"],
                dllOverrides: ["quartz": "native"]
            )
        case .bgi:
            return EnginePreset(
                components: ["quartz", "amstream", "lavfilters"],
                dllOverrides: [:]
            )
        case .catSystem2:
            return EnginePreset(
                components: ["dotnet40", "quartz", "vcrun2015"],
                dllOverrides: [:]
            )
        case .siglusEngine:
            return EnginePreset(
                components: ["quartz", "amstream", "lavfilters", "xact", "xinput", "vcrun2019"],
                dllOverrides: ["xaudio2_7": "native", "xactengine3_7": "native"]
            )
        case .rpgMaker:
            return EnginePreset(
                components: ["d3dx9"],
                dllOverrides: [:]
            )
        case .unity:
            return EnginePreset(
                components: ["dotnet48", "d3dcompiler_47"],
                dllOverrides: [:]
            )
        case .nscripter, .renpy, .artemis, .yuris, .majiro, .advHD, .realLive, .qlie, .unknown:
            return .empty
        }
    }

    public var displayName: String {
        switch self {
        case .kirikiri: return "KiriKiri"
        case .nscripter: return "NScripter"
        case .renpy: return "Ren'Py"
        case .rpgMaker: return "RPG Maker"
        case .unity: return "Unity"
        case .bgi: return "BGI/Ethornell"
        case .catSystem2: return "CatSystem2"
        case .siglusEngine: return "SiglusEngine"
        case .artemis: return "Artemis Engine"
        case .yuris: return "YU-RIS"
        case .majiro: return "Majiro"
        case .advHD: return "AdvHD"
        case .realLive: return "RealLive"
        case .qlie: return "QLIE"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this engine can potentially run natively on macOS without Wine
    public var supportsNativeLaunch: Bool {
        switch self {
        case .renpy, .rpgMaker, .unity: return true
        default: return false
        }
    }
}
```

**Step 4: Implement BottleConfig**

```swift
// GalaKit/Sources/GalaKit/Models/BottleConfig.swift
import Foundation

public enum WinVersion: String, Codable, CaseIterable, Sendable {
    case win7 = "win7"
    case win10 = "win10"
    case win11 = "win11"
}

public struct BottleConfig: Codable, Sendable {
    public var prefixPath: String
    public var windowsVersion: WinVersion
    public var dllOverrides: [String: String]
    public var environment: [String: String]
    public var launchArguments: [String]
    public var locale: String
    public var winetricksComponents: [String]

    public init(
        prefixPath: String,
        windowsVersion: WinVersion = .win10,
        dllOverrides: [String: String] = [:],
        environment: [String: String] = [:],
        launchArguments: [String] = [],
        locale: String = "ja_JP.UTF-8",
        winetricksComponents: [String] = []
    ) {
        self.prefixPath = prefixPath
        self.windowsVersion = windowsVersion
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.launchArguments = launchArguments
        self.locale = locale
        self.winetricksComponents = winetricksComponents
    }
}
```

**Step 5: Implement Game**

```swift
// GalaKit/Sources/GalaKit/Models/Game.swift
import Foundation

public enum GameStatus: String, Codable, CaseIterable, Sendable {
    case backlog, playing, completed, dropped
}

public struct Game: Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var originalTitle: String?
    public var vndbId: String?
    public var executablePath: String
    public var coverImagePath: String?
    public var engine: Engine?
    public var totalPlayTime: TimeInterval
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var rating: Double?
    public var developer: String?
    public var releasedAt: String?
    public var description: String?
    public var tags: [String]
    public var status: GameStatus
    public var bottleConfig: BottleConfig

    public init(
        id: UUID = UUID(),
        title: String,
        originalTitle: String? = nil,
        vndbId: String? = nil,
        executablePath: String,
        coverImagePath: String? = nil,
        engine: Engine? = nil,
        totalPlayTime: TimeInterval = 0,
        lastPlayedAt: Date? = nil,
        addedAt: Date = Date(),
        rating: Double? = nil,
        developer: String? = nil,
        releasedAt: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        status: GameStatus = .backlog,
        bottleConfig: BottleConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.vndbId = vndbId
        self.executablePath = executablePath
        self.coverImagePath = coverImagePath
        self.engine = engine
        self.totalPlayTime = totalPlayTime
        self.lastPlayedAt = lastPlayedAt
        self.addedAt = addedAt
        self.rating = rating
        self.developer = developer
        self.releasedAt = releasedAt
        self.description = description
        self.tags = tags
        self.status = status
        self.bottleConfig = bottleConfig ?? BottleConfig(prefixPath: "")
    }
}
```

**Step 6: Create GalaKit export**

```swift
// GalaKit/Sources/GalaKit/GalaKit.swift
// Re-export all public types
```

**Step 7: Run tests**

Run: `cd GalaKit && swift test`
Expected: All 4 tests pass.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Game, BottleConfig, Engine data models with tests"
```

---

## Task 3: LibraryStore (JSON Persistence)

**Files:**
- Create: `GalaKit/Sources/GalaKit/Library/LibraryStore.swift`
- Create: `GalaKit/Tests/GalaKitTests/LibraryStoreTests.swift`

**Step 1: Write tests**

```swift
// GalaKit/Tests/GalaKitTests/LibraryStoreTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func loadEmptyLibrary() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)
    let games = try store.load()
    #expect(games.isEmpty)
}

@Test func saveAndLoadGames() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)

    var game = Game(title: "Test Game", executablePath: "/test.exe")
    game.totalPlayTime = 3600
    game.engine = .kirikiri

    try store.save([game])
    let loaded = try store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].title == "Test Game")
    #expect(loaded[0].totalPlayTime == 3600)
    #expect(loaded[0].engine == .kirikiri)
}

@Test func addAndRemoveGame() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)

    let game1 = Game(title: "Game 1", executablePath: "/g1.exe")
    let game2 = Game(title: "Game 2", executablePath: "/g2.exe")

    try store.save([game1, game2])
    var games = try store.load()
    #expect(games.count == 2)

    games.removeAll { $0.id == game1.id }
    try store.save(games)
    let reloaded = try store.load()
    #expect(reloaded.count == 1)
    #expect(reloaded[0].title == "Game 2")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`
Expected: Compilation errors.

**Step 3: Implement LibraryStore**

```swift
// GalaKit/Sources/GalaKit/Library/LibraryStore.swift
import Foundation

public final class LibraryStore: Sendable {
    private let libraryFileURL: URL

    public init(baseURL: URL) {
        self.libraryFileURL = baseURL.appendingPathComponent("library.json")
    }

    public func load() throws -> [Game] {
        guard FileManager.default.fileExists(atPath: libraryFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: libraryFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Game].self, from: data)
    }

    public func save(_ games: [Game]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(games)
        try data.write(to: libraryFileURL, options: .atomic)
    }
}
```

**Step 4: Run tests**

Run: `cd GalaKit && swift test`
Expected: All tests pass (including previous model tests).

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add LibraryStore for JSON persistence"
```

---

## Task 4: Engine Detector

**Files:**
- Create: `GalaKit/Sources/GalaKit/Engine/EngineDetector.swift`
- Create: `GalaKit/Tests/GalaKitTests/EngineDetectorTests.swift`

**Step 1: Write tests**

Create temporary directories with engine-specific files to test detection.

```swift
// GalaKit/Tests/GalaKitTests/EngineDetectorTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func detectKiriKiriByXP3() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Create a fake data.xp3 file
    FileManager.default.createFile(atPath: dir.appendingPathComponent("data.xp3").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .kirikiri)
}

@Test func detectRenPyByDirectory() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let renpyDir = dir.appendingPathComponent("renpy")
    try FileManager.default.createDirectory(at: renpyDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .renpy)
}

@Test func detectUnityByDLL() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("UnityPlayer.dll").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .unity)
}

@Test func detectRPGMakerByRGSSDLL() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("RGSS301.dll").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("Game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .rpgMaker)
}

@Test func detectXP3ByMagicBytes() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // XP3 magic: 58 50 33 0D 0A 1A 08 00
    let xp3Magic = Data([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x08, 0x00])
    try xp3Magic.write(to: dir.appendingPathComponent("archive.dat"))
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .kirikiri)
}

@Test func detectUnknownForEmptyDir() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == nil)
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`
Expected: Compilation errors.

**Step 3: Implement EngineDetector**

```swift
// GalaKit/Sources/GalaKit/Engine/EngineDetector.swift
import Foundation

public enum EngineDetector {

    // MARK: - Public API

    /// Detect game engine by scanning the game directory.
    /// Returns nil if no engine could be identified.
    public static func detect(in directory: URL) -> Engine? {
        if let engine = detectByUniqueFiles(in: directory) { return engine }
        if let engine = detectByMagicBytes(in: directory) { return engine }
        if let engine = detectByDLLNames(in: directory) { return engine }
        return nil
    }

    // MARK: - Layer 1: Unique file/directory names

    private static func detectByUniqueFiles(in directory: URL) -> Engine? {
        let fm = FileManager.default

        // Check for directories
        if fm.fileExists(atPath: directory.appendingPathComponent("renpy").path) {
            return .renpy
        }

        // Check for unique files
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: directory.path)
        } catch {
            return nil
        }

        let lowercased = contents.map { $0.lowercased() }

        // Exact or pattern matches
        if lowercased.contains(where: { $0.hasSuffix(".xp3") }) { return .kirikiri }
        if lowercased.contains("nscript.dat") { return .nscripter }
        if lowercased.contains("siglusengine.exe") { return .siglusEngine }
        if lowercased.contains("seen.txt") { return .realLive }
        if lowercased.contains("rio.arc") { return .advHD }
        if lowercased.contains(where: { $0.hasSuffix(".ypf") }) { return .yuris }
        if lowercased.contains("unityplayer.dll") { return .unity }
        if lowercased.contains(where: { $0.hasPrefix("rgss") && $0.hasSuffix(".dll") }) { return .rpgMaker }
        if lowercased.contains(where: { $0.hasPrefix("cs2") && $0.hasSuffix(".exe") }) { return .catSystem2 }
        // RPG Maker MV/MZ: has www/ directory + package.json
        if fm.fileExists(atPath: directory.appendingPathComponent("www").path) &&
           lowercased.contains("package.json") { return .rpgMaker }

        return nil
    }

    // MARK: - Layer 2: File magic bytes

    private struct MagicSignature {
        let bytes: [UInt8]
        let engine: Engine
    }

    private static let magicSignatures: [MagicSignature] = [
        MagicSignature(bytes: [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x08, 0x00], engine: .kirikiri),  // XP3
        MagicSignature(bytes: [0x52, 0x50, 0x41, 0x2D], engine: .renpy),                              // RPA-
        MagicSignature(bytes: [0x59, 0x50, 0x46, 0x00], engine: .yuris),                               // YPF\0
        MagicSignature(bytes: [0x52, 0x47, 0x53, 0x53, 0x41, 0x44], engine: .rpgMaker),                // RGSSAD
        MagicSignature(bytes: [0x4B, 0x49, 0x46, 0x00], engine: .catSystem2),                          // KIF\0
    ]

    // "PackFile" or "BURIKO ARC" -> BGI
    private static let bgiMagic1: [UInt8] = Array("PackFile".utf8)
    private static let bgiMagic2: [UInt8] = Array("BURIKO ARC".utf8)
    // "MajiroArc" -> Majiro
    private static let majiroMagic: [UInt8] = Array("MajiroArc".utf8)
    // "FilePack" -> QLIE
    private static let qlieMagic: [UInt8] = Array("FilePack".utf8)

    private static func detectByMagicBytes(in directory: URL) -> Engine? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        // Check data files (not .exe/.dll) for magic bytes
        let dataFiles = contents.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return !["exe", "dll", "txt", "ini", "cfg", "log"].contains(ext)
        }

        for fileName in dataFiles {
            let filePath = directory.appendingPathComponent(fileName)
            guard let handle = try? FileHandle(forReadingFrom: filePath) else { continue }
            defer { handle.closeFile() }

            guard let headerData = try? handle.read(upToCount: 64), headerData.count >= 4 else { continue }
            let header = Array(headerData)

            // Check standard magic signatures
            for sig in magicSignatures {
                if header.count >= sig.bytes.count &&
                   Array(header.prefix(sig.bytes.count)) == sig.bytes {
                    return sig.engine
                }
            }

            // Check BGI
            if header.count >= bgiMagic1.count && Array(header.prefix(bgiMagic1.count)) == bgiMagic1 { return .bgi }
            if header.count >= bgiMagic2.count && Array(header.prefix(bgiMagic2.count)) == bgiMagic2 { return .bgi }
            // Check Majiro
            if header.count >= majiroMagic.count && Array(header.prefix(majiroMagic.count)) == majiroMagic { return .majiro }
            // Check QLIE
            if header.count >= qlieMagic.count && Array(header.prefix(qlieMagic.count)) == qlieMagic { return .qlie }
        }

        return nil
    }

    // MARK: - Layer 3: DLL/EXE name patterns

    private static func detectByDLLNames(in directory: URL) -> Engine? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        let lowercased = contents.map { $0.lowercased() }

        if lowercased.contains(where: { $0.contains("artemis") }) { return .artemis }

        return nil
    }
}
```

**Step 4: Run tests**

Run: `cd GalaKit && swift test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add EngineDetector with file signature and magic byte detection"
```

---

## Task 5: VNDB Client

**Files:**
- Create: `GalaKit/Sources/GalaKit/VNDB/VNDBClient.swift`
- Create: `GalaKit/Sources/GalaKit/VNDB/VNDBModels.swift`
- Create: `GalaKit/Tests/GalaKitTests/VNDBClientTests.swift`

**Step 1: Write model tests**

```swift
// GalaKit/Tests/GalaKitTests/VNDBClientTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func decodeVNDBSearchResponse() throws {
    let json = """
    {
        "results": [
            {
                "id": "v11",
                "title": "Fate/stay night",
                "alttitle": "Fate/stay night",
                "released": "2004-01-30",
                "rating": 83.5,
                "image": {
                    "url": "https://t.vndb.org/cv/71/89071.jpg",
                    "dims": [600, 900],
                    "thumbnail": "https://t.vndb.org/cv.t/71/89071.jpg",
                    "thumbnail_dims": [256, 384]
                }
            }
        ],
        "more": true
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(VNDBResponse<VNDBVn>.self, from: json)
    #expect(response.results.count == 1)
    #expect(response.results[0].id == "v11")
    #expect(response.results[0].title == "Fate/stay night")
    #expect(response.results[0].rating == 83.5)
    #expect(response.results[0].image?.url == "https://t.vndb.org/cv/71/89071.jpg")
    #expect(response.more == true)
}

@Test func decodeVNDBReleaseWithEngine() throws {
    let json = """
    {
        "results": [
            {
                "id": "r123",
                "title": "Fate/stay night",
                "engine": "KiriKiri",
                "platforms": ["win"]
            }
        ],
        "more": false
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(VNDBResponse<VNDBRelease>.self, from: json)
    #expect(response.results[0].engine == "KiriKiri")
    #expect(response.results[0].platforms?.contains("win") == true)
}

@Test func buildSearchRequestBody() throws {
    let body = VNDBClient.searchRequestBody(query: "Fate", results: 10)
    let data = try JSONSerialization.jsonObject(with: body) as! [String: Any]
    let filters = data["filters"] as! [Any]
    #expect(filters[0] as! String == "search")
    #expect(filters[1] as! String == "=")
    #expect(filters[2] as! String == "Fate")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`
Expected: Compilation errors.

**Step 3: Implement VNDB models**

```swift
// GalaKit/Sources/GalaKit/VNDB/VNDBModels.swift
import Foundation

public struct VNDBResponse<T: Decodable>: Decodable {
    public let results: [T]
    public let more: Bool
}

public struct VNDBVn: Decodable, Sendable {
    public let id: String
    public let title: String
    public let alttitle: String?
    public let released: String?
    public let rating: Double?
    public let votecount: Int?
    public let lengthMinutes: Int?
    public let description: String?
    public let image: VNDBImage?
    public let developers: [VNDBProducer]?
    public let tags: [VNDBTag]?

    enum CodingKeys: String, CodingKey {
        case id, title, alttitle, released, rating, votecount
        case lengthMinutes = "length_minutes"
        case description, image, developers, tags
    }
}

public struct VNDBImage: Decodable, Sendable {
    public let url: String
    public let dims: [Int]?
    public let thumbnail: String?
    public let thumbnailDims: [Int]?

    enum CodingKeys: String, CodingKey {
        case url, dims, thumbnail
        case thumbnailDims = "thumbnail_dims"
    }
}

public struct VNDBProducer: Decodable, Sendable {
    public let id: String?
    public let name: String
}

public struct VNDBTag: Decodable, Sendable {
    public let id: String?
    public let name: String
    public let rating: Double?
}

public struct VNDBRelease: Decodable, Sendable {
    public let id: String
    public let title: String?
    public let engine: String?
    public let platforms: [String]?
}
```

**Step 4: Implement VNDBClient**

```swift
// GalaKit/Sources/GalaKit/VNDB/VNDBClient.swift
import Foundation

public final class VNDBClient: Sendable {
    private let baseURL = URL(string: "https://api.vndb.org/kana")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    public func searchVN(query: String, results: Int = 25) async throws -> VNDBResponse<VNDBVn> {
        let body = Self.searchRequestBody(query: query, results: results)
        return try await post(endpoint: "vn", body: body)
    }

    public func getVNDetail(id: String) async throws -> VNDBVn? {
        let body = Self.detailRequestBody(id: id)
        let response: VNDBResponse<VNDBVn> = try await post(endpoint: "vn", body: body)
        return response.results.first
    }

    public func getReleases(vnId: String) async throws -> [VNDBRelease] {
        let body = Self.releasesRequestBody(vnId: vnId)
        let response: VNDBResponse<VNDBRelease> = try await post(endpoint: "release", body: body)
        return response.results
    }

    public func downloadImage(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Request Body Builders

    static func searchRequestBody(query: String, results: Int = 25) -> Data {
        let body: [String: Any] = [
            "filters": ["search", "=", query],
            "fields": "id, title, alttitle, released, rating, image{url,dims,thumbnail,thumbnail_dims}, developers{id,name}",
            "sort": "searchrank",
            "results": results
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func detailRequestBody(id: String) -> Data {
        let body: [String: Any] = [
            "filters": ["id", "=", id],
            "fields": "id, title, alttitle, released, rating, votecount, length_minutes, description, image{url,dims,thumbnail,thumbnail_dims}, developers{id,name}, tags{id,name,rating}"
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func releasesRequestBody(vnId: String) -> Data {
        let body: [String: Any] = [
            "filters": ["vn", "=", ["id", "=", vnId]],
            "fields": "id, title, engine, platforms",
            "results": 50
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Network

    private func post<T: Decodable>(endpoint: String, body: Data) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VNDBError.httpError(statusCode: statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

public enum VNDBError: Error, LocalizedError {
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "VNDB API error (HTTP \(code))"
        }
    }
}
```

**Step 5: Run tests**

Run: `cd GalaKit && swift test`
Expected: All tests pass (model tests are offline, no network calls).

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add VNDBClient with API models and search/detail/release support"
```

---

## Task 6: Image Cache

**Files:**
- Create: `GalaKit/Sources/GalaKit/Library/ImageCache.swift`
- Create: `GalaKit/Tests/GalaKitTests/ImageCacheTests.swift`

**Step 1: Write tests**

```swift
// GalaKit/Tests/GalaKitTests/ImageCacheTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func saveAndLoadImage() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let testData = Data("fake image data".utf8)

    try cache.save(testData, forKey: "v11")
    let loaded = cache.load(forKey: "v11")

    #expect(loaded == testData)
}

@Test func loadMissingImageReturnsNil() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let loaded = cache.load(forKey: "nonexistent")
    #expect(loaded == nil)
}

@Test func imagePathForKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let testData = Data("fake".utf8)
    try cache.save(testData, forKey: "v17")

    let path = cache.path(forKey: "v17")
    #expect(path != nil)
    #expect(FileManager.default.fileExists(atPath: path!))
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`

**Step 3: Implement ImageCache**

```swift
// GalaKit/Sources/GalaKit/Library/ImageCache.swift
import Foundation

public final class ImageCache: Sendable {
    private let cacheDirectory: URL

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func save(_ data: Data, forKey key: String) throws {
        let fileURL = fileURL(forKey: key)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(forKey key: String) -> Data? {
        let fileURL = fileURL(forKey: key)
        return try? Data(contentsOf: fileURL)
    }

    public func path(forKey key: String) -> String? {
        let fileURL = fileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL.path
    }

    public func delete(forKey key: String) {
        let fileURL = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key)
    }
}
```

**Step 4: Run tests**

Run: `cd GalaKit && swift test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ImageCache for local cover art storage"
```

---

## Task 7: Wine Manager + Bottle Manager

**Files:**
- Create: `GalaKit/Sources/GalaKit/Wine/WineManager.swift`
- Create: `GalaKit/Sources/GalaKit/Wine/BottleManager.swift`
- Create: `GalaKit/Sources/GalaKit/Wine/WineProcess.swift`
- Create: `GalaKit/Tests/GalaKitTests/WineManagerTests.swift`

**Step 1: Write tests for path logic (no actual Wine calls)**

```swift
// GalaKit/Tests/GalaKitTests/WineManagerTests.swift
import Testing
import Foundation
@testable import GalaKit

@Test func wineManagerDirectoryStructure() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    #expect(manager.wineDirectory.lastPathComponent == "Wine")
    #expect(manager.bottlesDirectory.lastPathComponent == "Bottles")
}

@Test func wineManagerDetectsNoInstallation() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    #expect(manager.isWineInstalled == false)
}

@Test func bottleManagerCreatesDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bottlesDir = tempDir.appendingPathComponent("Bottles")
    let bottleManager = BottleManager(bottlesDirectory: bottlesDir)
    let gameId = UUID()
    let prefixPath = bottleManager.prefixPath(for: gameId)

    #expect(prefixPath.contains(gameId.uuidString))
}
```

**Step 2: Run tests to verify they fail**

Run: `cd GalaKit && swift test`

**Step 3: Implement WineManager**

```swift
// GalaKit/Sources/GalaKit/Wine/WineManager.swift
import Foundation

public final class WineManager: ObservableObject, @unchecked Sendable {
    private let baseURL: URL

    public var wineDirectory: URL { baseURL.appendingPathComponent("Wine") }
    public var bottlesDirectory: URL { baseURL.appendingPathComponent("Bottles") }
    private var activeLink: URL { wineDirectory.appendingPathComponent("active") }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: wineDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
    }

    public var isWineInstalled: Bool {
        let wineBinary = activeLink
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
        return FileManager.default.fileExists(atPath: wineBinary.path)
    }

    public var wineBinaryURL: URL? {
        guard isWineInstalled else { return nil }
        return activeLink
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
    }

    public func installedVersions() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: wineDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents
            .filter { $0.lastPathComponent != "active" }
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
            .sorted()
    }

    public func setActiveVersion(_ versionDir: String) throws {
        let target = wineDirectory.appendingPathComponent(versionDir)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw WineError.versionNotFound(versionDir)
        }

        // Remove existing symlink
        try? FileManager.default.removeItem(at: activeLink)
        try FileManager.default.createSymbolicLink(at: activeLink, withDestinationURL: target)
    }

    /// Download GPTK Wine from a URL and extract to Wine directory.
    /// The caller provides the download URL (e.g., from GitHub Releases).
    public func downloadWine(from url: URL, versionName: String) async throws {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        let destinationDir = wineDirectory.appendingPathComponent(versionName)

        // Download
        let (tempURL, _) = try await URLSession.shared.download(from: url)

        // Extract tar.gz
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", tempURL.path, "-C", destinationDir.path, "--strip-components=1"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WineError.extractionFailed
        }

        // Set as active
        try setActiveVersion(versionName)

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempURL)

        await MainActor.run {
            downloadProgress = 1.0
        }
    }
}

public enum WineError: Error, LocalizedError {
    case versionNotFound(String)
    case extractionFailed
    case wineNotInstalled

    public var errorDescription: String? {
        switch self {
        case .versionNotFound(let v): return "Wine version '\(v)' not found"
        case .extractionFailed: return "Failed to extract Wine archive"
        case .wineNotInstalled: return "Wine is not installed"
        }
    }
}
```

**Step 4: Implement BottleManager**

```swift
// GalaKit/Sources/GalaKit/Wine/BottleManager.swift
import Foundation

public final class BottleManager: @unchecked Sendable {
    private let bottlesDirectory: URL
    private let wineManager: WineManager?

    public init(bottlesDirectory: URL, wineManager: WineManager? = nil) {
        self.bottlesDirectory = bottlesDirectory
        self.wineManager = wineManager
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
    }

    public func prefixPath(for gameId: UUID) -> String {
        bottlesDirectory.appendingPathComponent(gameId.uuidString).path
    }

    /// Create a new Wine prefix for a game. Runs wineboot --init.
    public func createBottle(for game: Game) async throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)

        guard let wineBinary = wineManager?.wineBinaryURL else {
            throw WineError.wineNotInstalled
        }

        // wineboot --init
        try await runWineCommand(
            wineBinary: wineBinary,
            arguments: ["wineboot", "--init"],
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )

        // Configure Japanese locale in registry
        try await configureJapaneseLocale(
            wineBinary: wineBinary,
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )
    }

    /// Apply engine-specific preset to a bottle.
    public func applyEnginePreset(for game: Game) async throws {
        guard let engine = game.engine else { return }
        let preset = engine.preset
        guard !preset.components.isEmpty || !preset.dllOverrides.isEmpty else { return }

        // Install winetricks components
        if !preset.components.isEmpty {
            try await installWinetricks(
                components: preset.components,
                prefix: game.bottleConfig.prefixPath
            )
        }

        // Set DLL overrides
        if !preset.dllOverrides.isEmpty {
            guard let wineBinary = wineManager?.wineBinaryURL else { return }
            for (dll, mode) in preset.dllOverrides {
                try await runWineCommand(
                    wineBinary: wineBinary,
                    arguments: [
                        "reg", "add",
                        "HKCU\\Software\\Wine\\DllOverrides",
                        "/v", dll, "/t", "REG_SZ", "/d", mode, "/f"
                    ],
                    prefix: game.bottleConfig.prefixPath,
                    locale: game.bottleConfig.locale
                )
            }
        }
    }

    /// Delete a bottle (Wine prefix directory).
    public func deleteBottle(for game: Game) throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            try FileManager.default.removeItem(at: prefixURL)
        }
    }

    // MARK: - Private

    private func configureJapaneseLocale(wineBinary: URL, prefix: String, locale: String) async throws {
        // Set codepage to 932 (Shift-JIS)
        let regCommands: [(key: String, value: String, data: String)] = [
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "ACP", "932"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "OEMCP", "932"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "Default", "0411"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "InstallLanguage", "0411"),
        ]

        for cmd in regCommands {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: ["reg", "add", cmd.key, "/v", cmd.value, "/t", "REG_SZ", "/d", cmd.data, "/f"],
                prefix: prefix,
                locale: locale
            )
        }
    }

    private func installWinetricks(components: [String], prefix: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["winetricks", "-q"] + components
        process.environment = [
            "WINEPREFIX": prefix,
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        ]
        try process.run()
        process.waitUntilExit()
    }

    private func runWineCommand(wineBinary: URL, arguments: [String], prefix: String, locale: String) async throws {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = arguments
        process.environment = [
            "WINEPREFIX": prefix,
            "LANG": locale,
            "LC_ALL": locale,
        ]
        try process.run()
        process.waitUntilExit()
    }
}
```

**Step 5: Implement WineProcess**

```swift
// GalaKit/Sources/GalaKit/Wine/WineProcess.swift
import Foundation

public final class WineProcess: ObservableObject, @unchecked Sendable {
    private var process: Process?

    @Published public var isRunning = false

    public init() {}

    /// Launch a game using Wine. Returns when the game process exits.
    /// Updates the game's play time via the provided callback.
    public func launch(
        game: Game,
        wineBinary: URL,
        onTermination: @escaping @Sendable (TimeInterval) -> Void
    ) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = game.bottleConfig.launchArguments + [game.executablePath]
        process.currentDirectoryURL = URL(fileURLWithPath: game.executablePath)
            .deletingLastPathComponent()

        var env: [String: String] = [
            "WINEPREFIX": game.bottleConfig.prefixPath,
            "LANG": game.bottleConfig.locale,
            "LC_ALL": game.bottleConfig.locale,
        ]
        // Merge custom environment
        for (key, value) in game.bottleConfig.environment {
            env[key] = value
        }
        process.environment = env

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

    /// Launch a native macOS app (for Ren'Py, Unity, etc.)
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
```

**Step 6: Run tests**

Run: `cd GalaKit && swift test`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add WineManager, BottleManager, and WineProcess"
```

---

## Task 8: App Shell UI (NavigationSplitView)

**Files:**
- Modify: `Gala/Views/ContentView.swift`
- Modify: `Gala/GalaApp.swift`
- Create: `Gala/ViewModels/LibraryViewModel.swift`

**Step 1: Create LibraryViewModel**

```swift
// Gala/ViewModels/LibraryViewModel.swift
import SwiftUI
import GalaKit

@Observable
final class LibraryViewModel {
    var games: [Game] = []
    var selectedGameId: UUID?
    var searchText = ""
    var isWineInstalled = false

    private let libraryStore: LibraryStore
    private let wineManager: WineManager
    let imageCache: ImageCache
    let vndbClient = VNDBClient()

    var selectedGame: Game? {
        games.first { $0.id == selectedGameId }
    }

    var filteredGames: [Game] {
        if searchText.isEmpty { return games }
        return games.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.originalTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gala")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        self.libraryStore = LibraryStore(baseURL: baseURL)
        self.wineManager = WineManager(baseURL: baseURL)
        self.imageCache = ImageCache(
            cacheDirectory: baseURL.appendingPathComponent("Cache").appendingPathComponent("covers")
        )

        loadLibrary()
        isWineInstalled = wineManager.isWineInstalled
    }

    func loadLibrary() {
        games = (try? libraryStore.load()) ?? []
    }

    func saveLibrary() {
        try? libraryStore.save(games)
    }

    func addGame(_ game: Game) {
        games.append(game)
        saveLibrary()
    }

    func removeGame(_ game: Game) {
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    func updateGame(_ game: Game) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index] = game
            saveLibrary()
        }
    }

    func recordPlayTime(gameId: UUID, duration: TimeInterval) {
        if let index = games.firstIndex(where: { $0.id == gameId }) {
            games[index].totalPlayTime += duration
            games[index].lastPlayedAt = Date()
            saveLibrary()
        }
    }

    var wineManagerInstance: WineManager { wineManager }
    var bottleManager: BottleManager {
        BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    }
}
```

**Step 2: Update ContentView with NavigationSplitView**

```swift
// Gala/Views/ContentView.swift
import SwiftUI
import GalaKit

enum SidebarCategory: String, CaseIterable {
    case all = "All Games"
    case recent = "Recent"
    case playing = "Playing"
    case backlog = "Backlog"
    case completed = "Completed"
    case dropped = "Dropped"

    var icon: String {
        switch self {
        case .all: return "gamecontroller"
        case .recent: return "clock"
        case .playing: return "play.circle"
        case .backlog: return "bookmark"
        case .completed: return "checkmark.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var selectedCategory: SidebarCategory = .all
    @State private var showingAddGame = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SidebarCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } content: {
            // Game grid
            GameGridView(
                games: filteredByCategory,
                selectedGameId: $viewModel.selectedGameId,
                imageCache: viewModel.imageCache
            )
            .searchable(text: $viewModel.searchText, prompt: "Search games...")
            .navigationSplitViewColumnWidth(min: 300, ideal: 500)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGame = true
                    } label: {
                        Label("Add Game", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let game = viewModel.selectedGame {
                GameDetailView(game: game, viewModel: viewModel)
            } else {
                Text("Select a game")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingAddGame) {
            AddGameView(viewModel: viewModel)
        }
    }

    private var filteredByCategory: [Game] {
        let games = viewModel.filteredGames
        switch selectedCategory {
        case .all: return games
        case .recent:
            return games
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .playing: return games.filter { $0.status == .playing }
        case .backlog: return games.filter { $0.status == .backlog }
        case .completed: return games.filter { $0.status == .completed }
        case .dropped: return games.filter { $0.status == .dropped }
        }
    }
}
```

**Step 3: Update GalaApp**

```swift
// Gala/GalaApp.swift
import SwiftUI

@main
struct GalaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 650)
    }
}
```

**Step 4: Build and verify**

Run: Build in Xcode.
Expected: App launches with three-pane layout, sidebar shows categories, empty content area.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add app shell with NavigationSplitView and LibraryViewModel"
```

---

## Task 9: Game Grid View + Cover Card

**Files:**
- Create: `Gala/Views/Library/GameGridView.swift`
- Create: `Gala/Views/Library/GameCoverCard.swift`

**Step 1: Implement GameCoverCard**

```swift
// Gala/Views/Library/GameCoverCard.swift
import SwiftUI
import GalaKit

struct GameCoverCard: View {
    let game: Game
    let isSelected: Bool
    let imageCache: ImageCache

    var body: some View {
        VStack(spacing: 6) {
            // Cover image
            coverImage
                .frame(width: 150, height: 212)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                .shadow(radius: isSelected ? 4 : 2)

            // Title
            Text(game.originalTitle ?? game.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 150)

            // Play time
            if game.totalPlayTime > 0 {
                Text(formatPlayTime(game.totalPlayTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverPath = game.coverImagePath,
           let data = imageCache.load(forKey: URL(fileURLWithPath: coverPath).lastPathComponent),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Placeholder
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack {
                    Image(systemName: "gamecontroller")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(String(game.title.prefix(1)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
```

**Step 2: Implement GameGridView**

```swift
// Gala/Views/Library/GameGridView.swift
import SwiftUI
import GalaKit

struct GameGridView: View {
    let games: [Game]
    @Binding var selectedGameId: UUID?
    let imageCache: ImageCache

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200))]

    var body: some View {
        if games.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(games) { game in
                        GameCoverCard(
                            game: game,
                            isSelected: selectedGameId == game.id,
                            imageCache: imageCache
                        )
                        .onTapGesture {
                            selectedGameId = game.id
                        }
                    }
                }
                .padding()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Click + to add your first game")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Step 3: Build and verify**

Run: Build in Xcode.
Expected: App shows empty state with "No games yet" placeholder.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add GameGridView and GameCoverCard with cover display and play time"
```

---

## Task 10: Add Game Flow

**Files:**
- Create: `Gala/Views/Setup/AddGameView.swift`
- Create: `Gala/Views/Setup/VNDBSearchView.swift`

**Step 1: Implement VNDBSearchView**

```swift
// Gala/Views/Setup/VNDBSearchView.swift
import SwiftUI
import GalaKit

struct VNDBSearchView: View {
    let initialQuery: String
    let onSelect: (VNDBVn) -> Void
    let onSkip: () -> Void

    @State private var searchText: String
    @State private var results: [VNDBVn] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let client = VNDBClient()

    init(initialQuery: String, onSelect: @escaping (VNDBVn) -> Void, onSkip: @escaping () -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        self.onSkip = onSkip
        self._searchText = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Match with VNDB")
                .font(.headline)

            HStack {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .disabled(searchText.isEmpty || isSearching)
            }

            if isSearching {
                ProgressView()
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            } else {
                List(results, id: \.id) { vn in
                    HStack {
                        // Thumbnail
                        if let thumbURL = vn.image?.thumbnail, let url = URL(string: thumbURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 40, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        VStack(alignment: .leading) {
                            Text(vn.alttitle ?? vn.title).font(.body)
                            if vn.alttitle != nil {
                                Text(vn.title).font(.caption).foregroundStyle(.secondary)
                            }
                            if let dev = vn.developers?.first?.name {
                                Text(dev).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if let rating = vn.rating {
                            Text(String(format: "%.0f", rating))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(vn) }
                }
                .frame(minHeight: 200)
            }

            HStack {
                Spacer()
                Button("Skip") { onSkip() }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .task { search() }
    }

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        errorMessage = nil

        Task {
            do {
                let response = try await client.searchVN(query: searchText, results: 15)
                results = response.results
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}
```

**Step 2: Implement AddGameView**

```swift
// Gala/Views/Setup/AddGameView.swift
import SwiftUI
import GalaKit

struct AddGameView: View {
    let viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: AddGameStep = .selectFile
    @State private var selectedExePath: String?
    @State private var gameDirectory: URL?
    @State private var detectedEngine: Engine?
    @State private var gameName = ""
    @State private var isSettingUp = false
    @State private var setupStatus = ""

    enum AddGameStep {
        case selectFile, vndbMatch, settingUp
    }

    var body: some View {
        VStack {
            switch step {
            case .selectFile:
                selectFileView
            case .vndbMatch:
                VNDBSearchView(
                    initialQuery: gameName,
                    onSelect: { vn in addGameWithVNDB(vn) },
                    onSkip: { addGameWithoutVNDB() }
                )
            case .settingUp:
                settingUpView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var selectFileView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Add a Game")
                .font(.title2)
            Text("Select the game's .exe file")
                .foregroundStyle(.secondary)
            Button("Choose .exe File...") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingUpView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(setupStatus)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the game's .exe file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        selectedExePath = url.path
        gameDirectory = url.deletingLastPathComponent()

        // Detect engine
        if let dir = gameDirectory {
            detectedEngine = EngineDetector.detect(in: dir)
        }

        // Extract name from parent folder
        gameName = gameDirectory?.lastPathComponent ?? url.deletingPathExtension().lastPathComponent

        step = .vndbMatch
    }

    private func addGameWithVNDB(_ vn: VNDBVn) {
        step = .settingUp
        Task {
            await setupGame(
                title: vn.alttitle ?? vn.title,
                originalTitle: vn.alttitle != nil ? vn.title : nil,
                vndbId: vn.id,
                rating: vn.rating,
                developer: vn.developers?.first?.name,
                released: vn.released,
                description: vn.description,
                coverURL: vn.image?.url
            )
        }
    }

    private func addGameWithoutVNDB() {
        step = .settingUp
        Task {
            await setupGame(title: gameName)
        }
    }

    private func setupGame(
        title: String,
        originalTitle: String? = nil,
        vndbId: String? = nil,
        rating: Double? = nil,
        developer: String? = nil,
        released: String? = nil,
        description: String? = nil,
        coverURL: String? = nil
    ) async {
        guard let exePath = selectedExePath else { return }

        let gameId = UUID()
        let prefixPath = viewModel.bottleManager.prefixPath(for: gameId)

        // Download cover image if available
        var coverImagePath: String?
        if let coverURL, let url = URL(string: coverURL) {
            setupStatus = "Downloading cover art..."
            if let data = try? await viewModel.vndbClient.downloadImage(from: url) {
                let key = vndbId ?? gameId.uuidString
                try? viewModel.imageCache.save(data, forKey: key)
                coverImagePath = viewModel.imageCache.path(forKey: key)
            }
        }

        // Detect engine from VNDB releases if available
        var engine = detectedEngine
        if let vndbId, engine == nil {
            setupStatus = "Checking engine info..."
            if let releases = try? await viewModel.vndbClient.getReleases(vnId: vndbId) {
                if let vndbEngine = releases.compactMap({ $0.engine }).first {
                    engine = Engine.allCases.first {
                        $0.displayName.lowercased() == vndbEngine.lowercased()
                    }
                }
            }
        }

        let game = Game(
            id: gameId,
            title: title,
            originalTitle: originalTitle,
            vndbId: vndbId,
            executablePath: exePath,
            coverImagePath: coverImagePath,
            engine: engine,
            rating: rating,
            developer: developer,
            releasedAt: released,
            description: description,
            bottleConfig: BottleConfig(prefixPath: prefixPath)
        )

        // Create bottle (skip if Ren'Py native)
        if engine != .renpy {
            setupStatus = "Creating Wine prefix..."
            // Bottle creation is async and may take time
            // For MVP, we just create the directory and set config
            // Full wineboot will happen on first launch
            try? FileManager.default.createDirectory(
                atPath: prefixPath,
                withIntermediateDirectories: true
            )
        }

        viewModel.addGame(game)
        dismiss()
    }
}
```

**Step 3: Build and verify**

Run: Build in Xcode.
Expected: Click +, file picker appears, selecting .exe goes to VNDB search, selecting or skipping adds game to library.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add AddGameView with file selection, engine detection, and VNDB matching"
```

---

## Task 11: Game Detail View + Launch

**Files:**
- Create: `Gala/Views/Detail/GameDetailView.swift`
- Create: `Gala/ViewModels/GameViewModel.swift`

**Step 1: Implement GameViewModel**

```swift
// Gala/ViewModels/GameViewModel.swift
import SwiftUI
import GalaKit

@Observable
final class GameViewModel {
    var isRunning = false
    var errorMessage: String?

    private let wineProcess = WineProcess()

    func launchGame(_ game: Game, viewModel: LibraryViewModel) {
        guard !isRunning else { return }

        let wineManager = viewModel.wineManagerInstance

        // Check for native launch (Ren'Py)
        if game.engine == .renpy {
            launchNative(game, viewModel: viewModel)
            return
        }

        guard let wineBinary = wineManager.wineBinaryURL else {
            errorMessage = "Wine is not installed. Please install it from Settings."
            return
        }

        isRunning = true
        errorMessage = nil

        do {
            try wineProcess.launch(game: game, wineBinary: wineBinary) { [weak self] duration in
                viewModel.recordPlayTime(gameId: game.id, duration: duration)
                DispatchQueue.main.async {
                    self?.isRunning = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    private func launchNative(_ game: Game, viewModel: LibraryViewModel) {
        let gameDir = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        // Look for .app or .sh in game directory
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: gameDir.path) {
            if let app = contents.first(where: { $0.hasSuffix(".app") }) {
                let appPath = gameDir.appendingPathComponent(app).path
                isRunning = true
                do {
                    try wineProcess.launchNative(path: appPath) { [weak self] duration in
                        viewModel.recordPlayTime(gameId: game.id, duration: duration)
                        DispatchQueue.main.async {
                            self?.isRunning = false
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
                return
            }
        }
        // Fallback: try launching the exe with Wine
        errorMessage = "No native macOS binary found. Wine will be used."
    }
}
```

**Step 2: Implement GameDetailView**

```swift
// Gala/Views/Detail/GameDetailView.swift
import SwiftUI
import GalaKit

struct GameDetailView: View {
    let game: Game
    let viewModel: LibraryViewModel
    @State private var gameVM = GameViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header: cover + title + launch
                HStack(alignment: .top, spacing: 20) {
                    coverImage
                        .frame(width: 200, height: 283)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        if let originalTitle = game.originalTitle {
                            Text(originalTitle)
                                .font(.title.bold())
                            Text(game.title)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(game.title)
                                .font(.title.bold())
                        }

                        if let developer = game.developer {
                            Text(developer)
                                .foregroundStyle(.secondary)
                        }

                        if let engine = game.engine {
                            Label(engine.displayName, systemImage: "gearshape")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        // Launch button
                        Button {
                            gameVM.launchGame(game, viewModel: viewModel)
                        } label: {
                            Label(
                                gameVM.isRunning ? "Running..." : "Launch",
                                systemImage: gameVM.isRunning ? "stop.circle" : "play.fill"
                            )
                            .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(gameVM.isRunning)

                        if let error = gameVM.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Divider()

                // Stats
                HStack(spacing: 30) {
                    statItem(label: "Play Time", value: formatPlayTime(game.totalPlayTime))
                    if let lastPlayed = game.lastPlayedAt {
                        statItem(label: "Last Played", value: lastPlayed.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let rating = game.rating {
                        statItem(label: "VNDB Rating", value: String(format: "%.0f", rating))
                    }
                    statItem(label: "Status", value: game.status.rawValue.capitalized)
                }

                // Description
                if let description = game.description {
                    Text("About")
                        .font(.headline)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Tags
                if !game.tags.isEmpty {
                    Text("Tags")
                        .font(.headline)
                    FlowLayout(spacing: 6) {
                        ForEach(game.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverPath = game.coverImagePath,
           let data = viewModel.imageCache.load(forKey: URL(fileURLWithPath: coverPath).lastPathComponent),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "Not played"
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

**Step 3: Build and verify**

Run: Build in Xcode.
Expected: Clicking a game in the grid shows detail view with cover, title, launch button, stats.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add GameDetailView with launch button and play time display"
```

---

## Task 12: Integration Testing & Polish

**Step 1: End-to-end manual test**

Test the full flow:
1. Launch app → empty library shown
2. Click + → file picker opens
3. Select a .exe → engine detected, VNDB search shown
4. Select VNDB match (or skip) → game added with cover
5. Game appears in grid
6. Click game → detail view shows
7. Verify data persists after app restart (check `~/Library/Application Support/Gala/library.json`)

**Step 2: Fix any issues found during testing**

Address UI layout issues, data flow problems, or crashes discovered.

**Step 3: Add .exe UTType declaration**

Add to the app's Info.plist or via code so NSOpenPanel can filter .exe files:

```swift
// In AddGameView, replace .exe with:
import UniformTypeIdentifiers

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
}
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: integration polish and .exe file type support"
```

---

## Task 13: Welcome Screen (Wine Setup)

**Files:**
- Create: `Gala/Views/Setup/WelcomeView.swift`
- Modify: `Gala/Views/ContentView.swift` (add wine check)

**Step 1: Implement WelcomeView**

```swift
// Gala/Views/Setup/WelcomeView.swift
import SwiftUI
import GalaKit

struct WelcomeView: View {
    let wineManager: WineManager
    let onComplete: () -> Void

    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    // TODO: Replace with actual GPTK Wine download URL
    private let wineDownloadURL = URL(string: "https://github.com/user/repo/releases/download/v1.0/wine-gptk.tar.gz")!
    private let wineVersionName = "wine-gptk-latest"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.accent)

            Text("Welcome to Gala")
                .font(.largeTitle.bold())

            Text("Gala needs GPTK Wine to run Windows visual novels.\nThis is a one-time setup.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 300)
                    Text("Downloading Wine...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Install Wine") {
                    downloadWine()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("I already have Wine installed") {
                onComplete()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 500, height: 400)
    }

    private func downloadWine() {
        isDownloading = true
        errorMessage = nil

        Task {
            do {
                try await wineManager.downloadWine(from: wineDownloadURL, versionName: wineVersionName)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
```

**Step 2: Update ContentView to show WelcomeView when Wine is missing**

Add to the top of ContentView's body:

```swift
// In ContentView, wrap the NavigationSplitView:
if !viewModel.isWineInstalled {
    WelcomeView(wineManager: viewModel.wineManagerInstance) {
        viewModel.isWineInstalled = true
    }
} else {
    // existing NavigationSplitView...
}
```

**Step 3: Build and verify**

Expected: First launch shows welcome screen. After Wine setup (or clicking skip), shows main library.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add WelcomeView for first-launch Wine installation"
```

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Scaffold | Xcode project + GalaKit package |
| 2 | Models | Game, BottleConfig, Engine with presets |
| 3 | LibraryStore | JSON persistence |
| 4 | EngineDetector | File signature + magic byte detection |
| 5 | VNDBClient | API client with search, detail, releases |
| 6 | ImageCache | Local cover art caching |
| 7 | Wine layer | WineManager, BottleManager, WineProcess |
| 8 | App shell | NavigationSplitView + LibraryViewModel |
| 9 | Game grid | GameGridView + GameCoverCard |
| 10 | Add game | File selection + VNDB matching |
| 11 | Detail + Launch | GameDetailView + launch button |
| 12 | Integration | End-to-end testing and polish |
| 13 | Welcome | First-launch Wine setup screen |

Tasks 1-7 are GalaKit (core logic, testable). Tasks 8-13 are UI (manual testing in Xcode).

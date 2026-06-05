import Foundation

public enum EngineDetector {
    public static func detect(in directory: URL) -> Engine? {
        detectCandidates(in: directory).first?.engine
    }

    private struct EngineCandidate: Sendable {
        let engine: Engine
        let score: Int
        let reason: String
    }

    private static func detectCandidates(in directory: URL) -> [EngineCandidate] {
        let fm = FileManager.default
        var scores: [Engine: (score: Int, reasons: [String])] = [:]

        func add(_ engine: Engine, score: Int, reason: String) {
            var current = scores[engine] ?? (0, [])
            current.score += score
            current.reasons.append(reason)
            scores[engine] = current
        }

        if fm.fileExists(atPath: directory.appendingPathComponent("renpy").path) {
            add(.renpy, score: 120, reason: "renpy directory")
        }

        let contents: [String]
        do { contents = try fm.contentsOfDirectory(atPath: directory.path) } catch { return [] }
        let lowercased = contents.map { $0.lowercased() }

        let hasXP3 = lowercased.contains(where: { $0.hasSuffix(".xp3") })
        let hasPFS = lowercased.contains(where: { $0.hasSuffix(".pfs") })
        let hasIarsys = lowercased.contains("iarsys.dll") || lowercased.contains("iarsys64.dll")
        let hasEmote = lowercased.contains("emotedriver.dll")

        if hasXP3 { add(.kirikiri, score: 45, reason: "xp3 archive") }
        if lowercased.contains("nscript.dat") { add(.nscripter, score: 100, reason: "nscript.dat") }
        if lowercased.contains("siglusengine.exe") { add(.siglusEngine, score: 120, reason: "SiglusEngine.exe") }
        if lowercased.contains("seen.txt") { add(.realLive, score: 100, reason: "seen.txt") }
        if lowercased.contains("rio.arc") { add(.advHD, score: 100, reason: "rio.arc") }
        if lowercased.contains(where: { $0.hasSuffix(".ypf") }) { add(.yuris, score: 80, reason: "ypf archive") }
        if detectsLeafAQUAPLUS(contents: lowercased) { add(.leaf, score: 140, reason: "Leaf/AQUAPLUS file group") }
        if detectsIkuraGDLFamilyProject(contents: lowercased) {
            add(.ikuraGDLFamilyProject, score: 160, reason: "Ikura GDL family project file group")
        }
        if lowercased.contains("unityplayer.dll") { add(.unity, score: 120, reason: "UnityPlayer.dll") }
        if lowercased.contains(where: { $0.hasPrefix("rgss") && $0.hasSuffix(".dll") }) {
            add(.rpgMaker, score: 100, reason: "RGSS DLL")
        }
        if lowercased.contains(where: { $0.hasPrefix("cs2") && $0.hasSuffix(".exe") }) {
            add(.catSystem2, score: 100, reason: "cs2 executable")
        }
        if fm.fileExists(atPath: directory.appendingPathComponent("www").path) &&
           lowercased.contains("package.json") {
            add(.rpgMaker, score: 100, reason: "RPG Maker MV/MZ www + package.json")
        }

        if hasPFS { add(.artemisD3D11, score: 35, reason: "pfs archive") }
        if hasIarsys { add(.artemisD3D11, score: 95, reason: "iarsys DLL") }
        if hasEmote { add(.artemisD3D11, score: 35, reason: "E-mote driver") }
        if hasPFS && hasIarsys { add(.artemisD3D11, score: 90, reason: "iarsys + pfs file group") }
        if hasPFS && hasEmote { add(.artemisD3D11, score: 35, reason: "E-mote + pfs file group") }
        if lowercased.contains(where: { $0.contains("artemis") }) {
            add(.artemis, score: 70, reason: "Artemis file name")
        }

        for candidate in magicCandidates(in: directory) {
            add(candidate.engine, score: candidate.score, reason: candidate.reason)
        }

        for candidate in executableStringCandidates(in: directory, contents: contents) {
            add(candidate.engine, score: candidate.score, reason: candidate.reason)
        }

        return scores
            .map { engine, value in
                EngineCandidate(engine: engine, score: value.score, reason: value.reasons.joined(separator: ", "))
            }
            .filter { $0.score >= 40 }
            .sorted {
                if $0.score == $1.score {
                    return $0.engine.rawValue < $1.engine.rawValue
                }
                return $0.score > $1.score
            }
    }

    static func detectsLeafAQUAPLUS(in directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return detectsLeafAQUAPLUS(contents: contents.map { $0.lowercased() })
    }

    static func detectsLeafAQUAPLUS(contents lowercased: [String]) -> Bool {
        let hasWA2Executable = lowercased.contains("wa2.exe") || lowercased.contains("wa2_chs.exe")
        let hasMoviePacks = lowercased.contains { name in
            name.hasPrefix("mv") && name.hasSuffix(".pak")
        }
        return hasWA2Executable && hasMoviePacks
    }

    static func detectsIkuraGDLFamilyProject(in directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return detectsIkuraGDLFamilyProject(contents: contents.map { $0.lowercased() })
    }

    static func detectsIkuraGDLFamilyProject(contents lowercased: [String]) -> Bool {
        let hasKizunarMarker = lowercased.contains("kizunar.suf") ||
            lowercased.contains("kzn_sc.dll")
        let hasLauncher = lowercased.contains("kzn_sc.exe") ||
            lowercased.contains("kizunar.exe")
        let hasOpeningMovie = lowercased.contains("fam_op.mpg") ||
            lowercased.contains("fam_ophq.mpg")
        return hasKizunarMarker && hasLauncher && hasOpeningMovie
    }

    private struct MagicSignature {
        let bytes: [UInt8]
        let engine: Engine
        let score: Int
    }

    private static let magicSignatures: [MagicSignature] = [
        MagicSignature(bytes: [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x08, 0x00], engine: .kirikiri, score: 70),
        MagicSignature(bytes: [0x52, 0x50, 0x41, 0x2D], engine: .renpy, score: 90),
        MagicSignature(bytes: [0x59, 0x50, 0x46, 0x00], engine: .yuris, score: 90),
        MagicSignature(bytes: [0x52, 0x47, 0x53, 0x53, 0x41, 0x44], engine: .rpgMaker, score: 90),
        MagicSignature(bytes: [0x4B, 0x49, 0x46, 0x00], engine: .catSystem2, score: 90),
    ]

    private static let bgiMagic1: [UInt8] = Array("PackFile".utf8)
    private static let bgiMagic2: [UInt8] = Array("BURIKO ARC".utf8)
    private static let majiroMagic: [UInt8] = Array("MajiroArc".utf8)
    private static let qlieMagic: [UInt8] = Array("FilePack".utf8)

    private static func magicCandidates(in directory: URL) -> [EngineCandidate] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var candidates: [EngineCandidate] = []

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

            for sig in magicSignatures {
                if header.count >= sig.bytes.count && Array(header.prefix(sig.bytes.count)) == sig.bytes {
                    candidates.append(EngineCandidate(
                        engine: sig.engine,
                        score: sig.score,
                        reason: "magic bytes in \(fileName)"
                    ))
                }
            }
            if header.count >= bgiMagic1.count && Array(header.prefix(bgiMagic1.count)) == bgiMagic1 {
                candidates.append(EngineCandidate(engine: .bgi, score: 100, reason: "BGI PackFile magic in \(fileName)"))
            }
            if header.count >= bgiMagic2.count && Array(header.prefix(bgiMagic2.count)) == bgiMagic2 {
                candidates.append(EngineCandidate(engine: .bgi, score: 100, reason: "BGI BURIKO magic in \(fileName)"))
            }
            if header.count >= majiroMagic.count && Array(header.prefix(majiroMagic.count)) == majiroMagic {
                candidates.append(EngineCandidate(engine: .majiro, score: 100, reason: "Majiro magic in \(fileName)"))
            }
            if header.count >= qlieMagic.count && Array(header.prefix(qlieMagic.count)) == qlieMagic {
                candidates.append(EngineCandidate(engine: .qlie, score: 100, reason: "QLIE magic in \(fileName)"))
            }
        }
        return candidates
    }

    private static func executableStringCandidates(in directory: URL, contents: [String]) -> [EngineCandidate] {
        var candidates: [EngineCandidate] = []
        let exeFiles = contents.filter { $0.lowercased().hasSuffix(".exe") }
        let lowercased = contents.map { $0.lowercased() }
        let hasArtemisFileGroup = lowercased.contains(where: { $0.hasSuffix(".pfs") }) ||
            lowercased.contains("iarsys.dll") ||
            lowercased.contains("iarsys64.dll") ||
            lowercased.contains("emotedriver.dll")

        for exe in exeFiles {
            let url = directory.appendingPathComponent(exe)
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { handle.closeFile() }
            guard let data = try? handle.read(upToCount: 8 * 1024 * 1024) else { continue }

            if data.containsASCII("Artemis") || data.containsASCII("iarsys") {
                candidates.append(EngineCandidate(engine: .artemisD3D11, score: 95, reason: "Artemis/iarsys string in \(exe)"))
            }
            if hasArtemisFileGroup && data.containsASCII("D3D11CreateDevice") {
                candidates.append(EngineCandidate(engine: .artemisD3D11, score: 45, reason: "D3D11CreateDevice import in \(exe)"))
            }
            if hasArtemisFileGroup &&
                (data.containsASCII("D3DCompile") || data.containsASCII("D3DCOMPILER_47.dll")) {
                candidates.append(EngineCandidate(engine: .artemisD3D11, score: 35, reason: "D3D compiler import in \(exe)"))
            }
        }

        return candidates
    }

    // MARK: - Engine Executable Resolution

    /// Given a detected engine and game directory, find the actual engine executable.
    /// Returns nil if no engine-specific exe is found (caller should use the user-selected exe).
    public static func resolveExecutable(engine: Engine, in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        let exeFiles = contents.filter { $0.lowercased().hasSuffix(".exe") }

        switch engine {
        case .ikuraGDLFamilyProject:
            if let match = exeFiles.first(where: { $0.lowercased() == "kzn_sc.exe" }) {
                return directory.appendingPathComponent(match)
            }
            if let match = exeFiles.first(where: { $0.lowercased() == "kizunar.exe" }) {
                return directory.appendingPathComponent(match)
            }
        case .bgi:
            // BGI/Ethornell: BGI.exe is the game engine
            if let match = exeFiles.first(where: { $0.lowercased() == "bgi.exe" }) {
                return directory.appendingPathComponent(match)
            }
            if let match = exeFiles.first(where: { $0.lowercased().contains("ethornell") }) {
                return directory.appendingPathComponent(match)
            }
        case .kirikiri:
            // KiriKiri: look for kirikiri.exe or *.exe that is NOT a patcher/launcher
            if let match = exeFiles.first(where: { $0.lowercased() == "kirikiri.exe" }) {
                return directory.appendingPathComponent(match)
            }
        case .siglusEngine:
            // SiglusEngine: SiglusEngine.exe
            if let match = exeFiles.first(where: { $0.lowercased() == "siglusengine.exe" }) {
                return directory.appendingPathComponent(match)
            }
        case .catSystem2:
            // CatSystem2: cs2.exe or cs2_*.exe
            if let match = exeFiles.first(where: { $0.lowercased().hasPrefix("cs2") }) {
                return directory.appendingPathComponent(match)
            }
        case .nscripter:
            // NScripter: nscript.exe or arc.nsa-based
            if let match = exeFiles.first(where: { $0.lowercased() == "nscript.exe" }) {
                return directory.appendingPathComponent(match)
            }
        case .rpgMaker:
            // RPG Maker: Game.exe is the standard name
            if let match = exeFiles.first(where: { $0.lowercased() == "game.exe" }) {
                return directory.appendingPathComponent(match)
            }
        case .leaf:
            // Leaf/AQUAPLUS: prefer localized launchers when present.
            if let match = exeFiles.first(where: { $0.lowercased() == "wa2_chs.exe" }) {
                return directory.appendingPathComponent(match)
            }
            if let match = exeFiles.first(where: { $0.lowercased() == "wa2.exe" }) {
                return directory.appendingPathComponent(match)
            }
        default:
            break
        }

        return nil
    }
}

private extension Data {
    func containsASCII(_ string: String) -> Bool {
        let needle = Array(string.utf8)
        guard !needle.isEmpty, count >= needle.count else { return false }

        return withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            let haystackCount = rawBuffer.count
            var offset = 0

            while offset <= haystackCount - needle.count {
                var matched = true
                for index in 0..<needle.count where base[offset + index] != needle[index] {
                    matched = false
                    break
                }
                if matched { return true }
                offset += 1
            }
            return false
        }
    }
}

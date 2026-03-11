import Foundation

public enum EngineDetector {
    public static func detect(in directory: URL) -> Engine? {
        if let engine = detectByUniqueFiles(in: directory) { return engine }
        if let engine = detectByMagicBytes(in: directory) { return engine }
        if let engine = detectByDLLNames(in: directory) { return engine }
        return nil
    }

    private static func detectByUniqueFiles(in directory: URL) -> Engine? {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.appendingPathComponent("renpy").path) { return .renpy }

        let contents: [String]
        do { contents = try fm.contentsOfDirectory(atPath: directory.path) } catch { return nil }
        let lowercased = contents.map { $0.lowercased() }

        if lowercased.contains(where: { $0.hasSuffix(".xp3") }) { return .kirikiri }
        if lowercased.contains("nscript.dat") { return .nscripter }
        if lowercased.contains("siglusengine.exe") { return .siglusEngine }
        if lowercased.contains("seen.txt") { return .realLive }
        if lowercased.contains("rio.arc") { return .advHD }
        if lowercased.contains(where: { $0.hasSuffix(".ypf") }) { return .yuris }
        if lowercased.contains("unityplayer.dll") { return .unity }
        if lowercased.contains(where: { $0.hasPrefix("rgss") && $0.hasSuffix(".dll") }) { return .rpgMaker }
        if lowercased.contains(where: { $0.hasPrefix("cs2") && $0.hasSuffix(".exe") }) { return .catSystem2 }
        if fm.fileExists(atPath: directory.appendingPathComponent("www").path) &&
           lowercased.contains("package.json") { return .rpgMaker }
        return nil
    }

    private struct MagicSignature {
        let bytes: [UInt8]
        let engine: Engine
    }

    private static let magicSignatures: [MagicSignature] = [
        MagicSignature(bytes: [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x08, 0x00], engine: .kirikiri),
        MagicSignature(bytes: [0x52, 0x50, 0x41, 0x2D], engine: .renpy),
        MagicSignature(bytes: [0x59, 0x50, 0x46, 0x00], engine: .yuris),
        MagicSignature(bytes: [0x52, 0x47, 0x53, 0x53, 0x41, 0x44], engine: .rpgMaker),
        MagicSignature(bytes: [0x4B, 0x49, 0x46, 0x00], engine: .catSystem2),
    ]

    private static let bgiMagic1: [UInt8] = Array("PackFile".utf8)
    private static let bgiMagic2: [UInt8] = Array("BURIKO ARC".utf8)
    private static let majiroMagic: [UInt8] = Array("MajiroArc".utf8)
    private static let qlieMagic: [UInt8] = Array("FilePack".utf8)

    private static func detectByMagicBytes(in directory: URL) -> Engine? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory.path) else { return nil }

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
                    return sig.engine
                }
            }
            if header.count >= bgiMagic1.count && Array(header.prefix(bgiMagic1.count)) == bgiMagic1 { return .bgi }
            if header.count >= bgiMagic2.count && Array(header.prefix(bgiMagic2.count)) == bgiMagic2 { return .bgi }
            if header.count >= majiroMagic.count && Array(header.prefix(majiroMagic.count)) == majiroMagic { return .majiro }
            if header.count >= qlieMagic.count && Array(header.prefix(qlieMagic.count)) == qlieMagic { return .qlie }
        }
        return nil
    }

    private static func detectByDLLNames(in directory: URL) -> Engine? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        let lowercased = contents.map { $0.lowercased() }
        if lowercased.contains(where: { $0.contains("artemis") }) { return .artemis }
        return nil
    }

    // MARK: - Engine Executable Resolution

    /// Given a detected engine and game directory, find the actual engine executable.
    /// Returns nil if no engine-specific exe is found (caller should use the user-selected exe).
    public static func resolveExecutable(engine: Engine, in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        let exeFiles = contents.filter { $0.lowercased().hasSuffix(".exe") }
        let lowercasedExes = exeFiles.map { $0.lowercased() }

        switch engine {
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
        default:
            break
        }

        return nil
    }
}

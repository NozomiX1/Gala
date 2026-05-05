import Foundation

public enum WineLaunchDiagnostics {
    public static func meaningfulQuickExitOutput(
        duration: TimeInterval,
        terminationStatus: Int32,
        output: String
    ) -> String? {
        guard duration < 5, terminationStatus != 0, !output.isEmpty else {
            return nil
        }

        let meaningful = output.components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !isHarmlessWineNoise(trimmed)
            }
            .joined(separator: "\n")

        guard !meaningful.isEmpty else { return nil }
        return String(meaningful.suffix(500))
    }

    private static func isHarmlessWineNoise(_ line: String) -> Bool {
        line.contains(":fixme:")
            || line.contains(") stub")
            || line.contains("MoltenVK")
            || line.contains("[mvk-")
            || (line.contains("EXT_texture_array") && line.contains("not supported"))
    }
}

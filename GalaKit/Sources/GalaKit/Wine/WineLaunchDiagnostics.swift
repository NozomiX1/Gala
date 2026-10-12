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

    /// Lines every launch prints whether or not anything is wrong.
    static func isHarmlessWineNoise(_ line: String) -> Bool {
        line.contains(":fixme:")
            // Printed many times by every launch on Apple silicon; the allocation is retried elsewhere.
            || line.contains("try_map_free_area")
            || line.contains(") stub")
            || line.contains("MoltenVK")
            || line.contains("[mvk-")
            || (line.contains("EXT_texture_array") && line.contains("not supported"))
    }
}

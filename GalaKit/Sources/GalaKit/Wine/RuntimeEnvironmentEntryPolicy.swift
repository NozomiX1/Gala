public enum RuntimeEnvironmentEntryPresentation: Equatable, Sendable {
    case library
    case prepareEnvironment
    case resetComplete
}

public enum RuntimeEnvironmentEntryPolicy {
    public static func presentation(
        isRuntimeEnvironmentReady: Bool,
        didResetAllApplicationData: Bool
    ) -> RuntimeEnvironmentEntryPresentation {
        if isRuntimeEnvironmentReady {
            return .library
        }

        if didResetAllApplicationData {
            return .resetComplete
        }

        return .prepareEnvironment
    }
}

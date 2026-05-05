import Testing
@testable import GalaKit

@Test func successfulQuickExitWithGraphicsWarningIsNotReportedAsCrash() {
    let output = "EXT_texture_array' is not supported"

    let meaningfulOutput = WineLaunchDiagnostics.meaningfulQuickExitOutput(
        duration: 0.8,
        terminationStatus: 0,
        output: output
    )

    #expect(meaningfulOutput == nil)
}

@Test func failedQuickExitWithMeaningfulOutputIsReported() {
    let output = """
    002c:fixme:winediag:loader_init wine-staging 11.6 is a testing version
    err:module:import_dll Library missing.dll not found
    """

    let meaningfulOutput = WineLaunchDiagnostics.meaningfulQuickExitOutput(
        duration: 1.2,
        terminationStatus: 1,
        output: output
    )

    #expect(meaningfulOutput == "err:module:import_dll Library missing.dll not found")
}

@Test func failedQuickExitWithOnlyGraphicsCapabilityWarningIsNotReported() {
    let output = "warn:vulkan: EXT_texture_array' is not supported"

    let meaningfulOutput = WineLaunchDiagnostics.meaningfulQuickExitOutput(
        duration: 0.8,
        terminationStatus: 1,
        output: output
    )

    #expect(meaningfulOutput == nil)
}

@Test func longRunningFailedProcessIsNotReportedAsQuickExit() {
    let meaningfulOutput = WineLaunchDiagnostics.meaningfulQuickExitOutput(
        duration: 10,
        terminationStatus: 1,
        output: "err:module:import_dll Library missing.dll not found"
    )

    #expect(meaningfulOutput == nil)
}

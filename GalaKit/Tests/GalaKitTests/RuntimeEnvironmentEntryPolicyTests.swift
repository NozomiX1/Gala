import Testing
@testable import GalaKit

@Test func runtimeEntryShowsLibraryWhenEnvironmentIsReady() {
    let presentation = RuntimeEnvironmentEntryPolicy.presentation(
        isRuntimeEnvironmentReady: true,
        didResetAllApplicationData: true
    )

    #expect(presentation == .library)
}

@Test func runtimeEntryShowsAutomaticSetupWhenEnvironmentIsMissing() {
    let presentation = RuntimeEnvironmentEntryPolicy.presentation(
        isRuntimeEnvironmentReady: false,
        didResetAllApplicationData: false
    )

    #expect(presentation == .prepareEnvironment)
}

@Test func runtimeEntryShowsResetCompleteAfterClearingAllData() {
    let presentation = RuntimeEnvironmentEntryPolicy.presentation(
        isRuntimeEnvironmentReady: false,
        didResetAllApplicationData: true
    )

    #expect(presentation == .resetComplete)
}

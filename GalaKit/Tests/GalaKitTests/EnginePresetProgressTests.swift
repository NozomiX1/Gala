import Testing
@testable import GalaKit

@Test func enginePresetProgressReportsFraction() {
    let progress = EnginePresetProgress(
        message: "安装组件 quartz",
        completedUnitCount: 1,
        totalUnitCount: 4,
        currentItemProgress: nil
    )

    #expect(progress.fraction == 0.25)
}

@Test func enginePresetProgressHasNilFractionWithoutUnits() {
    let progress = EnginePresetProgress(
        message: "准备引擎预设",
        completedUnitCount: 0,
        totalUnitCount: 0,
        currentItemProgress: nil
    )

    #expect(progress.fraction == nil)
}

@Test func enginePresetProgressCanReportCurrentItemProgress() {
    let progress = EnginePresetProgress(
        message: "下载 Windows 7 SP1 x64",
        completedUnitCount: 0,
        totalUnitCount: 3,
        currentItemProgress: 0.5
    )

    #expect(progress.currentItemProgress == 0.5)
}

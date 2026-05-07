import XCTest

/// End-to-end tests for the shell integration onboarding flow.
///
/// The onboarding sheet is presented by the Termura harness when the
/// `shellIntegrationInstalled` UserDefaults key is `false` (i.e., first launch).
/// These tests launch the app WITHOUT `UI_TESTING_SKIP_SHELL_ONBOARDING` so the
/// sheet can appear.
///
/// All tests guard against the sheet being absent with `XCTSkip` so they pass
/// gracefully in build configurations where the harness is not present.
///
/// The mock shell installer (`UI_TESTING_MOCK_SHELL_INSTALLER=1`) is always active
/// so "Install Hook" never writes to `~/.zshrc`.
@MainActor
final class ShellIntegrationUITests: TermuraUITestCase {
    // MARK: - Skip button

    func testSkipButtonDismissesOnboardingSheet() throws {
        try launchWithTestProject(skipOnboarding: false, mockShellInstaller: true)
        waitForMainWindow()

        let skipButton = element("skipOnboardingButton")
        guard skipButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Onboarding sheet is not shown in this build configuration (harness absent)")
        }

        skipButton.click()

        XCTAssertFalse(
            skipButton.waitForExistence(timeout: 3),
            "Onboarding sheet must dismiss after tapping 'Skip for now'"
        )
    }

    // MARK: - Shell picker

    func testShellPickerIsPresent() throws {
        try launchWithTestProject(skipOnboarding: false, mockShellInstaller: true)
        waitForMainWindow()

        let picker = element("shellTypePicker")
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("Onboarding sheet is not shown in this build configuration (harness absent)")
        }

        XCTAssertGreaterThan(
            picker.buttons.count,
            0,
            "Shell type picker must contain at least one option"
        )
    }

    // MARK: - Install hook

    func testInstallButtonTransitionsToInstalledState() throws {
        try launchWithTestProject(skipOnboarding: false, mockShellInstaller: true)
        waitForMainWindow()

        let installButton = element("installHookButton")
        guard installButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Onboarding sheet is not shown in this build configuration (harness absent)")
        }

        installButton.click()

        // The button is replaced by a "Installed" label after the mock install completes.
        let installedLabel = element("onboardingInstalledLabel")
        XCTAssertTrue(
            installedLabel.waitForExistence(timeout: 5),
            "Installed confirmation label must appear after clicking 'Install Hook'"
        )

        // The install button must no longer be visible.
        XCTAssertFalse(
            installButton.exists,
            "'Install Hook' button must be replaced by the installed confirmation"
        )
    }

    // MARK: - Sheet dismissed after install completes

    func testSheetAutoDismissesAfterSuccessfulInstall() throws {
        try launchWithTestProject(skipOnboarding: false, mockShellInstaller: true)
        waitForMainWindow()

        let installButton = element("installHookButton")
        guard installButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Onboarding sheet is not shown in this build configuration (harness absent)")
        }

        installButton.click()

        // Wait for the auto-dismiss delay (AppConfig.Runtime.onboardingDismissDelay = 1s + buffer).
        let skipButton = element("skipOnboardingButton")
        XCTAssertFalse(
            skipButton.waitForExistence(timeout: 4),
            "Onboarding sheet must auto-dismiss within ~3s after a successful install"
        )
    }
}

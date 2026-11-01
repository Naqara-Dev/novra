import AppKit
import Sparkle
import SwiftUI

/// Installs updates in place with Sparkle: download, verify the EdDSA signature, swap the app, relaunch.
/// The signing certificate stays the same, so macOS keeps Full Disk Access. Sparkle does the work and
/// reports each step here; the update card in the sidebar draws it. Novra's own check (Updates) still
/// decides when to offer an update, so Sparkle only checks once the user has asked to update.
@MainActor
final class AppUpdater: NSObject, SPUUserDriver {
    private static let shared = AppUpdater()

    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
    private var cancel: (() -> Void)?
    private var install: ((SPUUserUpdateChoice) -> Void)?
    private var received: Int64 = 0
    private var total: Int64 = 0

    static func activate() {
        let me = shared
        // Without a working updater, Update falls back to opening the release on GitHub.
        guard Updates.shared.installer == nil, (try? me.updater.start()) != nil else { return }
        Updates.shared.installer = { me.begin() }
        Updates.shared.cancelUpdate = {
            me.cancel?()
            me.cancel = nil
            me.set(.idle)
        }
        Updates.shared.restartToUpdate = {
            me.set(.installing)
            me.install?(.install)
            me.install = nil
        }
        #if DEBUG
        // `-NovraTestUpdate 1.2.0 -SUFeedURL <appcast> -checkForUpdates NO` runs a whole in-place update on
        // launch, restart included, to try the card without publishing a release.
        if let version = UserDefaults.standard.string(forKey: "NovraTestUpdate") {
            Updates.shared.available = Updates.Release(version: version, page: URL(string: "https://github.com/Naqara-Dev/novra/releases")!,
                                                       download: nil)
            me.begin()
        }
        #endif
    }

    private func begin() {
        guard !Updates.shared.isUpdating else { return }
        set(.preparing)
        updater.checkForUpdates()
    }

    private func set(_ phase: Updates.Phase) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { Updates.shared.phase = phase }
    }

    private func fail(_ reason: String) {
        cancel = nil
        install = nil
        set(.failed(reason))
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        cancel = cancellation
        set(.preparing)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The user already chose to update. An update downloaded earlier only needs the restart.
        if state.stage == .installing {
            install = reply
            set(.ready)
        } else {
            reply(.install)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        fail(String(localized: "The update isn't ready yet. Try again in a few minutes."))
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        fail(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancel = cancellation
        received = 0
        total = 0
        set(.downloading(received: 0, total: 0))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        total = Int64(expectedContentLength)
        Updates.shared.phase = .downloading(received: received, total: total)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let before = total > 0 ? received * 100 / total : 0
        received += Int64(length)
        // Chunks arrive many times a second; redraw once per percent.
        if total == 0 || received * 100 / total != before {
            Updates.shared.phase = .downloading(received: received, total: total)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        cancel = nil
        set(.verifying)
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        install = reply
        set(.ready)
        #if DEBUG
        if UserDefaults.standard.string(forKey: "NovraTestUpdate") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { Updates.shared.restartToUpdate?() }
        }
        #endif
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        set(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        set(.idle)
    }

    func showUpdateInFocus() {
        NSApp.activate()
    }

    func dismissUpdateInstallation() {
        cancel = nil
        install = nil
        if case .failed = Updates.shared.phase { return }
        set(.idle)
    }
}

//
//  UpdateCheckerViewModel.swift
//  OrangeNote
//
//  ViewModel for managing update check state and user interactions.
//

import SwiftUI

/// ViewModel for managing update check state and user interactions.
@MainActor
final class UpdateCheckerViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: UpdateStatus = .idle
    @Published var showingUpdateSheet: Bool = false

    // MARK: - Private

    private let service = UpdateCheckerService()

    // MARK: - Computed Properties

    var isChecking: Bool {
        if case .checking = status { return true }
        return false
    }

    var currentVersion: String {
        UpdateCheckerService.currentAppVersion
    }

    // MARK: - Actions

    /// Initiates an update check.
    func checkForUpdates() async {
        status = .checking

        do {
            status = try await service.checkForUpdates()
            showingUpdateSheet = true
        } catch {
            status = .error(message: error.localizedDescription)
            showingUpdateSheet = true
        }
    }

    /// Opens the release page in the default browser.
    func openReleasePage() {
        guard case .updateAvailable(_, _, let releaseURL, _, _) = status else { return }
        NSWorkspace.shared.open(releaseURL)
    }

    /// Dismisses the update sheet.
    func dismiss() {
        showingUpdateSheet = false
    }
}

//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
//  Fork doctoralvarez/GetMoreRam — version 1.4.0 (2026-11-12)
//  Changelog:
//   - 1.4.0 (2026-11-12): Extended Virtual Addressing (EXTENDED_VIRTUAL_ADDRESSING),
//     requested together with Increased Memory Limit so the one granted before
//     stays; both requests share one function.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AppIDModel : ObservableObject, Hashable {
    static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    var appID: AppID
    @Published var bundleID: String
    @Published var result: String = ""
    @Published var isUpdating = false
    
    init(appID: AppID) {
        self.appID = appID
        bundleID = appID.bundleIdentifier
    }
    
    @MainActor
    func addIncreasedMemory() async throws {
        try await addCapabilities(["INCREASED_MEMORY_LIMIT"], name: "Increased Memory Limit")
    }

    /// fork 1.4: Extended Virtual Addressing. Sent together with Increased
    /// Memory Limit: the request lists the capabilities the App ID should have,
    /// so asking for this one alone could drop the memory limit granted before.
    @MainActor
    func addExtendedVirtualAddressing() async throws {
        try await addCapabilities(["INCREASED_MEMORY_LIMIT", "EXTENDED_VIRTUAL_ADDRESSING"],
                                  name: "Increased Memory Limit + Extended Virtual Addressing")
    }

    @MainActor
    private func addCapabilities(_ capabilities: [String], name: String) async throws {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        result = "Refreshing anisette before updating \(bundleID)..."
        do {
            session.anisetteData = try await AnisetteDataHelper.shared.getAnisetteData(refresh: true)
            result = "Requesting \(name) for \(bundleID)..."
            _ = try await AppleAPI.shared.updateAppID(appID, capabilities: capabilities, team: team, session: session)
            result = "Apple accepted the \(name) request for:\n\(bundleID)\n\nRefresh or reinstall the app in SideStore to obtain a new provisioning profile, then check the entitlements inside the app. The entitlement in the installed app and the resulting memory limit have not been verified."
        } catch {
            result = "Capability update could not be confirmed:\n\(error.detailedDescription)"
            throw error
        }
    }
    
}

class AppIDViewModel : ObservableObject {
    @Published var appIDs : [AppIDModel] = []
    
    @MainActor
    func fetchAppIDs() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }
        
        session.anisetteData = try await AnisetteDataHelper.shared.getAnisetteData(refresh: true)
        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        await MainActor.run {
            appIDs.removeAll()
            for id in ids {
                appIDs.append(AppIDModel(appID: id))
            }
        }
    }
}

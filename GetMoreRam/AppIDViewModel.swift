//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
//  Fork doctoralvarez/GetMoreRam — version 1.6.0 (2026-11-12)
//  Changelog:
//   - 1.6.0 (2026-11-12): Push Notifications and iCloud (paid accounts). Every
//     request now keeps what the App ID already has: it sends the capabilities
//     read from Apple plus the new one, so nothing granted before is dropped.
//     Status of the four is read after Refresh.
//   - 1.5.0 (2026-11-12): after Refresh, each App ID reads its capabilities on
//     Apple's server (v1 bundleIds/{id}?include=bundleIdCapabilities) and shows
//     whether Increased Memory Limit and Extended Virtual Addressing are on;
//     re-read after a request.
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
    /* fork 1.5: what Apple's server says this App ID has */
    @Published var memoryLimit: CapabilityState = .unknown
    @Published var virtualAddressing: CapabilityState = .unknown
    @Published var pushNotifications: CapabilityState = .unknown
    @Published var iCloud: CapabilityState = .unknown
    /* the capabilities Apple reported, sent again with every request */
    var enabledOnServer = Set<String>()
    @Published var isChecking = false
    
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

    /// fork 1.6: Push Notifications (paid accounts; the app also needs aps-environment and a server)
    @MainActor
    func addPushNotifications() async throws {
        try await addCapabilities(["PUSH_NOTIFICATIONS"], name: "Push Notifications")
    }

    /// fork 1.6: iCloud (paid accounts; containers are assigned separately)
    @MainActor
    func addICloud() async throws {
        try await addCapabilities(["ICLOUD"], name: "iCloud")
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
            /* keep what the App ID already has (read just before) */
            await checkCapabilities()
            var wanted = enabledOnServer
            for capability in capabilities { wanted.insert(capability) }
            let ordered = wanted.sorted()
            result = "Requesting \(name) for \(bundleID)...\nSending: \(ordered.joined(separator: ", "))"
            _ = try await AppleAPI.shared.updateAppID(appID, capabilities: ordered, team: team, session: session)
            await checkCapabilities()
            result = "Apple accepted the \(name) request for:\n\(bundleID)\n\nRefresh or reinstall the app in SideStore to obtain a new provisioning profile, then check the entitlements inside the app. The entitlement in the installed app and the resulting memory limit have not been verified."
        } catch {
            result = "Capability update could not be confirmed:\n\(error.detailedDescription)"
            await checkCapabilities()
            throw error
        }
    }
    
    /// Reads which capabilities Apple has for this App ID
    @MainActor
    func checkCapabilities() async {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let enabled = try await CapabilityReader.enabledCapabilities(of: appID, team: team, session: session)
            enabledOnServer = enabled
            memoryLimit = enabled.contains("INCREASED_MEMORY_LIMIT") ? .on : .off
            virtualAddressing = enabled.contains("EXTENDED_VIRTUAL_ADDRESSING") ? .on : .off
            pushNotifications = enabled.contains("PUSH_NOTIFICATIONS") ? .on : .off
            iCloud = enabled.contains("ICLOUD") ? .on : .off
        } catch {
            memoryLimit = .unknown
            virtualAddressing = .unknown
            pushNotifications = .unknown
            iCloud = .unknown
        }
    }
}

/// fork 1.5: on (green), off (red) or not read (gray)
enum CapabilityState {
    case on, off, unknown
}

/// fork 1.5: the capabilities of one App ID, from Apple's Developer Services
enum CapabilityReader {
    /// "<bundleIdId>_<CAPABILITY>" -> "CAPABILITY"
    static func capabilityName(fromID id: String, appID: AppID) -> String? {
        let prefix = appID.identifier + "_"
        if id.hasPrefix(prefix) {
            let name = String(id.dropFirst(prefix.count))
            return name.isEmpty ? nil : name
        }
        guard let underscore = id.firstIndex(of: "_") else { return nil }
        let name = String(id[id.index(after: underscore)...])
        return name.isEmpty ? nil : name
    }

    static func enabledCapabilities(of appID: AppID, team: Team, session: AppleAPISession) async throws -> Set<String> {
        let url = AppleAPI.shared.v1URL.appendingPathComponent("bundleIds").appendingPathComponent(appID.identifier)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response = try await AppleAPI.shared.sendServicesRequest(originalRequest: request,
                                                                     additionalParameters: ["include": "bundleIdCapabilities"],
                                                                     session: session, team: team)
        if response["data"] == nil, response["errors"] != nil || response["error"] != nil {
            throw "Apple did not return the App ID."
        }
        var found = Set<String>()
        /* included bundleIdCapabilities: attributes.capabilityType (or the capability relationship) */
        let included = response["included"] as? [[String: Any]] ?? []
        for item in included {
            let attributes = item["attributes"] as? [String: Any] ?? [:]
            if let enabled = attributes["enabled"] as? Bool, enabled == false { continue }
            if let type = attributes["capabilityType"] as? String, !type.isEmpty {
                found.insert(type)
                continue
            }
            if let relationships = item["relationships"] as? [String: Any],
               let capability = relationships["capability"] as? [String: Any],
               let data = capability["data"] as? [String: Any],
               let id = data["id"] as? String, !id.isEmpty {
                found.insert(id)
                continue
            }
            if let id = item["id"] as? String, let name = capabilityName(fromID: id, appID: appID) {
                found.insert(name)
            }
        }
        /* the relationship ids alone ("<bundleIdId>_<CAPABILITY>") when nothing is included */
        if included.isEmpty,
           let data = response["data"] as? [String: Any],
           let relationships = data["relationships"] as? [String: Any],
           let capabilities = relationships["bundleIdCapabilities"] as? [String: Any],
           let list = capabilities["data"] as? [[String: Any]] {
            for entry in list {
                if let id = entry["id"] as? String, let name = capabilityName(fromID: id, appID: appID) {
                    found.insert(name)
                }
            }
        }
        return found
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
        /* fork 1.5: what Apple has for each one (one after another, to stay gentle) */
        for model in appIDs {
            await model.checkCapabilities()
        }
    }
}

//
//  AnisettePresets.swift
//  GetMoreRam
//
//  Fork doctoralvarez/GetMoreRam — version 1.3.0 (2026-11-12)
//  Changelog:
//   - 1.3.0 (2026-11-12): preset anisette servers (SideStore's official list,
//     built in and refreshable from servers.sidestore.io), client profiles
//     (Windows / iTunes, SideStore macOS, Mac / Xcode, custom) and a server
//     reachability test.
//

import Foundation

/// One anisette server (same shape as SideStore's servers.json)
struct AnisetteServerPreset: Codable, Identifiable, Hashable {
    var id: String { address }
    let name: String
    let address: String
}

/// The headers GetMoreRam sends as a given Apple client
struct AuthenticationClientProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let clientInfo: String
    let userAgent: String
}

enum AnisettePresets {
    /// SideStore's official list (servers.sidestore.io/servers.json, November 2026)
    static let builtInServers: [AnisetteServerPreset] = [
        AnisetteServerPreset(name: "SideStore", address: "https://ani.sidestore.io"),
        AnisetteServerPreset(name: "SideStore (.app)", address: "https://ani.sidestore.app"),
        AnisetteServerPreset(name: "SideStore (.zip)", address: "https://ani.sidestore.zip"),
        AnisetteServerPreset(name: "SideStore (.xyz)", address: "https://ani.846969.xyz"),
        AnisetteServerPreset(name: "SideStore (New)", address: "https://new.ani.sidestore.io"),
        AnisetteServerPreset(name: "jkcoxson", address: "https://mac-ani.jkcoxson.com"),
        AnisetteServerPreset(name: "jkcoxson (Windows ADI)", address: "https://ani.jkcoxson.com"),
        AnisetteServerPreset(name: "SideStore (Windows ADI)", address: "https://win.ani.sidestore.io"),
        AnisetteServerPreset(name: "nythepegasus", address: "https://ani.npeg.us"),
        AnisetteServerPreset(name: "Macley", address: "http://5.249.163.88:6969"),
        AnisetteServerPreset(name: "WE. Studio", address: "https://anisette.wedotstud.io"),
        AnisetteServerPreset(name: "SteX", address: "https://ani.xu30.top"),
        AnisetteServerPreset(name: "owoellen", address: "https://ani.owoellen.rocks"),
        AnisetteServerPreset(name: "iDH Server", address: "https://ani.idevicehacked.com"),
        AnisetteServerPreset(name: "neoarz", address: "https://ani.neoarz.com"),
        AnisetteServerPreset(name: "pythonplayer123", address: "https://ani3server.fly.dev"),
        AnisetteServerPreset(name: "Jayden's Server", address: "https://ani.jaydenha.uk"),
        AnisetteServerPreset(name: "crystall1nedev", address: "https://anisette.crystall1ne.dev"),
        AnisetteServerPreset(name: "ethxn (omnisette)", address: "https://omni.ethxn.xyz"),
        AnisetteServerPreset(name: "koremi", address: "https://ani.sjwon0368.dpdns.org"),
        AnisetteServerPreset(name: "uwucloud", address: "https://ani.uwucloud.fun"),
        AnisetteServerPreset(name: "Lill q", address: "https://anisette.lillq.me")
    ]

    static let listURL = URL(string: "https://servers.sidestore.io/servers.json")!
    static let savedListKey = "AnisetteServerList"

    static let windowsITunes = AuthenticationClientProfile(
        id: "windows-itunes",
        name: "Windows / iTunes",
        detail: "What this fork used so far (SideStore's Windows / iTunes setup)",
        clientInfo: AuthenticationConfiguration.defaultClientInfo,
        userAgent: AuthenticationConfiguration.defaultUserAgent)

    static let sideStoreMac = AuthenticationClientProfile(
        id: "sidestore-macos",
        name: "macOS (SideStore 0.6+)",
        detail: "The default of current SideStore (AnisetteKit): a Mac on macOS 26.6",
        clientInfo: "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>",
        userAgent: "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.akd/1.0)")

    static let macXcode = AuthenticationClientProfile(
        id: "mac-xcode",
        name: "Mac / Xcode (AltStore classic)",
        detail: "The classic AltSign / AltStore headers (Xcode on macOS 10.15)",
        clientInfo: "<MacBookPro15,1> <Mac OS X;10.15.2;19C57> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>",
        userAgent: "Xcode")

    static let clientProfiles: [AuthenticationClientProfile] = [windowsITunes, sideStoreMac, macXcode]

    /// The profile whose headers are exactly these, if any
    static func profile(clientInfo: String, userAgent: String) -> AuthenticationClientProfile? {
        clientProfiles.first {
            $0.clientInfo == clientInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                && $0.userAgent == userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Servers saved from the last refresh, else the built-in list
    static func savedServers() -> [AnisetteServerPreset] {
        guard let data = UserDefaults.standard.data(forKey: savedListKey),
              let list = try? JSONDecoder().decode([AnisetteServerPreset].self, from: data),
              !list.isEmpty else { return builtInServers }
        return list
    }

    private struct ServerList: Decodable {
        let servers: [AnisetteServerPreset]
    }

    /// Downloads SideStore's current list and saves it
    static func refreshServers() async throws -> [AnisetteServerPreset] {
        var request = URLRequest(url: listURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw "The server list answered HTTP \(http.statusCode)."
        }
        let servers = try JSONDecoder().decode(ServerList.self, from: data).servers
            .filter { URL(string: $0.address) != nil }
        guard !servers.isEmpty else { throw "The server list is empty." }
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: savedListKey)
        }
        return servers
    }

    /// Result of asking one server for its client info (anisette v3)
    struct TestResult {
        let ok: Bool
        let summary: String
    }

    /// Asks a server for /v3/client_info and reports whether it answered, how fast
    static func test(_ address: String) async -> TestResult {
        guard let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return TestResult(ok: false, summary: "Not a valid address")
        }
        var request = URLRequest(url: base.appendingPathComponent("v3").appendingPathComponent("client_info"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
            if status == 200 && isJSON {
                return TestResult(ok: true, summary: "OK · \(milliseconds) ms")
            }
            return TestResult(ok: false, summary: "HTTP \(status)\(isJSON ? "" : ", not anisette v3") · \(milliseconds) ms")
        } catch {
            return TestResult(ok: false, summary: (error as NSError).localizedDescription)
        }
    }
}

//
//  SettingsView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/14.
//
//  Fork doctoralvarez/GetMoreRam — version 1.3.0 (2026-11-12)
//  Changelog:
//   - 1.3.0 (2026-11-12): Authentication: the anisette server is chosen from
//     SideStore's list (with a reachability test and a refresh) or typed; a
//     Client picker sets the headers (Windows / iTunes, SideStore macOS,
//     Mac / Xcode, or custom); the raw headers stay editable.
//

import SwiftUI
import UniformTypeIdentifiers
import StosSign_API
import StosSign_Auth
import StosSign_Common

struct SettingsView: View {

    @State var email = ""
    @State var teamId = ""
    @StateObject var viewModel : LoginViewModel
    @EnvironmentObject private var sharedModel : SharedModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var importResultShow = false
    @State private var importResultInfo = ""
    @State private var isImportingSideStoreAccount = false
    /* fork: anisette server list and client profiles */
    @State private var serverPickerShow = false
    private let customProfileID = "custom"

    private var currentServerName: String {
        AnisettePresets.savedServers().first(where: { $0.address == sharedModel.anisetteServerURL })?.name ?? "Custom"
    }

    /// The profile matching the saved headers; choosing one fills them in
    private var clientProfileSelection: Binding<String> {
        Binding(
            get: {
                AnisettePresets.profile(clientInfo: sharedModel.authenticationClientInfo,
                                        userAgent: sharedModel.authenticationUserAgent)?.id ?? customProfileID
            },
            set: { id in
                guard let profile = AnisettePresets.clientProfiles.first(where: { $0.id == id }) else { return }
                sharedModel.authenticationClientInfo = profile.clientInfo
                sharedModel.authenticationUserAgent = profile.userAgent
            }
        )
    }
    

    var body: some View {
        Form {

            Section {
                if sharedModel.isLogin {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(email)
                    }
                    HStack {
                        Text("Team ID")
                        Spacer()
                        Text(teamId)
                    }
                } else {
                    Button("Sign in") {
                        viewModel.loginModalShow = true
                    }
                    
                    Button("Import SideStore Account") {
                        isImportingSideStoreAccount = true
                    }
                }
            } header: {
                Text("Account")
            }
            
            Section {
                /* fork: pick a server from SideStore's list (or type one) */
                Button {
                    serverPickerShow = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anisette Server").foregroundStyle(.primary)
                            Text(sharedModel.anisetteServerURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(currentServerName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .sheet(isPresented: $serverPickerShow) {
                    AnisetteServerPickerView(selection: $sharedModel.anisetteServerURL)
                }

                /* fork: client profiles (the headers Apple sees) */
                Picker("Client", selection: clientProfileSelection) {
                    ForEach(AnisettePresets.clientProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                    Text("Custom").tag(customProfileID)
                }
                if let profile = AnisettePresets.clientProfiles.first(where: { $0.id == clientProfileSelection.wrappedValue }) {
                    Text(profile.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Headers (Client Info, User Agent)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client Info").font(.caption).foregroundStyle(.secondary)
                        TextField("Client Info", text: $sharedModel.authenticationClientInfo, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                            .accessibilityLabel("Client Info")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("User Agent").font(.caption).foregroundStyle(.secondary)
                        TextField("User Agent", text: $sharedModel.authenticationUserAgent, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                            .accessibilityLabel("User Agent")
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Used for anisette provisioning, Apple ID sign-in and two-factor verification. If sign-in fails (GrandSlam, 403, 503), try another server first, then another client. To change them while signed in, sign out (Clean Up Keychain) and sign in again.")
            }
            .disabled(viewModel.isLoginInProgress || sharedModel.isLogin)
            
            Section {
                Button("Clean Up Keychain") {
                    cleanUp()
                }
            } footer: {
                Text("If something went wrong during signing in, please try to clean up the keychain, repoen the app and try again. \n \nIf you use SideStore and are already signed in, please also try exporting SideStore Account from SideStore settings and import it here to sign in.")
            }
        }
        .alert("Error", isPresented: $errorShow){
            Button("OK".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .alert("SideStore Account", isPresented: $importResultShow){
            Button("OK".loc, action: {
            })
        } message: {
            Text(importResultInfo)
        }
        .fileImporter(
            isPresented: $isImportingSideStoreAccount,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importSideStoreAccount(result)
        }
        
        .sheet(isPresented: $viewModel.loginModalShow, onDismiss: {
            viewModel.cancelAuthentication()
        }) {
            loginModal
        }
        .sheet(isPresented: $viewModel.teamSelectionShow) {
            teamSelectionView
        }
    }
    
    var loginModal: some View {
        NavigationView {
            Form {
                Section {
                    TextField("", text: $viewModel.appleID)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .disabled(viewModel.isLoginInProgress)
                } header: {
                    Text("Apple ID")
                }
                Section {
                    SecureField("", text: $viewModel.password)
                        .disabled(viewModel.isLoginInProgress)
                } header: {
                    Text("Password")
                }
                if viewModel.needVerificationCode {
                    Section {
                        Text("Enter the code Apple sent to your trusted device.")
                            .font(.footnote)
                        TextField("", text: $viewModel.verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .disabled(viewModel.isVerificationCodeSubmitting)
                    } header: {
                        Text("Verification Code")
                    }
                }
                Section {
                    Button("Continue") {
                        Task{ await loginButtonClicked() }
                    }
                    .disabled(continueButtonDisabled)
                }
                
                Section {
                    Text(viewModel.logs)
                        .font(.system(.subheadline, design: .monospaced))
                } header: {
                    Text("Debugging")
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelAuthentication()
                        viewModel.loginModalShow = false
                    }
                }
            }
        }
        .onAppear {
            if let email = Keychain.shared.appleIDEmailAddress, let password = Keychain.shared.appleIDPassword {
                viewModel.appleID = email
                viewModel.password = password
            }
        }
    }
    
    var teamSelectionView: some View {
        NavigationView {
            List {
                ForEach(Array(viewModel.availableTeams.enumerated()), id: \.offset) { _, team in
                    Button {
                        selectTeam(team)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.name)
                                .foregroundStyle(.primary)
                            Text("\(team.identifier) · \(teamTypeDescription(team.type))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Choose Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        cancelTeamSelection()
                    }
                }
            }
        }
    }
    
    func loginButtonClicked() async {
        do {
            if viewModel.needVerificationCode {
                viewModel.submitVerificationCode()
                return
            }
            
            let result = try await viewModel.authenticate()
            if result {
                await MainActor.run {
                    viewModel.loginModalShow = false
                    email = sharedModel.account!.appleID
                    teamId = ""
                }

                if viewModel.availableTeams.count == 1,
                   let team = viewModel.availableTeams.first {
                    await MainActor.run {
                        selectTeam(team)
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await MainActor.run {
                        viewModel.teamSelectionShow = true
                    }
                }
            }
            
        } catch is CancellationError {
            return
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }

    private var continueButtonDisabled: Bool {
        if viewModel.needVerificationCode {
            return viewModel.isVerificationCodeSubmitting ||
                viewModel.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return viewModel.isLoginInProgress
    }
    
    func cleanUp() {
        Keychain.shared.adiPb = nil
        Keychain.shared.identifier = nil
        Keychain.shared.appleIDPassword = nil
        Keychain.shared.appleIDEmailAddress = nil
        AnisetteDataHelper.shared.resetClientInfo()
        sharedModel.session = nil
        sharedModel.account = nil
        sharedModel.team = nil
        sharedModel.isLogin = false
        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false
        email = ""
        teamId = ""
    }
    
    func importSideStoreAccount(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw "No file selected."
            }
            
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let data = try Data(contentsOf: url)
            let account = try SideStoreAccountImporter.importAccount(from: data)
            
            viewModel.appleID = account.email
            viewModel.password = account.password
            sharedModel.session = nil
            sharedModel.account = nil
            sharedModel.team = nil
            sharedModel.isLogin = false
            viewModel.availableTeams = []
            viewModel.teamSelectionShow = false
            email = account.email
            teamId = ""
            importResultInfo = "Imported \(account.email).\nTap \"Sign In\" to continue."
            importResultShow = true
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }
    
    func selectTeam(_ team: Team) {
        sharedModel.team = team
        sharedModel.isLogin = true
        email = sharedModel.account?.appleID ?? email
        teamId = team.identifier
        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false
    }
    
    func cancelTeamSelection() {
        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false
        sharedModel.session = nil
        sharedModel.account = nil
        sharedModel.team = nil
        sharedModel.isLogin = false
        email = ""
        teamId = ""
    }
    
    func teamTypeDescription(_ type: TeamType) -> String {
        switch type {
        case .free:
            return "Free"
        case .individual:
            return "Individual"
        case .organization:
            return "Organization"
        case .unknown:
            return "Unknown"
        }
    }
    
}

// MARK: - fork: anisette server picker

struct AnisetteServerPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [AnisetteServerPreset] = AnisettePresets.savedServers()
    @State private var results: [String: AnisettePresets.TestResult] = [:]
    @State private var testing: Set<String> = []
    @State private var custom = ""
    @State private var refreshing = false
    @State private var message = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(servers) { server in
                        serverRow(server)
                    }
                } header: {
                    Text("SideStore's servers")
                } footer: {
                    Text(message.isEmpty ? "Tap one to use it. \"Test All\" asks each server for its anisette data and shows which answer and how fast." : message)
                }

                Section {
                    TextField("https://", text: $custom)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use This Address") {
                        let address = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !address.isEmpty else { return }
                        selection = address
                        dismiss()
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Other server")
                }

                Section {
                    Button(refreshing ? "Downloading…" : "Download the Latest List") {
                        Task { await refreshList() }
                    }
                    .disabled(refreshing)
                    Button("Use the Built-in List") {
                        UserDefaults.standard.removeObject(forKey: AnisettePresets.savedListKey)
                        servers = AnisettePresets.builtInServers
                        results = [:]
                        message = "Built-in list (\(servers.count) servers)."
                    }
                }
            }
            .navigationTitle("Anisette Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Test All") {
                        Task { await testAll() }
                    }
                    .disabled(!testing.isEmpty)
                }
            }
            .onAppear {
                if !servers.contains(where: { $0.address == selection }) {
                    custom = selection
                }
            }
        }
    }

    private func serverRow(_ server: AnisetteServerPreset) -> some View {
        let result = results[server.address]
        let isTesting = testing.contains(server.address)
        return Button {
            selection = server.address
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).foregroundStyle(.primary)
                    Text(server.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let result {
                        Text(result.summary)
                            .font(.caption2)
                            .foregroundStyle(result.ok ? Color.green : Color.red)
                    }
                }
                Spacer()
                if isTesting {
                    ProgressView()
                } else if server.address == selection {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Test") {
                Task { await test(server.address) }
            }
            .tint(.blue)
        }
    }

    private func test(_ address: String) async {
        testing.insert(address)
        let result = await AnisettePresets.test(address)
        results[address] = result
        testing.remove(address)
    }

    private func testAll() async {
        let addresses = servers.map(\.address)
        for address in addresses { testing.insert(address) }
        await withTaskGroup(of: (String, AnisettePresets.TestResult).self) { group in
            for address in addresses {
                group.addTask { (address, await AnisettePresets.test(address)) }
            }
            for await (address, result) in group {
                results[address] = result
                testing.remove(address)
            }
        }
        let working = results.values.filter(\.ok).count
        message = "\(working) of \(addresses.count) servers answered."
        /* the ones that answered first, fastest first */
        servers.sort { first, second in
            let a = results[first.address]
            let b = results[second.address]
            if (a?.ok ?? false) != (b?.ok ?? false) { return a?.ok ?? false }
            return milliseconds(a) < milliseconds(b)
        }
    }

    private func milliseconds(_ result: AnisettePresets.TestResult?) -> Int {
        guard let summary = result?.summary,
              let range = summary.range(of: #"(\d+) ms"#, options: .regularExpression) else { return Int.max }
        return Int(summary[range].replacingOccurrences(of: " ms", with: "")) ?? Int.max
    }

    private func refreshList() async {
        refreshing = true
        defer { refreshing = false }
        do {
            servers = try await AnisettePresets.refreshServers()
            results = [:]
            message = "Downloaded \(servers.count) servers from servers.sidestore.io."
        } catch {
            message = "Could not download the list: \(error.localizedDescription). The saved list stays."
        }
    }
}

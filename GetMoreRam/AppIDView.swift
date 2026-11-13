//
//  AppIDView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
//  Fork doctoralvarez/GetMoreRam — version 1.6.0 (2026-11-12)
//  Changelog:
//   - 1.6.0 (2026-11-12): Push Notifications and iCloud buttons and status
//     (bell and cloud icons in the list).
//   - 1.5.0 (2026-11-12): each App ID in the list shows two icons, green when
//     Apple has the capability on and red when not (gray: not read): memory
//     chip = Increased Memory Limit, arrows = Extended Virtual Addressing; the
//     App ID screen shows them too.
//   - 1.4.0 (2026-11-12): "Add Extended Virtual Addressing" button.
//
import SwiftUI

struct AppIDEditView : View {
    @StateObject var viewModel : AppIDModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    var body: some View {
        Form {
            Section {
                Button {
                    Task { await addIncreasedMemoryLimit() }
                } label: {
                    Text("Add Increased Memory Limit")
                }
                .disabled(viewModel.isUpdating)
                /* fork 1.4 */
                Button {
                    Task { await addExtendedVirtualAddressing() }
                } label: {
                    Text("Add Extended Virtual Addressing")
                }
                .disabled(viewModel.isUpdating)
                /* fork 1.6 */
                Button {
                    Task { await run { try await viewModel.addPushNotifications() } }
                } label: {
                    Text("Add Push Notifications")
                }
                .disabled(viewModel.isUpdating)
                Button {
                    Task { await run { try await viewModel.addICloud() } }
                } label: {
                    Text("Add iCloud")
                }
                .disabled(viewModel.isUpdating)
                if viewModel.isUpdating { ProgressView("Updating capability…") }
            } footer: {
                Text("Each request keeps what the App ID already has. Extended Virtual Addressing, Push Notifications and iCloud need a paid developer account; Apple says so below if not. The app itself must also ask for the entitlement, or the signer leaves it out.")
            }
            
            Section {
                CapabilityStatusRow(title: "Increased Memory Limit", systemImage: "memorychip", state: viewModel.memoryLimit)
                CapabilityStatusRow(title: "Extended Virtual Addressing", systemImage: "arrow.up.left.and.arrow.down.right", state: viewModel.virtualAddressing)
                CapabilityStatusRow(title: "Push Notifications", systemImage: "bell.badge", state: viewModel.pushNotifications)
                CapabilityStatusRow(title: "iCloud", systemImage: "icloud", state: viewModel.iCloud)
                Button("Check Again") {
                    Task { await viewModel.checkCapabilities() }
                }
                .disabled(viewModel.isChecking || viewModel.isUpdating)
            } header: {
                Text("On Apple's Server")
            }

            Section {
                Text(viewModel.result)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("Server Response")
            }
        }
        .alert("Error", isPresented: $errorShow){
            Button("OK".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .navigationTitle(viewModel.bundleID)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }

    func addExtendedVirtualAddressing() async {
        do {
            try await viewModel.addExtendedVirtualAddressing()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }

    func addIncreasedMemoryLimit() async {
        do {
            try await viewModel.addIncreasedMemory()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }

    }
}


struct AppIDView : View {
    @StateObject var viewModel : AppIDViewModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(viewModel.appIDs, id: \.self) { appID in
                        NavigationLink {
                            AppIDEditView(viewModel: appID)
                        } label: {
                            AppIDRow(viewModel: appID)
                        }
                    }
                } header: {
                    Text("App IDs")
                } footer: {
                    Text("Green: Apple has it on for that App ID. Red: not on. Gray: could not be read. Memory chip = Increased Memory Limit, arrows = Extended Virtual Addressing, bell = Push Notifications, cloud = iCloud. Once both you want are green, refresh or reinstall that app in SideStore.")
                }
                
                Section {
                    Button("Refresh") {
                        Task { await refreshButtonClicked() }
                    }
                }
            }
            .alert("Error", isPresented: $errorShow){
                Button("OK".loc, action: {
                })
            } message: {
                Text(errorInfo)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func refreshButtonClicked() async {
        do {
            try await viewModel.fetchAppIDs()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }
}


// MARK: - fork 1.5: capability icons

private func capabilityColor(_ state: CapabilityState) -> Color {
    switch state {
    case .on: return .green
    case .off: return .red
    case .unknown: return .gray
    }
}

private func capabilityText(_ state: CapabilityState) -> String {
    switch state {
    case .on: return "On"
    case .off: return "Off"
    case .unknown: return "Not read"
    }
}

struct AppIDRow: View {
    @ObservedObject var viewModel: AppIDModel

    var body: some View {
        HStack(spacing: 10) {
            Text(viewModel.bundleID)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if viewModel.isChecking {
                ProgressView()
            } else {
                Image(systemName: "memorychip.fill")
                    .foregroundStyle(capabilityColor(viewModel.memoryLimit))
                    .accessibilityLabel("Increased Memory Limit: \(capabilityText(viewModel.memoryLimit))")
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(capabilityColor(viewModel.virtualAddressing))
                    .accessibilityLabel("Extended Virtual Addressing: \(capabilityText(viewModel.virtualAddressing))")
                Image(systemName: "bell.fill")
                    .foregroundStyle(capabilityColor(viewModel.pushNotifications))
                    .accessibilityLabel("Push Notifications: \(capabilityText(viewModel.pushNotifications))")
                Image(systemName: "icloud.fill")
                    .foregroundStyle(capabilityColor(viewModel.iCloud))
                    .accessibilityLabel("iCloud: \(capabilityText(viewModel.iCloud))")
            }
        }
    }
}

struct CapabilityStatusRow: View {
    let title: String
    let systemImage: String
    let state: CapabilityState

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(capabilityText(state))
                .foregroundStyle(capabilityColor(state))
        }
    }
}

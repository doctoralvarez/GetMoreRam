//
//  AppIDView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
//  Fork doctoralvarez/GetMoreRam — version 1.4.0 (2026-11-12)
//  Changelog:
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
                if viewModel.isUpdating { ProgressView("Updating capability…") }
            } footer: {
                Text("Extended Virtual Addressing is requested together with Increased Memory Limit, so the memory limit stays. Apple may refuse it for free accounts; the response below says.")
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
                            Text(appID.bundleID)
                        }
                    }
                } header: {
                    Text("App IDs")
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

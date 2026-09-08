//
//  Helper.swift
//  Silocleaner
//
//  Created by Alin Lupascu on 3/14/25.
//

import SwiftUI
import Foundation

struct HelperSettingsTab: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var helperToolManager = HelperToolManager.shared

    var body: some View {
        VStack(spacing: 20) {

            // === Frequency ============================================================================================
            PearGroupBox(
                header: {
                    HStack {
                        Text("Management").foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText).font(.title2)
                        Spacer()
//                        Button(action: {
                    }

                },
                content: {

                    VStack {
                        HStack(spacing: 0) {
                            Image(systemName: "key")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .padding(.trailing)
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)
                            Text("Perform privileged operations seamlessly without password prompts")
                                .font(.callout)
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)
                                .frame(minWidth: 450, maxWidth: .infinity, alignment: .leading)

//                            Spacer()

                            Toggle(isOn: Binding(
                                get: { helperToolManager.isHelperToolInstalled },
                                set: { newValue in
                                    Task {
                                        if newValue {
                                            await helperToolManager.manageHelperTool(action: .install)
                                        } else {
                                            await helperToolManager.manageHelperTool(action: .uninstall)
                                        }
                                    }
                                }
                            ), label: {
                            })
                            .toggleStyle(SettingsToggle())
                            .frame(alignment: .trailing)
                            .disabled(helperToolManager.lifecycleState.isBusy)

                        }

                        Divider()
                            .padding(.vertical, 5)

                        HStack(alignment: .top) {
                            Label(
                                helperToolManager.lifecycleState.title,
                                systemImage: helperStateSymbol
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(helperStateColor)

                            Text(helperToolManager.message)
                                .font(.footnote)
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                            Spacer()

                            if helperToolManager.lifecycleState.needsSystemSettings {
                                Button("Open Login Items") {
                                    helperToolManager.openSMSettings()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(5)



                })


            PearGroupBox(header: {
                Text("Information").foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText).font(.title2)
            }, content: {
                let message: LocalizedStringKey = """
                Silocleaner will ask you to enter your password once to enable the helper, then all subsequent privileged operations will run without any other prompts as long as the helper stays enabled in Settings > Login Items. This authorization is all managed by macOS via SMAppService.
                """

                VStack(alignment: .leading, spacing: 20) {
                    Text(message).foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText).font(.body).lineSpacing(5)

                    Text("Since **AuthorizationExecuteWithPrivileges** has been deprecated by Apple as a less secure authentication method, it has been removed from Silocleaner and the helper tool will be the only option going forward.").font(.footnote).foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                }

            })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await helperToolManager.manageHelperTool()
            }
        }

    }

    private var helperStateSymbol: String {
        switch helperToolManager.lifecycleState {
        case .enabled: return "checkmark.circle.fill"
        case .approvalRequired, .denied: return "exclamationmark.triangle.fill"
        case .invalidSignature, .failed: return "xmark.octagon.fill"
        case .installing, .checking, .maintenance: return "arrow.triangle.2.circlepath"
        case .unavailable, .installable: return "arrow.down.circle"
        }
    }

    private var helperStateColor: Color {
        switch helperToolManager.lifecycleState {
        case .enabled: return .green
        case .approvalRequired, .denied: return .orange
        case .invalidSignature, .failed: return .red
        default: return ThemeColors.shared(for: colorScheme).secondaryText
        }
    }

}

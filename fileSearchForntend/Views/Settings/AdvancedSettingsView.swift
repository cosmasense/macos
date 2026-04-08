//
//  AdvancedSettingsView.swift
//  fileSearchForntend
//
//  Layer 2 settings: AI model configuration, queue settings, scheduler, metrics.
//  Opened as a sheet from the main SettingsView.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Advanced Settings")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Processing Models
                    SettingsSectionHeader(title: "Processing Models", icon: "cpu")
                    BackendSettingsSection()

                    Divider()

                    // Queue & Scheduler
                    SettingsSectionHeader(title: "Queue & Scheduler", icon: "clock.arrow.2.circlepath")
                    IndexingSettingsSection()

                    Spacer()
                }
                .padding(24)
            }
        }
        .background(.ultraThinMaterial)
    }
}

#Preview {
    AdvancedSettingsView()
        .environment(AppModel())
        .environment(CosmaManager())
        .frame(width: 600, height: 600)
}

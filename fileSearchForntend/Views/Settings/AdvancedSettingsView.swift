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
        VStack(alignment: .leading, spacing: 28) {
            Text("Advanced")
                .font(.system(size: 22, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "Processing Models", icon: "cpu")
                BackendSettingsSection()
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "Queue & Scheduler", icon: "clock.arrow.2.circlepath")
                IndexingSettingsSection()
            }
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environment(AppModel())
        .environment(CosmaManager())
        .frame(width: 600, height: 600)
}

//
//  SettingsView.swift
//  fileSearchForntend
//
//  Settings placeholder view
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Settings")
                .font(.title)
                .fontWeight(.semibold)

            Text("Settings options will be available here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
}

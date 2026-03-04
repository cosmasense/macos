//
//  SidebarView.swift
//  fileSearchForntend
//
//  Navigation sidebar with Home, Folders, and Settings
//  Styled for macOS 26 with native sidebar appearance
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            List(selection: $model.selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label {
                            Text(item.rawValue)
                                .font(.system(size: 14))
                        } icon: {
                            Image(systemName: iconName(for: item))
                                .font(.system(size: 16))
                        }
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaPadding(.top)

            SidebarConnectionFooter(state: model.backendConnectionState)
        }
    }

    private func iconName(for item: SidebarItem) -> String {
        switch item {
        case .home:
            return "house.fill"
        case .folders:
            return "folder.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

// MARK: - Connection Status Footer

private struct SidebarConnectionFooter: View {
    let state: AppModel.BackendConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(state.statusDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .idle:
            return .gray
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppModel())
}

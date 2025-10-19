//
//  SidebarView.swift
//  fileSearchForntend
//
//  Navigation sidebar with Home, Jobs, and Settings
//  Styled for macOS 26 with native sidebar appearance
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

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
        .navigationTitle("File Organizer")
        .scrollContentBackground(.hidden)
    }

    private func iconName(for item: SidebarItem) -> String {
        switch item {
        case .home:
            return "house.fill"
        case .jobs:
            return "tray.2.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppModel())
}

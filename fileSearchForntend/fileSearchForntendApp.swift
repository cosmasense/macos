//
//  fileSearchForntendApp.swift
//  fileSearchForntend
//
//  Created by Ethan Pan on 10/19/25.
//

import SwiftUI

@main
struct fileSearchForntendApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}

//
//  SearchToken.swift
//  fileSearchForntend
//
//  Represents a token in the search query (e.g., @FolderName)
//

import Foundation

struct SearchToken: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case folder
        /// `@Applications` — restricts the unified search to the apps
        /// source; files are skipped entirely backend-side.
        case applicationsOnly
        /// `@*.pdf` / `@*report*` — pushes a glob filter into the
        /// backend SQL LIKE clause for both file_path and app_path.
        case glob
    }

    var id: UUID = UUID()
    var kind: Kind
    var value: String
}

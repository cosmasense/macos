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
    }

    var id: UUID = UUID()
    var kind: Kind
    var value: String
}

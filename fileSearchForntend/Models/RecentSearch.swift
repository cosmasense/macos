//
//  RecentSearch.swift
//  fileSearchForntend
//
//  Stores a recent search query with its tokens
//

import Foundation

struct RecentSearch: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var date: Date
    var rawQuery: String
    var tokens: [SearchToken]
}

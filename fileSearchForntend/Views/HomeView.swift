//
//  HomeView.swift
//  fileSearchForntend
//
//  Search view with tokenized @folder support and recent searches
//  Redesigned for macOS 26 with Liquid Glass aesthetics
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 32) {
            // Search area with generous top padding
            SearchFieldView()
                .frame(maxWidth: 680)
                .padding(.top, 80)

            Divider()
                .padding(.horizontal, 40)

            // Recent searches
            RecentSearchesView()
                .frame(maxWidth: 680)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Search Files")
    }
}

// MARK: - Search Field Component

struct SearchFieldView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            // Main search field with Liquid Glass material
            HStack(spacing: 12) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                // Combined token + text input
                HStack(spacing: 8) {
                    // Token chips inline
                    ForEach(model.searchTokens) { token in
                        TokenChipView(token: token) {
                            removeToken(token)
                        }
                    }

                    // Text field
                    TextField("Search files or type @folder...", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit {
                            if !model.searchText.isEmpty || !model.searchTokens.isEmpty {
                                model.performSearch()
                            }
                        }
                        .onChange(of: model.searchText) { oldValue, newValue in
                            checkForTokenCreation()
                        }
                }

                // Clear button
                if !model.searchText.isEmpty || !model.searchTokens.isEmpty {
                    Button(action: {
                        model.searchText = ""
                        model.searchTokens = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

            // Folder suggestions dropdown
            if model.searchText.contains("@") {
                FolderSuggestionsView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.searchText.contains("@"))
    }

    private func removeToken(_ token: SearchToken) {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.searchTokens.removeAll { $0.id == token.id }
        }
    }

    private func checkForTokenCreation() {
        let words = model.searchText.split(separator: " ")
        guard let lastWord = words.last else { return }

        let word = String(lastWord)
        guard word.hasPrefix("@"), word.count > 1 else { return }

        let folderName = String(word.dropFirst())
        let matchingFolder = model.watchedFolders.first {
            $0.name.caseInsensitiveCompare(folderName) == .orderedSame
        }

        if let folder = matchingFolder {
            withAnimation(.easeInOut(duration: 0.2)) {
                createToken(for: folder.name)
            }
        }
    }

    private func createToken(for folderName: String) {
        let newToken = SearchToken(kind: .folder, value: folderName)
        if !model.searchTokens.contains(newToken) {
            model.searchTokens.append(newToken)
        }
        // Remove the @folder from text
        model.searchText = model.searchText
            .replacingOccurrences(of: "@\(folderName)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Token Chip (Apple Music style)

struct TokenChipView: View {
    let token: SearchToken
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(token.value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.9), Color.blue],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Folder Suggestions

struct FolderSuggestionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestions = getSuggestions()

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, folder in
                    Button(action: {
                        selectFolder(folder)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)

                            Text("@\(folder.name)")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.0001))
                    .onHover { hovering in
                        // Optional: add hover effect
                    }

                    if index < suggestions.count - 1 {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .padding(.top, 4)
        }
    }

    private func getSuggestions() -> [WatchedFolder] {
        let words = model.searchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@"), word.count > 1 else { return [] }

        let query = String(word.dropFirst()).lowercased()
        return model.watchedFolders.filter {
            $0.name.lowercased().hasPrefix(query)
        }
    }

    private func selectFolder(_ folder: WatchedFolder) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let newToken = SearchToken(kind: .folder, value: folder.name)
            if !model.searchTokens.contains(newToken) {
                model.searchTokens.append(newToken)
            }
            // Remove @ and the partial folder name from text
            let words = model.searchText.split(separator: " ")
            var newText = model.searchText
            if let lastWord = words.last, String(lastWord).hasPrefix("@") {
                newText = model.searchText
                    .replacingOccurrences(of: String(lastWord), with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            model.searchText = newText
        }
    }
}

// MARK: - Recent Searches

struct RecentSearchesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.recentSearches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)

                    Text("No recent searches")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Try typing @FolderName to scope your search")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                Text("Recent Searches")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(model.recentSearches) { search in
                        RecentSearchRowView(search: search)
                    }
                }
            }
        }
    }
}

struct RecentSearchRowView: View {
    @Environment(AppModel.self) private var model
    let search: RecentSearch
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            model.loadRecentSearch(search)
        }) {
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(search.rawQuery)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(search.date, style: .relative)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}

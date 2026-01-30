//
//  HomeView.swift
//  fileSearchForntend
//
//  Search view with tokenized @folder support and recent searches
//  Redesigned for macOS 26 with Liquid Glass aesthetics and keyboard navigation
//  Enhanced with simplified backspace deletion and improved visibility
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            // Search area with generous top padding
            SearchFieldView(isFocused: $searchFieldFocused)
                .frame(minWidth: 400, maxWidth: 680)
                .padding(.horizontal, 40)
                .padding(.top, 40)

            Divider()
                .padding(.horizontal, 40)

            // Show search results if available, otherwise show recent searches
            if !model.searchResults.isEmpty || model.isSearching || model.searchError != nil {
                SearchResultsView()
                    .frame(minWidth: 400, maxWidth: 680)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // Recent searches
                RecentSearchesView()
                    .frame(minWidth: 400, maxWidth: 680)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFieldFocused = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Search Files")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.3), value: model.searchResults.isEmpty)
        .animation(.easeInOut(duration: 0.3), value: model.isSearching)
    }
    
}

// MARK: - Search Field Component

struct SearchFieldView: View {
    @Environment(AppModel.self) private var model
    @FocusState.Binding var isFocused: Bool
    @State private var selectedSuggestionIndex: Int = 0
    @State private var backspaceMonitor: Any?
    @State private var searchGradientRotation: Double = 0

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            // Main search field with enhanced Liquid Glass material and focus animation
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

                    // Text field with keyboard handling
                    TextField("Search files or type @folder...", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit {
                            handleEnterKey()
                        }
                        .onChange(of: model.searchText) { oldValue, newValue in
                            handleTextChange(oldValue: oldValue, newValue: newValue)
                        }
                        .onKeyPress(.tab) {
                            handleTabKey()
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            handleUpArrow()
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            handleDownArrow()
                            return .handled
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
            // Layered Liquid Glass for enhanced visibility
            .background {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                if #available(macOS 14.0, *) {
                    Color.clear.glassEffect(in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if model.isSearching {
                    // Rotating gradient border while searching
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor.opacity(0.1),
                                    Color.cyan.opacity(0.4),
                                    Color.accentColor.opacity(0.1),
                                    Color.accentColor.opacity(0.8),
                                ]),
                                center: .center,
                                angle: .degrees(searchGradientRotation)
                            ),
                            lineWidth: 2.5
                        )
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? Color.accentColor.opacity(0.5)
                                : Color.white.opacity(0.2),
                            lineWidth: isFocused ? 2 : 1
                        )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.3), value: model.isSearching)
            .shadow(
                color: model.isSearching
                    ? Color.accentColor.opacity(0.45)
                    : (isFocused ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.08)),
                radius: model.isSearching ? 20 : (isFocused ? 16 : 12),
                x: 0,
                y: model.isSearching ? 0 : (isFocused ? 6 : 4)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .onChange(of: model.isSearching) { _, isSearching in
                if isSearching {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        searchGradientRotation = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        searchGradientRotation = 0
                    }
                }
            }

            // Folder suggestions dropdown
            if model.searchText.contains("@") {
                FolderSuggestionsView(selectedIndex: $selectedSuggestionIndex)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.searchText.contains("@"))
        .onChange(of: model.searchText.contains("@")) { oldValue, newValue in
            if !newValue {
                selectedSuggestionIndex = 0
            }
        }
        .onAppear {
            setupBackspaceMonitor()
        }
        .onDisappear {
            removeBackspaceMonitor()
        }
    }

    // MARK: - Backspace Monitor for Token Deletion

    private func setupBackspaceMonitor() {
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle when search field is focused
            guard isFocused else { return event }

            // Check for backspace key (keyCode 51)
            if event.keyCode == 51 && model.searchText.isEmpty && !model.searchTokens.isEmpty {
                _ = withAnimation(.easeInOut(duration: 0.2)) {
                    model.searchTokens.removeLast()
                }
                return nil // Consume the event
            }
            return event
        }
    }

    private func removeBackspaceMonitor() {
        if let monitor = backspaceMonitor {
            NSEvent.removeMonitor(monitor)
            backspaceMonitor = nil
        }
    }

    // MARK: - Keyboard Handlers

    private func handleTextChange(oldValue: String, newValue: String) {
        selectedSuggestionIndex = 0
        checkForTokenCreation()
    }

    private func handleEnterKey() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.searchText.contains("@") {
            // Select the highlighted suggestion
            selectFolder(suggestions[selectedSuggestionIndex])
        } else if !model.searchText.isEmpty || !model.searchTokens.isEmpty {
            model.performSearch()
        }
    }

    private func handleTabKey() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.searchText.contains("@") {
            // Autocomplete with first suggestion
            selectFolder(suggestions[0])
        }
    }

    private func handleUpArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.searchText.contains("@") {
            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
        }
    }

    private func handleDownArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.searchText.contains("@") {
            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
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
    @Binding var selectedIndex: Int

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
                        .background(
                            index == selectedIndex
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

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
        GeometryReader { geometry in
            ScrollView {
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
                            ForEach(model.recentSearches.prefix(25)) { search in //prefix(n) = first n items to display in RecentSearchesView
                                RecentSearchRowView(search: search)
                            }
                        }
                    }
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

struct RecentSearchRowView: View {
    @Environment(AppModel.self) private var model
    let search: RecentSearch
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            // Click to load search
            Button(action: {
                model.loadRecentSearch(search)
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(search.rawQuery)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            
            // Delete button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.recentSearches.removeAll { $0.id == search.id }
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle()) //onHover includes whitespace between search and x button
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    @Previewable @FocusState var focused: Bool

    HomeView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}

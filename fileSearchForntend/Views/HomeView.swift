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
    @Environment(CosmaManager.self) private var cosmaManager
    @FocusState private var searchFieldFocused: Bool

    // Search + index are disabled while AI models are still being set up.
    // Rationale: searching with an unready index returns stale/no-AI
    // results, and triggering a new index when the summarizer isn't ready
    // just queues thousands of files to fail. Better to show a clear
    // "still setting up" state than to let the user kick off no-ops.
    private var aiReady: Bool { cosmaManager.bootstrapReady }

    private var isActive: Bool {
        searchFieldFocused || !model.searchResults.isEmpty || model.isSearching || model.searchError != nil
    }

    private var hasResults: Bool {
        !model.searchResults.isEmpty || model.isSearching || model.searchError != nil
    }

    var body: some View {
        ZStack {
            // Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.white.opacity(0.3))
                .ignoresSafeArea()

            // Main content — all elements stay in tree for smooth animation
            VStack(spacing: 0) {
                // Top spacer: shrinks when active, pushes content down when idle
                Spacer()
                    .frame(maxHeight: isActive ? 36 : 140)

                // Title — always present, animated opacity + height
                VStack(spacing: 8) {
                    Text("COSMA SENSE")
                        .font(.system(size: 32, weight: .thin))
                        .tracking(8)
                        .foregroundStyle(.primary)

                    DashboardStatsView()
                }
                .opacity(isActive ? 0 : 1)
                .frame(height: isActive ? 0 : nil)
                .clipped()
                .padding(.bottom, isActive ? 0 : 20)

                // Search bar — disabled until AI models are ready so the
                // user can't kick off useless queries against an unready
                // pipeline. Overlay shows why.
                SearchFieldView(isFocused: $searchFieldFocused)
                    .frame(minWidth: 400, maxWidth: isActive ? 680 : 520)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 14)
                    .disabled(!aiReady)
                    .opacity(aiReady ? 1 : 0.55)
                    .overlay(alignment: .center) {
                        if !aiReady {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Setting up AI models — search paused")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                        }
                    }

                // Below search: results or chips/recent
                if hasResults {
                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 40)

                    SearchResultsView()
                        .frame(minWidth: 400, maxWidth: 680)
                        .padding(.horizontal, 40)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    VStack(spacing: 16) {
                        FolderChipsView()
                            .frame(maxWidth: isActive ? 680 : 520)
                            .padding(.horizontal, 40)

                        RecentSearchesView()
                            .frame(maxWidth: isActive ? 680 : 520)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // Force resign first responder on macOS — more reliable than @FocusState alone
            NSApp.keyWindow?.makeFirstResponder(nil)
            searchFieldFocused = false

            // If search text is empty, reset to idle state
            if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.searchTokens.isEmpty {
                model.searchResults = []
                model.searchError = nil
                model.isSearching = false
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: hasResults)
        .onChange(of: searchFieldFocused) { _, newValue in
            model.isSearchFieldFocused = newValue
        }
        .background(
            // Invisible monitor that routes loose keystrokes to the search
            // field. Lets the user just start typing anywhere on Home to
            // begin a search, and hit Esc to bail out — matching how
            // Spotlight and most launcher UIs feel. Placed in .background
            // so it doesn't affect layout or hit-testing.
            HomeKeyCaptureView(
                isSearchFocused: searchFieldFocused,
                aiReady: aiReady,
                onType: { chars in
                    // Focus first, then append on the next runloop tick.
                    // When SwiftUI focuses an NSTextField it auto-selects
                    // the existing text; appending *before* focus meant the
                    // next user keystroke replaced what they just typed.
                    // Deferring the append puts the insertion point at the
                    // end after focus settles, so typing continues normally.
                    searchFieldFocused = true
                    DispatchQueue.main.async {
                        model.searchText.append(chars)
                        // Move the field editor's caret to the end so the
                        // newly-appended chars aren't left selected.
                        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                            let end = editor.string.count
                            editor.setSelectedRange(NSRange(location: end, length: 0))
                        }
                    }
                },
                onEscape: {
                    model.searchText = ""
                    model.searchTokens = []
                    model.searchResults = []
                    model.searchError = nil
                    model.isSearching = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    searchFieldFocused = false
                }
            )
            .allowsHitTesting(false)
        )
    }

}

/// NSViewRepresentable that installs a local NSEvent monitor while the
/// HomeView is on-screen. We use NSEvent rather than SwiftUI's .onKeyPress
/// because we need to capture keystrokes *without* a focused control —
/// SwiftUI's modifiers only fire when the attached view already has focus.
private struct HomeKeyCaptureView: NSViewRepresentable {
    let isSearchFocused: Bool
    let aiReady: Bool
    let onType: (String) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(parent: self)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Rebind the latest closures so the monitor always sees current
        // focus/aiReady state without re-installing the monitor each update.
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var parent: HomeKeyCaptureView?
        private var monitor: Any?

        func install(parent: HomeKeyCaptureView) {
            self.parent = parent
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let p = self.parent else { return event }

                // Esc (keyCode 53): always clear + blur, even while focused.
                if event.keyCode == 53 {
                    p.onEscape()
                    return nil
                }

                // Only auto-capture typing when the field isn't already
                // focused (otherwise the TextField handles it) and when AI
                // is ready (no point starting a search we can't run).
                guard !p.isSearchFocused, p.aiReady else { return event }

                // Skip modified key combos (Cmd-Q, Cmd-W, etc.) — those
                // belong to menus/system shortcuts, not to the search field.
                let blockingFlags: NSEvent.ModifierFlags = [.command, .control, .function]
                if !event.modifierFlags.isDisjoint(with: blockingFlags) {
                    return event
                }

                // Printable characters only. charactersIgnoringModifiers
                // filters out arrow keys / fn keys (which return empty or
                // private-use-area strings).
                guard let chars = event.charactersIgnoringModifiers,
                      !chars.isEmpty,
                      chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F })
                else { return event }

                p.onType(chars)
                return nil
            }
        }

        func uninstall() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { uninstall() }
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
                        model.searchResults = []
                        model.searchError = nil
                        model.isSearching = false
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
                colors: [Color.brandBlue.opacity(0.9), Color.brandBlue],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .brandBlue.opacity(0.3), radius: 2, x: 0, y: 1)
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
                                .foregroundStyle(Color.brandBlue)

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

    private let maxRecentSearches = 25

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.recentSearches.isEmpty {
                        VStack(spacing: 8) {
                            Text("Drag and drop to add folders")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 56)
                        .padding(.bottom, 16)
                    } else {
                        Text("Recent Searches")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(model.recentSearches.prefix(maxRecentSearches)) { search in
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

// MARK: - Dashboard Stats

private struct DashboardStatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.watchedFolders.isEmpty {
            Text(statsText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .task {
                    await model.refreshFileStats()
                }
        }
    }

    private var statsText: String {
        let folderCount = model.watchedFolders.count
        let folderLabel = folderCount == 1 ? "folder" : "folders"

        if let stats = model.fileStats {
            let fileCount = stats.totalFiles
            let fileLabel = fileCount == 1 ? "file" : "files"
            return "\(folderCount) \(folderLabel) · \(fileCount) \(fileLabel) indexed"
        } else {
            return "\(folderCount) \(folderLabel)"
        }
    }
}

// MARK: - Folder Chips

private struct FolderChipsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.watchedFolders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search in")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.watchedFolders) { folder in
                            FolderFilterChip(folder: folder)
                        }
                    }
                }
            }
        }
    }
}

private struct FolderFilterChip: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder

    private var isActive: Bool {
        model.searchTokens.contains { $0.kind == .folder && $0.value == folder.name }
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if !isActive {
                    let token = SearchToken(kind: .folder, value: folder.name)
                    model.searchTokens.append(token)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                Text(folder.name)
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isActive
                    ? Color.brandBlue
                    : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @FocusState var focused: Bool

    HomeView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}

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
    //
    // Two gates: bootstrapReady (model FILES exist on disk) AND
    // embedderReady (the embedder has actually been loaded into memory
    // and can answer queries). Bootstrap-only was insufficient because
    // the embedder load happens lazily on the backend's first use and
    // takes 2-5s after launch — search submitted in that window came
    // back with no results, which read to users as "search is broken."
    private var aiReady: Bool { cosmaManager.bootstrapReady && model.embedderReady }

    private var isActive: Bool {
        searchFieldFocused || !model.searchResults.isEmpty || model.isSearching || model.searchError != nil
    }

    private var hasResults: Bool {
        !model.searchResults.isEmpty || model.isSearching || model.searchError != nil
    }

    /// Friendly "an upgrade is in flight" copy to show in place of the
    /// red incompatibility banner. Returns nil when no upgrade is
    /// active — let the caller fall through to the normal incompatible
    /// banner (or no banner at all). Keyed off both the version
    /// handshake state AND CosmaManager's update progress so the
    /// friendly banner only appears when we both know the backend is
    /// "wrong" AND know we have a fix queued.
    private var pendingUpdateBannerCopy: String? {
        // Only swap in the friendly banner when the handshake itself is
        // unhappy. If the backend is fine, no banner is needed at all.
        guard model.backendIncompatibleMessage != nil else { return nil }
        switch cosmaManager.updateStatus {
        case .checking:
            // Just kicked off a PyPI check. We expect it to land on
            // either .downloading or .upToDate within a few seconds.
            // While it's running, show the friendly banner so the user
            // doesn't see the red "Backend incompatible" flash.
            return "Checking for an update — please wait, the app will restart automatically."
        case let .downloading(_, target):
            return "Downloading update v\(target) — please wait, the app will restart automatically."
        case let .downloadedPendingRestart(_, downloaded):
            return "Update v\(downloaded) downloaded — restarting backend automatically…"
        case .idle, .upToDate, .failed:
            return nil
        }
    }

    var body: some View {
        ZStack {
            // Background — glass with a Light-only tint. The app pins
            // NSApp.appearance to .aqua in AppDelegate, so the material
            // renders its Light variant even when the system is Dark.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            // Main content — all elements stay in tree for smooth animation
            VStack(spacing: 0) {
                // Backend version-handshake banner. Only shown when
                // BackendCompatibility.check returned a mismatch
                // (frontend/backend api_version drift). Hard error —
                // the user can't do anything from here until the app
                // and the backend agree on the wire contract.
                // Three-way version banner. We pick exactly one:
                //   * Update in flight → friendly "Updating, please wait"
                //     banner. Used when the version handshake failed but
                //     we know an upgrade is downloading or already on
                //     disk waiting for restart. CosmaManager runs a
                //     catch-up restart automatically, so the user just
                //     needs to know "we're handling it" — not see a
                //     scary red error.
                //   * Genuine incompatibility → red BackendIncompatibleBanner.
                //   * Otherwise → no banner.
                if let pendingUpdate = pendingUpdateBannerCopy {
                    UpdateInProgressBanner(message: pendingUpdate)
                        .padding(.horizontal, 40)
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let msg = model.backendIncompatibleMessage {
                    BackendIncompatibleBanner(message: msg)
                        // Clear two pieces of top chrome:
                        //   1. The hidden title-bar zone (~28pt, where
                        //      the traffic-lights live) — without this
                        //      the banner draws over the close/min/max
                        //      buttons.
                        //   2. ContentView's floating action-button row
                        //      (top padding 12pt + ~46pt button) on the
                        //      trailing side. 64pt of clearance keeps
                        //      the banner squarely below both, with a
                        //      bit of breathing room.
                        .padding(.horizontal, 40)
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Top spacer: shrinks when active, pushes content down when idle
                Spacer()
                    .frame(maxHeight: isActive ? 60 : 84)

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
                // pipeline. The "models loading" message is rendered as
                // the field's placeholder text (see SearchFieldView), not
                // as an overlay above it; the placeholder transitions
                // back to the normal search prompt the moment
                // `aiReadyForSearch` flips true. This matches
                // PopupSearchFieldView, which has done it this way from
                // the start.
                SearchFieldView(isFocused: $searchFieldFocused)
                    .frame(minWidth: 400, maxWidth: isActive ? 680 : 520)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 14)
                    .disabled(!aiReady)
                    .opacity(aiReady ? 1 : 0.55)

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
                    VStack(spacing: 8) {
                        FolderChipsView()
                            .frame(maxWidth: isActive ? 680 : 520)
                            .padding(.horizontal, 40)

                        RecentSearchesView()
                            .frame(maxWidth: isActive ? 680 : 520)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
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
        .onAppear {
            // Don't auto-focus the search field when the window opens.
            // SwiftUI's TextField would otherwise grab first responder as
            // the only focusable control, so the user sees a blinking
            // caret without having asked for it. Wait a tick for the
            // window to settle, then clear focus.
            DispatchQueue.main.async {
                searchFieldFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
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
                // Once results are on screen, stop hijacking keystrokes
                // into the search field. Space, arrows, and Return belong
                // to the results view (Quick Look + grid/list navigation),
                // and silently re-typing into the search bar would also
                // re-trigger a search the user didn't ask for.
                hasResults: hasResults,
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
    /// True when search results / loading / error are currently on screen.
    /// Skips type-capture so the results view can own arrows / space /
    /// return for navigation and Quick Look.
    let hasResults: Bool
    let onType: (String) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(parent: self, view: view)
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
        weak var hostView: NSView?
        private var monitor: Any?

        func install(parent: HomeKeyCaptureView, view: NSView) {
            self.parent = parent
            self.hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let p = self.parent else { return event }

                // Only capture keystrokes when HomeView's window is the key
                // window. Otherwise the Quick Search overlay panel (and any
                // other secondary window) would have its input swallowed
                // here before reaching its own text field.
                if let host = self.hostView?.window,
                   NSApp.keyWindow !== host {
                    return event
                }

                // Esc (keyCode 53): always clear + blur, even while focused.
                if event.keyCode == 53 {
                    p.onEscape()
                    return nil
                }

                // Only auto-capture typing when the field isn't already
                // focused (otherwise the TextField handles it), when AI
                // is ready (no point starting a search we can't run),
                // and when no results are showing (results-view owns
                // space / arrows / return once the user has hits on
                // screen — re-routing them into the field would also
                // re-trigger a search).
                guard !p.isSearchFocused, p.aiReady, !p.hasResults else { return event }

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

    /// True while the user is composing an @folder mention: the last
    /// whitespace-separated word starts with `@` and the text does not end
    /// with a trailing space (space means "done with the mention").
    private var isInFolderMention: Bool {
        if model.searchText.hasSuffix(" ") { return false }
        guard let lastWord = model.searchText.split(separator: " ").last else { return false }
        return String(lastWord).hasPrefix("@")
    }

    /// String shown inside the field when there's no user input. Drives
    /// the animated swap: when this value changes, SwiftUI removes the
    /// old Text and inserts a new one, and the .transition on that Text
    /// scrolls the old line off and the new one in.
    private var placeholderText: String {
        model.aiReadyForSearch
            ? "Search files or type @folder..."
            : "Setting up AI models — search paused"
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            // Main search field with enhanced Liquid Glass material and focus animation
            HStack(spacing: 12) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                // Combined token + text input.
                // minHeight matches the token-chip height so the search
                // bar keeps a constant height whether a token is present
                // or not (otherwise the field grows when a chip appears).
                HStack(spacing: 8) {
                    // Token chips inline
                    ForEach(model.searchTokens) { token in
                        TokenChipView(token: token) {
                            removeToken(token)
                        }
                    }

                    // Text field with custom animated placeholder.
                    //
                    // SwiftUI's native TextField placeholder is rendered
                    // by AppKit and can't be animated, so we pass "" for
                    // the prompt and overlay a regular Text view that
                    // SwiftUI can transition. Keying the Text on its
                    // string value forces a fresh insert/remove pair on
                    // every change, and the asymmetric move-edge
                    // transition makes the old line scroll off to the
                    // left while the new one scrolls in from the right
                    // — a smooth swap that signals "the model just
                    // finished loading" without any popping.
                    ZStack(alignment: .leading) {
                        if model.searchText.isEmpty {
                            Text(placeholderText)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .id(placeholderText)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing)
                                        .combined(with: .opacity),
                                    removal: .move(edge: .leading)
                                        .combined(with: .opacity),
                                ))
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($isFocused)
                            .onSubmit {
                                handleEnterKey()
                            }
                            .onChange(of: model.searchText) { oldValue, newValue in
                                handleTextChange(oldValue: oldValue, newValue: newValue)
                                // Tell the backend the user is typing so it
                                // pauses indexing + cancels in-flight work.
                                // Debounced server-side, idempotent.
                                model.notifySearchTyping()
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
                    // clipped() so the slide-out doesn't leak into the
                    // search-icon area on the left of the bar.
                    .clipped()
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.85),
                        value: placeholderText,
                    )
                }
                .frame(minHeight: 30)

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
            .padding(.vertical, 8)
            .searchBarChrome()
            .overlay {
                // Rotating gradient stays as an extra overlay on top of the
                // shared chrome — only HomeView has a "searching" state.
                if model.isSearching {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: model.isSearching)
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
            if isInFolderMention {
                FolderSuggestionsView(selectedIndex: $selectedSuggestionIndex)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInFolderMention)
        .onChange(of: isInFolderMention) { _, isActive in
            if !isActive {
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
        } else {
            // Empty field + no tokens: treat Return like Esc — reset to the
            // idle home state and blur the search field.
            model.searchResults = []
            model.searchError = nil
            model.isSearching = false
            isFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
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
        // A trailing space means the user has "finished" the mention —
        // surface no suggestions so the dropdown dismisses.
        if model.searchText.hasSuffix(" ") { return [] }

        let words = model.searchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@") else { return [] }

        let query = String(word.dropFirst()).lowercased()
        if query.isEmpty {
            // Bare "@" — show every watched folder so the user can pick.
            return model.watchedFolders
        }
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
                                ? Color.white.opacity(0.85)
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
        // A trailing space means the user has "finished" the mention —
        // surface no suggestions so the dropdown dismisses.
        if model.searchText.hasSuffix(" ") { return [] }

        let words = model.searchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@") else { return [] }

        let query = String(word.dropFirst()).lowercased()
        if query.isEmpty {
            // Bare "@" — show every watched folder so the user can pick.
            return model.watchedFolders
        }
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 20)

                        VStack(spacing: 2) {
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
            .contentShape(Rectangle())
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

// MARK: - Update In-Progress Banner

/// Friendly banner shown in place of the red "Backend incompatible"
/// banner when we detect a mismatch *and* know an upgrade is being
/// downloaded or has already been downloaded and is waiting for the
/// catch-up restart in CosmaManager. Tells the user "we're handling
/// it" instead of alarming them with a hard-error red banner during
/// what is, in practice, a self-healing situation.
struct UpdateInProgressBanner: View {
    let message: String
    @State private var spin: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.brandBlue)
                .rotationEffect(.degrees(spin))
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        spin = 360
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandBlue)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.brandBlue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.brandBlue.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Backend Incompatibility Banner

/// Hard-error banner shown when the frontend's pinned backend
/// api_version disagrees with what's actually running. Replaces the
/// previous "search just doesn't work and the error is mysterious"
/// behavior with a clear message that names the version mismatch.
/// See BackendCompatibility.swift.
struct BackendIncompatibleBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Backend incompatible")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

#Preview {
    @Previewable @FocusState var focused: Bool

    HomeView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}

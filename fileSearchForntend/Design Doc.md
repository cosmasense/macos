# Project: AI File Organizer — macOS Frontend (macOS 26 “Liquid Glass”)

**Owner:** Ethan (Frontend)
**Platform:** macOS 26 (target), macOS 15+ (back-compat)
**Tech:** SwiftUI, Combine, AppKit bridges (as needed), SF Symbols

------

## 1) Product Overview

A native macOS app for organizing and searching files summarized/indexed by a Python backend. The app uses a **sidebar-first layout** with two primary destinations:

1. **Home** — global search (tokenized) + recent searches.
2. **Jobs** — manage “watching folders” and view **per-folder indexing progress**.

### Goals

- Feel 100% native on macOS 26 using Apple’s **Liquid Glass** aesthetic and updated HIG patterns.
- Make search fast and scannable, with **tokenized @folder** scope chips.
- Keep the Jobs view simple: a flat list of watched folders with clear progress and affordances to add/remove folders.

------

## 2) Information Architecture

- **Main container:** `NavigationSplitView` with a **Sidebar** and a **Detail area**.
- **Sidebar items:**
  - Home
  - Jobs
- **Detail areas:**
  - Home → Search field (centered), Recent searches underneath.
  - Jobs → Watched folders list; Add Folder control in the toolbar.

> Rationale: `NavigationSplitView` is the canonical pattern for macOS with sidebars and adapts well to window resizing, multi-column, and state restoration.

------

## 3) Visual & Interaction Design (macOS 26)

### 3.1 Materials & Depth

- **Liquid Glass**: Use Apple’s new **Liquid Glass** material for chrome surfaces where appropriate (e.g., **sidebar background**, **search field container**, floating toolbars). Keep translucency subtle to preserve readability.
- **Vibrancy**: Prefer **sidebar vibrancy** for background blending. Ensure foreground text meets accessibility contrast.

### 3.2 Sidebar

- **Style**: macOS Sidebar with icon + label,
  - Home (house icon)
  - Jobs (tray.full or folder.badge.gear)
- **Selection** persists across launches.
- **Width** resizable; maintain a sensible `minWidth`.

### 3.3 Home (Search)

- **Search field** centered horizontally in the content area.
- Supports **tokens**: typing `@` followed by a **watched folder name** converts to a **token chip** (blue background, white text). Multiple tokens allowed.
- **Inline suggestions**: when the user types `@`, show completion list of watched folders; pressing Return or Tab commits a token.
- **Recent searches** under the field as a vertically stacked list with timestamp + query preview; clicking a recent item repopulates the field.
- **Empty state**: friendly prompt and tips (“Try `@Documents` to scope to that folder”).

### 3.4 Jobs (Watching Folders)

- **Toolbar**: "+ Add Folder" primary button (uses file importer) + help action.
- **List item layout** (each folder row):
  - **Leading**: folder icon thumbnail (from system),
  - **Main**: **Name** (prominent) and **Path** (secondary style, mono, truncated in middle),
  - **Trailing**: **Circular Progress** (like iOS download ring) with % label, and a **Remove** button (destructive tint).
- **Behaviors**:
  - **Add**: Opens a folder picker; upon selection, we post to backend to register & begin indexing.
  - **Remove**: Confirmation popover, then deregister with backend.
  - **Progress**: Live-updates from backend stream; paused/error states show an icon + tooltip.

### 3.5 Motion & Micro-interactions

- **Token creation**: fade-in + scale from 0.95 → 1.0.
- **Progress ring**: animates smoothly; on completion, briefly shows a checkmark pulse.

### 3.6 Accessibility

- Respect **Reduce Transparency**: fall back to opaque materials.
- Respect **Increase Contrast**: use higher-contrast token and ring strokes.
- VoiceOver: tokens expose the folder scope; each row exposes percentage and status.

------

## 4) macOS 26 Design References (What we’re using where)

- **Liquid Glass material** for sidebar/search chrome and toolbars; adapt to light/dark and windowed backgrounds.
- **Updated Sidebar patterns** (HIG): adaptive widths, clear selection states.
- **Search tokens** (SwiftUI): native tokenized search field behavior for `@folder` scoping.
- **SF Symbols 6+**: consistent iconography; use filled variants for emphasis.
- **App icon** (later): updated 2025 grid for concentric balance.

> Implementation notes & citations are included inline in the comments of the prototype code and in the “Developer Notes” section below.

------

## 5) Data Model (Frontend)

```mermaid
classDiagram
class WatchedFolder {
  String id
  String name
  URL path
  Double progress // 0.0..1.0
  IndexStatus status // idle, indexing, paused, error, complete
}

class RecentSearch {
  String id
  Date date
  String rawQuery
  [SearchToken] tokens // e.g., .folder("Documents")
}

class SearchToken {
  enum kind { folder }
  String value // folder name
}
```

------

## 6) Networking

- **Backend**: Python service (local or LAN) exposes REST/WebSocket:
  - `GET /watched` → list of `WatchedFolder`
  - `POST /watched` with folder path
  - `DELETE /watched/:id`
  - `GET /progress/stream` → SSE or WebSocket progress updates per folder
  - `POST /search` → results for query + tokens

------

## 7) State & Architecture

- SwiftUI with **Observable** models powered by **@Observable / @State / @Environment**.
- **Combine** for streaming updates.
- Persistent storage via **AppStorage** or lightweight local DB for recents.
- Unit-test token parsing & search formatting.

------

## 8) Developer Notes (HIG + APIs)

- **Sidebar**: Apple HIG “Sidebars” + SwiftUI `NavigationSplitView`.
- **Materials**: HIG “Materials” (use system materials; tune vibrancy/opacity under accessibility settings).
- **Search Field**: HIG “Search fields”; SwiftUI `.searchable(text:tokens:prompt:)` and `.searchSuggestions` for completions.
- **Token Fields**: HIG “Token fields” — we mirror behavior using `searchable` tokens in SwiftUI.
- **Progress**: SwiftUI `ProgressViewStyle.circular` with percentage overlay.
- **File import**: SwiftUI `.fileImporter` (folders) or AppKit `NSOpenPanel` bridge.

------

## 9) User Stories (acceptance criteria)

### Home

- As a user, when I type `@` I see **watched-folder suggestions**; selecting one creates a **blue token chip** with the folder’s name.
- I can combine multiple folder tokens and free text; pressing Return starts a search.
- Recent searches appear below; clicking one restores tokens + text.

### Jobs

- I see a list of **watched folders** with **name**, **path**, **progress ring**, and **Remove**.
- Clicking **+ Add Folder** opens a folder picker; on confirm, the folder appears and the ring starts at 0%.
- Progress rings **update live**; completed folders show a brief checkmark.
- Remove prompts a confirmation and then the row disappears.

------

## 10) Prototype — SwiftUI (macOS)

> **Note**: The code uses SwiftUI `NavigationSplitView`, `searchable` with tokens, and a custom token parser for `@folder`syntax. The visual token is native (capsule) and tinted according to the system accent (blue by default in macOS 26). Liquid effects rely on system `Material`.

```swift
import SwiftUI
import Combine

// MARK: - Models

enum IndexStatus: String, Codable { case idle, indexing, paused, error, complete }

struct WatchedFolder: Identifiable, Hashable, Codable {
    var id: UUID = .init()
    var name: String
    var path: String
    var progress: Double // 0.0...1.0
    var status: IndexStatus
}

struct RecentSearch: Identifiable, Hashable, Codable {
    var id: UUID = .init()
    var date: Date
    var rawQuery: String
    var tokens: [SearchToken]
}

struct SearchToken: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case folder }
    var id: UUID = .init()
    var kind: Kind
    var value: String
}

// MARK: - App State

@Observable
class AppModel {
    var selection: SidebarItem? = .home
    var watched: [WatchedFolder] = []
    var recent: [RecentSearch] = []

    // Search state
    var searchText: String = ""
    var searchTokens: [SearchToken] = []

    // Simulated networking
    private var timer: AnyCancellable?

    init() {
        // Seed state
        watched = [
            .init(name: "Documents", path: "/Users/you/Documents", progress: 0.42, status: .indexing),
            .init(name: "Photos", path: "/Users/you/Pictures/Photos", progress: 0.91, status: .indexing)
        ]
        recent = []

        // Fake progress updates
        timer = Timer.publish(every: 1.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                for i in watched.indices { if watched[i].status == .indexing { watched[i].progress = min(1.0, watched[i].progress + 0.03) ; if watched[i].progress >= 1.0 { watched[i].status = .complete } } }
            }
    }

    func addFolder(url: URL) {
        let name = url.lastPathComponent
        watched.append(.init(name: name, path: url.path, progress: 0.0, status: .indexing))
    }

    func removeFolder(_ f: WatchedFolder) {
        watched.removeAll { $0.id == f.id }
    }

    func performSearch() {
        let raw = serializedQuery()
        recent.insert(.init(date: .now, rawQuery: raw, tokens: searchTokens), at: 0)
        // TODO: call backend /search with `raw` and `tokens`
    }

    func serializedQuery() -> String {
        let tokenStrings = searchTokens.map { token in
            switch token.kind { case .folder: return "@\(token.value)" }
        }
        let joined = (tokenStrings + [searchText]).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined
    }
}

enum SidebarItem: String, CaseIterable, Identifiable { case home = "Home", jobs = "Jobs"; var id: String { rawValue } }

// MARK: - App Entry

@main
struct FileOrganizerApp: App {
    @State var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .windowStyle(.automatic)
    }
}

// MARK: - Root Layout

struct ContentView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationSplitView {
            Sidebar()
                .background(.regularMaterial) // Liquid Glass vibe on macOS 26
        } detail: {
            switch model.selection {
            case .home, .none: HomeView()
            case .jobs: JobsView()
            }
        }
        .toolbarRole(.automatic)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List(selection: $model.selection) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.rawValue, systemImage: item == .home ? "house" : "tray.full")
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Home (Search)

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Centered search field with tokens
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay( RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1) )
                HStack { Image(systemName: "magnifyingglass"); Text("Search files or type @folder…") .foregroundStyle(.secondary); Spacer() }
                    .padding(.horizontal)
                    .opacity(model.searchText.isEmpty && model.searchTokens.isEmpty ? 1 : 0)
            }
            .frame(maxWidth: 560, minHeight: 44)
            .overlay(
                // Actual searchable surface
                SearchableField()
                    .frame(maxWidth: 560)
            )
            .padding(.top, 40)

            // Recent searches
            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent searches").font(.headline)
                    ForEach(model.recent) { r in
                        Button(action: { model.searchTokens = r.tokens; model.searchText = r.rawQuery.replacingOccurrences(of: r.tokens.map { "@" + $0.value }.joined(separator: " "), with: "").trimmingCharacters(in: .whitespaces) }) {
                            HStack {
                                Image(systemName: "clock")
                                Text(r.rawQuery).lineLimit(1)
                                Spacer()
                                Text(r.date, style: .time).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: 560)
            } else {
                Text("Tip: scope your query with `@FolderName`.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { focused = true }
    }
}

// Custom searchable field using native tokens
struct SearchableField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused

    var folderNames: [String] { model.watched.map { $0.name } }

    var body: some View {
        VStack {
            TextField("", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: model.searchText) { _, newValue in
                    // Convert @Folder tokens when a full match is typed followed by space
                    tokenizeIfNeeded()
                }
                .onSubmit { model.performSearch() }
                .searchable(text: $model.searchText, tokens: $model.searchTokens, prompt: Text("Search files or type @folder…")) { token in
                    switch token.kind {
                    case .folder: Label(token.value, systemImage: "folder").labelStyle(.titleOnly)
                    }
                }
                .searchSuggestions {
                    // Suggest folders after typing @
                    if model.searchText.contains("@") {
                        ForEach(suggestions(), id: \.self) { name in
                            Text("@\(name)").searchCompletion("@\(name) ")
                        }
                    }
                }
        }
        .frame(height: 44)
    }

    private func suggestions() -> [String] {
        let typed = model.searchText.split(separator: " ").last ?? ""
        let needle = typed.replacingOccurrences(of: "@", with: "").lowercased()
        guard !needle.isEmpty else { return [] }
        return folderNames.filter { $0.lowercased().hasPrefix(needle) }
    }

    private func tokenizeIfNeeded() {
        let parts = model.searchText.split(separator: " ")
        guard let last = parts.last else { return }
        let word = String(last)
        guard word.hasPrefix("@") else { return }
        let name = String(word.dropFirst())
        if folderNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            // Commit token and remove it from text
            let token = SearchToken(kind: .folder, value: name)
            if !model.searchTokens.contains(token) { model.searchTokens.append(token) }
            model.searchText = model.searchText.replacingOccurrences(of: word, with: "").trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - Jobs (Watched Folders)

struct JobsView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button {
                    showImporter = true
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                Spacer()
            }
            .padding(.bottom, 8)

            List {
                ForEach(model.watched) { f in
                    FolderRow(folder: f) {
                        model.removeFolder(f)
                    }
                }
            }
        }
        .padding()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { model.addFolder(url: url) }
        }
    }
}

struct FolderRow: View {
    var folder: WatchedFolder
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.headline)
                Text(folder.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            ProgressView(value: folder.progress)
                .progressViewStyle(.circular)
                .frame(width: 24, height: 24)
                .overlay(Text("\(Int(folder.progress*100))%").font(.caption2))
            Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
        }
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

------

## 11) Handoff for Designer

- **Deliverables requested**
  1. Visual spec for **Home** and **Jobs** (desktop @1x and @2x).
  2. Sidebar icons (SF Symbols proposals ok) and accent color guidance.
  3. Token chip styles (default, hover, focus, selected), with Liquid Glass vs. opaque fallbacks.
  4. Progress ring visual spec: default, paused, error, complete (with subtle completion check pulse).
  5. States: empty, loading, error (backend offline), no watched folders.
- **Constraints**
  - Must pass AA contrast in both Light/Dark, with Reduce Transparency enabled.
  - Sidebar width 220–320pt responsive; Home search container max 560pt.
- **References to consult**
  - HIG: Sidebars, Materials, Search Fields, Token Fields.
  - WWDC25: New design system (Liquid Glass), App Icon grid update.

------

## 12) Open Questions

- Do we need multi-folder token logic like `@FolderA OR @FolderB` vs implicit AND?
- Should Jobs support grouping or tags if the watched list grows large?
- Do we want pause/resume per folder?
- What does “indexing progress” measure (files vs. bytes vs. tasks)?

------

## 13) Next Steps

- Validate backend endpoints and progress streaming contract.
- Designer to provide token chip + ring specs; iterate.
- Implement actual search results UI (table or grid) in a follow-up.
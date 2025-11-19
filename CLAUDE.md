# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build the project
xcodebuild -project fileSearchForntend.xcodeproj -scheme fileSearchForntend -configuration Debug build

# Clean build (recommended after entitlements or model changes)
xcodebuild clean -project fileSearchForntend.xcodeproj -scheme fileSearchForntend
rm -rf ~/Library/Developer/Xcode/DerivedData/fileSearchForntend-*

# Run from Xcode
open fileSearchForntend.xcodeproj
# Then: Cmd+R to build and run
```

**Backend requirement:** The app requires a Python backend running at `http://localhost:60534` (configurable in Settings).

## Architecture Overview

This is a macOS SwiftUI application that provides a native frontend for an AI-powered file search and indexing system. The backend is a Python service that indexes files and provides semantic search capabilities.

### Core Architecture Pattern

**@Observable state management** with a single source of truth:

```swift
@MainActor
@Observable
class AppModel {
    // Navigation & UI state
    var selection: SidebarItem? = .home

    // Data (automatically triggers UI updates)
    var watchedFolders: [WatchedFolder] = []
    var searchResults: [SearchResultItem] = []
    var recentSearches: [RecentSearch] = []

    // Non-observable services (performance optimization)
    @ObservationIgnored private let apiClient: APIClient
    @ObservationIgnored private let updatesStream = UpdatesStream()
}
```

- All views access state via `@Environment(AppModel.self)`
- **@MainActor** ensures thread safety for UI updates
- **@ObservationIgnored** excludes heavy services from observation tracking

### Real-Time Updates Architecture

The app uses **Server-Sent Events (SSE)** for real-time indexing progress:

1. `UpdatesStream` connects to `/api/updates` endpoint
2. Backend sends events as `data: {json}\n\n`
3. Events parsed and routed to `AppModel.handleBackend(event:)`
4. AppModel mutates `WatchedFolder` objects → UI updates reactively
5. Auto-reconnect with exponential backoff on connection loss

**Event flow:**
```
Backend indexing → SSE stream → UpdatesStream → AppModel → WatchedFolder mutation → View update
```

### Backend API Integration

All API communication goes through `APIClient.swift` singleton.

**Critical implementation detail:** Backend requires **trailing slashes** on all POST/DELETE endpoints:
- ✅ `POST /api/search/`
- ❌ `POST /api/search` (returns 308 redirect)

**Search is POST, not GET:**
```swift
// Search request is JSON body, not query params
let request = SearchRequest(
    query: "meeting notes @Documents",
    directory: "/Users/you/Documents",  // Extracted from @token
    filters: ["folder": "/path"],        // Additional filters
    limit: 50
)
let response = try await apiClient.search(...)
```

### Token-Based Search Scoping

Users can scope searches using `@FolderName` tokens:

1. User types `@Doc` → dropdown suggests `@Documents`
2. Tab/Enter → creates blue token chip
3. Backend receives: `query: "meeting notes"` + `directory: "/Users/you/Documents"`

**Implementation:** `HomeView` parses `@` prefix, matches against `watchedFolders`, creates `SearchToken`, removes from text.

## Important Files & Responsibilities

### Core State & Logic
- `AppModel.swift` - Central @Observable state, orchestrates API calls and SSE handling
- `APIClient.swift` - URLSession-based HTTP client with async/await
- `UpdatesStream.swift` - SSE client with URLSessionDataDelegate for streaming
- `WatchedFolder.swift` - Represents indexed folder with progress tracking

### API Models
- `APIModels.swift` - Codable request/response models with CodingKeys for snake_case ↔ camelCase

**Critical pattern:** Backend uses Python snake_case, frontend uses Swift camelCase:
```swift
struct FileResponse: Codable {
    let filePath: String       // Swift camelCase
    let fileExtension: String  // Avoid `extension` keyword

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"       // Maps to backend
        case fileExtension = "extension"  // Maps to backend
    }
}
```

### Views
- `ContentView.swift` - NavigationSplitView root layout
- `HomeView.swift` - Search interface with token parsing
- `JobsView.swift` - Watched folders with connection status
- `SettingsView.swift` - Backend URL config (stored in UserDefaults)
- `FolderRowView.swift` - Watched folder row with progress ring

## Configuration & Entitlements

**File:** `fileSearchForntend.entitlements`

**Required for localhost connections:**
```xml
<key>com.apple.security.network.client</key>
<true/>
```

**Sandbox status:** Currently disabled for development (`app-sandbox = false`). Re-enable for App Store distribution.

**Common pitfall:** Duplicate entitlement keys (last one wins!). Always verify:
```bash
plutil -lint fileSearchForntend/fileSearchForntend.entitlements
```

## API Endpoints Reference

Base URL: `http://localhost:60534` (default)

| Method | Endpoint | Purpose | Notes |
|--------|----------|---------|-------|
| GET | `/api/status/` | Backend health check | Returns `{"jobs": N}` |
| GET | `/api/watch/jobs` | List watched folders | Returns JobResponse array |
| POST | `/api/watch/` | Start watching folder | Body: `{"directoryPath": "/path"}` |
| DELETE | `/api/watch/jobs/{id}/` | Stop watching | Requires trailing slash |
| POST | `/api/search/` | Search files | Body: SearchRequest JSON |
| POST | `/api/index/directory/` | Force reindex | Body: `{"directoryPath": "/path"}` |
| GET | `/api/files/stats` | File statistics | Total files, size, etc. |
| GET | `/api/updates` | SSE stream | Real-time indexing events |

**Testing API health:**
```bash
curl http://127.0.0.1:60534/api/status/
# Expected: {"jobs": 0, ...}

curl -X POST http://127.0.0.1:60534/api/search/ \
  -H "Content-Type: application/json" \
  -d '{"query":"test","limit":5}'
# Expected: {"results": [...]}
```

## Common Development Tasks

### Adding New API Endpoints

1. Add request/response models to `APIModels.swift` with CodingKeys
2. Add method to `APIClient.swift` (remember trailing slash!)
3. Call from `AppModel.swift` with error handling
4. Update UI in relevant view

### Handling New SSE Event Types

1. Add event opcode to `EventOpcode` enum in `APIModels.swift`
2. Handle in `AppModel.handleBackend(event:)` switch statement
3. Update relevant WatchedFolder state
4. UI updates automatically via @Observable

### Modifying Search Behavior

Search logic lives in `AppModel.searchFiles(query:)`:
- Token extraction: `directoryFromTokens()` and `filtersFromTokens()`
- Query normalization: Strips `@FolderName` from query text
- Result handling: Sets `searchResults` array → triggers `SearchResultsView` update

## Design System (macOS 26 "Liquid Glass")

The app follows macOS 26 HIG with:
- **Materials:** `.ultraThinMaterial` for backgrounds
- **Vibrancy:** `.sidebar` style for NavigationSplitView
- **SF Symbols:** Filled variants for emphasis
- **Progress rings:** Circular with percentage overlay
- **Token chips:** Blue capsule with white text/X button

**Accessibility compliance:**
- Respect "Reduce Transparency" (fallback to opaque)
- Respect "Increase Contrast" (higher-contrast strokes)
- VoiceOver support for tokens and progress states

## Known Limitations

1. **Folder removal:** Backend DELETE endpoint implemented but shows placeholder confirmation
2. **Summarizer models:** Deprecated API—methods throw 404, UI section hidden
3. **Feedback form:** Only logs to console, no backend submission
4. **Floating panel:** Directory exists but unused in current version
5. **Testing:** No unit tests; only SwiftUI #Preview blocks

## Troubleshooting

### "Operation not permitted" network errors

**Symptoms:**
```
nw_socket_connect connectx failed [1: Operation not permitted]
networkd_settings_read_from_file Sandbox is preventing...
```

**Fixes:**
1. Check entitlements for duplicate keys: `grep -A1 "app-sandbox" fileSearchForntend/fileSearchForntend.entitlements`
2. Ensure `com.apple.security.network.client` is `<true/>`
3. Clean build: Delete DerivedData and rebuild
4. Verify backend is running: `curl http://127.0.0.1:60534/api/status/`

### Build errors after model changes

1. Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
2. Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/fileSearchForntend-*`
3. Restart Xcode
4. Rebuild: Cmd+B

### Git merge conflicts with project files

`.xcodeproj/project.pbxproj` conflicts are common. Strategy:
1. Accept incoming changes for project structure
2. Keep current changes for entitlements and build settings
3. Verify in Xcode after merge: File → Project Settings → Check entitlements path

## Code Conventions

- **Property naming:** Avoid Swift keywords (`extension` → `fileExtension`)
- **Path normalization:** Always use `(path as NSString).standardizingPath` before API calls
- **Error messages:** User-facing errors via `searchError`, `statusMessage` in AppModel
- **Date formatting:** ISO8601 for API, localized for UI
- **Threading:** All AppModel mutations on @MainActor, nonisolated for heavy callbacks
- **Asset management:** SF Symbols preferred over custom icons

## Related Documentation

- `Design Doc.md` - Comprehensive UI/UX specifications
- `API_INTEGRATION.md` - API client architecture details
- `NETWORK_FIX.md` - Entitlements troubleshooting guide

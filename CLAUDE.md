# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build the project
xcodebuild -project fileSearchForntend.xcodeproj -scheme fileSearchForntend -configuration Debug build

# Clean build (recommended after entitlements or model changes)
xcodebuild clean -project fileSearchForntend.xcodeproj -scheme fileSearchForntend
rm -rf ~/Library/Developer/Xcode/DerivedData/fileSearchForntend-*
```

**Backend requirement:** The app requires the cosma Python backend at `http://localhost:60534`. The app auto-starts it via `CosmaManager` — no manual launch needed.

## Architecture Overview

macOS SwiftUI app providing a native frontend for AI-powered file search and indexing. The backend (separate `cosma` repo) handles indexing, embedding, and semantic search.

### State Management

Single `@Observable` source of truth split across extensions:

```
AppModel.swift            — Core state, SSE event routing, navigation
AppModel+Search.swift     — Main window + popup search (query, tokens, cache)
AppModel+Folders.swift    — Watched folder CRUD, progress tracking
AppModel+Queue.swift      — Queue status, item tracking, scheduler
AppModel+Settings.swift   — Backend settings, filter configuration
```

All views access state via `@Environment(AppModel.self)`. All mutations happen on `@MainActor`. Heavy services (`APIClient`, `UpdatesStream`) are `@ObservationIgnored`.

### Navigation

ContentView uses a flat **ZStack with page switching** (`AppPage` enum: `.home`, `.folders`), not NavigationSplitView. The floating folder button on the home page triggers the transition.

### App Startup Flow

```
fileSearchForntendApp.onAppear
  → checkFullDiskAccessPermission()      // Gate: FullDiskAccessGateView
  → cosmaManager.startManagedBackend()   // Installs uv/cosma if needed, launches backend
  → onChange(cosmaManager.setupStage == .running)
      → appModel.connectToBackend()      // SSE stream + initial data fetch
      → isBackendConnected = true        // Transitions to ContentView
```

### Backend Lifecycle (CosmaManager)

`CosmaManager` is an `@Observable` class managing the backend process:
- **Auto-install:** Checks for `uv` and `cosma`, installs via `uv tool install` if missing
- **Launch strategies:** Local dev checkout → installed `cosma` binary → fresh install
- **Health polling:** Retries `/api/status/` until backend responds
- **Crash recovery:** Detects process death, auto-restarts
- **Graceful shutdown:** SIGTERM with 6s window before SIGKILL
- **Update detection:** Checks PyPI for new versions every 6 hours

Setup stages: `.idle` → `.checkingUV` → `.installingUV` → `.checkingCosma` → `.installingCosma` → `.startingServer` → `.running`

### Real-Time Updates (SSE)

```
Backend indexing → SSE stream (/api/updates/) → UpdatesStream → AppModel.handleBackend(event:) → WatchedFolder mutation → View update
```

Auto-reconnect with exponential backoff on connection loss. Events are `EventOpcode` enums (40+ types) handled in a switch in `AppModel.swift`.

### Search

Search is **POST** to `/api/search/` with JSON body. Users scope searches with `@FolderName` tokens:

1. `HomeView.SearchFieldView` detects `@` prefix → creates `SearchToken`
2. `directoryFromTokens()` maps token to watched folder path (case-insensitive)
3. Query sent to backend with token text stripped out
4. Results cached in-memory (5-min TTL, 50-entry cap)

Both main window and popup overlay have independent search state.

## API Integration

All API calls go through `APIClient.swift` singleton.

**Critical:** Backend requires **trailing slashes** on POST/DELETE endpoints. `POST /api/search` returns 308; must be `POST /api/search/`.

**CodingKeys pattern:** Backend uses snake_case, Swift uses camelCase — every Codable model needs explicit `CodingKeys`.

### Key Endpoint Groups

| Group | Endpoints | Notes |
|-------|-----------|-------|
| Status | `GET /api/status/` | Health check, embedder readiness, init progress |
| Search | `POST /api/search/` | JSON body: query, directory, filters, limit |
| Watch | `GET /api/watch/jobs`, `POST /api/watch/`, `DELETE /api/watch/jobs/{id}/` | Folder management |
| Queue | `GET /api/queue/status`, `POST /api/queue/pause`, `GET /api/queue/items` | Indexing queue |
| Scheduler | `GET /api/queue/scheduler`, `POST /api/queue/scheduler` | Rule-based auto-pause |
| Filters | `GET/PUT /api/filters/config` | Whitelist/blacklist patterns |
| Settings | `GET/POST /api/settings/`, `POST /api/settings/test_model` | Backend config |
| SSE | `GET /api/updates/` | Real-time event stream |
| Index | `POST /api/index/directory/` | Force reindex |

## Design System (macOS 26)

- **Primary pattern:** `.glassEffect(.regular, in: .rect(cornerRadius: N))` for panels, buttons, badges
- **Fallback:** `.ultraThinMaterial` for backgrounds where glass isn't appropriate
- **Buttons:** `.glassEffect(.regular, in: .circle)` or `.glassEffect(.regular, in: .capsule)`
- **SF Symbols:** Filled variants for emphasis
- **Progress:** Circular gauge rings with percentage overlay

## Configuration & Entitlements

Sandbox is disabled (`app-sandbox = false`). Network client entitlement required for localhost.

**Common pitfall:** Duplicate entitlement keys (last one wins). Verify with:
```bash
plutil -lint fileSearchForntend/fileSearchForntend.entitlements
```

## Code Conventions

- **Path normalization:** Always use `(path as NSString).standardizingPath` before API calls or comparisons
- **Property naming:** Avoid Swift keywords (`extension` → `fileExtension`)
- **Folder matching:** Use `caseInsensitiveCompare` for folder name comparisons
- **Threading:** All AppModel mutations on @MainActor; `nonisolated` for heavy callbacks
- **Date formatting:** ISO8601 for API, localized for UI

## Troubleshooting

### "Connection refused" on startup
Normal during first ~10s while backend boots. CosmaManager polls until ready.

### "Operation not permitted" network errors
1. Check entitlements: `grep -A1 "app-sandbox" fileSearchForntend/fileSearchForntend.entitlements`
2. Ensure `com.apple.security.network.client` is `<true/>`
3. Clean build: `rm -rf ~/Library/Developer/Xcode/DerivedData/fileSearchForntend-*`

### SourceKit "Cannot find X in scope" errors
Cross-file false positives (separate compilation units). If `xcodebuild` succeeds, ignore them.

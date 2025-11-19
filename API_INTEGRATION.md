# API Integration Guide (Updated November 2025)

The Scalar Cosma backend exposes a REST + SSE surface that powers every screen in `fileSearchForntend`. This document summarizes the current contract so you do not need to hunt through logs or the Scalar portal (`https://registry.scalar.com/share/apis/egE5PsTubqGBeeJ5Q1tSA`). All paths below are relative to the configurable base URL (defaults to `http://127.0.0.1:60534` in `APIClient`).

## Endpoint Reference

| Endpoint | Method | Description | Swift Entry Point |
| --- | --- | --- | --- |
| `/api/status/` | GET | Lightweight health + queue depth check. Returns `StatusResponse` with `status`, `jobs`, `version`. | `APIClient.fetchStatus()` |
| `/api/watch/jobs` | GET | Lists watched folders (active + inactive). Returns `JobsListResponse`. | `fetchWatchJobs()` |
| `/api/watch/` | POST | Starts watching a folder. Body: `{ "directory_path": "<abs path>" }`. Returns `WatchResponse { success, message, files_indexed }`. | `startWatchingDirectory(path:)` |
| `/api/watch/jobs/{job_id}/` | DELETE | Stops watching / removes a job. | `deleteWatchJob(jobId:)` (UI currently shows a disabled button until backend supports removal). |
| `/api/index/directory/` | POST | Forces a re-crawl of a directory. Body matches watch request. | `indexDirectory(path:)` |
| `/api/index/file/` | POST | Re-indexes a single file by absolute path. | `indexFile(path:)` |
| `/api/search/` | POST | Hybrid semantic/keyword search. Body `SearchRequest { query, directory?, filters?, limit? }`. Returns ranked `SearchResponse`. | `search(query:directory:filters:limit:)` |
| `/api/files/stats` | GET | Aggregate counts, file types, and “last indexed” timestamp for dashboard cards. | `fetchFileStats()` |
| `/api/files/{file_id}/` | GET | Full metadata + summary for a single file. Used for detail panels. | `fetchFile(fileId:)` |
| `/api/updates/` | GET (SSE) | Server Sent Events stream that pushes pipeline progress (watch started, file parsed, failures, etc.). | `UpdatesStream.connect(to:)` |

All GET endpoints return JSON payloads with ISO 8601 timestamps (some include fractional seconds, e.g., `2025-11-19T19:05:04.456229+00:00`). `APIClient` already uses a custom decoding strategy that accepts both formats, so no additional conversion is needed.

## Request / Response Details

### Search (`POST /api/search/`)
```jsonc
// Request
{
  "query": "file @Documents",
  "directory": "/Users/you/Documents",   // optional
  "filters": { "folder": "/Users/you/Documents" }, // optional key/value pairs
  "limit": 50
}

// Response (SearchResponse)
{
  "results": [
    {
      "file": {
        "file_path": "/Users/you/Documents/Notes1_SS.pdf",
        "filename": "Notes1_SS.pdf",
        "extension": "pdf",
        "created": "2025-09-09T13:25:36+00:00",
        "modified": "2025-09-09T13:25:36+00:00",
        "accessed": "2025-11-19T19:05:30.272586Z",
        "title": "Intro to Statistics",
        "summary": "…",
        "keywords": ["statistics", "sampling", "RStudio"]
      },
      "relevance_score": 0.92
    }
  ]
}
```

### Watch Jobs
- `JobsListResponse.jobs` mirrors `JobResponse` in `Models/APIModels.swift` (fields: `id`, `path`, `is_active`, `recursive`, `file_pattern`, `last_scan`, `created_at`, `updated_at`).
- `WatchResponse` reports whether the server immediately queued indexing and how many files were scheduled.
- The UI listens to `/api/updates/` for granular progress rather than polling.

### Indexing
Use `/api/index/directory/` when a user presses “Re-index” on a watched folder row. The backend will emit `watch_started` and file-level events through SSE so progress bars stay in sync. `/api/index/file/` is wired for future detail screens but available in the client if needed.

### Files & Stats
- `/api/files/stats` populates hero metrics on the Home tab via `FileStatsResponse { total_files, total_size, file_types, last_indexed }`.
- `/api/files/{id}/` returns the same `FileResponse` structure used in search results and is useful if you need to show a detail sheet after tapping a result.

### SSE Updates (`GET /api/updates/`)
The stream emits JSON events shaped like `BackendUpdateEvent` with an `opcode` plus optional `file_path`, `directory_path`, `error_message`, and `progress`. Known opcodes (see `EventOpcode` enum):

`watch_started`, `directory_processing_started`, `directory_processing_completed`, `file_parsing`, `file_parsed`, `file_summarizing`, `file_summarized`, `file_embedding`, `file_embedded`, `file_complete`, `file_failed`.

The macOS client automatically:
- bumps progress when file events arrive,
- marks folders complete at `directory_processing_completed`,
- records transient “skipped file” warnings for `file_failed` while continuing the overall job.

### Error Semantics
- All REST calls expect `application/json`. Non-2xx codes are decoded as `{ "error": "..."} or { "message": "..." }`.
- `APIError.decodingError` now: “Failed to decode response: …” (common causes are incorrect base URLs or HTML error pages).
- SSE intentionally suppresses `NSURLErrorCancelled` events so swapping backends or stopping the stream does not log a false error.

## Configuring the Client

```swift
// Change base URL at runtime (e.g., Settings screen)
model.backendURL = "http://10.0.0.12:8080"
// AppModel automatically calls `APIClient.updateBaseURL` and reconnects SSE.
```

Timeouts: 30 s per request, 300 s per resource configured in `URLSessionConfiguration`. SSE uses `.infinity` to keep the stream open.

## Testing Checklist

1. Start Cosma: `cosma serve` (port 60534 by default).
2. `curl http://127.0.0.1:60534/api/status/` → verify JSON.
3. `curl http://127.0.0.1:60534/api/watch/jobs` → should list active jobs (may be empty initially).
4. Add a watch from the UI; confirm POST `/api/watch/` returns 201 in the logs.
5. Trigger a search from the Home tab; POST `/api/search/` should return 200 and the UI should render results or the empty-state.
6. Observe `/api/updates/` streaming events in the server log or via `curl -N`.

If any endpoint deviates from the structures above, consult the Scalar portal (link at the top) and adjust `Models/APIModels.swift` accordingly.

# API Integration Guide

## Overview
The API client has been fully integrated into the SwiftUI app, connecting the search bar to the `/api/search` endpoint and displaying results.

## What Was Added

### 1. API Models (`Models/APIModels.swift`)
- `FileResponse`: File metadata from the backend
- `SearchRequest`: Request parameters for search endpoint
- `SearchResultItem`: Individual search result with file and relevance score
- `SearchResponse`: Complete search response

### 2. API Client (`Services/APIClient.swift`)
- `APIClient`: Main service for backend communication
- `APIConfiguration`: Configurable base URL and timeout settings
- `APIError`: Comprehensive error handling
- Convenience methods for common search operations
- Shared singleton instance: `APIClient.shared`

### 3. Updated AppModel (`Models/AppModel.swift`)
New properties:
- `searchResults`: Array of search results
- `isSearching`: Loading state indicator
- `searchError`: Error message if search fails

New methods:
- `searchFiles(query:)`: Async method that calls the API
- `clearSearchResults()`: Clears results and errors

Enhanced methods:
- `performSearch()`: Now calls the API client
- `loadRecentSearch(_:)`: Automatically performs search when loading from history

### 4. Search Results View (`Views/SearchResultsView.swift`)
New component that displays:
- Loading state with progress indicator
- Error state with retry button
- Empty state when no results found
- Results list with:
  - File icon (based on extension)
  - Filename and path
  - Relevance score badge
  - Title and summary (if available)
  - Metadata (modified date, file extension)
  - Click to open file in default app

### 5. Updated HomeView (`Views/HomeView.swift`)
- Automatically switches between recent searches and search results
- Smooth transitions with animations
- Shows search results when:
  - Results are available
  - Search is in progress
  - An error occurred

## Configuration

The API client defaults to `http://localhost:8000`. To change this:

```swift
// In AppModel.swift or wherever you initialize the API client
let customConfig = APIConfiguration(
    baseURL: URL(string: "http://your-api-url:port")!,
    timeout: 30.0
)
let apiClient = APIClient(configuration: customConfig)
```

## How It Works

1. User types a query and presses Enter
2. `performSearch()` is called in AppModel
3. Query is added to recent searches
4. `searchFiles(query:)` makes an async API call
5. `isSearching` is set to true (shows loading state)
6. API response is decoded into `SearchResponse`
7. `searchResults` is updated with results
8. HomeView automatically switches to show SearchResultsView
9. User can click results to open files

## API Request Format

The search request includes:
- `query`: The search text (including folder tokens like "@Documents")
- `filters`: Optional key-value pairs (e.g., `{"folder": "Documents"}`)
- `limit`: Maximum results (default: 50)
- `directory`: Optional directory path from tokens

## Error Handling

The integration handles:
- Network errors
- Invalid responses
- Decoding errors
- Server errors (with status codes)
- Timeout errors

All errors are displayed in the UI with a retry option.

## Testing

The app includes preview providers with mock data for testing the UI without a backend.

## Next Steps

To complete the integration:
1. Ensure your backend is running on `http://localhost:8000`
2. Verify the `/api/search` endpoint matches the expected format
3. Test with various search queries
4. Adjust the API configuration if needed
5. Consider adding additional endpoints (watched folders, jobs, etc.)

## File Structure

```
fileSearchForntend/
├── Models/
│   ├── APIModels.swift          (NEW)
│   ├── AppModel.swift           (UPDATED)
│   ├── RecentSearch.swift
│   ├── SearchToken.swift
│   └── WatchedFolder.swift
├── Services/
│   └── APIClient.swift          (NEW)
├── Views/
│   ├── HomeView.swift           (UPDATED)
│   ├── SearchResultsView.swift  (NEW)
│   ├── SettingsView.swift
│   ├── JobsView.swift
│   └── Components/
│       └── FolderRowView.swift
└── ...
```

//
//  APIModels.swift
//  fileSearchForntend
//
//  Codable models for backend API communication.
//  All types use CodingKeys to map snake_case API fields to camelCase Swift properties.
//
//  Organization:
//  - File Models      (12-58)   - FileResponse, FileStatsResponse
//  - Watch/Job Models (60-168)  - Job management requests/responses
//  - Search Models    (170-207) - Search request/response types
//  - Status Models    (209-215) - Backend status
//  - SSE Event Models (217-405) - Server-Sent Events types
//  - Filter Models    (437-552) - File filter configuration
//  - Queue Models     (554-680) - Queue status, items, processed files
//  - Scheduler Models (682-765) - Scheduler rules and configuration
//  - Settings Models  (771-809) - Backend settings
//  - Error Models     (811-837) - API error types
//

import Foundation

// MARK: - File Models

struct FileResponse: Codable, Identifiable, Hashable {
    let filePath: String
    let filename: String
    let fileExtension: String
    let created: Date
    let modified: Date
    let accessed: Date
    let title: String?
    let summary: String?
    let keywords: [String]?

    var id: String { filePath }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case filename
        case fileExtension = "extension"
        case created
        case modified
        case accessed
        case title
        case summary
        case keywords
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
    }

    static func == (lhs: FileResponse, rhs: FileResponse) -> Bool {
        lhs.filePath == rhs.filePath
    }
}

/// Full debug-level snapshot of one indexed file: every files-table
/// column the backend exposes plus keywords and embedding presence.
/// Backs the "Stats for Nerds" panel — used to triage bad search hits
/// (especially images, where the LLM-generated summary is the only
/// signal the embedder ever sees) without having to crack open SQLite.
///
/// `found = false` is returned when the path isn't in the index;
/// every other field is nil in that case. The Swift call site handles
/// that uniform "not indexed" shape rather than parsing HTTP statuses.
struct FileDetailsResponse: Codable {
    let found: Bool
    let filePath: String
    let fileId: Int?
    let filename: String?
    let fileExtension: String?
    let fileSize: Int?
    /// Unix epoch seconds. The backend stores filesystem timestamps as
    /// integers, not ISO strings, so they come through as Int — convert
    /// at the view layer.
    let created: Int?
    let modified: Int?
    let accessed: Int?
    let contentType: String?
    let contentHash: String?
    let parsedAt: Int?
    let title: String?
    let summary: String?
    let summarizedAt: Int?
    let embeddedAt: Int?
    /// One of DISCOVERED / PARSED / SUMMARIZED / COMPLETE / FAILED.
    let status: String?
    let processingError: String?
    let owner: String?
    let permissions: String?
    let createdAt: Int?
    let updatedAt: Int?
    let keywords: [String]
    let hasEmbedding: Bool
    let embeddingModel: String?
    let embeddingDimensions: Int?

    enum CodingKeys: String, CodingKey {
        case found
        case filePath = "file_path"
        case fileId = "file_id"
        case filename
        case fileExtension = "extension"
        case fileSize = "file_size"
        case created
        case modified
        case accessed
        case contentType = "content_type"
        case contentHash = "content_hash"
        case parsedAt = "parsed_at"
        case title
        case summary
        case summarizedAt = "summarized_at"
        case embeddedAt = "embedded_at"
        case status
        case processingError = "processing_error"
        case owner
        case permissions
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case keywords
        case hasEmbedding = "has_embedding"
        case embeddingModel = "embedding_model"
        case embeddingDimensions = "embedding_dimensions"
    }
}

struct FileStatsResponse: Codable {
    let totalFiles: Int
    let totalSize: Int
    let fileTypes: [String: Int]
    let lastIndexed: String?

    enum CodingKeys: String, CodingKey {
        case totalFiles = "total_files"
        case totalSize = "total_size"
        case fileTypes = "file_types"
        case lastIndexed = "last_indexed"
    }
}

// MARK: - Watch Job Models

struct JobResponse: Codable, Identifiable, Hashable {
    let id: Int
    let path: String
    let isActive: Bool
    let recursive: Bool
    let filePattern: String?
    let lastScan: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let fileCount: Int?
    let totalFiles: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case isActive = "is_active"
        case recursive
        case filePattern = "file_pattern"
        case lastScan = "last_scan"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case fileCount = "file_count"
        case totalFiles = "total_files"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JobResponse, rhs: JobResponse) -> Bool {
        lhs.id == rhs.id
    }
}

struct JobsListResponse: Codable {
    let jobs: [JobResponse]
}

struct WatchRequest: Codable {
    let directoryPath: String

    enum CodingKeys: String, CodingKey {
        case directoryPath = "directory_path"
    }
}

struct WatchResponse: Codable {
    let success: Bool
    let message: String
    let filesIndexed: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case filesIndexed = "files_indexed"
    }
}

struct DeleteJobResponse: Codable {
    let success: Bool
    let message: String
    let jobId: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case jobId = "job_id"
    }
}

// MARK: - Index Models

struct IndexDirectoryRequest: Codable {
    let directoryPath: String

    enum CodingKeys: String, CodingKey {
        case directoryPath = "directory_path"
    }
}

struct IndexDirectoryResponse: Codable {
    let success: Bool
    let message: String
    let filesIndexed: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case filesIndexed = "files_indexed"
    }
}

struct IndexFileRequest: Codable {
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

struct IndexFileResponse: Codable {
    let success: Bool
    let message: String
    let fileId: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case fileId = "file_id"
    }
}

// MARK: - Search Models

struct SearchRequest: Codable {
    let query: String
    let directory: String?
    let filters: [String: String]?
    let limit: Int?
}

struct SearchResponse: Codable {
    let results: [SearchResultItem]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case results
        case totalCount = "total_count"
    }
}

struct SearchResultItem: Codable, Identifiable, Hashable {
    let file: FileResponse
    let relevanceScore: Double

    var id: String { file.filePath }

    enum CodingKeys: String, CodingKey {
        case file
        case relevanceScore = "relevance_score"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(file.filePath)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.file.filePath == rhs.file.filePath
    }
}

// MARK: - Status Models

struct StatusResponse: Codable {
    let status: String?
    let jobs: Int?
    let version: String?
    let embedderReady: Bool?
    let initProgress: Double?

    enum CodingKeys: String, CodingKey {
        case status, jobs, version
        case embedderReady = "embedder_ready"
        case initProgress = "init_progress"
    }
}

/// Returned from `GET /api/status/version`. Used at app launch to confirm
/// that the running backend speaks an API contract this frontend
/// understands. See `BackendCompatibility` for the matching policy and
/// `cosma_backend/__init__.py` for the bump procedure.
struct BackendVersionResponse: Codable {
    let backendVersion: String
    let apiVersion: Int
    let minFrontendApiVersion: Int

    enum CodingKeys: String, CodingKey {
        case backendVersion = "backend_version"
        case apiVersion = "api_version"
        case minFrontendApiVersion = "min_frontend_api_version"
    }
}

/// Response from POST /api/settings/test_model.
/// Indicates whether the configured summarizer model is reachable without loading it.
struct ModelTestResponse: Codable {
    let ok: Bool
    let provider: String
    let model: String
    let detail: String
}

// MARK: - Backend Update Events (for SSE)

/// Backend SSE event structure
/// Backend sends: {"opcode": "file_parsing", "data": {"path": "...", "filename": "..."}}
struct BackendUpdateEvent: Codable {
    let opcode: EventOpcode
    let data: EventData

    /// Convenience accessors that map backend field names to frontend expectations
    var filePath: String? {
        data.path
    }

    var directoryPath: String? {
        // For directory events, path is the directory
        // For file events, extract directory from file path
        if opcode.isDirectoryEvent {
            return data.path
        }
        return nil
    }

    var errorMessage: String? {
        data.error
    }

    var reason: String? {
        data.reason
    }

    var filename: String? {
        data.filename
    }

    var srcPath: String? {
        data.srcPath
    }

    var destPath: String? {
        data.destPath
    }

    var message: String? {
        data.message
    }
}

/// Nested data payload from backend events
struct EventData: Codable {
    let path: String?
    let filename: String?
    let error: String?
    let reason: String?
    let srcPath: String?
    let destPath: String?
    let message: String?
    let filePath: String?
    let action: String?
    let status: String?
    let source: String?
    let id: String?
    // Used by `queue_batch_added`: the coalesced list of newly-enqueued
    // file paths. Optional so older payloads / unrelated opcodes decode
    // unchanged.
    let paths: [String]?
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case filename
        case error
        case reason
        case srcPath = "src_path"
        case destPath = "dest_path"
        case message
        case filePath = "file_path"
        case action
        case status
        case source
        case id
        case paths
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        srcPath = try container.decodeIfPresent(String.self, forKey: .srcPath)
        destPath = try container.decodeIfPresent(String.self, forKey: .destPath)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        paths = try container.decodeIfPresent([String].self, forKey: .paths)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
    }
}

enum EventOpcode: String, Codable {
    // Watch management
    case watchStarted = "watch_started"
    case watchAdded = "watch_added"
    case watchRemoved = "watch_removed"

    // Directory processing
    case directoryProcessingStarted = "directory_processing_started"
    case directoryProcessingCompleted = "directory_processing_completed"

    // Directory system events
    case directoryDeleted = "directory_deleted"
    case directoryMoved = "directory_moved"

    // File processing pipeline
    case fileParsing = "file_parsing"
    case fileParsed = "file_parsed"
    case fileSummarizing = "file_summarizing"
    case fileSummarized = "file_summarized"
    case fileEmbedding = "file_embedding"
    case fileEmbedded = "file_embedded"
    case fileComplete = "file_complete"
    case fileFailed = "file_failed"
    case fileSkipped = "file_skipped"

    // File system events
    case fileCreated = "file_created"
    case fileModified = "file_modified"
    case fileDeleted = "file_deleted"
    case fileMoved = "file_moved"

    // Queue events
    case queueItemAdded = "queue_item_added"
    // Coalesced burst of newly-enqueued items emitted by the backend
    // during bulk discovery to keep the SSE stream from drowning in
    // per-file ADDED events. Carries `paths: [String]` and `count`.
    case queueBatchAdded = "queue_batch_added"
    case queueItemUpdated = "queue_item_updated"
    case queueItemProcessing = "queue_item_processing"
    case queueItemCompleted = "queue_item_completed"
    case queueItemFailed = "queue_item_failed"
    case queueItemRemoved = "queue_item_removed"
    case queuePaused = "queue_paused"
    case queueResumed = "queue_resumed"

    // Scheduler events
    case schedulerPaused = "scheduler_paused"
    case schedulerResumed = "scheduler_resumed"

    // General events
    case statusUpdate = "status_update"
    case error = "error"
    case info = "info"
    case shuttingDown = "shutting_down"

    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = EventOpcode(rawValue: rawValue) ?? .unknown
    }

    /// Whether this opcode represents a directory-level event
    var isDirectoryEvent: Bool {
        switch self {
        case .watchStarted, .watchAdded, .watchRemoved,
             .directoryProcessingStarted, .directoryProcessingCompleted,
             .directoryDeleted, .directoryMoved:
            return true
        default:
            return false
        }
    }

    /// Whether this opcode represents a file-level event
    var isFileEvent: Bool {
        switch self {
        case .fileParsing, .fileParsed, .fileSummarizing, .fileSummarized,
             .fileEmbedding, .fileEmbedded, .fileComplete, .fileFailed,
             .fileSkipped, .fileCreated, .fileModified, .fileDeleted, .fileMoved:
            return true
        default:
            return false
        }
    }

    /// Whether this opcode represents a queue-level event
    var isQueueEvent: Bool {
        switch self {
        case .queueItemAdded, .queueItemUpdated, .queueItemProcessing,
             .queueItemCompleted, .queueItemFailed, .queueItemRemoved,
             .queuePaused, .queueResumed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Deprecated Models (kept for compatibility during migration)

// These models are deprecated as the backend no longer supports summarizer model selection
struct SummarizerModelsResponse: Codable {
    let providers: [SummarizerModelOption]
    let current: String
}

struct SummarizerModelOption: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let description: String?
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case description
        case available
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

// MARK: - Filter Config Models

/// Filter mode - whether patterns are used as blacklist or whitelist
enum FilterMode: String, Codable {
    case blacklist
    case whitelist
}

/// Response containing the current filter configuration
struct FilterConfigResponse: Codable {
    let version: Int
    let mode: String
    // Legacy fields (deprecated but kept for compatibility)
    let exclude: [String]
    let include: [String]
    // Mode-specific pattern storage (NEW)
    let blacklistExclude: [String]
    let blacklistInclude: [String]
    let whitelistInclude: [String]
    let whitelistExclude: [String]
    let configPath: String

    enum CodingKeys: String, CodingKey {
        case version
        case mode
        case exclude
        case include
        case blacklistExclude = "blacklist_exclude"
        case blacklistInclude = "blacklist_include"
        case whitelistInclude = "whitelist_include"
        case whitelistExclude = "whitelist_exclude"
        case configPath = "config_path"
    }
}

/// Request to update filter configuration
struct UpdateFilterConfigRequest: Codable {
    let mode: String?
    // Legacy fields (deprecated but kept for compatibility)
    let exclude: [String]?
    let include: [String]?
    // Mode-specific pattern storage (NEW)
    let blacklistExclude: [String]?
    let blacklistInclude: [String]?
    let whitelistInclude: [String]?
    let whitelistExclude: [String]?
    // Control whether to apply changes immediately
    let applyImmediately: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case exclude
        case include
        case blacklistExclude = "blacklist_exclude"
        case blacklistInclude = "blacklist_include"
        case whitelistInclude = "whitelist_include"
        case whitelistExclude = "whitelist_exclude"
        case applyImmediately = "apply_immediately"
    }
}

/// Response after updating filter configuration
struct UpdateFilterConfigResponse: Codable {
    let success: Bool
    let message: String
    let config: FilterConfigResponse
    let removedCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case config
        case removedCount = "removed_count"
    }
}

/// Request to add a filter pattern
struct AddPatternRequest: Codable {
    let pattern: String
    let patternType: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case patternType = "pattern_type"
    }
}

/// Response after adding a pattern
struct AddPatternResponse: Codable {
    let success: Bool
    let message: String
    let removedCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case removedCount = "removed_count"
    }
}

/// Request to remove a filter pattern
struct RemovePatternRequest: Codable {
    let pattern: String
    let patternType: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case patternType = "pattern_type"
    }
}

/// Response after removing a pattern
struct RemovePatternResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Processed File Models (Failed / Recent)

struct ProcessedFileItem: Codable, Identifiable, Hashable {
    let filePath: String
    let filename: String
    let fileExtension: String
    let processingError: String?
    let status: String
    let updatedAt: Int?

    var id: String { filePath }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case filename
        case fileExtension = "extension"
        case processingError = "processing_error"
        case status
        case updatedAt = "updated_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
    }

    static func == (lhs: ProcessedFileItem, rhs: ProcessedFileItem) -> Bool {
        lhs.filePath == rhs.filePath
    }
}

struct ProcessedFilesResponse: Codable {
    let files: [ProcessedFileItem]
    let totalCount: Int
    let offset: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case files
        case totalCount = "total_count"
        case offset
        case limit
    }
}

struct ReindexRequest: Codable {
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

struct ReindexResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Queue Models

struct QueueStatusResponse: Codable {
    let paused: Bool
    let manuallyPaused: Bool
    let schedulerPaused: Bool
    let totalItems: Int
    let coolingDown: Int
    let waiting: Int
    let processing: Int
    let failingRules: [String]
    /// One-shot user override on top of the scheduler decision (backend
    /// v0.8.8+). nil = no override / scheduler in control. true = user
    /// forced "run now" (may run even while scheduler_paused). false =
    /// user forced "pause now". Auto-cleared on next scheduler
    /// transition. The button uses this so we can label correctly when
    /// the override is in effect.
    let userOverride: Bool?
    /// True for ~10s after every /api/search/ hit. The queue is paused
    /// so the embedder/LLM can serve the user query without contention.
    /// UI: render a distinct "paused for search" reason badge.
    /// Defaults to false on older backends that don't emit this field.
    let searchPreempted: Bool

    enum CodingKeys: String, CodingKey {
        case paused
        case manuallyPaused = "manually_paused"
        case schedulerPaused = "scheduler_paused"
        case totalItems = "total_items"
        case coolingDown = "cooling_down"
        case waiting
        case processing
        case failingRules = "failing_rules"
        case userOverride = "user_override"
        case searchPreempted = "search_preempted"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paused = try container.decode(Bool.self, forKey: .paused)
        manuallyPaused = try container.decode(Bool.self, forKey: .manuallyPaused)
        schedulerPaused = try container.decode(Bool.self, forKey: .schedulerPaused)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        coolingDown = try container.decode(Int.self, forKey: .coolingDown)
        waiting = try container.decode(Int.self, forKey: .waiting)
        processing = try container.decode(Int.self, forKey: .processing)
        failingRules = (try? container.decode([String].self, forKey: .failingRules)) ?? []
        userOverride = try? container.decodeIfPresent(Bool.self, forKey: .userOverride)
        searchPreempted = (try? container.decodeIfPresent(Bool.self, forKey: .searchPreempted)) ?? false
    }
}

struct QueueActionResponse: Codable {
    let success: Bool
    let message: String
}

struct QueueItemResponse: Codable, Identifiable, Hashable {
    let id: String
    let filePath: String
    let action: String
    let status: String
    let enqueuedAt: Double
    let cooldownExpiresAt: Double
    let destPath: String?
    let retryCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case filePath = "file_path"
        case action
        case status
        case enqueuedAt = "enqueued_at"
        case cooldownExpiresAt = "cooldown_expires_at"
        case destPath = "dest_path"
        case retryCount = "retry_count"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QueueItemResponse, rhs: QueueItemResponse) -> Bool {
        lhs.id == rhs.id
    }
}

struct QueueItemsResponse: Codable {
    let items: [QueueItemResponse]
    let totalCount: Int
    let offset: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case items
        case totalCount = "total_count"
        case offset
        case limit
    }
}

struct SchedulerRuleResponse: Codable {
    let rule: String
    let `operator`: String
    let value: AnyCodableValue?
    let enabled: Bool
}

struct SchedulerRuleResult: Codable {
    let rule: String
    let passed: Bool
    let metricAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case rule
        case passed
        case metricAvailable = "metric_available"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rule = try container.decode(String.self, forKey: .rule)
        passed = try container.decode(Bool.self, forKey: .passed)
        metricAvailable = try container.decodeIfPresent(Bool.self, forKey: .metricAvailable) ?? true
    }
}

struct SchedulerResponse: Codable {
    let enabled: Bool
    let combineMode: String
    let checkIntervalSeconds: Int
    let rules: [SchedulerRuleResponse]
    let conditionsMet: Bool
    let warnings: [String]
    let ruleResults: [SchedulerRuleResult]

    enum CodingKeys: String, CodingKey {
        case enabled
        case combineMode = "combine_mode"
        case checkIntervalSeconds = "check_interval_seconds"
        case rules
        case conditionsMet = "conditions_met"
        case warnings
        case ruleResults = "rule_results"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        combineMode = try container.decode(String.self, forKey: .combineMode)
        checkIntervalSeconds = try container.decode(Int.self, forKey: .checkIntervalSeconds)
        rules = try container.decode([SchedulerRuleResponse].self, forKey: .rules)
        conditionsMet = try container.decode(Bool.self, forKey: .conditionsMet)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        ruleResults = try container.decodeIfPresent([SchedulerRuleResult].self, forKey: .ruleResults) ?? []
    }
}

struct SchedulerUpdateRequest: Codable {
    let enabled: Bool?
    let combineMode: String?
    let checkIntervalSeconds: Int?
    let rules: [SchedulerRuleRequest]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case combineMode = "combine_mode"
        case checkIntervalSeconds = "check_interval_seconds"
        case rules
    }
}

struct SchedulerRuleRequest: Codable {
    let rule: String
    let `operator`: String
    let value: AnyCodableValue?
    let enabled: Bool
}

/// Type-erased Codable value for scheduler rule values (Int, Double, Bool, String, [String])
enum AnyCodableValue: Codable, Hashable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case stringArray([String])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String].self) {
            self = .stringArray(v)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unsupported value type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .stringArray(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

struct ModelStatus: Codable {
    let name: String
    let loaded: Bool
    let idleSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case loaded
        case idleSeconds = "idle_seconds"
    }
}

struct MetricsResponse: Codable {
    let metrics: [String: AnyCodableValue]
    let models: [ModelStatus]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metrics = try container.decode([String: AnyCodableValue].self, forKey: .metrics)
        models = (try? container.decode([ModelStatus].self, forKey: .models)) ?? []
    }
}

struct SchedulerTestResponse: Codable {
    let conditionsMet: Bool
    let ruleResults: [SchedulerRuleResult]
    let metrics: [String: AnyCodableValue]

    enum CodingKeys: String, CodingKey {
        case conditionsMet = "conditions_met"
        case ruleResults = "rule_results"
        case metrics
    }
}

// MARK: - Backend Settings Models

struct BackendSettingsResponse: Codable {
    let queue: QueueConfigResponse
    let scheduler: SchedulerConfigSettingsResponse
    let summarizer: SummarizerConfigSettingsResponse?
}

struct SummarizerConfigSettingsResponse: Codable {
    let idleUnloadSeconds: Int
    /// Cap every file at exactly one chunk's worth of summarize work.
    /// Trades long-doc coverage for throughput. Backend default false.
    let fastMode: Bool
    /// Wall-clock budget per file for the summarize stage; remaining
    /// chunks are skipped after this with a "[partial: ...]"
    /// annotation in the summary. 0 = unlimited.
    let summarizeBudgetSeconds: Double

    enum CodingKeys: String, CodingKey {
        case idleUnloadSeconds = "idle_unload_seconds"
        case fastMode = "fast_mode"
        case summarizeBudgetSeconds = "summarize_budget_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idleUnloadSeconds = try c.decode(Int.self, forKey: .idleUnloadSeconds)
        // Default-on-missing so older backends round-trip cleanly.
        fastMode = (try? c.decodeIfPresent(Bool.self, forKey: .fastMode)) ?? false
        summarizeBudgetSeconds = (try? c.decodeIfPresent(Double.self, forKey: .summarizeBudgetSeconds)) ?? 60.0
    }
}

// MARK: - Full Backend Settings (for /api/settings/ endpoint)

struct BackendSettings: Codable, Equatable {
    var embedder: EmbedderSettings
    var parser: ParserSettings
    var summarizer: SummarizerSettings
    /// Queue knobs (concurrency, search-preempt window, indexing
    /// grace period). Optional so older backends without queue
    /// settings still decode. Mostly read-only from the UI for now;
    /// surfacing them in Advanced settings would let power users
    /// tune for their hardware.
    var queue: QueueSettings?

    enum CodingKeys: String, CodingKey {
        case embedder, parser, summarizer, queue
    }
}

struct QueueSettings: Codable, Equatable {
    var cooldownSeconds: Int
    var initialCooldownSeconds: Int
    var maxConcurrency: Int
    var maxRetries: Int
    var fileProcessingTimeout: Int
    var gpuMemoryCap: Double
    var parseConcurrency: Int
    var summarizeConcurrency: Int
    var embedConcurrency: Int
    var indexingStartGraceSeconds: Double
    var searchPreemptSeconds: Double

    enum CodingKeys: String, CodingKey {
        case cooldownSeconds = "cooldown_seconds"
        case initialCooldownSeconds = "initial_cooldown_seconds"
        case maxConcurrency = "max_concurrency"
        case maxRetries = "max_retries"
        case fileProcessingTimeout = "file_processing_timeout"
        case gpuMemoryCap = "gpu_memory_cap"
        case parseConcurrency = "parse_concurrency"
        case summarizeConcurrency = "summarize_concurrency"
        case embedConcurrency = "embed_concurrency"
        case indexingStartGraceSeconds = "indexing_start_grace_seconds"
        case searchPreemptSeconds = "search_preempt_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Provide sensible defaults so a backend missing any new knob
        // round-trips. This is the same forward-compat pattern used
        // by QueueStatusResponse for `searchPreempted`.
        cooldownSeconds = (try? c.decodeIfPresent(Int.self, forKey: .cooldownSeconds)) ?? 60
        initialCooldownSeconds = (try? c.decodeIfPresent(Int.self, forKey: .initialCooldownSeconds)) ?? 5
        maxConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .maxConcurrency)) ?? 6
        maxRetries = (try? c.decodeIfPresent(Int.self, forKey: .maxRetries)) ?? 3
        fileProcessingTimeout = (try? c.decodeIfPresent(Int.self, forKey: .fileProcessingTimeout)) ?? 300
        gpuMemoryCap = (try? c.decodeIfPresent(Double.self, forKey: .gpuMemoryCap)) ?? 0.75
        parseConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .parseConcurrency)) ?? 4
        summarizeConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .summarizeConcurrency)) ?? 1
        embedConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .embedConcurrency)) ?? 1
        indexingStartGraceSeconds = (try? c.decodeIfPresent(Double.self, forKey: .indexingStartGraceSeconds)) ?? 5.0
        searchPreemptSeconds = (try? c.decodeIfPresent(Double.self, forKey: .searchPreemptSeconds)) ?? 10.0
    }
}

struct EmbedderSettings: Codable, Equatable {
    var dimensions: Int
    var localDimensions: Int
    var localModel: String
    var model: String
    var provider: String

    enum CodingKeys: String, CodingKey {
        case dimensions
        case localDimensions = "local_dimensions"
        case localModel = "local_model"
        case model
        case provider
    }
}

struct ParserSettings: Codable, Equatable {
    var extractionStrategy: String
    var spotlightEnabled: Bool
    var spotlightTimeoutSeconds: Int
    var whisper: WhisperSettings

    enum CodingKeys: String, CodingKey {
        case extractionStrategy = "extraction_strategy"
        case spotlightEnabled = "spotlight_enabled"
        case spotlightTimeoutSeconds = "spotlight_timeout_seconds"
        case whisper
    }
}

struct WhisperSettings: Codable, Equatable {
    var localModel: String
    var onlineModel: String
    var provider: String

    enum CodingKeys: String, CodingKey {
        case localModel = "local_model"
        case onlineModel = "online_model"
        case provider
    }
}

struct SummarizerSettings: Codable, Equatable {
    var chunkOverlapTokens: Int
    var llamacpp: LlamaCppSettings
    var maxTokensPerRequest: Int
    var ollama: OllamaSettings
    var online: OnlineSettings
    var provider: String
    /// Cap every file at exactly one chunk's worth of summarize work.
    /// Trades long-doc coverage for throughput. Backend default false.
    /// Decoded with default fallback so the frontend stays compatible
    /// with backends that pre-date this knob.
    var fastMode: Bool
    /// Wall-clock budget for the summarize stage per file. After this,
    /// remaining chunks are skipped and the existing partial summary
    /// is finalized with a "[partial: ...]" annotation. 0 = unlimited.
    var summarizeBudgetSeconds: Double

    enum CodingKeys: String, CodingKey {
        case chunkOverlapTokens = "chunk_overlap_tokens"
        case llamacpp
        case maxTokensPerRequest = "max_tokens_per_request"
        case ollama
        case online
        case provider
        case fastMode = "fast_mode"
        case summarizeBudgetSeconds = "summarize_budget_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chunkOverlapTokens = try c.decode(Int.self, forKey: .chunkOverlapTokens)
        llamacpp = try c.decode(LlamaCppSettings.self, forKey: .llamacpp)
        maxTokensPerRequest = try c.decode(Int.self, forKey: .maxTokensPerRequest)
        ollama = try c.decode(OllamaSettings.self, forKey: .ollama)
        online = try c.decode(OnlineSettings.self, forKey: .online)
        provider = try c.decode(String.self, forKey: .provider)
        // Default-on-missing so older backends round-trip cleanly.
        fastMode = (try? c.decodeIfPresent(Bool.self, forKey: .fastMode)) ?? false
        summarizeBudgetSeconds = (try? c.decodeIfPresent(Double.self, forKey: .summarizeBudgetSeconds)) ?? 60.0
    }
}

struct LlamaCppSettings: Codable, Equatable {
    var contextLength: Int
    var filename: String
    var modelPath: String
    var nCtx: Int
    var nGpuLayers: Int
    var nThreads: Int
    var repoId: String
    var verbose: Bool

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case filename
        case modelPath = "model_path"
        case nCtx = "n_ctx"
        case nGpuLayers = "n_gpu_layers"
        case nThreads = "n_threads"
        case repoId = "repo_id"
        case verbose
    }
}

struct OllamaSettings: Codable, Equatable {
    var contextLength: Int
    var host: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case host
        case model
    }
}

struct OnlineSettings: Codable, Equatable {
    var contextLength: Int
    var model: String

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case model
    }
}

struct QueueConfigResponse: Codable {
    let cooldownSeconds: Int
    let maxConcurrency: Int
    let maxRetries: Int
    /// Per-stage concurrency knobs (added 2026-05). Defaults match
    /// backend defaults so the UI shows sensible values when the
    /// backend is older than these fields.
    let parseConcurrency: Int
    let summarizeConcurrency: Int
    let embedConcurrency: Int
    /// Search-typing nudge window. Indexing pauses for this long
    /// after every search keystroke so the embedder/LLM gets
    /// uncontended hardware. Default 10 s.
    let searchPreemptSeconds: Double
    /// Hold-off after model load before indexing starts. Lets a
    /// search at app launch hit a quiet GPU. Default 5 s.
    let indexingStartGraceSeconds: Double

    enum CodingKeys: String, CodingKey {
        case cooldownSeconds = "cooldown_seconds"
        case maxConcurrency = "max_concurrency"
        case maxRetries = "max_retries"
        case parseConcurrency = "parse_concurrency"
        case summarizeConcurrency = "summarize_concurrency"
        case embedConcurrency = "embed_concurrency"
        case searchPreemptSeconds = "search_preempt_seconds"
        case indexingStartGraceSeconds = "indexing_start_grace_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cooldownSeconds = try c.decode(Int.self, forKey: .cooldownSeconds)
        maxConcurrency = try c.decode(Int.self, forKey: .maxConcurrency)
        maxRetries = try c.decode(Int.self, forKey: .maxRetries)
        parseConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .parseConcurrency)) ?? 4
        summarizeConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .summarizeConcurrency)) ?? 1
        embedConcurrency = (try? c.decodeIfPresent(Int.self, forKey: .embedConcurrency)) ?? 1
        searchPreemptSeconds = (try? c.decodeIfPresent(Double.self, forKey: .searchPreemptSeconds)) ?? 10.0
        indexingStartGraceSeconds = (try? c.decodeIfPresent(Double.self, forKey: .indexingStartGraceSeconds)) ?? 5.0
    }
}

struct SchedulerConfigSettingsResponse: Codable {
    let enabled: Bool
    let combineMode: String
    let checkIntervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case combineMode = "combine_mode"
        case checkIntervalSeconds = "check_interval_seconds"
    }
}

// MARK: - Error Models

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

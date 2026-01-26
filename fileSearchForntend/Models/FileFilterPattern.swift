//
//  FileFilterPattern.swift
//  fileSearchForntend
//
//  File filtering system with gitignore-like pattern matching.
//  Supports glob patterns, negation, and path matching.
//

import Foundation

// MARK: - Filter Pattern Model

/// Represents a single filter pattern for excluding files from search results.
/// Uses a gitignore-like syntax for pattern matching.
///
/// ## Pattern Syntax
///
/// | Pattern | Description | Example Matches |
/// |---------|-------------|-----------------|
/// | `.*` | Files starting with dot (hidden files) | `.gitignore`, `.env`, `.DS_Store` |
/// | `*.ext` | Files with specific extension | `*.log` matches `debug.log`, `error.log` |
/// | `prefix*` | Files starting with prefix | `temp*` matches `temp.txt`, `temporary.doc` |
/// | `*suffix` | Files ending with suffix | `*_backup` matches `file_backup`, `data_backup` |
/// | `*keyword*` | Files containing keyword | `*cache*` matches `mycache.db`, `cache_file.txt` |
/// | `exact.txt` | Exact filename match | `Thumbs.db` matches only `Thumbs.db` |
/// | `/path/` | Match path component | `/node_modules/` matches any file in node_modules |
/// | `!pattern` | Negation (exclude from filter) | `!*.important` keeps `.important` files visible |
///
/// ## Examples
///
/// ```
/// .*                    # Hide all hidden files (starting with .)
/// *.log                 # Hide all log files
/// *.tmp                 # Hide temporary files
/// *~                    # Hide backup files (ending with ~)
/// .DS_Store             # Hide macOS metadata
/// Thumbs.db             # Hide Windows thumbnails
/// /node_modules/        # Hide node_modules directories
/// /__pycache__/         # Hide Python cache
/// !.gitignore           # But show .gitignore files
/// ```
struct FileFilterPattern: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var pattern: String
    var isEnabled: Bool
    var description: String?

    init(id: UUID = UUID(), pattern: String, isEnabled: Bool = true, description: String? = nil) {
        self.id = id
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.description = description
    }

    /// Whether this pattern is a negation (starts with !)
    var isNegation: Bool {
        pattern.hasPrefix("!")
    }

    /// The actual pattern without the negation prefix
    var effectivePattern: String {
        isNegation ? String(pattern.dropFirst()) : pattern
    }

    /// Whether this is a path-based pattern (contains /)
    var isPathPattern: Bool {
        effectivePattern.contains("/")
    }
}

// MARK: - Filter Service

/// Service for matching files against filter patterns.
///
/// **Note: This is a temporary client-side implementation.**
/// In the future, filtering should be performed server-side via the search API
/// for better performance with large result sets. The API endpoint should accept
/// filter patterns and apply them during the search query, not after.
///
/// TODO: Implement server-side filtering via POST /api/search with filters parameter
/// Expected API format:
/// ```json
/// {
///   "query": "search text",
///   "directory": "/path/to/search",
///   "filters": {
///     "exclude_patterns": [".*", "*.log", "/node_modules/"],
///     "include_patterns": ["!.gitignore"]
///   },
///   "limit": 50
/// }
/// ```
final class FileFilterService {

    /// Default filter patterns for common hidden/system files
    static let defaultPatterns: [FileFilterPattern] = [
        FileFilterPattern(pattern: ".*", description: "Hidden files (starting with dot)"),
        FileFilterPattern(pattern: ".DS_Store", description: "macOS folder metadata"),
        FileFilterPattern(pattern: "Thumbs.db", description: "Windows thumbnail cache"),
        FileFilterPattern(pattern: "*.swp", description: "Vim swap files"),
        FileFilterPattern(pattern: "*~", description: "Backup files"),
    ]

    /// Check if a file should be filtered (hidden) based on the given patterns.
    ///
    /// **Temporary Implementation Note:**
    /// This function performs client-side filtering after search results are returned.
    /// For production use with large datasets, this logic should be moved to the server
    /// to avoid transferring unnecessary data over the network.
    ///
    /// - Parameters:
    ///   - filePath: The full path to the file
    ///   - filename: The filename (last path component)
    ///   - patterns: Array of filter patterns to check against
    /// - Returns: `true` if the file should be hidden, `false` if it should be shown
    static func shouldFilter(filePath: String, filename: String, patterns: [FileFilterPattern]) -> Bool {
        // First, check all regular (non-negation) patterns
        var isFiltered = false

        for pattern in patterns where pattern.isEnabled && !pattern.isNegation {
            if matches(filePath: filePath, filename: filename, pattern: pattern.effectivePattern) {
                isFiltered = true
                break
            }
        }

        // If filtered, check if any negation pattern saves it
        if isFiltered {
            for pattern in patterns where pattern.isEnabled && pattern.isNegation {
                if matches(filePath: filePath, filename: filename, pattern: pattern.effectivePattern) {
                    // Negation pattern matches, so DON'T filter this file
                    return false
                }
            }
        }

        return isFiltered
    }

    /// Check if a file matches a single pattern
    private static func matches(filePath: String, filename: String, pattern: String) -> Bool {
        // Path-based pattern (contains /)
        if pattern.contains("/") {
            return matchesPathPattern(filePath: filePath, pattern: pattern)
        }

        // Filename-based pattern
        return matchesGlobPattern(filename: filename, pattern: pattern)
    }

    /// Match a path pattern like `/node_modules/` or `path/to/dir/`
    private static func matchesPathPattern(filePath: String, pattern: String) -> Bool {
        let cleanPattern = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Check if any path component matches
        let components = filePath.split(separator: "/").map(String.init)
        for component in components {
            if matchesGlobPattern(filename: component, pattern: cleanPattern) {
                return true
            }
        }

        // Also check if the pattern appears anywhere in the path
        return filePath.contains("/\(cleanPattern)/") || filePath.hasSuffix("/\(cleanPattern)")
    }

    /// Match a glob pattern against a filename
    /// Supports: *, ?, and character matching
    private static func matchesGlobPattern(filename: String, pattern: String) -> Bool {
        // Exact match
        if pattern == filename {
            return true
        }

        // Convert glob to regex
        let regexPattern = globToRegex(pattern)

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
            let range = NSRange(filename.startIndex..., in: filename)
            return regex.firstMatch(in: filename, options: [], range: range) != nil
        } catch {
            // If regex fails, fall back to simple contains check
            let cleanPattern = pattern.replacingOccurrences(of: "*", with: "")
            return filename.localizedCaseInsensitiveContains(cleanPattern)
        }
    }

    /// Convert a glob pattern to a regex pattern
    private static func globToRegex(_ glob: String) -> String {
        var regex = "^"

        for char in glob {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            case "[", "]", "(", ")", "{", "}", "+", "^", "$", "|", "\\":
                regex += "\\\(char)"
            default:
                regex += String(char)
            }
        }

        regex += "$"
        return regex
    }

    // MARK: - Placeholder for Server-Side Implementation

    /// **PLACEHOLDER: Server-side filter request**
    ///
    /// This struct represents the expected format for server-side filtering.
    /// When the backend API supports filtering, use this structure to send
    /// filter patterns along with search requests.
    struct ServerFilterRequest: Codable {
        let excludePatterns: [String]
        let includePatterns: [String]  // Negation patterns (without ! prefix)

        enum CodingKeys: String, CodingKey {
            case excludePatterns = "exclude_patterns"
            case includePatterns = "include_patterns"
        }

        init(from patterns: [FileFilterPattern]) {
            var exclude: [String] = []
            var include: [String] = []

            for pattern in patterns where pattern.isEnabled {
                if pattern.isNegation {
                    include.append(pattern.effectivePattern)
                } else {
                    exclude.append(pattern.pattern)
                }
            }

            self.excludePatterns = exclude
            self.includePatterns = include
        }
    }

    /// **PLACEHOLDER: Convert patterns to server request format**
    ///
    /// Use this when the backend API supports filtering:
    /// ```swift
    /// let filterRequest = FileFilterService.makeServerRequest(from: patterns)
    /// let response = try await apiClient.search(
    ///     query: query,
    ///     directory: directory,
    ///     filters: filterRequest,  // Pass filter patterns
    ///     limit: 50
    /// )
    /// ```
    static func makeServerRequest(from patterns: [FileFilterPattern]) -> ServerFilterRequest {
        return ServerFilterRequest(from: patterns)
    }
}

// MARK: - Pattern Validation

extension FileFilterPattern {
    /// Validate the pattern syntax
    var isValid: Bool {
        let effective = effectivePattern
        guard !effective.isEmpty else { return false }

        // Check for invalid characters or patterns
        // Allow: alphanumeric, *, ?, ., -, _, /, [, ]
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "*?._-/[]"))
        return effective.unicodeScalars.allSatisfy { allowedChars.contains($0) }
    }

    /// Get a human-readable description of what this pattern matches
    var matchDescription: String {
        let effective = effectivePattern
        let action = isNegation ? "Show" : "Hide"

        if effective == ".*" {
            return "\(action) hidden files (starting with .)"
        } else if effective.hasPrefix("*.") {
            let ext = String(effective.dropFirst(2))
            return "\(action) .\(ext) files"
        } else if effective.hasPrefix("*") && effective.hasSuffix("*") {
            let keyword = String(effective.dropFirst().dropLast())
            return "\(action) files containing '\(keyword)'"
        } else if effective.hasPrefix("*") {
            let suffix = String(effective.dropFirst())
            return "\(action) files ending with '\(suffix)'"
        } else if effective.hasSuffix("*") {
            let prefix = String(effective.dropLast())
            return "\(action) files starting with '\(prefix)'"
        } else if effective.contains("/") {
            let path = effective.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(action) files in '\(path)' directories"
        } else {
            return "\(action) '\(effective)'"
        }
    }
}

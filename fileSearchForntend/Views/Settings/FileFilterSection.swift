//
//  FileFilterSection.swift
//  fileSearchForntend
//
//  File filtering configuration with pattern tags and help
//

import SwiftUI

// MARK: - File Filter Section

struct FileFilterSection: View {
    @Environment(AppModel.self) private var model
    @State private var newExcludePattern = ""
    @State private var newIncludePattern = ""
    @State private var showingHelp = false

    private var modeDescription: String {
        switch model.filterMode {
        case "blacklist":
            return "All files are indexed except those matching exclude patterns"
        case "whitelist":
            return "Only files matching include patterns are indexed"
        default:
            return "Configure file filtering patterns"
        }
    }

    private var excludeLabel: String {
        model.filterMode == "blacklist"
            ? "Exclude Patterns"
            : "Exclude Exceptions"
    }

    private var includeLabel: String {
        model.filterMode == "blacklist"
            ? "Include Exceptions"
            : "Include Patterns"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("File Filters")
                            .font(.system(size: 14, weight: .medium))

                        if model.hasUnsavedFilterChanges {
                            Text("Unsaved Changes")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                        }

                        Button(action: { showingHelp = true }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }

                    Text(modeDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isLoadingFilterConfig {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Error message if any
            if let error = model.filterConfigError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            }

            // Filter Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { model.filterMode },
                    set: { model.updateFilterMode($0) }
                )) {
                    Text("Blacklist (exclude matching files)").tag("blacklist")
                    Text("Whitelist (only include matching files)").tag("whitelist")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 350, alignment: .leading)
            }

            // Exclude Patterns Block
            PatternTagBlock(
                title: excludeLabel,
                patterns: model.excludePatterns,
                emptyText: model.filterMode == "blacklist" ? "No exclude patterns" : "No exclude exceptions",
                newPattern: $newExcludePattern,
                onAdd: { pattern in
                    model.addFilterPattern(pattern)
                },
                onRemove: { pattern in
                    model.removeFilterPattern(FileFilterPattern(pattern: pattern))
                },
                isLoading: model.isLoadingFilterConfig
            )

            // Include Patterns Block
            PatternTagBlock(
                title: includeLabel,
                patterns: model.includePatterns,
                emptyText: model.filterMode == "blacklist" ? "No include exceptions" : "No include patterns",
                newPattern: $newIncludePattern,
                onAdd: { pattern in
                    // Include patterns are stored with ! prefix internally
                    model.addFilterPattern("!\(pattern)")
                },
                onRemove: { pattern in
                    model.removeFilterPattern(FileFilterPattern(pattern: "!\(pattern)"))
                },
                isLoading: model.isLoadingFilterConfig
            )

            // Save/Discard buttons (shown when there are unsaved changes)
            if model.hasUnsavedFilterChanges {
                HStack(spacing: 12) {
                    Button("Discard Changes") {
                        model.discardFilterChanges()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(model.isLoadingFilterConfig)

                    Button("Save Changes") {
                        Task {
                            await model.saveFilterConfig()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(model.isLoadingFilterConfig)
                }
                .padding(.top, 4)
            }

            // Action buttons
            HStack {
                Button("Reset to Defaults") {
                    model.resetFilterPatternsToDefaults()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .disabled(model.isLoadingFilterConfig)

                Spacer()

                Button {
                    Task {
                        await model.refreshFilterConfig()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .disabled(model.isLoadingFilterConfig || model.hasUnsavedFilterChanges)
            }
        }
        .sheet(isPresented: $showingHelp) {
            FilterPatternHelpView()
        }
    }
}

// MARK: - Pattern Tag Block

private struct PatternTagBlock: View {
    let title: String
    let patterns: [String]
    let emptyText: String
    @Binding var newPattern: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            // Tags in a flow layout
            FlowLayout(spacing: 6) {
                ForEach(patterns, id: \.self) { pattern in
                    PatternTag(pattern: pattern) {
                        onRemove(pattern)
                    }
                }

                // Add new pattern inline
                AddPatternTag(text: $newPattern) {
                    let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onAdd(trimmed)
                    newPattern = ""
                }
                .disabled(isLoading)
            }

            if patterns.isEmpty && newPattern.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Pattern Tag

private struct PatternTag: View {
    let pattern: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(pattern)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

// MARK: - Add Pattern Tag

private struct AddPatternTag: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Add...", text: $text)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(width: text.isEmpty ? 40 : max(40, CGFloat(text.count * 8)))
                .focused($isFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.04), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

// MARK: - Filter Pattern Help View

private struct FilterPatternHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filter Pattern Syntax")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Introduction
                    Text("Use gitignore-like patterns to filter files from search results. Patterns are case-insensitive.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    // Pattern types
                    VStack(alignment: .leading, spacing: 16) {
                        PatternHelpRow(
                            pattern: ".*",
                            description: "Hidden files (starting with dot)",
                            examples: ".gitignore, .env, .DS_Store"
                        )

                        PatternHelpRow(
                            pattern: "*.ext",
                            description: "Files with specific extension",
                            examples: "*.log matches debug.log, error.log"
                        )

                        PatternHelpRow(
                            pattern: "prefix*",
                            description: "Files starting with prefix",
                            examples: "temp* matches temp.txt, temporary.doc"
                        )

                        PatternHelpRow(
                            pattern: "*suffix",
                            description: "Files ending with suffix",
                            examples: "*_backup matches file_backup"
                        )

                        PatternHelpRow(
                            pattern: "*keyword*",
                            description: "Files containing keyword",
                            examples: "*cache* matches mycache.db"
                        )

                        PatternHelpRow(
                            pattern: "exact.txt",
                            description: "Exact filename match",
                            examples: "Thumbs.db matches only Thumbs.db"
                        )

                        PatternHelpRow(
                            pattern: "/path/",
                            description: "Match directory in path",
                            examples: "/node_modules/ hides files in node_modules"
                        )

                        PatternHelpRow(
                            pattern: "!pattern",
                            description: "Negation (show file despite other filters)",
                            examples: "!.gitignore shows .gitignore even with .* filter"
                        )
                    }

                    Divider()

                    // Common patterns
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Patterns")
                            .font(.system(size: 14, weight: .semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            PatternExample(pattern: ".*", note: "All hidden files")
                            PatternExample(pattern: "*.log", note: "Log files")
                            PatternExample(pattern: "*.tmp", note: "Temporary files")
                            PatternExample(pattern: "*~", note: "Backup files")
                            PatternExample(pattern: "/node_modules/", note: "Node.js dependencies")
                            PatternExample(pattern: "/__pycache__/", note: "Python cache")
                            PatternExample(pattern: "/.git/", note: "Git internals")
                            PatternExample(pattern: "/build/", note: "Build output")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Pattern Help Row

private struct PatternHelpRow: View {
    let pattern: String
    let description: String
    let examples: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pattern)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)

                Text("-")
                    .foregroundStyle(.secondary)

                Text(description)
                    .font(.system(size: 13))
            }

            Text("Examples: \(examples)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pattern Example

private struct PatternExample: View {
    let pattern: String
    let note: String

    var body: some View {
        HStack(spacing: 8) {
            Text(pattern)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)

            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

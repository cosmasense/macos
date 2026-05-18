//
//  AppSearchSection.swift
//  fileSearchForntend
//
//  Renders matching applications above file results with a thin
//  divider. Shared between the main window search view and the
//  popup overlay so the apps-on-top layout is consistent.
//
//  Contract: callers pass `apps` directly (already filtered for the
//  `disableAppsSearch` setting on the AppModel). When `apps` is empty
//  these views render nothing — no divider, no header, no UX change
//  for users without apps indexed.
//

import AppKit
import SwiftUI

// MARK: - List Style

/// Apps section for the main-window LIST view. Stacks compact rows
/// vertically and follows with a thin divider before docs render.
struct AppSearchListSection: View {
    let apps: [ApplicationResultItem]
    let onOpen: (ApplicationResultItem) -> Void

    var body: some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                AppsSectionHeader(count: apps.count)
                VStack(spacing: 4) {
                    ForEach(apps) { app in
                        AppListRow(app: app) { onOpen(app) }
                    }
                }
                AppsSectionDivider()
            }
        }
    }
}

// MARK: - Grid Style

/// Apps section for the main-window GRID view and the popup overlay
/// (which is always grid). Uses the same column layout as the
/// surrounding file grid by accepting an explicit column count.
struct AppSearchGridSection: View {
    let apps: [ApplicationResultItem]
    let columnCount: Int
    let onOpen: (ApplicationResultItem) -> Void

    var body: some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AppsSectionHeader(count: apps.count)
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                        count: max(1, columnCount)
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(apps) { app in
                        AppGridTile(app: app) { onOpen(app) }
                    }
                }
                AppsSectionDivider()
            }
        }
    }
}

// MARK: - Shared chrome

private struct AppsSectionHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "app.badge")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(count == 1 ? "Application" : "Applications")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

/// A single hair-line rule. Visible only when apps render so the
/// docs-only case (the historical layout) stays untouched.
private struct AppsSectionDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 6)
    }
}

// MARK: - List row

private struct AppListRow: View {
    let app: ApplicationResultItem
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                AppIconView(app: app, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let version = app.shortVersion, !version.isEmpty {
                    Text("v\(version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.appPath)
    }

    private var subtitleText: String? {
        // Prefer the LLM-enriched use_cases when present. Fall back
        // to the Info.plist description, then the bundle category
        // tag (stripped to the trailing component for readability:
        // "public.app-category.productivity" → "productivity").
        if let u = app.useCases, !u.isEmpty { return u }
        if let d = app.description, !d.isEmpty { return d }
        if let c = app.category, let last = c.split(separator: ".").last {
            return String(last).replacingOccurrences(of: "-", with: " ")
        }
        return nil
    }
}

// MARK: - Grid tile

private struct AppGridTile: View {
    let app: ApplicationResultItem
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                AppIconView(app: app, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.appPath)
    }

    private var subtitleText: String? {
        if let u = app.useCases, !u.isEmpty { return u }
        if let d = app.description, !d.isEmpty { return d }
        if let c = app.category, let last = c.split(separator: ".").last {
            return String(last).replacingOccurrences(of: "-", with: " ")
        }
        return nil
    }
}

// MARK: - Icon

/// Loads the app's icon from disk if the discoverer found a .icns,
/// otherwise asks NSWorkspace for the bundle icon (which resolves
/// the system fallback). NSWorkspace caches internally so repeated
/// loads of the same bundle don't pay disk cost.
private struct AppIconView: View {
    let app: ApplicationResultItem
    let size: CGFloat

    var body: some View {
        Image(nsImage: resolveIcon())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private func resolveIcon() -> NSImage {
        if let path = app.iconPath, !path.isEmpty,
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: app.appPath)
    }
}

// MARK: - Open helper

/// Open an .app bundle the same way Finder would. The popup and
/// main result handlers both call this so the launch behavior is
/// consistent (and unlike `NSWorkspace.open(URL)` for files, an
/// app launch shouldn't reveal the bundle in Finder).
@MainActor
func openApplicationBundle(_ app: ApplicationResultItem) {
    let url = URL(fileURLWithPath: app.appPath)
    NSWorkspace.shared.open(url)
}

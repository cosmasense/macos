//
//  FullDiskAccessGateView.swift
//  fileSearchForntend
//
//  Startup gate: requires Full Disk Access before proceeding.
//

import SwiftUI
import AppKit

struct FullDiskAccessGateView: View {
    let onGranted: () -> Void
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Full Disk Access Required")
                .font(.system(size: 24, weight: .semibold))

            VStack(spacing: 8) {
                Text("Cosma Sense needs Full Disk Access to index your files")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("and run the backend server.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Click \"Open System Settings\" below")
                StepRow(number: 2, text: "Find Cosma Sense in the list and enable it")
                StepRow(number: 3, text: "Come back and click \"Check Again\"")
            }
            .padding(.horizontal, 40)

            HStack(spacing: 16) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task {
                        isChecking = true
                        // Slight delay to let system settings propagate
                        try? await Task.sleep(for: .milliseconds(500))
                        if checkFullDiskAccessPermission() {
                            onGranted()
                        }
                        isChecking = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check Again")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if checkFullDiskAccessPermission() {
                onGranted()
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

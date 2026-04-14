//
//  FullDiskAccessGateView.swift
//  fileSearchForntend
//
//  Startup gate: requires Full Disk Access before proceeding.
//  Styled to match the SetupWizard's Full Disk Access step.
//

import SwiftUI
import AppKit

struct FullDiskAccessGateView: View {
    let onGranted: () -> Void
    @State private var hasAccess: Bool = false
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.brandBlue)

            Text("Full Disk Access")
                .font(.system(size: 22, weight: .semibold))

            Text("Cosma Sense searches your whole Mac to find files by name, content, and meaning — powered by local semantic search. To do that, it needs permission to read your files.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Click \"Open System Settings\" below")
                StepRow(number: 2, text: "Find Cosma Sense in the list and enable it")
                StepRow(number: 3, text: "Come back and click \"Continue\"")

                if !hasAccess {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Access not granted yet — Continue will unlock once enabled.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings", systemImage: "gear").frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task {
                        isChecking = true
                        try? await Task.sleep(for: .milliseconds(300))
                        hasAccess = checkFullDiskAccessPermission()
                        isChecking = false
                        if hasAccess { onGranted() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isChecking { ProgressView().controlSize(.small) }
                        Text("Continue")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                .controlSize(.large)
                .disabled(!hasAccess)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.white.opacity(0.4))
                .ignoresSafeArea()
        )
        .onAppear {
            hasAccess = checkFullDiskAccessPermission()
            if hasAccess { onGranted() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = checkFullDiskAccessPermission()
            if hasAccess { onGranted() }
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
                .background(Circle().fill(Color.brandBlue))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

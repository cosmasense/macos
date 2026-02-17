//
//  ModelsSection.swift
//  fileSearchForntend
//
//  Processing configuration: Embedding, Summarizer, Whisper, and Advanced Settings
//

import SwiftUI

// MARK: - Backend Settings Section

struct BackendSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Processing Configuration")
                    .font(.system(size: 20, weight: .semibold))

                Spacer()

                if model.isLoadingSettings {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await model.refreshSettings() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isLoadingSettings)
            }

            if let error = model.settingsError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            }

            if let settings = model.processingSettings {
                // Embedding card
                SettingsCard(title: "Embedding", icon: "cube.fill") {
                    SettingPicker(
                        label: "Provider",
                        path: "embedder.provider",
                        value: settings.embedder.provider,
                        options: ["local", "online"]
                    )

                    if settings.embedder.provider == "local" {
                        SettingTextField(
                            label: "Local Model",
                            path: "embedder.local_model",
                            value: settings.embedder.localModel
                        )
                    } else {
                        SettingTextField(
                            label: "Online Model",
                            path: "embedder.model",
                            value: settings.embedder.model
                        )
                    }
                }

                // Summarizer card
                SettingsCard(title: "Summarizer", icon: "text.badge.star") {
                    SettingPicker(
                        label: "Provider",
                        path: "summarizer.provider",
                        value: settings.summarizer.provider,
                        options: ["ollama", "online", "llamacpp", "auto"]
                    )

                    switch settings.summarizer.provider {
                    case "ollama":
                        SettingTextField(
                            label: "Model",
                            path: "summarizer.ollama.model",
                            value: settings.summarizer.ollama.model
                        )
                        SettingTextField(
                            label: "Host",
                            path: "summarizer.ollama.host",
                            value: settings.summarizer.ollama.host
                        )
                    case "online":
                        SettingTextField(
                            label: "Model",
                            path: "summarizer.online.model",
                            value: settings.summarizer.online.model
                        )
                    case "llamacpp":
                        SettingTextField(
                            label: "Repo ID",
                            path: "summarizer.llamacpp.repo_id",
                            value: settings.summarizer.llamacpp.repoId
                        )
                        SettingTextField(
                            label: "Filename",
                            path: "summarizer.llamacpp.filename",
                            value: settings.summarizer.llamacpp.filename
                        )
                    default:
                        EmptyView()
                    }
                }

                // Whisper card
                SettingsCard(title: "Audio Transcription (Whisper)", icon: "waveform") {
                    SettingPicker(
                        label: "Provider",
                        path: "parser.whisper.provider",
                        value: settings.parser.whisper.provider,
                        options: ["local", "online"]
                    )

                    if settings.parser.whisper.provider == "local" {
                        SettingTextField(
                            label: "Local Model",
                            path: "parser.whisper.local_model",
                            value: settings.parser.whisper.localModel
                        )
                    } else {
                        SettingTextField(
                            label: "Online Model",
                            path: "parser.whisper.online_model",
                            value: settings.parser.whisper.onlineModel
                        )
                    }
                }

                // Advanced Settings
                DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Embedder advanced
                        Text("Embedder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        SettingIntField(label: "Dimensions", path: "embedder.dimensions", value: settings.embedder.dimensions)
                        SettingIntField(label: "Local Dimensions", path: "embedder.local_dimensions", value: settings.embedder.localDimensions)
                        SettingTextField(label: "Local Model", path: "embedder.local_model", value: settings.embedder.localModel)
                        SettingTextField(label: "Online Model", path: "embedder.model", value: settings.embedder.model)

                        Divider()

                        // Parser advanced
                        Text("Parser")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        SettingPicker(
                            label: "Extraction Strategy",
                            path: "parser.extraction_strategy",
                            value: settings.parser.extractionStrategy,
                            options: ["spotlight_first", "textract", "tika"]
                        )
                        SettingToggle(label: "Spotlight Enabled", path: "parser.spotlight_enabled", value: settings.parser.spotlightEnabled)
                        SettingIntField(label: "Spotlight Timeout (s)", path: "parser.spotlight_timeout_seconds", value: settings.parser.spotlightTimeoutSeconds)

                        Divider()

                        // Summarizer advanced
                        Text("Summarizer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        SettingIntField(label: "Chunk Overlap Tokens", path: "summarizer.chunk_overlap_tokens", value: settings.summarizer.chunkOverlapTokens)
                        SettingIntField(label: "Max Tokens per Request", path: "summarizer.max_tokens_per_request", value: settings.summarizer.maxTokensPerRequest)

                        // Ollama
                        Text("Ollama")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)

                        SettingIntField(label: "Context Length", path: "summarizer.ollama.context_length", value: settings.summarizer.ollama.contextLength)
                        SettingTextField(label: "Host", path: "summarizer.ollama.host", value: settings.summarizer.ollama.host)
                        SettingTextField(label: "Model", path: "summarizer.ollama.model", value: settings.summarizer.ollama.model)

                        // Online
                        Text("Online")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)

                        SettingIntField(label: "Context Length", path: "summarizer.online.context_length", value: settings.summarizer.online.contextLength)
                        SettingTextField(label: "Model", path: "summarizer.online.model", value: settings.summarizer.online.model)

                        // LlamaCpp
                        Text("LlamaCpp")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)

                        SettingIntField(label: "Context Length", path: "summarizer.llamacpp.context_length", value: settings.summarizer.llamacpp.contextLength)
                        SettingIntField(label: "n_ctx", path: "summarizer.llamacpp.n_ctx", value: settings.summarizer.llamacpp.nCtx)
                        SettingIntField(label: "GPU Layers", path: "summarizer.llamacpp.n_gpu_layers", value: settings.summarizer.llamacpp.nGpuLayers)
                        SettingIntField(label: "Threads", path: "summarizer.llamacpp.n_threads", value: settings.summarizer.llamacpp.nThreads)
                        SettingToggle(label: "Verbose", path: "summarizer.llamacpp.verbose", value: settings.summarizer.llamacpp.verbose)
                        SettingTextField(label: "Model Path", path: "summarizer.llamacpp.model_path", value: settings.summarizer.llamacpp.modelPath)
                        SettingTextField(label: "Repo ID", path: "summarizer.llamacpp.repo_id", value: settings.summarizer.llamacpp.repoId)
                        SettingTextField(label: "Filename", path: "summarizer.llamacpp.filename", value: settings.summarizer.llamacpp.filename)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

                // Reset button
                Button("Reset to Defaults") {
                    model.resetSettingsToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isLoadingSettings)
            } else if !model.isLoadingSettings {
                Text("Unable to load backend settings. Check that the backend is running.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if model.processingSettings == nil {
                await model.refreshSettings()
            }
        }
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Setting Field Components

private struct SettingPicker: View {
    @Environment(AppModel.self) private var model
    let label: String
    let path: String
    let value: String
    let options: [String]

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            Picker("", selection: Binding(
                get: { value },
                set: { model.updateSetting(path: path, value: $0) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 250)

            SettingSaveIndicator(path: path)
        }
    }
}

private struct SettingTextField: View {
    @Environment(AppModel.self) private var model
    let label: String
    let path: String
    let value: String
    @State private var editedValue: String = ""
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            TextField("", text: $editedValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: 250)
                .onSubmit {
                    if editedValue != value {
                        model.updateSetting(path: path, value: editedValue)
                    }
                }

            SettingSaveIndicator(path: path)
        }
        .onAppear {
            if !hasAppeared {
                editedValue = value
                hasAppeared = true
            }
        }
        .onChange(of: value) { _, newValue in
            editedValue = newValue
        }
    }
}

private struct SettingIntField: View {
    @Environment(AppModel.self) private var model
    let label: String
    let path: String
    let value: Int
    @State private var editedValue: String = ""
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            TextField("", text: $editedValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: 120)
                .onSubmit {
                    if let intVal = Int(editedValue), intVal != value {
                        model.updateSetting(path: path, value: intVal)
                    }
                }

            SettingSaveIndicator(path: path)
        }
        .onAppear {
            if !hasAppeared {
                editedValue = String(value)
                hasAppeared = true
            }
        }
        .onChange(of: value) { _, newValue in
            editedValue = String(newValue)
        }
    }
}

private struct SettingToggle: View {
    @Environment(AppModel.self) private var model
    let label: String
    let path: String
    let value: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { value },
                set: { model.updateSetting(path: path, value: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            SettingSaveIndicator(path: path)
        }
    }
}

private struct SettingSaveIndicator: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        Group {
            if model.savingSettingPaths.contains(path) {
                ProgressView()
                    .controlSize(.small)
            } else if model.savedSettingPaths.contains(path) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            }
        }
        .frame(width: 16, height: 16)
    }
}

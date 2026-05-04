//
//  LicensesView.swift
//  fileSearchForntend
//
//  Open-source acknowledgements panel. Lists every third-party
//  library Cosma Sense bundles, with its license name and a link to
//  the canonical license text. Surfaced from Settings → General so
//  users (and reviewers) can verify compliance without having to dig
//  through the source tree.
//
//  Maintenance note: when adding a new dependency in either the
//  backend (cosma/packages/cosma-backend/pyproject.toml) or the
//  frontend (Xcode project), add a matching `Library` entry below.
//  This file is the single visible record of "what we ship."
//

import SwiftUI
import AppKit

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    ForEach(libraries) { lib in
                        LibraryRow(library: lib)
                    }
                    notes
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 16))
                .foregroundStyle(Color.brandBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open Source Acknowledgements")
                    .font(.system(size: 14, weight: .semibold))
                Text("Libraries used by Cosma Sense and the cosma backend.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var intro: some View {
        Text("This page lists open-source libraries Cosma Sense distributes or links against. Each entry includes the project's license; click the project name to read the full upstream license text.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)
            Text("• ffmpeg is bundled by imageio-ffmpeg only as a runtime fallback when no system ffmpeg is available. The bundled binary is the LGPL build provided by imageio-ffmpeg's maintainers.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("• Some libraries listed here are transitive dependencies of others. The list is intentionally inclusive rather than minimal so reviewers can audit anything that ships.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Concrete library entries. Add a new row here whenever a new
    /// library is added to the frontend or backend.
    private var libraries: [Library] {
        [
            // --- Frontend (macOS app) ---
            // No third-party Swift packages bundled today; the app links
            // against Apple system frameworks only (SwiftUI, AppKit,
            // QuickLookUI, ServiceManagement, UserNotifications), which
            // are governed by the Apple SDK license, not third-party
            // licenses. No entry needed here unless that changes.

            // --- Backend (cosma-backend Python package) ---
            Library(
                name: "Quart",
                purpose: "Async ASGI web framework powering the backend HTTP API",
                license: "MIT",
                url: "https://github.com/pallets/quart"
            ),
            Library(
                name: "uvicorn",
                purpose: "ASGI server hosting the Quart app",
                license: "BSD-3-Clause",
                url: "https://github.com/encode/uvicorn"
            ),
            Library(
                name: "asqlite",
                purpose: "Async wrapper around SQLite",
                license: "MIT",
                url: "https://github.com/Rapptz/asqlite"
            ),
            Library(
                name: "sqlite-vec",
                purpose: "Vector search extension for SQLite (semantic search)",
                license: "Apache-2.0",
                url: "https://github.com/asg017/sqlite-vec"
            ),
            Library(
                name: "sentence-transformers",
                purpose: "Local sentence embedding models (e5-base-v2)",
                license: "Apache-2.0",
                url: "https://github.com/UKPLab/sentence-transformers"
            ),
            Library(
                name: "huggingface-hub",
                purpose: "Model file downloads from Hugging Face",
                license: "Apache-2.0",
                url: "https://github.com/huggingface/huggingface_hub"
            ),
            Library(
                name: "llama-cpp-python (cosmasense fork)",
                purpose: "Local vision-language model runtime (Qwen3-VL)",
                license: "MIT",
                url: "https://github.com/abetlen/llama-cpp-python"
            ),
            Library(
                name: "ollama-python",
                purpose: "Optional Ollama backend for summarization",
                license: "MIT",
                url: "https://github.com/ollama/ollama-python"
            ),
            Library(
                name: "litellm",
                purpose: "Unified LLM client API (multi-provider)",
                license: "MIT",
                url: "https://github.com/BerriAI/litellm"
            ),
            Library(
                name: "MarkItDown",
                purpose: "Document → markdown extraction (docx, pdf, pptx)",
                license: "MIT",
                url: "https://github.com/microsoft/markitdown"
            ),
            Library(
                name: "pywhispercpp",
                purpose: "Local speech transcription via whisper.cpp",
                license: "MIT",
                url: "https://github.com/abdeladim-s/pywhispercpp"
            ),
            Library(
                name: "imageio-ffmpeg",
                purpose: "Bundled fallback ffmpeg binary for media decoding",
                license: "BSD-2-Clause (Python wrapper); LGPL (bundled ffmpeg binary)",
                url: "https://github.com/imageio/imageio-ffmpeg"
            ),
            Library(
                name: "tiktoken",
                purpose: "Token counting for LLM context budgeting",
                license: "MIT",
                url: "https://github.com/openai/tiktoken"
            ),
            Library(
                name: "structlog",
                purpose: "Structured backend logging",
                license: "Apache-2.0 / MIT",
                url: "https://github.com/hynek/structlog"
            ),
            Library(
                name: "watchdog",
                purpose: "File system change monitoring for indexing",
                license: "Apache-2.0",
                url: "https://github.com/gorakhargosh/watchdog"
            ),
            Library(
                name: "platformdirs",
                purpose: "Cross-platform OS-conventional config / cache dirs",
                license: "MIT",
                url: "https://github.com/platformdirs/platformdirs"
            ),
            Library(
                name: "psutil",
                purpose: "Process and system metrics (scheduler thresholds)",
                license: "BSD-3-Clause",
                url: "https://github.com/giampaolo/psutil"
            ),
            Library(
                name: "tomli-w",
                purpose: "TOML writer for settings persistence",
                license: "MIT",
                url: "https://github.com/hukkin/tomli-w"
            ),
            Library(
                name: "quart-schema",
                purpose: "Request/response validation for Quart endpoints",
                license: "MIT",
                url: "https://github.com/pgjones/quart-schema"
            ),
            Library(
                name: "PyObjC (Quartz, Vision)",
                purpose: "macOS Vision framework bindings for OCR fallback",
                license: "MIT",
                url: "https://github.com/ronaldoussoren/pyobjc"
            ),

            // --- Models (downloaded at first launch, not bundled) ---
            Library(
                name: "Qwen3-VL-2B-Instruct",
                purpose: "Vision-language model for image and frame summarization",
                license: "Apache-2.0",
                url: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct"
            ),
            Library(
                name: "intfloat/e5-base-v2",
                purpose: "Sentence embedding model used for semantic search",
                license: "MIT",
                url: "https://huggingface.co/intfloat/e5-base-v2"
            ),
            Library(
                name: "ggerganov/whisper.cpp models",
                purpose: "Whisper speech-recognition model weights (ggml format)",
                license: "MIT",
                url: "https://huggingface.co/ggerganov/whisper.cpp"
            ),
        ]
    }
}

// MARK: - Library Row

private struct Library: Identifiable {
    var id: String { name }
    let name: String
    let purpose: String
    let license: String
    let url: String
}

private struct LibraryRow: View {
    let library: Library

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        if let url = URL(string: library.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(library.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.brandBlue)
                    }
                    .buttonStyle(.plain)

                    Text(library.license)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(library.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

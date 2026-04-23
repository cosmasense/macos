//
//  CosmaManager+Bootstrap.swift
//  fileSearchForntend
//
//  Consumes the backend's /api/bootstrap endpoints so the setup wizard can
//  show live progress while llama.cpp + whisper.cpp models download.
//
//  Why a separate file:
//  - CosmaManager.swift already handles process lifecycle, update checks,
//    and Ollama bootstrap. Piling the model-download SSE parser on top
//    would push it past readable size.
//  - Bootstrap is logically a post-startup concern (the server must be
//    reachable before we can hit the endpoints), so isolating it keeps
//    the startup flow in CosmaManager.swift easier to scan.
//

import Foundation

/// One row in the bootstrap status table. Mirrors the backend's
/// `ComponentStatus` JSON so we can decode straight into it.
struct BootstrapComponent: Identifiable, Equatable, Codable {
    // Frontend-only derived id so SwiftUI lists are stable.
    var id: String { name }

    let name: String
    var present: Bool
    var path: String?
    var detail: String?

    // Download progress — populated from SSE events, not from /status.
    var bytesDone: Int = 0
    var bytesTotal: Int = 0
    var message: String = ""
    var done: Bool = false

    var fraction: Double {
        guard bytesTotal > 0 else { return present || done ? 1.0 : 0.0 }
        return min(1.0, Double(bytesDone) / Double(bytesTotal))
    }

    var displayLabel: String {
        switch name {
        case "llama_cpp_python": return "llama.cpp binding"
        case "llama_model":      return "Qwen3-VL model"
        case "llama_mmproj":     return "Vision projector"
        case "whisper_cpp":      return "whisper.cpp binding"
        case "whisper_model":    return "Whisper model"
        default:                 return name
        }
    }

    // Friendly downloaded-so-far / total string, e.g. "412 MB / 1.2 GB".
    var progressText: String? {
        guard bytesTotal > 0 else { return message.isEmpty ? nil : message }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return "\(f.string(fromByteCount: Int64(bytesDone))) / \(f.string(fromByteCount: Int64(bytesTotal)))"
    }

    /// Single-line label shown on the bar: "N% · 412 MB / 1.2 GB" when we
    /// have totals, else just the message text so the row isn't blank
    /// during the first second or two before total_bytes is resolved.
    var inlineProgressText: String {
        if bytesTotal > 0 {
            let pct = Int((Double(bytesDone) / Double(bytesTotal)) * 100)
            if let mb = progressText { return "\(pct)% · \(mb)" }
            return "\(pct)%"
        }
        return message.isEmpty ? "…" : message
    }

    enum CodingKeys: String, CodingKey {
        // The backend sends only these; the rest are frontend-only and default
        // to their stored values (see memberwise init).
        case name, present, path, detail
    }
}

/// Decode shape for GET /api/bootstrap/status.
private struct BootstrapStatusResponse: Decodable {
    let ready: Bool
    let components: [BootstrapComponent]
}

/// Decode shape for a single SSE `progress` event.
private struct ProgressEvent: Decodable {
    let stage: String
    let message: String
    let bytesDone: Int?
    let bytesTotal: Int?
    let done: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case stage, message, done, error
        case bytesDone = "bytes_done"
        case bytesTotal = "bytes_total"
    }
}

extension CosmaManager {

    // MARK: - Public entry points

    /// Refresh the snapshot of which AI components are ready. Cheap (no
    /// downloads), safe to call on every wizard-appear.
    ///
    /// Retries a few times because the wizard can fire this during cold
    /// backend startup (first HTTP attempt → connection refused because
    /// Quart hasn't bound the port yet). Silent-fail + no-retry was the
    /// root cause of "wizard shows empty rows" — we gave up after the
    /// first probe and the page stayed blank for the rest of the session.
    func refreshBootstrapStatus() async {
        guard let url = URL(string: "http://127.0.0.1:60534/api/bootstrap/status") else { return }
        for attempt in 0..<15 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                // 404 means the attached backend predates the /api/bootstrap/*
                // routes (cosma-backend < 0.8.0). Surfacing the raw JSON
                // decode failure — "The data couldn't be read because it
                // isn't in the correct format" — wedges the wizard behind
                // an opaque message. Instead, tell the user exactly what
                // happened so they can quit/relaunch (which triggers the
                // auto-upgrade path) or kill the stray backend process.
                if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    self.bootstrapError = "Backend is outdated (missing /api/bootstrap). Quit Cosma Sense and relaunch to auto-upgrade. If the error persists, run `pkill -f \"cosma serve\"` in Terminal to clear a stale backend process, then relaunch."
                    self.bootstrapReady = false
                    return
                }
                let decoded = try JSONDecoder().decode(BootstrapStatusResponse.self, from: data)
                self.bootstrapComponents = decoded.components
                self.bootstrapReady = decoded.ready
                self.bootstrapError = nil
                return
            } catch {
                // Retry with backoff: cold backend usually binds its port
                // within ~5 s, so 15 attempts × ~600 ms = 9 s is comfortably
                // more than enough without stretching the wizard UX.
                if attempt == 14 {
                    self.bootstrapError = "Could not reach backend: \(error.localizedDescription)"
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    /// Persist the user's AI-provider choice to the backend settings and
    /// then kick off a bootstrap install scoped to that choice.
    ///
    /// Why bundle these two operations: the bootstrap runner reads
    /// `summarizer.provider` at the moment it starts, so the settings
    /// write must finish *before* we POST /install — otherwise the
    /// runner will install the old provider's components.
    func setProviderAndBootstrap(summarizer: String, whisper: String) async {
        guard let url = URL(string: "http://127.0.0.1:60534/api/settings/") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "summarizer.provider": summarizer,
            "parser.whisper.provider": whisper,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
        await runBootstrap()
    }

    /// Kick off (or join) a bootstrap install and stream progress events
    /// into `bootstrapComponents`. Returns when the run completes or errors.
    func runBootstrap() async {
        await refreshBootstrapStatus()
        if bootstrapReady {
            // Nothing missing — skip both the POST and the SSE stream.
            return
        }

        bootstrapRunning = true
        bootstrapError = nil
        defer { bootstrapRunning = false }

        // POST /install — fire and forget. Backend returns immediately with
        // {started, running}; the real work happens over SSE.
        if let installURL = URL(string: "http://127.0.0.1:60534/api/bootstrap/install") {
            var req = URLRequest(url: installURL)
            req.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: req)
        }

        await streamBootstrapEvents()
        await refreshBootstrapStatus()
    }

    // MARK: - SSE consumption

    private func streamBootstrapEvents() async {
        guard let url = URL(string: "http://127.0.0.1:60534/api/bootstrap/events") else { return }
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60 * 60  // allow slow downloads; no hard cap

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            // We only care about `data:` lines — the backend always tags
            // events as `event: progress` but we decode by stage field,
            // which is simpler than a full SSE parser.
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let evt = try? JSONDecoder().decode(ProgressEvent.self, from: data)
                else { continue }

                apply(evt)

                // Terminal events — break out of the loop. The stream
                // won't close on its own because the server keeps the
                // connection open for late subscribers.
                if evt.done == true, evt.stage == "complete" || evt.stage == "error" {
                    if evt.stage == "error" {
                        bootstrapError = evt.error ?? evt.message
                    }
                    return
                }
            }
        } catch {
            bootstrapError = error.localizedDescription
        }
    }

    /// Merge an SSE event into the corresponding component row.
    private func apply(_ evt: ProgressEvent) {
        guard let idx = bootstrapComponents.firstIndex(where: { $0.name == evt.stage }) else {
            // "complete" / "error" have no matching component — ignore silently
            // unless it's an error, which the caller promotes to bootstrapError.
            return
        }
        var comp = bootstrapComponents[idx]
        if let done = evt.bytesDone { comp.bytesDone = done }
        if let total = evt.bytesTotal { comp.bytesTotal = total }
        comp.message = evt.message
        if evt.done == true {
            comp.done = true
            comp.present = true  // downloaded now implies present
            // If the server reported a complete transfer but never emitted a
            // total (cache hit path), normalize fraction to 1.0 by
            // equalizing done/total.
            if comp.bytesTotal == 0 { comp.bytesTotal = 1; comp.bytesDone = 1 }
        }
        bootstrapComponents[idx] = comp
    }
}

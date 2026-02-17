//
//  IndexingSettingsSection.swift
//  fileSearchForntend
//
//  Queue configuration, scheduler rules, and system metrics
//

import SwiftUI

// MARK: - Indexing Settings Section

struct IndexingSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var metricsResponse: MetricsResponse?
    @State private var metricsTimer: Timer?

    // Local scheduler editing state
    @State private var schedulerEnabled: Bool = false
    @State private var schedulerCombineMode: String = "ALL"
    @State private var schedulerCheckInterval: Int = 30
    @State private var schedulerRules: [EditableRule] = []
    @State private var hasLoadedScheduler: Bool = false
    @State private var hasUnsavedChanges: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Indexing")
                .font(.system(size: 20, weight: .semibold))

            // Queue Configuration
            GroupBox("Queue Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                    if let settings = model.backendSettings {
                        StepperRow(
                            label: "Cooldown (seconds)",
                            value: settings.queue.cooldownSeconds,
                            range: 1...300,
                            step: 5,
                            path: "queue.cooldown_seconds"
                        )

                        StepperRow(
                            label: "Max Concurrency",
                            value: settings.queue.maxConcurrency,
                            range: 1...8,
                            step: 1,
                            path: "queue.max_concurrency"
                        )

                        StepperRow(
                            label: "Max Retries",
                            value: settings.queue.maxRetries,
                            range: 0...10,
                            step: 1,
                            path: "queue.max_retries"
                        )

                        Divider()

                        StepperRow(
                            label: "Unload models after idle (seconds)",
                            value: settings.summarizer?.idleUnloadSeconds ?? 60,
                            range: 0...600,
                            step: 10,
                            path: "summarizer.idle_unload_seconds"
                        )

                        Text("Set to 0 to keep models loaded permanently.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading queue settings...")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Scheduler — uses the shared SchedulerEditor component
            GroupBox("Scheduler") {
                SchedulerEditor(
                    enabled: $schedulerEnabled,
                    combineMode: $schedulerCombineMode,
                    checkInterval: $schedulerCheckInterval,
                    rules: $schedulerRules,
                    hasUnsavedChanges: $hasUnsavedChanges,
                    onSave: saveScheduler
                )
                .padding(.vertical, 4)
            }

            // Live Metrics
            GroupBox("System Metrics") {
                if let response = metricsResponse {
                    VStack(alignment: .leading, spacing: 10) {
                        // Row 1: Power & thermal
                        HStack(spacing: 0) {
                            MetricBadge(
                                icon: batteryIcon(for: response.metrics),
                                label: "Battery",
                                value: batteryText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: powerIcon(for: response.metrics),
                                label: "Power",
                                value: powerText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: "thermometer.medium",
                                label: "CPU Temp",
                                value: cpuTempText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: "fan.fill",
                                label: "Fan",
                                value: fanText(from: response.metrics)
                            )
                        }

                        // Row 2: Resources & status
                        HStack(spacing: 0) {
                            MetricBadge(
                                icon: "memorychip",
                                label: "Memory",
                                value: memoryText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: "gauge.medium",
                                label: "Pressure",
                                value: memoryPressureText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: "rectangle.3.group",
                                label: "GPU",
                                value: gpuText(from: response.metrics)
                            )
                            Spacer()
                            MetricBadge(
                                icon: "bolt.slash",
                                label: "Low Power",
                                value: lowPowerText(from: response.metrics)
                            )
                        }

                        // Row 3: Models
                        if !response.models.isEmpty {
                            Divider()
                            Text("Models")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                ForEach(response.models, id: \.name) { model in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(model.loaded ? .green : .gray)
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(model.name)
                                                .font(.system(size: 12, weight: .medium))
                                            Text(modelIdleText(model))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading metrics...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await loadSchedulerState()
            await fetchMetrics()
            startMetricsPolling()
        }
        .onDisappear {
            metricsTimer?.invalidate()
            metricsTimer = nil
        }
    }

    // MARK: - Scheduler helpers

    private func loadSchedulerState() async {
        guard !hasLoadedScheduler else { return }
        await model.refreshSchedulerConfig()
        if let config = model.schedulerConfig {
            schedulerEnabled = config.enabled
            schedulerCombineMode = config.combineMode
            schedulerCheckInterval = config.checkIntervalSeconds
            schedulerRules = config.rules.map { EditableRule(from: $0) }
        }
        hasLoadedScheduler = true
    }

    private func saveScheduler() async {
        let ruleRequests = schedulerRules.map { rule in
            SchedulerRuleRequest(
                rule: rule.ruleType.rawValue,
                operator: rule.op,
                value: rule.codableValue,
                enabled: rule.enabled
            )
        }
        await model.updateSchedulerConfig(
            enabled: schedulerEnabled,
            combineMode: schedulerCombineMode,
            checkIntervalSeconds: schedulerCheckInterval,
            rules: ruleRequests
        )
        hasUnsavedChanges = false
    }

    // MARK: - Metrics helpers

    private func fetchMetrics() async {
        do {
            metricsResponse = try await APIClient.shared.fetchSystemMetrics()
        } catch {
            // Non-critical
        }
    }

    private func startMetricsPolling() {
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                await fetchMetrics()
            }
        }
    }

    private func batteryIcon(for metrics: [String: AnyCodableValue]) -> String {
        guard let level = intValue(metrics["battery_level"]) else { return "battery.0" }
        switch level {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 1...25: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryText(from metrics: [String: AnyCodableValue]) -> String {
        guard let level = intValue(metrics["battery_level"]) else { return "N/A" }
        return "\(level)%"
    }

    private func powerIcon(for metrics: [String: AnyCodableValue]) -> String {
        guard let plugged = boolValue(metrics["power_source_plugged"]) else { return "battery.100" }
        return plugged ? "powerplug.fill" : "battery.100"
    }

    private func powerText(from metrics: [String: AnyCodableValue]) -> String {
        guard let plugged = boolValue(metrics["power_source_plugged"]) else { return "N/A" }
        return plugged ? "Plugged In" : "Battery"
    }

    private func cpuTempText(from metrics: [String: AnyCodableValue]) -> String {
        if let temp = intValue(metrics["cpu_temperature"]) {
            return "\(temp) C"
        }
        if let temp = doubleValue(metrics["cpu_temperature"]) {
            return String(format: "%.0f C", temp)
        }
        return "N/A"
    }

    private func fanText(from metrics: [String: AnyCodableValue]) -> String {
        if let rpm = intValue(metrics["fan_speed"]) {
            return "\(rpm) RPM"
        }
        if let rpm = doubleValue(metrics["fan_speed"]) {
            return String(format: "%.0f RPM", rpm)
        }
        return "N/A"
    }

    private func memoryText(from metrics: [String: AnyCodableValue]) -> String {
        if let pct = doubleValue(metrics["memory_usage"]) {
            return String(format: "%.0f%%", pct)
        }
        if let pct = intValue(metrics["memory_usage"]) {
            return "\(pct)%"
        }
        return "N/A"
    }

    private func gpuText(from metrics: [String: AnyCodableValue]) -> String {
        if let pct = doubleValue(metrics["gpu_usage"]) {
            return String(format: "%.0f%%", pct)
        }
        if let pct = intValue(metrics["gpu_usage"]) {
            return "\(pct)%"
        }
        return "N/A"
    }

    private func memoryPressureText(from metrics: [String: AnyCodableValue]) -> String {
        if let pct = doubleValue(metrics["memory_pressure"]) {
            return String(format: "%.0f%%", pct)
        }
        if let pct = intValue(metrics["memory_pressure"]) {
            return "\(pct)%"
        }
        return "N/A"
    }

    private func modelIdleText(_ model: ModelStatus) -> String {
        if !model.loaded { return "Unloaded" }
        guard let idle = model.idleSeconds else { return "Loaded" }
        if idle < 60 { return "Idle \(Int(idle))s" }
        return "Idle \(Int(idle / 60))m"
    }

    private func lowPowerText(from metrics: [String: AnyCodableValue]) -> String {
        if let val = boolValue(metrics["low_power_mode"]) {
            return val ? "On" : "Off"
        }
        return "N/A"
    }

    private func intValue(_ v: AnyCodableValue?) -> Int? {
        guard let v else { return nil }
        switch v {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    private func doubleValue(_ v: AnyCodableValue?) -> Double? {
        guard let v else { return nil }
        switch v {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    private func stringValue(_ v: AnyCodableValue?) -> String? {
        guard let v else { return nil }
        if case .string(let s) = v { return s }
        return nil
    }

    private func boolValue(_ v: AnyCodableValue?) -> Bool? {
        guard let v else { return nil }
        if case .bool(let b) = v { return b }
        return nil
    }
}

// MARK: - Stepper Row (for queue settings)

private struct StepperRow: View {
    @Environment(AppModel.self) private var model
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let path: String

    @State private var localValue: Int = 0

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Stepper(
                value: $localValue,
                in: range,
                step: step
            ) {
                Text("\(localValue)")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
            .onChange(of: localValue) { oldVal, newVal in
                guard oldVal != newVal else { return }
                Task {
                    await model.updateBackendSetting(path: path, value: .int(newVal))
                }
            }
        }
        .onAppear {
            localValue = value
        }
        .onChange(of: value) { _, newVal in
            localValue = newVal
        }
    }
}

// MARK: - Metric Badge

private struct MetricBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
    }
}

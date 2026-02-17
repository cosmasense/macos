//
//  SchedulerSettingsView.swift
//  fileSearchForntend
//
//  Scheduler rules editor: enable/disable, combine mode, rules list
//

import SwiftUI

// MARK: - Rule Type Metadata

/// Mirrors backend SCHEDULER_RULE_TYPES for type-specific UI rendering
enum SchedulerRuleType: String, CaseIterable, Identifiable {
    case batteryLevel = "battery_level"
    case powerSource = "power_source"
    case cpuIdle = "cpu_idle"
    case lowPowerMode = "low_power_mode"
    case memoryPressure = "memory_pressure"
    case timeWindow = "time_window"
    case cpuTemperature = "cpu_temperature"
    case fanSpeed = "fan_speed"
    case gpuUsage = "gpu_usage"
    case memoryUsage = "memory_usage"
    case queueSize = "queue_size"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .batteryLevel: return "Battery Level"
        case .powerSource: return "Power Source"
        case .cpuIdle: return "CPU Idle"
        case .lowPowerMode: return "Low Power Mode"
        case .memoryPressure: return "Memory Pressure"
        case .timeWindow: return "Time Window"
        case .cpuTemperature: return "CPU Temperature"
        case .fanSpeed: return "Fan Speed"
        case .gpuUsage: return "GPU Usage"
        case .memoryUsage: return "Memory Usage"
        case .queueSize: return "Queue Size"
        }
    }

    var valueType: ValueType {
        switch self {
        case .powerSource, .cpuIdle, .lowPowerMode: return .boolean
        case .batteryLevel, .gpuUsage, .memoryUsage, .memoryPressure: return .percentage
        case .cpuTemperature, .fanSpeed, .queueSize: return .number
        case .timeWindow: return .timeRange
        }
    }

    var defaultOperator: String {
        switch self {
        case .powerSource, .cpuIdle, .lowPowerMode: return "eq"
        case .batteryLevel: return "gte"
        case .gpuUsage, .memoryUsage, .memoryPressure, .cpuTemperature, .fanSpeed: return "lte"
        case .queueSize: return "gte"
        case .timeWindow: return "within"
        }
    }

    var unit: String? {
        switch self {
        case .batteryLevel, .gpuUsage, .memoryUsage, .memoryPressure: return "%"
        case .cpuTemperature: return "\u{00B0}C"
        case .fanSpeed: return "RPM"
        default: return nil
        }
    }

    var minValue: Int {
        switch self {
        case .batteryLevel, .gpuUsage, .memoryUsage, .queueSize: return 0
        case .cpuTemperature: return 0
        case .fanSpeed: return 0
        default: return 0
        }
    }

    var maxValue: Int {
        switch self {
        case .batteryLevel, .gpuUsage, .memoryUsage: return 100
        case .cpuTemperature: return 120
        case .fanSpeed: return 10000
        case .queueSize: return 1000
        default: return 100
        }
    }

    var booleanLabels: (trueLabel: String, falseLabel: String) {
        switch self {
        case .powerSource: return ("Plugged In", "On Battery")
        case .cpuIdle: return ("Idle", "Busy")
        case .lowPowerMode: return ("Active", "Inactive")
        default: return ("Yes", "No")
        }
    }

    /// Human-readable description of what this rule means
    func descriptionText(op: String, numberValue: Int, boolValue: Bool) -> String {
        switch self.valueType {
        case .boolean:
            let label = boolValue ? booleanLabels.trueLabel : booleanLabels.falseLabel
            return "Queue runs when \(self.label.lowercased()) is \(label.lowercased())"
        case .percentage, .number:
            let opSymbol: String
            switch op {
            case "gte": opSymbol = "\u{2265}"
            case "gt": opSymbol = ">"
            case "eq": opSymbol = "="
            case "lt": opSymbol = "<"
            case "lte": opSymbol = "\u{2264}"
            default: opSymbol = op
            }
            let unitStr = unit ?? ""
            return "Queue runs when \(self.label.lowercased()) \(opSymbol) \(numberValue)\(unitStr)"
        case .timeRange:
            return "Queue runs during the specified time window"
        }
    }

    enum ValueType {
        case boolean
        case percentage
        case number
        case timeRange
    }
}

// MARK: - Shared Scheduler Editor

/// Reusable scheduler editor used by both the dedicated page and the Settings section.
struct SchedulerEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var enabled: Bool
    @Binding var combineMode: String
    @Binding var checkInterval: Int
    @Binding var rules: [EditableRule]
    @Binding var hasUnsavedChanges: Bool
    let onSave: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Scheduler", isOn: $enabled)
                .font(.system(size: 14, weight: .medium))
                .onChange(of: enabled) { _, _ in hasUnsavedChanges = true }

            HStack {
                Text("Combine Mode")
                    .font(.system(size: 13, weight: .medium))
                Picker("", selection: $combineMode) {
                    Text("ALL").tag("ALL")
                    Text("ANY").tag("ANY")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: combineMode) { _, _ in hasUnsavedChanges = true }

                Text(combineMode == "ALL" ? "Every rule must pass" : "At least one rule must pass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Check Interval (seconds)")
                    .font(.system(size: 13, weight: .medium))
                Stepper(
                    value: $checkInterval,
                    in: 10...600,
                    step: 5
                ) {
                    Text("\(checkInterval)")
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                }
                .onChange(of: checkInterval) { _, _ in hasUnsavedChanges = true }
            }

            Divider()

            // Warnings from backend
            if let config = model.schedulerConfig, !config.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(config.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 12))
                            Text(warning)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Rules
            HStack {
                Text("Rules")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    rules.append(EditableRule())
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text("Passing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                    Text("Failing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 11))
                    Text("Unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Text("Not evaluated")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            let ruleResults = model.schedulerConfig?.ruleResults ?? []
            let usedTypes = Set(rules.map(\.ruleType))

            ForEach(rules.indices, id: \.self) { index in
                SchedulerRuleRow(
                    rule: $rules[index],
                    ruleResult: ruleResults.first(where: { $0.rule == rules[index].ruleType.rawValue }),
                    usedTypes: usedTypes,
                    onRemove: {
                        rules.remove(at: index)
                        hasUnsavedChanges = true
                    }
                )
                .onChange(of: rules[index].ruleType) { _, _ in hasUnsavedChanges = true }
                .onChange(of: rules[index].op) { _, _ in hasUnsavedChanges = true }
                .onChange(of: rules[index].enabled) { _, _ in hasUnsavedChanges = true }
                .onChange(of: rules[index].numberValue) { _, _ in hasUnsavedChanges = true }
                .onChange(of: rules[index].boolValue) { _, _ in hasUnsavedChanges = true }
            }

            if rules.isEmpty {
                Text("No rules configured. Add a rule to control when the queue processes items.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            // Save + Test buttons
            HStack {
                if hasUnsavedChanges {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Unsaved changes")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Test Rules Now") {
                    Task {
                        do {
                            let result = try await APIClient.shared.testSchedulerRules()
                            // Refresh config to pick up updated rule_results
                            await model.refreshSchedulerConfig()
                        } catch {
                            // Non-critical
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Evaluate rules against live metrics without saving")

                Button("Save Scheduler") {
                    Task { await onSave() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }
}

// MARK: - Main View (Dedicated Page)

struct SchedulerSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Bool = false
    @State private var combineMode: String = "ALL"
    @State private var checkInterval: Int = 30
    @State private var rules: [EditableRule] = []
    @State private var hasLoaded: Bool = false
    @State private var hasUnsavedChanges: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheduler Settings")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                SchedulerEditor(
                    enabled: $enabled,
                    combineMode: $combineMode,
                    checkInterval: $checkInterval,
                    rules: $rules,
                    hasUnsavedChanges: $hasUnsavedChanges,
                    onSave: save
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task {
            guard !hasLoaded else { return }
            await model.refreshSchedulerConfig()
            if let config = model.schedulerConfig {
                enabled = config.enabled
                combineMode = config.combineMode
                checkInterval = config.checkIntervalSeconds
                rules = config.rules.map { EditableRule(from: $0) }
            }
            hasLoaded = true
        }
    }

    private func save() async {
        let ruleRequests = rules.map { rule in
            SchedulerRuleRequest(
                rule: rule.ruleType.rawValue,
                operator: rule.op,
                value: rule.codableValue,
                enabled: rule.enabled
            )
        }
        await model.updateSchedulerConfig(
            enabled: enabled,
            combineMode: combineMode,
            checkIntervalSeconds: checkInterval,
            rules: ruleRequests
        )
        hasUnsavedChanges = false
    }
}

// MARK: - Editable Rule Model

struct EditableRule: Identifiable, Equatable {
    let id = UUID()
    var ruleType: SchedulerRuleType = .batteryLevel
    var op: String = "gte"
    var enabled: Bool = true

    // Value storage for different types
    var numberValue: Int = 80
    var boolValue: Bool = true
    var startTime: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    var endTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()

    static func == (lhs: EditableRule, rhs: EditableRule) -> Bool {
        lhs.id == rhs.id &&
        lhs.ruleType == rhs.ruleType &&
        lhs.op == rhs.op &&
        lhs.enabled == rhs.enabled &&
        lhs.numberValue == rhs.numberValue &&
        lhs.boolValue == rhs.boolValue
    }

    init() {
        self.op = ruleType.defaultOperator
    }

    init(from response: SchedulerRuleResponse) {
        self.ruleType = SchedulerRuleType(rawValue: response.rule) ?? .batteryLevel
        self.op = response.operator.isEmpty ? ruleType.defaultOperator : response.operator
        self.enabled = response.enabled

        if let v = response.value {
            switch ruleType.valueType {
            case .boolean:
                if case .bool(let b) = v {
                    self.boolValue = b
                } else if case .string(let s) = v {
                    self.boolValue = s.lowercased() == "true" || s == "ac"
                }
            case .percentage, .number:
                if case .int(let i) = v {
                    self.numberValue = i
                } else if case .double(let d) = v {
                    self.numberValue = Int(d)
                } else if case .string(let s) = v, let i = Int(s) {
                    self.numberValue = i
                }
            case .timeRange:
                if case .stringArray(let arr) = v, arr.count == 2 {
                    parseTimeRange(arr[0], arr[1])
                } else if case .string(let s) = v {
                    // Legacy format "22:00-06:00"
                    let parts = s.split(separator: "-")
                    if parts.count == 2 {
                        parseTimeRange(String(parts[0]), String(parts[1]))
                    }
                }
            }
        }
    }

    private mutating func parseTimeRange(_ startStr: String, _ endStr: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        if let start = formatter.date(from: startStr) {
            startTime = start
        }
        if let end = formatter.date(from: endStr) {
            endTime = end
        }
    }

    var codableValue: AnyCodableValue? {
        switch ruleType.valueType {
        case .boolean:
            return .bool(boolValue)
        case .percentage, .number:
            return .int(numberValue)
        case .timeRange:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return .stringArray([formatter.string(from: startTime), formatter.string(from: endTime)])
        }
    }
}

// MARK: - Rule Row

struct SchedulerRuleRow: View {
    @Binding var rule: EditableRule
    var ruleResult: SchedulerRuleResult?
    var usedTypes: Set<SchedulerRuleType> = []
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Pass/fail indicator
                if let result = ruleResult {
                    if !result.metricAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))
                            .help("Metric unavailable - rule passes by default (no protection)")
                    } else {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                            .font(.system(size: 14))
                            .help(result.passed ? "Rule is currently passing" : "Rule is currently failing")
                    }
                } else {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                        .help("Not yet evaluated")
                }

                // Enable toggle
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden()
                    .frame(width: 30)

                // Rule type picker — show all types but mark duplicates
                Picker("Type", selection: $rule.ruleType) {
                    ForEach(SchedulerRuleType.allCases) { type in
                        if type == rule.ruleType || !usedTypes.contains(type) {
                            Text(type.label).tag(type)
                        } else {
                            Text("\(type.label) (in use)").tag(type)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .onChange(of: rule.ruleType) { _, newType in
                    rule.op = newType.defaultOperator
                }

                // Type-specific value input
                valueInputView

                Spacer()

                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove rule")
            }

            // Plain-English description
            Text(rule.ruleType.descriptionText(
                op: rule.op,
                numberValue: rule.numberValue,
                boolValue: rule.boolValue
            ))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.leading, 46)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var valueInputView: some View {
        switch rule.ruleType.valueType {
        case .boolean:
            booleanInput
        case .percentage:
            percentageInput
        case .number:
            numberInput
        case .timeRange:
            timeRangeInput
        }
    }

    // MARK: - Boolean Input (Toggle or Segmented)

    private var booleanInput: some View {
        let labels = rule.ruleType.booleanLabels
        return Picker("", selection: $rule.boolValue) {
            Text(labels.trueLabel).tag(true)
            Text(labels.falseLabel).tag(false)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    // MARK: - Percentage Input (Slider + Number)

    private var percentageInput: some View {
        HStack(spacing: 8) {
            operatorPicker

            Slider(
                value: Binding(
                    get: { Double(rule.numberValue) },
                    set: { rule.numberValue = Int($0) }
                ),
                in: Double(rule.ruleType.minValue)...Double(rule.ruleType.maxValue),
                step: 5
            )
            .frame(width: 120)

            Text("\(rule.numberValue)%")
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 45, alignment: .trailing)
        }
    }

    // MARK: - Number Input (Stepper)

    private var numberInput: some View {
        HStack(spacing: 8) {
            operatorPicker

            TextField("", value: $rule.numberValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

            if let unit = rule.ruleType.unit {
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Time Range Input

    private var timeRangeInput: some View {
        HStack(spacing: 8) {
            Text("From")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            DatePicker("", selection: $rule.startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(width: 80)

            Text("to")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            DatePicker("", selection: $rule.endTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(width: 80)
        }
    }

    // MARK: - Operator Picker (for numeric types)

    private var operatorPicker: some View {
        Picker("", selection: $rule.op) {
            Text("\u{2265}").tag("gte")  // ≥
            Text(">").tag("gt")
            Text("=").tag("eq")
            Text("<").tag("lt")
            Text("\u{2264}").tag("lte")  // ≤
        }
        .labelsHidden()
        .frame(width: 55)
    }
}

#Preview {
    SchedulerSettingsView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}

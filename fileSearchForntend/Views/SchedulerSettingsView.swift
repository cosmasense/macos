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
        case .powerSource, .cpuIdle: return .boolean
        case .batteryLevel, .gpuUsage, .memoryUsage: return .percentage
        case .cpuTemperature, .fanSpeed, .queueSize: return .number
        case .timeWindow: return .timeRange
        }
    }

    var defaultOperator: String {
        switch self {
        case .powerSource, .cpuIdle: return "eq"
        case .batteryLevel: return "gte"
        case .gpuUsage, .memoryUsage, .cpuTemperature, .fanSpeed: return "lte"
        case .queueSize: return "gte"
        case .timeWindow: return "within"
        }
    }

    var unit: String? {
        switch self {
        case .batteryLevel, .gpuUsage, .memoryUsage: return "%"
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
        default: return ("Yes", "No")
        }
    }

    enum ValueType {
        case boolean
        case percentage
        case number
        case timeRange
    }
}

// MARK: - Main View

struct SchedulerSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Bool = false
    @State private var combineMode: String = "ALL"
    @State private var rules: [EditableRule] = []
    @State private var hasLoaded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheduler Settings")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()

                Button("Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Enable toggle
                    Toggle("Enable Scheduler", isOn: $enabled)
                        .font(.system(size: 14, weight: .medium))

                    // Combine mode picker
                    HStack {
                        Text("Combine Mode")
                            .font(.system(size: 14, weight: .medium))
                        Picker("", selection: $combineMode) {
                            Text("ALL").tag("ALL")
                            Text("ANY").tag("ANY")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    Divider()

                    // Rules
                    HStack {
                        Text("Rules")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button {
                            rules.append(EditableRule())
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ForEach(rules.indices, id: \.self) { index in
                        SchedulerRuleRow(rule: $rules[index]) {
                            rules.remove(at: index)
                        }
                    }

                    if rules.isEmpty {
                        Text("No rules configured. Add a rule to control when the queue processes items.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
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
            rules: ruleRequests
        )
    }
}

// MARK: - Editable Rule Model

struct EditableRule: Identifiable {
    let id = UUID()
    var ruleType: SchedulerRuleType = .batteryLevel
    var op: String = "gte"
    var enabled: Bool = true

    // Value storage for different types
    var numberValue: Int = 80
    var boolValue: Bool = true
    var startTime: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    var endTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()

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
                // Parse time range string like "22:00-06:00"
                if case .string(let s) = v {
                    parseTimeRange(s)
                }
            }
        }
    }

    private mutating func parseTimeRange(_ value: String) {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        if let start = formatter.date(from: String(parts[0])) {
            startTime = start
        }
        if let end = formatter.date(from: String(parts[1])) {
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
            let rangeString = "\(formatter.string(from: startTime))-\(formatter.string(from: endTime))"
            return .string(rangeString)
        }
    }
}

// MARK: - Rule Row

struct SchedulerRuleRow: View {
    @Binding var rule: EditableRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .frame(width: 30)

            // Rule type picker
            Picker("Type", selection: $rule.ruleType) {
                ForEach(SchedulerRuleType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .onChange(of: rule.ruleType) { _, newType in
                // Update operator to default for new type
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

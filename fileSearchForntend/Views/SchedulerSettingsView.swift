//
//  SchedulerSettingsView.swift
//  fileSearchForntend
//
//  Scheduler rules editor: enable/disable, combine mode, rules list
//

import SwiftUI

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
                rule: rule.ruleType,
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
    var ruleType: String = "battery_level"
    var op: String = "gt"
    var value: String = ""
    var enabled: Bool = true

    init() {}

    init(from response: SchedulerRuleResponse) {
        self.ruleType = response.rule
        self.op = response.operator
        self.enabled = response.enabled
        if let v = response.value {
            switch v {
            case .int(let i): self.value = "\(i)"
            case .double(let d): self.value = "\(d)"
            case .bool(let b): self.value = b ? "true" : "false"
            case .string(let s): self.value = s
            case .stringArray(let arr): self.value = arr.joined(separator: ",")
            }
        }
    }

    var codableValue: AnyCodableValue? {
        if let intVal = Int(value) {
            return .int(intVal)
        }
        if let doubleVal = Double(value) {
            return .double(doubleVal)
        }
        if value.lowercased() == "true" { return .bool(true) }
        if value.lowercased() == "false" { return .bool(false) }
        if !value.isEmpty { return .string(value) }
        return nil
    }
}

// MARK: - Rule Row

struct SchedulerRuleRow: View {
    @Binding var rule: EditableRule
    let onRemove: () -> Void

    private let ruleTypes = [
        "battery_level", "power_source", "cpu_idle",
        "time_window", "cpu_temperature", "fan_speed"
    ]

    private let operators = ["gt", "lt", "eq", "gte", "lte", "within"]

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .frame(width: 40)

            Picker("Type", selection: $rule.ruleType) {
                ForEach(ruleTypes, id: \.self) { type in
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(type)
                }
            }
            .frame(width: 160)

            Picker("Op", selection: $rule.op) {
                ForEach(operators, id: \.self) { op in
                    Text(op).tag(op)
                }
            }
            .frame(width: 80)

            TextField("Value", text: $rule.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    SchedulerSettingsView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}

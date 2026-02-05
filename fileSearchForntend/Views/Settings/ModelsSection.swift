//
//  ModelsSection.swift
//  fileSearchForntend
//
//  Embedding model selection
//

import SwiftUI

// MARK: - Models Section

struct ModelsSection: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedEmbeddingModel: String

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            Text("Models")
                .font(.system(size: 20, weight: .semibold))

            // Embedding Model
            VStack(alignment: .leading, spacing: 8) {
                Text("Embedding Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedEmbeddingModel) {
                    ForEach(["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"], id: \.self) { model in
                        Text(model)
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }
}

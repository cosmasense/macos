//
//  AppModel+Settings.swift
//  fileSearchForntend
//
//  Backend settings and filter configuration management
//

import Foundation

// MARK: - Backend Settings

extension AppModel {

    /// Fetches backend settings (queue/scheduler config used by IndexingSettingsSection)
    func refreshBackendSettings() async {
        do {
            backendSettings = try await apiClient.fetchBackendSettings()
        } catch {
            #if DEBUG
            print("Failed to fetch backend settings: \(error)")
            #endif
        }
    }

    /// Updates a single backend setting (queue/scheduler) via AnyCodableValue
    func updateBackendSetting(path: String, value: AnyCodableValue) async {
        do {
            backendSettings = try await apiClient.updateBackendSetting(path: path, value: value)
        } catch {
            #if DEBUG
            print("Failed to update backend setting: \(error)")
            #endif
        }
    }

    /// Fetches full processing configuration from backend
    func refreshSettings() async {
        isLoadingSettings = true
        settingsError = nil
        defer { isLoadingSettings = false }

        do {
            processingSettings = try await apiClient.fetchSettings()
        } catch let error as APIError {
            settingsError = error.localizedDescription
        } catch {
            settingsError = error.localizedDescription
        }
    }

    /// Updates a single processing setting via dotted path (e.g., "embedder.provider")
    func updateSetting(path: String, value: Any) {
        savingSettingPaths.insert(path)
        savedSettingPaths.remove(path)

        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await apiClient.updateSetting(path: path, value: value)
                processingSettings = updated
                savingSettingPaths.remove(path)
                savedSettingPaths.insert(path)
                // Clear the checkmark after a delay
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    self.savedSettingPaths.remove(path)
                }
            } catch {
                savingSettingPaths.remove(path)
                settingsError = error.localizedDescription
            }
        }
    }

    /// Resets all processing settings to backend defaults
    func resetSettingsToDefaults() {
        Task { [weak self] in
            guard let self else { return }
            isLoadingSettings = true
            settingsError = nil
            defer { isLoadingSettings = false }

            do {
                let defaults = try await apiClient.fetchSettingsDefaults()
                let data = try JSONEncoder().encode(defaults)
                guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                for (section, sectionValue) in dict {
                    guard let sectionDict = sectionValue as? [String: Any] else { continue }
                    for (key, value) in sectionDict {
                        if let nested = value as? [String: Any] {
                            for (nestedKey, nestedValue) in nested {
                                _ = try await apiClient.updateSetting(path: "\(section).\(key).\(nestedKey)", value: nestedValue)
                            }
                        } else {
                            _ = try await apiClient.updateSetting(path: "\(section).\(key)", value: value)
                        }
                    }
                }

                processingSettings = try await apiClient.fetchSettings()
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    /// Tests the backend connection and returns status
    func testBackendConnection() async -> (success: Bool, message: String) {
        do {
            let status = try await apiClient.fetchStatus()
            let jobsCount = status.jobs ?? 0
            return (true, "Connected (\(jobsCount) jobs running)")
        } catch let error as APIError {
            return (false, error.localizedDescription)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Filter Configuration

extension AppModel {

    /// Fetches filter configuration from backend
    func refreshFilterConfig() async {
        isLoadingFilterConfig = true
        filterConfigError = nil
        defer { isLoadingFilterConfig = false }

        do {
            let config = try await apiClient.fetchFilterConfig()

            // Update local state
            filterMode = config.mode
            blacklistExclude = config.blacklistExclude
            blacklistInclude = config.blacklistInclude
            whitelistInclude = config.whitelistInclude
            whitelistExclude = config.whitelistExclude
            fileFilterEnabled = true

            // Save as "clean" state for dirty tracking
            savedFilterMode = config.mode
            savedBlacklistExclude = config.blacklistExclude
            savedBlacklistInclude = config.blacklistInclude
            savedWhitelistInclude = config.whitelistInclude
            savedWhitelistExclude = config.whitelistExclude
        } catch let error as APIError {
            filterConfigError = error.localizedDescription
            #if DEBUG
            print("Failed to fetch filter config: \(error)")
            #endif
        } catch {
            filterConfigError = error.localizedDescription
            #if DEBUG
            print("Failed to fetch filter config: \(error)")
            #endif
        }
    }

    /// Adds a new filter pattern locally (call saveFilterConfig() to persist)
    ///
    /// - Parameters:
    ///   - pattern: The pattern string (prefix with ! for negation)
    ///   - description: Optional description
    func addFilterPattern(_ pattern: String, description: String? = nil) {
        let isNegation = pattern.hasPrefix("!")
        let effectivePattern = isNegation ? String(pattern.dropFirst()) : pattern

        if filterMode == "blacklist" {
            if isNegation {
                if !blacklistInclude.contains(effectivePattern) {
                    blacklistInclude.append(effectivePattern)
                }
            } else {
                if !blacklistExclude.contains(effectivePattern) {
                    blacklistExclude.append(effectivePattern)
                }
            }
        } else {
            if isNegation {
                if !whitelistExclude.contains(effectivePattern) {
                    whitelistExclude.append(effectivePattern)
                }
            } else {
                if !whitelistInclude.contains(effectivePattern) {
                    whitelistInclude.append(effectivePattern)
                }
            }
        }
    }

    /// Removes a filter pattern locally (call saveFilterConfig() to persist)
    func removeFilterPattern(_ pattern: FileFilterPattern) {
        let effectivePattern = pattern.effectivePattern

        if filterMode == "blacklist" {
            if pattern.isNegation {
                blacklistInclude.removeAll { $0 == effectivePattern }
            } else {
                blacklistExclude.removeAll { $0 == effectivePattern }
            }
        } else {
            if pattern.isNegation {
                whitelistExclude.removeAll { $0 == effectivePattern }
            } else {
                whitelistInclude.removeAll { $0 == effectivePattern }
            }
        }
    }

    /// Saves filter configuration changes to backend
    func saveFilterConfig() async {
        isLoadingFilterConfig = true
        filterConfigError = nil
        defer { isLoadingFilterConfig = false }

        do {
            let response = try await apiClient.updateFilterConfig(
                mode: filterMode,
                blacklistExclude: blacklistExclude,
                blacklistInclude: blacklistInclude,
                whitelistInclude: whitelistInclude,
                whitelistExclude: whitelistExclude,
                applyImmediately: true
            )

            if response.success {
                // Update saved state
                savedFilterMode = response.config.mode
                savedBlacklistExclude = response.config.blacklistExclude
                savedBlacklistInclude = response.config.blacklistInclude
                savedWhitelistInclude = response.config.whitelistInclude
                savedWhitelistExclude = response.config.whitelistExclude

                // Sync local state
                filterMode = response.config.mode
                blacklistExclude = response.config.blacklistExclude
                blacklistInclude = response.config.blacklistInclude
                whitelistInclude = response.config.whitelistInclude
                whitelistExclude = response.config.whitelistExclude
            } else {
                filterConfigError = response.message
            }
        } catch let error as APIError {
            filterConfigError = error.localizedDescription
        } catch {
            filterConfigError = error.localizedDescription
        }
    }

    /// Discards unsaved filter configuration changes
    func discardFilterChanges() {
        filterMode = savedFilterMode
        blacklistExclude = savedBlacklistExclude
        blacklistInclude = savedBlacklistInclude
        whitelistInclude = savedWhitelistInclude
        whitelistExclude = savedWhitelistExclude
        filterConfigError = nil
    }

    /// Resets filter patterns to defaults
    func resetFilterPatternsToDefaults() {
        Task {
            do {
                let response = try await apiClient.resetFilterConfig()
                if response.success {
                    // Update both local and saved state
                    filterMode = response.config.mode
                    blacklistExclude = response.config.blacklistExclude
                    blacklistInclude = response.config.blacklistInclude
                    whitelistInclude = response.config.whitelistInclude
                    whitelistExclude = response.config.whitelistExclude

                    savedFilterMode = response.config.mode
                    savedBlacklistExclude = response.config.blacklistExclude
                    savedBlacklistInclude = response.config.blacklistInclude
                    savedWhitelistInclude = response.config.whitelistInclude
                    savedWhitelistExclude = response.config.whitelistExclude
                } else {
                    filterConfigError = response.message
                }
            } catch let error as APIError {
                filterConfigError = error.localizedDescription
            } catch {
                filterConfigError = error.localizedDescription
            }
        }
    }

    /// Updates filter mode locally (call saveFilterConfig() to persist)
    func updateFilterMode(_ mode: String) {
        filterMode = mode
    }

    /// Checks if a file should be filtered based on current settings
    ///
    /// Note: This is kept for backward compatibility. Filtering is now done server-side.
    func shouldFilterFile(filePath: String, filename: String) -> Bool {
        guard fileFilterEnabled else { return false }
        return FileFilterService.shouldFilter(
            filePath: filePath,
            filename: filename,
            patterns: fileFilterPatterns
        )
    }
}

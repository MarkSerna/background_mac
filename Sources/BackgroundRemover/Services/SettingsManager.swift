//
//  SettingsManager.swift
//  BackgroundRemover
//
//  Gestor de persistencia de preferencias de usuario y estadísticas en UserDefaults.
//

import Foundation
import SwiftUI

public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    private let configKey = "com.dfiesta.backgroundremover.config"
    private let statsKey = "com.dfiesta.backgroundremover.stats"
    
    @Published public var config: ProcessingConfig {
        didSet {
            saveConfig()
        }
    }
    
    @Published public var stats: ProcessingStats {
        didSet {
            saveStats()
        }
    }
    
    public init() {
        // Cargar configuración guardada o usar valores predeterminados
        if let data = defaults.data(forKey: configKey),
           let saved = try? JSONDecoder().decode(ProcessingConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = ProcessingConfig()
        }
        
        // Cargar estadísticas
        if let data = defaults.data(forKey: statsKey),
           let saved = try? JSONDecoder().decode(ProcessingStats.self, from: data) {
            self.stats = saved
        } else {
            self.stats = ProcessingStats()
        }
    }
    
    private func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: configKey)
        }
    }
    
    private func saveStats() {
        if let encoded = try? JSONEncoder().encode(stats) {
            defaults.set(encoded, forKey: statsKey)
        }
    }
    
    public func recordProcessing(success: Bool, duration: Double = 0.0) {
        DispatchQueue.main.async {
            if success {
                self.stats.recordSuccess(duration: duration)
            } else {
                self.stats.recordFailure()
            }
        }
    }
    
    public func resetStats() {
        DispatchQueue.main.async {
            self.stats.reset()
        }
    }
    
    public func resetToDefaults() {
        DispatchQueue.main.async {
            self.config = ProcessingConfig()
        }
    }
}

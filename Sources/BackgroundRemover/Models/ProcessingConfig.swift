//
//  ProcessingConfig.swift
//  BackgroundRemover
//
//  Estructuras de configuración tipada para la remoción y composición de fondos con IA Híbrida.
//

import SwiftUI

public enum AIEngineMode: String, CaseIterable, Identifiable, Codable {
    case auto = "Automático (Híbrido)"
    case appleVision = "Apple Vision (ANE)"
    case coreML = "CoreML Deep Neural"
    
    public var id: String { self.rawValue }
    
    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .appleVision: return "bolt.fill"
        case .coreML: return "brain.head.profile"
        }
    }
}

public enum BackgroundMode: String, CaseIterable, Identifiable, Codable {
    case white = "Blanco"
    case customColor = "Color"
    case transparent = "Transparente"
    
    public var id: String { self.rawValue }
}

public enum OutputImageFormat: String, CaseIterable, Identifiable, Codable {
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"
    
    public var id: String { self.rawValue }
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        }
    }
    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .heic: return "image/heic"
        }
    }
}

public struct ProcessingConfig: Codable, Equatable {
    public var aiEngine: AIEngineMode
    public var backgroundMode: BackgroundMode
    public var customColorHex: String
    public var outputFormat: OutputImageFormat
    public var outputQuality: Double // 0.1 to 1.0 (ej. 0.95 = 95%)
    public var autoCrop: Bool
    public var paddingPercent: Double // 0% a 50%
    public var batchLimit: Int
    public var maxConcurrentWorkers: Int
    
    public init(
        aiEngine: AIEngineMode = .auto,
        backgroundMode: BackgroundMode = .white,
        customColorHex: String = "#FFFFFF",
        outputFormat: OutputImageFormat = .jpeg,
        outputQuality: Double = 0.95,
        autoCrop: Bool = false,
        paddingPercent: Double = 5.0,
        batchLimit: Int = 20,
        maxConcurrentWorkers: Int = 4
    ) {
        self.aiEngine = aiEngine
        self.backgroundMode = backgroundMode
        self.customColorHex = customColorHex
        self.outputFormat = outputFormat
        self.outputQuality = outputQuality
        self.autoCrop = autoCrop
        self.paddingPercent = paddingPercent
        self.batchLimit = batchLimit
        self.maxConcurrentWorkers = maxConcurrentWorkers
    }
    
    public var activeColor: Color {
        switch backgroundMode {
        case .white:
            return .white
        case .customColor:
            return Color(hexString: customColorHex)
        case .transparent:
            return .clear
        }
    }
}

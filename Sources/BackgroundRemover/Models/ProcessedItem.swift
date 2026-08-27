//
//  ProcessedItem.swift
//  BackgroundRemover
//
//  Modelo de estado y metadatos para cada imagen cargada o procesada.
//

import Foundation
import CoreGraphics
import SwiftUI

public enum ProcessingStatus: String, Codable {
    case pending = "Pendiente"
    case processing = "Procesando..."
    case completed = "Completado"
    case failed = "Error"
    
    public var iconName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    public var badgeColor: Color {
        switch self {
        case .pending: return .secondary
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

public struct ProcessedItem: Identifiable, Equatable {
    public let id: UUID
    public var filename: String
    public var originalImage: PlatformImage
    public var processedImage: PlatformImage?
    public var maskImage: CGImage?
    public var status: ProcessingStatus
    public var errorMessage: String?
    public var errorCode: String?
    public var processingTimeSeconds: Double?
    public var originalDimensions: CGSize
    public var processedDimensions: CGSize?
    public var sourceURL: URL?
    public var creationDate: Date
    
    public init(
        id: UUID = UUID(),
        filename: String,
        originalImage: PlatformImage,
        processedImage: PlatformImage? = nil,
        maskImage: CGImage? = nil,
        status: ProcessingStatus = .pending,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        processingTimeSeconds: Double? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.filename = filename
        self.originalImage = originalImage
        self.processedImage = processedImage
        self.maskImage = maskImage
        self.status = status
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.processingTimeSeconds = processingTimeSeconds
        self.sourceURL = sourceURL
        self.creationDate = Date()
        
        #if os(iOS)
        self.originalDimensions = CGSize(width: originalImage.size.width * originalImage.scale, height: originalImage.size.height * originalImage.scale)
        if let proc = processedImage {
            self.processedDimensions = CGSize(width: proc.size.width * proc.scale, height: proc.size.height * proc.scale)
        } else {
            self.processedDimensions = nil
        }
        #elseif os(macOS)
        self.originalDimensions = originalImage.size
        self.processedDimensions = processedImage?.size
        #endif
    }
    
    public static func == (lhs: ProcessedItem, rhs: ProcessedItem) -> Bool {
        return lhs.id == rhs.id && lhs.status == rhs.status && lhs.processingTimeSeconds == rhs.processingTimeSeconds
    }
}

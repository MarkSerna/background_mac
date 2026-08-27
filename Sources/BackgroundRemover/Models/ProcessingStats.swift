//
//  ProcessingStats.swift
//  BackgroundRemover
//
//  Modelo de estadísticas y métricas acumuladas de procesamiento.
//

import Foundation

public struct ProcessingStats: Codable, Equatable {
    public var totalProcessedCount: Int
    public var successCount: Int
    public var failureCount: Int
    public var totalProcessingTimeSeconds: Double
    public var lastProcessedDate: Date?
    
    public init(
        totalProcessedCount: Int = 0,
        successCount: Int = 0,
        failureCount: Int = 0,
        totalProcessingTimeSeconds: Double = 0.0,
        lastProcessedDate: Date? = nil
    ) {
        self.totalProcessedCount = totalProcessedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.totalProcessingTimeSeconds = totalProcessingTimeSeconds
        self.lastProcessedDate = lastProcessedDate
    }
    
    public var successRatePercent: Double {
        guard totalProcessedCount > 0 else { return 100.0 }
        return (Double(successCount) / Double(totalProcessedCount)) * 100.0
    }
    
    public var averageTimePerImage: Double {
        guard successCount > 0 else { return 0.0 }
        return totalProcessingTimeSeconds / Double(successCount)
    }
    
    public mutating func recordSuccess(duration: Double) {
        totalProcessedCount += 1
        successCount += 1
        totalProcessingTimeSeconds += duration
        lastProcessedDate = Date()
    }
    
    public mutating func recordFailure() {
        totalProcessedCount += 1
        failureCount += 1
        lastProcessedDate = Date()
    }
    
    public mutating func reset() {
        self = ProcessingStats()
    }
}

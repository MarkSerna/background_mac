//
//  BatchProcessorService.swift
//  BackgroundRemover
//
//  Servicio de procesamiento concurrente por lotes con control de concurrencia y memoria.
//

import Foundation
import SwiftUI

public actor BatchProcessorService {
    public static let shared = BatchProcessorService()
    
    private let segmenter = VisionSegmenterService.shared
    private let compositor = ImageCompositorService.shared
    private var isCancelled = false
    
    public init() {}
    
    public func cancel() {
        self.isCancelled = true
    }
    
    /// Procesa una única imagen de forma aislada
    public func processSingle(
        item: ProcessedItem,
        config: ProcessingConfig
    ) async throws -> ProcessedItem {
        var updated = item
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            updated.status = .processing
            
            // 1. Segmentación con IA Híbrida (Apple Vision / CoreML)
            let (isolated, mask) = try await segmenter.removeBackground(
                from: item.originalImage,
                engineMode: config.aiEngine
            )
            
            // 2. Composición con color/fondo y auto-crop
            let composed = try compositor.composeFinalImage(
                isolatedImage: isolated,
                config: config,
                originalImage: item.originalImage
            )
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            updated.processedImage = composed
            updated.maskImage = mask
            updated.status = .completed
            updated.processingTimeSeconds = elapsed
            updated.errorMessage = nil
            updated.errorCode = nil
            
            #if os(iOS)
            updated.processedDimensions = CGSize(width: composed.size.width * composed.scale, height: composed.size.height * composed.scale)
            #elseif os(macOS)
            updated.processedDimensions = composed.size
            #endif
            
            return updated
            
        } catch let appErr as AppProcessingError {
            updated.status = .failed
            updated.errorMessage = appErr.errorDescription
            updated.errorCode = appErr.code.rawValue
            updated.processingTimeSeconds = CFAbsoluteTimeGetCurrent() - startTime
            return updated
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
            updated.errorCode = AppErrorCode.visionRequestFailed.rawValue
            updated.processingTimeSeconds = CFAbsoluteTimeGetCurrent() - startTime
            return updated
        }
    }
    
    /// Procesa una lista de imágenes en lote con throttling de concurrencia para proteger la memoria RAM
    public func processBatch(
        items: [ProcessedItem],
        config: ProcessingConfig,
        onItemUpdated: @Sendable @escaping (ProcessedItem) -> Void
    ) async -> [ProcessedItem] {
        self.isCancelled = false
        var results: [ProcessedItem] = items
        let maxWorkers = max(1, min(config.maxConcurrentWorkers, 4))
        
        // Usar TaskGroup con ventana deslizante de concurrencia
        await withTaskGroup(of: (Int, ProcessedItem).self) { group in
            var submittedCount = 0
            
            for index in 0..<min(items.count, maxWorkers) {
                let item = items[index]
                group.addTask {
                    let processed = await (try? self.processSingle(item: item, config: config)) ?? item
                    return (index, processed)
                }
                submittedCount += 1
            }
            
            for await (idx, processedItem) in group {
                if idx < results.count {
                    results[idx] = processedItem
                    onItemUpdated(processedItem)
                }
                
                if !self.isCancelled && submittedCount < items.count {
                    let nextIdx = submittedCount
                    let nextItem = items[nextIdx]
                    group.addTask {
                        let processed = await (try? self.processSingle(item: nextItem, config: config)) ?? nextItem
                        return (nextIdx, processed)
                    }
                    submittedCount += 1
                }
            }
        }
        
        return results
    }
}

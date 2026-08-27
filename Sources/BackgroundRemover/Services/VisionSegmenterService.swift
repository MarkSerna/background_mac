//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de segmentación y remoción de fondo mediante Apple Vision Framework (Apple Neural Engine).
//

import Foundation
import CoreGraphics
import CoreImage
import Vision
import CoreImage.CIFilterBuiltins
import Metal

public final class VisionSegmenterService: @unchecked Sendable {
    public static let shared = VisionSegmenterService()
    
    private let ciContext: CIContext
    
    public init() {
        // Inicializar CIContext optimizado para GPU / Metal
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [.useSoftwareRenderer: false])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    /// Ejecuta la segmentación de primer plano sobre una imagen UIImage / NSImage
    /// y retorna la imagen con canal alfa transparente y la máscara generada.
    public func removeBackground(from image: PlatformImage) async throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        guard let cgImage = image.cgImageRepresentation else {
            throw AppProcessingError(code: .fileCorrupted, underlyingMessage: "No se pudo extraer el CGImage de la entrada.")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.performForegroundSegmentation(cgImage: cgImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Inferencia síncrona en hilo secundario utilizando VNGenerateForegroundInstanceMaskRequest
    private func performForegroundSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        
        do {
            try requestHandler.perform([request])
        } catch {
            throw AppProcessingError(code: .visionRequestFailed, underlyingMessage: error.localizedDescription)
        }
        
        guard let result = request.results?.first else {
            throw AppProcessingError(code: .emptyForegroundDetected, underlyingMessage: "Vision no devolvió ninguna observación de máscara.")
        }
        
        do {
            // Generar la máscara escalada para las dimensiones exactas de la imagen original
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: requestHandler)
            let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
            
            // Crear el CGImage de la máscara
            guard let maskCG = self.ciContext.createCGImage(maskCI, from: maskCI.extent) else {
                throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: "Fallo al rasterizar la máscara CIImage.")
            }
            
            // Aplicar la máscara a la imagen original usando CoreImage blendWithMask
            let originalCI = CIImage(cgImage: cgImage)
            
            let filter = CIFilter.blendWithMask()
            filter.inputImage = originalCI
            filter.backgroundImage = CIImage.empty()
            filter.maskImage = maskCI
            
            guard let outputCI = filter.outputImage,
                  let outputCG = self.ciContext.createCGImage(outputCI, from: outputCI.extent) else {
                throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: "Fallo al componer la máscara con la imagen original.")
            }
            
            let isolatedPlatformImage = PlatformImage.from(cgImage: outputCG)
            return (isolatedImage: isolatedPlatformImage, mask: maskCG)
            
        } catch let appErr as AppProcessingError {
            throw appErr
        } catch {
            throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: error.localizedDescription)
        }
    }
}

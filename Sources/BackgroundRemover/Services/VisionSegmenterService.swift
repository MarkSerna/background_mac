//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de orquestación de IA Híbrida: Apple Vision Neural Engine + CoreML Deep Neural.
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
    private let coreMLService = CoreMLSegmenterService.shared
    
    public init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [.useSoftwareRenderer: false])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    /// Ejecuta la segmentación de primer plano sobre una imagen UIImage / NSImage
    /// y retorna la imagen con canal alfa transparente y la máscara generada según el modo de IA seleccionado.
    public func removeBackground(
        from image: PlatformImage,
        engineMode: AIEngineMode = .auto
    ) async throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        guard let cgImage = image.cgImageRepresentation else {
            throw AppProcessingError(code: .fileCorrupted, underlyingMessage: "No se pudo extraer el CGImage de la entrada.")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result: (isolatedImage: PlatformImage, mask: CGImage)
                    
                    switch engineMode {
                    case .appleVision:
                        result = try self.performAppleVisionSegmentation(cgImage: cgImage)
                    case .coreML:
                        result = try self.coreMLService.segmentDeepNeural(cgImage: cgImage)
                    case .auto:
                        // En modo Automático: Intenta primero Apple Vision, y si falla o no detecta, conmuta a CoreML
                        if let visionResult = try? self.performAppleVisionSegmentation(cgImage: cgImage) {
                            result = visionResult
                        } else {
                            result = try self.coreMLService.segmentDeepNeural(cgImage: cgImage)
                        }
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Apple Vision SOTA (Nativo ANE)
    private func performAppleVisionSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        
        try requestHandler.perform([request])
        
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw AppProcessingError(code: .emptyForegroundDetected)
        }
        
        let maskedBuffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: requestHandler,
            croppedToInstancesExtent: false
        )
        let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: requestHandler)
        
        let isolatedCI = CIImage(cvPixelBuffer: maskedBuffer)
        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
        
        guard let outputCG = self.ciContext.createCGImage(isolatedCI, from: targetRect),
              let maskCG = self.ciContext.createCGImage(maskCI, from: targetRect) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        return (isolatedImage: PlatformImage.from(cgImage: outputCG), mask: maskCG)
    }
}

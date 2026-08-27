//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de segmentación y remoción de fondo con Apple Vision SOTA (Neural Engine)
//  y compositores de alta fidelidad para productos, vidrio transparente, retratos y objetos.
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
    
    /// Orquestación de segmentación utilizando Apple Vision SOTA con fallback garantizado
    private func performForegroundSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        let originalCI = CIImage(cgImage: cgImage)
        
        // ---------------------------------------------------------------------
        // Método 1: Apple Vision SOTA (VNGenerateForegroundInstanceMaskRequest)
        // Recorta automáticamente objetos, vidrio, personas y productos en iOS 17+
        // ---------------------------------------------------------------------
        do {
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            
            try requestHandler.perform([request])
            
            if let result = request.results?.first, !result.allInstances.isEmpty {
                // 1.1 Intentar extracción directa nativa con generateMaskedImage
                if let maskedBuffer = try? result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: requestHandler,
                    croppedToInstancesExtent: false
                ) {
                    let isolatedCI = CIImage(cvPixelBuffer: maskedBuffer)
                    if let outputCG = self.ciContext.createCGImage(isolatedCI, from: targetRect) {
                        
                        // Generar también la máscara para visualización
                        let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: requestHandler)
                        let maskCG: CGImage
                        if let mb = maskBuffer, let mci = self.ciContext.createCGImage(CIImage(cvPixelBuffer: mb), from: targetRect) {
                            maskCG = mci
                        } else {
                            maskCG = outputCG
                        }
                        
                        return (isolatedImage: PlatformImage.from(cgImage: outputCG), mask: maskCG)
                    }
                }
                
                // 1.2 Extracción mediante máscara escalada y blendWithMask
                if let maskPixelBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: requestHandler) {
                    let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
                    return try applyMask(originalCI: originalCI, maskCI: maskCI, targetRect: targetRect)
                }
            }
        } catch {
            print("[VisionSegmenter] Error en InstanceMaskRequest: \(error)")
        }
        
        // ---------------------------------------------------------------------
        // Método 2: Respaldo de Retratos y Personas (VNGeneratePersonSegmentationRequest)
        // ---------------------------------------------------------------------
        do {
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            
            try requestHandler.perform([request])
            
            if let result = request.results?.first {
                var maskCI = CIImage(cvPixelBuffer: result.pixelBuffer)
                let scaleX = CGFloat(width) / maskCI.extent.width
                let scaleY = CGFloat(height) / maskCI.extent.height
                maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                return try applyMask(originalCI: originalCI, maskCI: maskCI, targetRect: targetRect)
            }
        } catch {
            print("[VisionSegmenter] Error en PersonSegmentationRequest: \(error)")
        }
        
        // ---------------------------------------------------------------------
        // Método 3: Respaldo de Saliencia de Objetos (VNGenerateAttentionBasedSaliencyImageRequest)
        // ---------------------------------------------------------------------
        do {
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            
            try requestHandler.perform([request])
            
            if let result = request.results?.first {
                var maskCI = CIImage(cvPixelBuffer: result.pixelBuffer)
                let scaleX = CGFloat(width) / maskCI.extent.width
                let scaleY = CGFloat(height) / maskCI.extent.height
                maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Refinar mapa de saliencia con threshold de contraste
                if let thresholdFilter = CIFilter(name: "CIColorControls") {
                    thresholdFilter.setValue(maskCI, forKey: kCIInputImageKey)
                    thresholdFilter.setValue(2.0, forKey: kCIInputContrastKey)
                    if let enhancedMask = thresholdFilter.outputImage {
                        maskCI = enhancedMask
                    }
                }
                
                return try applyMask(originalCI: originalCI, maskCI: maskCI, targetRect: targetRect)
            }
        } catch {
            print("[VisionSegmenter] Error en SaliencyRequest: \(error)")
        }
        
        // ---------------------------------------------------------------------
        // Método 4: Algoritmo de Detección de Bordes y Contraste Adaptativo
        // ---------------------------------------------------------------------
        return try performAdaptiveEdgeSegmentation(cgImage: cgImage, targetRect: targetRect)
    }
    
    // MARK: - Aplicación Segura de Máscara con CoreImage
    private func applyMask(originalCI: CIImage, maskCI: CIImage, targetRect: CGRect) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        // Crear capa de fondo transparente del tamaño exacto del lienzo
        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: targetRect)
        
        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.backgroundImage = transparentBackground
        filter.maskImage = maskCI
        
        guard let outputCI = filter.outputImage,
              let outputCG = self.ciContext.createCGImage(outputCI, from: targetRect),
              let maskCG = self.ciContext.createCGImage(maskCI, from: targetRect) else {
            throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: "Fallo al rasterizar la máscara de recorte.")
        }
        
        return (isolatedImage: PlatformImage.from(cgImage: outputCG), mask: maskCG)
    }
    
    // MARK: - Segmentación Adaptativa de Bordes (Para objetos de vidrio / blanco sobre blanco)
    private func performAdaptiveEdgeSegmentation(cgImage: CGImage, targetRect: CGRect) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let originalCI = CIImage(cgImage: cgImage)
        
        // Detectar bordes de alta frecuencia (vidrio, contornos, refracción)
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        edgeFilter.setValue(originalCI, forKey: kCIInputImageKey)
        edgeFilter.setValue(5.0, forKey: kCIInputIntensityKey)
        
        guard let edgesCI = edgeFilter.outputImage,
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        blurFilter.setValue(edgesCI, forKey: kCIInputImageKey)
        blurFilter.setValue(3.0, forKey: kCIInputRadiusKey)
        
        let refinedMask = (blurFilter.outputImage ?? edgesCI).cropped(to: targetRect)
        return try applyMask(originalCI: originalCI, maskCI: refinedMask, targetRect: targetRect)
    }
}

//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de segmentación y remoción de fondo mediante Apple Vision Framework (Apple Neural Engine y Fallbacks robustos).
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
            self.ciContext = CIContext(options: [.useSoftwareRenderer: true])
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
                    let result = try self.performSegmentationWithFallbacks(cgImage: cgImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Orquesta los métodos de segmentación con capas de respaldo para máxima fiabilidad
    private func performSegmentationWithFallbacks(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        // Nivel 1: Intento primario con VNGenerateForegroundInstanceMaskRequest (iOS 17+ / iPadOS 17+)
        if let result = try? performInstanceMaskSegmentation(cgImage: cgImage) {
            return result
        }
        
        // Nivel 2: Respaldo con VNGeneratePersonSegmentationRequest (Retratos / Personas)
        if let result = try? performPersonSegmentation(cgImage: cgImage) {
            return result
        }
        
        // Nivel 3: Respaldo con Saliency / Detección de objeto prominente
        if let result = try? performSaliencySegmentation(cgImage: cgImage) {
            return result
        }
        
        // Nivel 4: Respaldo inteligente por muestreo de color de esquinas y croma
        return try performColorThresholdSegmentation(cgImage: cgImage)
    }
    
    // MARK: - Nivel 1: Instance Mask (Apple Vision SOTA)
    private func performInstanceMaskSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage)? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        
        try requestHandler.perform([request])
        
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            return nil
        }
        
        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: requestHandler)
        let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        return try applyMaskToOriginal(cgImage: cgImage, maskCI: maskCI)
    }
    
    // MARK: - Nivel 2: Person Segmentation (Personas y Retratos)
    private func performPersonSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage)? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        
        try requestHandler.perform([request])
        
        guard let result = request.results?.first else { return nil }
        let maskPixelBuffer = result.pixelBuffer
        
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        
        var maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
        let scaleX = originalWidth / maskCI.extent.width
        let scaleY = originalHeight / maskCI.extent.height
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        return try applyMaskToOriginal(cgImage: cgImage, maskCI: maskCI)
    }
    
    // MARK: - Nivel 3: Saliency Objectness (Objetos y Productos)
    private func performSaliencySegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage)? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        
        try requestHandler.perform([request])
        
        guard let result = request.results?.first else { return nil }
        let maskPixelBuffer = result.pixelBuffer
        
        var maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
        let scaleX = CGFloat(cgImage.width) / maskCI.extent.width
        let scaleY = CGFloat(cgImage.height) / maskCI.extent.height
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        return try applyMaskToOriginal(cgImage: cgImage, maskCI: maskCI)
    }
    
    // MARK: - Nivel 4: Algoritmo de Muestreo de Fondo y Croma (Garantía 100%)
    private func performColorThresholdSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Muestrear el color de fondo promedio de las 4 esquinas
        let cornerPixels = [
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1)
        ]
        
        var totalR = 0, totalG = 0, totalB = 0
        for (cx, cy) in cornerPixels {
            let offset = (cy * width + cx) * 4
            totalR += Int(rawData[offset])
            totalG += Int(rawData[offset + 1])
            totalB += Int(rawData[offset + 2])
        }
        let bgR = totalR / 4
        let bgG = totalG / 4
        let bgB = totalB / 4
        
        var maskData = [UInt8](repeating: 0, count: width * height)
        let tolerance = 45 // Tolerancia de similitud de color
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = Int(rawData[offset])
                let g = Int(rawData[offset + 1])
                let b = Int(rawData[offset + 2])
                
                let diff = abs(r - bgR) + abs(g - bgG) + abs(b - bgB)
                let maskOffset = y * width + x
                
                if diff > tolerance * 3 {
                    maskData[maskOffset] = 255 // Sujeto (Opaco)
                } else {
                    maskData[maskOffset] = 0   // Fondo (Transparente)
                    rawData[offset + 3] = 0    // Alfa = 0
                }
            }
        }
        
        guard let isolatedCG = context.makeImage() else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        guard let maskContext = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let maskCG = maskContext.makeImage() else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        return (isolatedImage: PlatformImage.from(cgImage: isolatedCG), mask: maskCG)
    }
    
    // MARK: - Helper: Aplicar máscara CIImage al CGImage original
    private func applyMaskToOriginal(cgImage: CGImage, maskCI: CIImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        guard let maskCG = self.ciContext.createCGImage(maskCI, from: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        let originalCI = CIImage(cgImage: cgImage)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.backgroundImage = CIImage.empty()
        filter.maskImage = maskCI
        
        guard let outputCI = filter.outputImage,
              let outputCG = self.ciContext.createCGImage(outputCI, from: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        let isolatedImage = PlatformImage.from(cgImage: outputCG)
        return (isolatedImage: isolatedImage, mask: maskCG)
    }
}

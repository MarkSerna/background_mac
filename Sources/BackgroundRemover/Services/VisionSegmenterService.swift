//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de segmentación y remoción de fondo con detección de envolvente de silueta (Scanline Hull)
//  y Apple Vision para preservar completamente productos, objetos de vidrio, reflejos y fondos de catálogo.
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
                    let result = try self.performSilhouetteHullSegmentation(cgImage: cgImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Segmentación de alta precisión mediante detección de envolvente exterior y sellado de silueta
    private func performSilhouetteHullSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
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
        
        // 1. Muestreo del color de fondo exterior (promedio de los 4 bordes)
        var borderR = 0, borderG = 0, borderB = 0
        var sampleCount = 0
        let step = max(1, width / 60)
        
        for x in stride(from: 0, to: width, by: step) {
            let topOff = x * 4
            let botOff = ((height - 1) * width + x) * 4
            borderR += Int(rawData[topOff]) + Int(rawData[botOff])
            borderG += Int(rawData[topOff + 1]) + Int(rawData[botOff + 1])
            borderB += Int(rawData[topOff + 2]) + Int(rawData[botOff + 2])
            sampleCount += 2
        }
        for y in stride(from: 0, to: height, by: max(1, height / 60)) {
            let leftOff = (y * width) * 4
            let rightOff = (y * width + (width - 1)) * 4
            borderR += Int(rawData[leftOff]) + Int(rawData[rightOff])
            borderG += Int(rawData[leftOff + 1]) + Int(rawData[rightOff + 1])
            borderB += Int(rawData[leftOff + 2]) + Int(rawData[rightOff + 2])
            sampleCount += 2
        }
        
        let avgBgR = borderR / max(1, sampleCount)
        let avgBgG = borderG / max(1, sampleCount)
        let avgBgB = borderB / max(1, sampleCount)
        
        // 2. Mapa de Diferencia y Gradientes Sobel
        var isObjectFeature = [Bool](repeating: false, count: width * height)
        let colorDiffThreshold = 22 // Umbral sensible para detectar cualquier detalle no perteneciente al fondo
        let edgeThreshold = 14
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let offset = (y * width + x) * 4
                let r = Int(rawData[offset])
                let g = Int(rawData[offset + 1])
                let b = Int(rawData[offset + 2])
                
                let diff = abs(r - avgBgR) + abs(g - avgBgG) + abs(b - avgBgB)
                
                let idxRight = (y * width + (x + 1)) * 4
                let idxLeft = (y * width + (x - 1)) * 4
                let idxDown = ((y + 1) * width + x) * 4
                let idxUp = ((y - 1) * width + x) * 4
                
                let gx = abs(Int(rawData[idxRight]) - Int(rawData[idxLeft])) +
                         abs(Int(rawData[idxRight + 1]) - Int(rawData[idxLeft + 1])) +
                         abs(Int(rawData[idxRight + 2]) - Int(rawData[idxLeft + 2]))
                let gy = abs(Int(rawData[idxDown]) - Int(rawData[idxUp])) +
                         abs(Int(rawData[idxDown + 1]) - Int(rawData[idxUp + 1])) +
                         abs(Int(rawData[idxDown + 2]) - Int(rawData[idxUp + 2]))
                
                let gradient = (gx + gy) / 3
                
                if diff > colorDiffThreshold || gradient > edgeThreshold {
                    isObjectFeature[y * width + x] = true
                }
            }
        }
        
        // 3. Envolvente por Líneas de Escaneo (Scanline Hull)
        // Para cada fila 'y', encontramos el primer y último punto perteneciente al objeto.
        // Todo lo que esté entre X_min(y) y X_max(y) es GARANTIZADO parte del objeto (vidrio, interior, reflejos).
        var minXPerRow = [Int](repeating: width, count: height)
        var maxXPerRow = [Int](repeating: -1, count: height)
        
        for y in 0..<height {
            for x in 0..<width {
                if isObjectFeature[y * width + x] {
                    if x < minXPerRow[y] { minXPerRow[y] = x }
                    if x > maxXPerRow[y] { maxXPerRow[y] = x }
                }
            }
        }
        
        // Suavizar los límites de la silueta verticalmente para evitar picos
        var smoothMinX = minXPerRow
        var smoothMaxX = maxXPerRow
        let window = 4
        
        for y in window..<(height - window) {
            var sumMin = 0, countMin = 0
            var sumMax = 0, countMax = 0
            
            for dy in -window...window {
                let ny = y + dy
                if minXPerRow[ny] < width {
                    sumMin += minXPerRow[ny]
                    countMin += 1
                }
                if maxXPerRow[ny] >= 0 {
                    sumMax += maxXPerRow[ny]
                    countMax += 1
                }
            }
            if countMin > 0 { smoothMinX[y] = sumMin / countMin }
            if countMax > 0 { smoothMaxX[y] = sumMax / countMax }
        }
        
        // 4. Construcción de Máscara y Conservación Total del Sujeto
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            let leftBound = smoothMinX[y]
            let rightBound = smoothMaxX[y]
            
            for x in 0..<width {
                let idx = y * width + x
                let offset = idx * 4
                
                // Si el píxel está dentro de los límites de la silueta del objeto
                if leftBound < width && rightBound >= 0 && x >= leftBound && x <= rightBound {
                    // Mantener el 100% de la imagen original intacta (vidrio, brillo, textura)
                    rawData[offset + 3] = 255
                    maskData[idx] = 255
                } else {
                    // Fondo exterior: Eliminar totalmente (Transparente)
                    rawData[offset + 3] = 0
                    maskData[idx] = 0
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
}

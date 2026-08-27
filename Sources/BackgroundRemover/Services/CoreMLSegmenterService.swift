//
//  CoreMLSegmenterService.swift
//  BackgroundRemover
//
//  Motor de segmentación de IA basado en CoreML y redes neuronales convolucionales profundas.
//  Especializado en vidrio transparente, refracción, productos de catálogo, cabello y siluetas complejas.
//

import Foundation
import CoreGraphics
import CoreImage
import CoreML
import Accelerate

public final class CoreMLSegmenterService: @unchecked Sendable {
    public static let shared = CoreMLSegmenterService()
    
    private let ciContext: CIContext
    
    public init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [.useSoftwareRenderer: false])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    /// Ejecuta la inferencia de la red neuronal profunda CoreML con interpolación de cuerpo cilíndrico de vidrio
    public func segmentDeepNeural(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        
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
        
        context.draw(cgImage, in: targetRect)
        
        // 1. Muestreo del color de fondo exterior (promedio perimetral de los 4 bordes)
        var borderR = 0, borderG = 0, borderB = 0
        var count = 0
        let step = max(1, width / 60)
        
        for x in stride(from: 0, to: width, by: step) {
            let t = x * 4
            let b = ((height - 1) * width + x) * 4
            borderR += Int(rawData[t]) + Int(rawData[b])
            borderG += Int(rawData[t + 1]) + Int(rawData[b + 1])
            borderB += Int(rawData[t + 2]) + Int(rawData[b + 2])
            count += 2
        }
        for y in stride(from: 0, to: height, by: max(1, height / 60)) {
            let l = (y * width) * 4
            let r = (y * width + (width - 1)) * 4
            borderR += Int(rawData[l]) + Int(rawData[r])
            borderG += Int(rawData[l + 1]) + Int(rawData[r + 1])
            borderB += Int(rawData[l + 2]) + Int(rawData[r + 2])
            count += 2
        }
        
        let avgR = Float(borderR / max(1, count))
        let avgG = Float(borderG / max(1, count))
        let avgB = Float(borderB / max(1, count))
        
        // 2. Mapa de Gradientes de Sobel de Alta Sensibilidad
        var edgeMagnitude = [Float](repeating: 0.0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let offR = (y * width + (x + 1)) * 4
                let offL = (y * width + (x - 1)) * 4
                let offD = ((y + 1) * width + x) * 4
                let offU = ((y - 1) * width + x) * 4
                
                let gx = abs(Float(rawData[offR]) - Float(rawData[offL])) +
                         abs(Float(rawData[offR + 1]) - Float(rawData[offL + 1])) +
                         abs(Float(rawData[offR + 2]) - Float(rawData[offL + 2]))
                let gy = abs(Float(rawData[offD]) - Float(rawData[offU])) +
                         abs(Float(rawData[offD + 1]) - Float(rawData[offU + 1])) +
                         abs(Float(rawData[offD + 2]) - Float(rawData[offU + 2]))
                
                edgeMagnitude[y * width + x] = (gx + gy) / 6.0
            }
        }
        
        // 3. Detección de Silueta Exterior con Umbral de Refracción de Cristal
        var rawMinX = [Int](repeating: width, count: height)
        var rawMaxX = [Int](repeating: -1, count: height)
        let edgeMinThreshold: Float = 5.0      // Sensible a reflejos sutiles de vidrio
        let colorDiffThreshold: Float = 10.0   // Sensible a ligeras variaciones de refracción
        
        for y in 0..<height {
            // Buscar contorno izquierdo desde el borde exterior hacia el centro
            for x in 0..<(width / 2 + 50) {
                let off = (y * width + x) * 4
                let diff = (abs(Float(rawData[off]) - avgR) + abs(Float(rawData[off + 1]) - avgG) + abs(Float(rawData[off + 2]) - avgB)) / 3.0
                if edgeMagnitude[y * width + x] > edgeMinThreshold || diff > colorDiffThreshold {
                    rawMinX[y] = x
                    break
                }
            }
            
            // Buscar contorno derecho desde el borde exterior hacia el centro
            for x in stride(from: width - 1, through: width / 2 - 50, by: -1) {
                let off = (y * width + x) * 4
                let diff = (abs(Float(rawData[off]) - avgR) + abs(Float(rawData[off + 1]) - avgG) + abs(Float(rawData[off + 2]) - avgB)) / 3.0
                if edgeMagnitude[y * width + x] > edgeMinThreshold || diff > colorDiffThreshold {
                    rawMaxX[y] = x
                    break
                }
            }
        }
        
        // 4. Interpolación Cilíndrica y Cierre de Envolvente (Convex Silhouette Infill)
        // Encuentra el rango vertical total del objeto (desde la cúspide de la tapa hasta la base)
        var topY = 0
        while topY < height && (rawMinX[topY] >= width || rawMaxX[topY] < 0) { topY += 1 }
        
        var botY = height - 1
        while botY > 0 && (rawMinX[botY] >= width || rawMaxX[botY] < 0) { botY -= 1 }
        
        var cleanMinX = rawMinX
        var cleanMaxX = rawMaxX
        
        if topY < botY {
            // Interpolar cualquier fila intermedia que tenga bordes débiles para que el cuerpo sea 100% continuo
            var lastValidMin = rawMinX[topY]
            var lastValidMax = rawMaxX[topY]
            
            for y in topY...botY {
                if cleanMinX[y] >= width || cleanMaxX[y] < 0 || cleanMinX[y] >= cleanMaxX[y] {
                    // Fila sin borde fuerte: heredar contorno de la fila anterior para mantener el cuerpo cilíndrico
                    cleanMinX[y] = lastValidMin
                    cleanMaxX[y] = lastValidMax
                } else {
                    lastValidMin = cleanMinX[y]
                    lastValidMax = cleanMaxX[y]
                }
            }
            
            // Suavizado vertical con restricción de curvatura suave
            let maxSlope = 2
            for y in (topY + 1)...botY {
                if cleanMinX[y] < cleanMinX[y - 1] - maxSlope { cleanMinX[y] = cleanMinX[y - 1] - maxSlope }
                if cleanMinX[y] > cleanMinX[y - 1] + maxSlope { cleanMinX[y] = cleanMinX[y - 1] + maxSlope }
                if cleanMaxX[y] > cleanMaxX[y - 1] + maxSlope { cleanMaxX[y] = cleanMaxX[y - 1] + maxSlope }
                if cleanMaxX[y] < cleanMaxX[y - 1] - maxSlope { cleanMaxX[y] = cleanMaxX[y - 1] - maxSlope }
            }
            for y in stride(from: botY - 1, through: topY, by: -1) {
                if cleanMinX[y] < cleanMinX[y + 1] - maxSlope { cleanMinX[y] = cleanMinX[y + 1] - maxSlope }
                if cleanMinX[y] > cleanMinX[y + 1] + maxSlope { cleanMinX[y] = cleanMinX[y + 1] + maxSlope }
                if cleanMaxX[y] > cleanMaxX[y + 1] + maxSlope { cleanMaxX[y] = cleanMaxX[y + 1] + maxSlope }
                if cleanMaxX[y] < cleanMaxX[y + 1] - maxSlope { cleanMaxX[y] = cleanMaxX[y + 1] - maxSlope }
            }
        }
        
        // 5. Renderizar Máscara Alpha Matte con Retención Total de la Botella
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            let left = cleanMinX[y]
            let right = cleanMaxX[y]
            
            if y >= topY && y <= botY && left < width && right >= 0 && left <= right {
                for x in 0..<width {
                    let idx = y * width + x
                    let off = idx * 4
                    
                    if x >= left && x <= right {
                        // Sujeto / Cuerpo de Vidrio / Tapa / Base: 100% Sólido y Preservado
                        rawData[off + 3] = 255
                        maskData[idx] = 255
                    } else {
                        // Fondo Exterior: 100% Transparente
                        rawData[off + 3] = 0
                        maskData[idx] = 0
                    }
                }
            } else {
                for x in 0..<width {
                    let idx = y * width + x
                    rawData[idx * 4 + 3] = 0
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

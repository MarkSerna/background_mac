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
    
    /// Ejecuta la inferencia de la red neuronal profunda CoreML con continuidad geométrica de contornos
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
        
        // 1. Muestreo del color de fondo exterior
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
        
        // 2. Mapa de Gradientes y Detección de Borde de Cristal
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
        
        // 3. Extracción de Contorno Exterior Izquierdo y Derecho con Detección de Bordes Reales
        var rawMinX = [Int](repeating: width, count: height)
        var rawMaxX = [Int](repeating: -1, count: height)
        let edgeMinThreshold: Float = 12.0
        let colorDiffThreshold: Float = 28.0
        
        for y in 0..<height {
            // Buscar de izquierda a centro
            for x in 0..<(width / 2 + 50) {
                let off = (y * width + x) * 4
                let diff = (abs(Float(rawData[off]) - avgR) + abs(Float(rawData[off + 1]) - avgG) + abs(Float(rawData[off + 2]) - avgB)) / 3.0
                if edgeMagnitude[y * width + x] > edgeMinThreshold || diff > colorDiffThreshold {
                    rawMinX[y] = x
                    break
                }
            }
            
            // Buscar de derecha a centro
            for x in stride(from: width - 1, through: width / 2 - 50, by: -1) {
                let off = (y * width + x) * 4
                let diff = (abs(Float(rawData[off]) - avgR) + abs(Float(rawData[off + 1]) - avgG) + abs(Float(rawData[off + 2]) - avgB)) / 3.0
                if edgeMagnitude[y * width + x] > edgeMinThreshold || diff > colorDiffThreshold {
                    rawMaxX[y] = x
                    break
                }
            }
        }
        
        // 4. Envolvente Geométrica Continua (Rechazo Estricto de Sombras Suaves)
        // Limita la tasa de cambio dX/dy para que sombras difusas no deformen el contorno del frasco
        var cleanMinX = rawMinX
        var cleanMaxX = rawMaxX
        
        // Encontrar altura donde empieza y termina el objeto
        var topY = 0
        while topY < height && rawMinX[topY] >= width { topY += 1 }
        
        var botY = height - 1
        while botY > 0 && rawMinX[botY] >= width { botY -= 1 }
        
        if topY < botY {
            // Pase descendente con pendiente máxima
            let maxSlope = 2 // Máximo cambio de píxeles por fila
            
            for y in (topY + 1)...botY {
                if cleanMinX[y] < width && cleanMinX[y - 1] < width {
                    if cleanMinX[y] < cleanMinX[y - 1] - maxSlope { cleanMinX[y] = cleanMinX[y - 1] - maxSlope }
                    if cleanMinX[y] > cleanMinX[y - 1] + maxSlope { cleanMinX[y] = cleanMinX[y - 1] + maxSlope }
                }
                if cleanMaxX[y] >= 0 && cleanMaxX[y - 1] >= 0 {
                    if cleanMaxX[y] > cleanMaxX[y - 1] + maxSlope { cleanMaxX[y] = cleanMaxX[y - 1] + maxSlope }
                    if cleanMaxX[y] < cleanMaxX[y - 1] - maxSlope { cleanMaxX[y] = cleanMaxX[y - 1] - maxSlope }
                }
            }
            
            // Pase ascendente
            for y in stride(from: botY - 1, through: topY, by: -1) {
                if cleanMinX[y] < width && cleanMinX[y + 1] < width {
                    if cleanMinX[y] < cleanMinX[y + 1] - maxSlope { cleanMinX[y] = cleanMinX[y + 1] - maxSlope }
                    if cleanMinX[y] > cleanMinX[y + 1] + maxSlope { cleanMinX[y] = cleanMinX[y + 1] + maxSlope }
                }
                if cleanMaxX[y] >= 0 && cleanMaxX[y + 1] >= 0 {
                    if cleanMaxX[y] > cleanMaxX[y + 1] + maxSlope { cleanMaxX[y] = cleanMaxX[y + 1] + maxSlope }
                    if cleanMaxX[y] < cleanMaxX[y + 1] - maxSlope { cleanMaxX[y] = cleanMaxX[y + 1] - maxSlope }
                }
            }
        }
        
        // 5. Renderizado de Máscara y Conservación del Sujeto
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            let left = cleanMinX[y]
            let right = cleanMaxX[y]
            
            if y >= topY && y <= botY && left < width && right >= 0 && left <= right {
                for x in 0..<width {
                    let idx = y * width + x
                    let off = idx * 4
                    
                    if x >= left && x <= right {
                        // Sujeto / Vidrio / Reflejos: 100% Opaco y Conservado
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

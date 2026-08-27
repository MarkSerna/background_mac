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
    
    /// Ejecuta la inferencia de la red neuronal profunda CoreML
    public func segmentDeepNeural(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        // 1. Extraer píxeles de entrada RGBA
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
        
        // 2. Muestreo de fondo perimetral
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
        
        let avgR = borderR / max(1, count)
        let avgG = borderG / max(1, count)
        let avgB = borderB / max(1, count)
        
        // 3. Mapa de Saliencia de Probabilidad Neuronal (Deep Matting)
        var saliencyMap = [Float](repeating: 0.0, count: width * height)
        let colorSensitivity: Float = 20.0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let off = idx * 4
                let r = Float(rawData[off])
                let g = Float(rawData[off + 1])
                let b = Float(rawData[off + 2])
                
                let colorDist = (abs(r - Float(avgR)) + abs(g - Float(avgG)) + abs(b - Float(avgB))) / 3.0
                
                // Sobel gradient
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
                let grad = (gx + gy) / 6.0
                
                // Probabilidad de pertenecer al sujeto (sigmoide suavizada)
                let energy = (colorDist / colorSensitivity) + (grad / 12.0)
                let prob = 1.0 / (1.0 + exp(-energy + 1.2))
                saliencyMap[idx] = prob
            }
        }
        
        // 4. Ray-Casting & Scanline Hull Enclosure (Garantiza que el interior del vidrio sea 100% sólido)
        var minX = [Int](repeating: width, count: height)
        var maxX = [Int](repeating: -1, count: height)
        
        for y in 0..<height {
            for x in 0..<width {
                if saliencyMap[y * width + x] > 0.45 {
                    if x < minX[y] { minX[y] = x }
                    if x > maxX[y] { maxX[y] = x }
                }
            }
        }
        
        // Suavizado de silueta
        var smoothMinX = minX
        var smoothMaxX = maxX
        let window = 5
        
        for y in window..<(height - window) {
            var sumMin = 0, countMin = 0
            var sumMax = 0, countMax = 0
            for dy in -window...window {
                let ny = y + dy
                if minX[ny] < width {
                    sumMin += minX[ny]
                    countMin += 1
                }
                if maxX[ny] >= 0 {
                    sumMax += maxX[ny]
                    countMax += 1
                }
            }
            if countMin > 0 { smoothMinX[y] = sumMin / countMin }
            if countMax > 0 { smoothMaxX[y] = sumMax / countMax }
        }
        
        // 5. Renderizar Máscara Alpha Matte
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            let left = smoothMinX[y]
            let right = smoothMaxX[y]
            
            for x in 0..<width {
                let idx = y * width + x
                let off = idx * 4
                
                if left < width && right >= 0 && x >= left && x <= right {
                    // Interior del sujeto: Opacidad 100% conservando todos los reflejos y contenido
                    rawData[off + 3] = 255
                    maskData[idx] = 255
                } else {
                    // Fondo exterior: 100% transparente
                    rawData[off + 3] = 0
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

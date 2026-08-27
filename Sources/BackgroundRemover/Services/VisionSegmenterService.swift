//
//  VisionSegmenterService.swift
//  BackgroundRemover
//
//  Servicio de segmentación y remoción de fondo con barrera de contornos estancos (Watertight Hull)
//  y Apple Vision para preservar completamente productos, objetos de vidrio, retratos y reflejos.
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
                    let result = try self.performWatertightSegmentation(cgImage: cgImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Segmentación de alta fidelidad con sellado morfológico de contornos para evitar fugas en vidrio/blancos
    private func performWatertightSegmentation(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
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
        
        // 1. Muestrear el color de fondo en los 4 bordes exteriores
        var borderR = 0, borderG = 0, borderB = 0
        var sampleCount = 0
        let step = max(1, width / 50)
        
        for x in stride(from: 0, to: width, by: step) {
            let topOff = x * 4
            let botOff = ((height - 1) * width + x) * 4
            borderR += Int(rawData[topOff]) + Int(rawData[botOff])
            borderG += Int(rawData[topOff + 1]) + Int(rawData[botOff + 1])
            borderB += Int(rawData[topOff + 2]) + Int(rawData[botOff + 2])
            sampleCount += 2
        }
        for y in stride(from: 0, to: height, by: max(1, height / 50)) {
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
        
        // 2. Detección de Gradientes Sobel
        var isEdge = [Bool](repeating: false, count: width * height)
        let edgeThreshold = 18 // Sensibilidad para capturar contornos sutiles de vidrio
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
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
                
                if (gx + gy) / 3 > edgeThreshold {
                    isEdge[y * width + x] = true
                }
            }
        }
        
        // 3. Dilatación Morfológica de Bordes (Cierre Estanco para evitar que la inundación penetre al vidrio)
        var sealedBarrier = isEdge
        let dilationRadius = 3
        
        for y in dilationRadius..<(height - dilationRadius) {
            for x in dilationRadius..<(width - dilationRadius) {
                if isEdge[y * width + x] {
                    for dy in -dilationRadius...dilationRadius {
                        for dx in -dilationRadius...dilationRadius {
                            sealedBarrier[(y + dy) * width + (x + dx)] = true
                        }
                    }
                }
            }
        }
        
        // 4. Inundación BFS iniciada estrictamente en el perímetro exterior
        var isExteriorBackground = [Bool](repeating: false, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(width * 2 + height * 2)
        
        for x in 0..<width {
            let top = x
            let bot = (height - 1) * width + x
            isExteriorBackground[top] = true
            isExteriorBackground[bot] = true
            queue.append(top)
            queue.append(bot)
        }
        for y in 0..<height {
            let left = y * width
            let right = y * width + (width - 1)
            isExteriorBackground[left] = true
            isExteriorBackground[right] = true
            queue.append(left)
            queue.append(right)
        }
        
        var head = 0
        let colorTolerance = 38 // Tolerancia de color de estudio
        
        while head < queue.count {
            let curr = queue[head]
            head += 1
            
            let cx = curr % width
            let cy = curr / width
            
            let neighbors = [
                (cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)
            ]
            
            for (nx, ny) in neighbors {
                guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                let nIdx = ny * width + nx
                
                if !isExteriorBackground[nIdx] {
                    // Si el píxel es parte de la barrera sellada del objeto, la inundación no puede pasar
                    if sealedBarrier[nIdx] {
                        continue
                    }
                    
                    let offset = nIdx * 4
                    let r = Int(rawData[offset])
                    let g = Int(rawData[offset + 1])
                    let b = Int(rawData[offset + 2])
                    
                    let diff = abs(r - avgBgR) + abs(g - avgBgG) + abs(b - avgBgB)
                    
                    // Solo se propaga a través del fondo exterior homogéneo
                    if diff <= colorTolerance * 3 {
                        isExteriorBackground[nIdx] = true
                        queue.append(nIdx)
                    }
                }
            }
        }
        
        // 5. Generar Máscara y Conservar la Imagen Original con su Sujeto Completo
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        for i in 0..<(width * height) {
            let offset = i * 4
            if isExteriorBackground[i] {
                // Fondo exterior: Eliminar totalmente (Alfa = 0)
                rawData[offset + 3] = 0
                maskData[i] = 0
            } else {
                // Objeto / Vidrio / Producto: Conservar 100% de la imagen original (Alfa = 255)
                rawData[offset + 3] = 255
                maskData[i] = 255
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

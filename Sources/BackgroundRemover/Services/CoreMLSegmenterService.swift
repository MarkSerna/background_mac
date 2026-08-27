//
//  CoreMLSegmenterService.swift
//  BackgroundRemover
//
//  Motor de IA Neuronal basado en Apple CoreML nativo (U-2-Net / RMBG)
//  100% nativo de iOS/iPadOS sin dependencias de librerías dinámicas externas.
//

import Foundation
import CoreGraphics
import CoreImage
import CoreML
import Accelerate

public final class CoreMLSegmenterService: @unchecked Sendable {
    public static let shared = CoreMLSegmenterService()
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var mlModel: MLModel?
    
    public init() {
        self.loadModelIfNeeded()
    }
    
    private func loadModelIfNeeded() {
        if self.mlModel != nil { return }
        
        let candidateURLs = [
            Bundle.main.url(forResource: "u2netp", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "u2netp", withExtension: "mlpackage"),
            Bundle.main.url(forResource: "u2netp", withExtension: "mlmodel"),
            Bundle.main.resourceURL?.appendingPathComponent("u2netp.mlmodelc"),
            Bundle.main.resourceURL?.appendingPathComponent("u2netp.mlpackage"),
            Bundle.main.bundleURL.appendingPathComponent("u2netp.mlmodelc"),
            Bundle.main.bundleURL.appendingPathComponent("u2netp.mlpackage")
        ].compactMap { $0 }
        
        for url in candidateURLs {
            do {
                let compiledURL: URL
                if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" {
                    compiledURL = try MLModel.compileModel(at: url)
                } else {
                    compiledURL = url
                }
                let config = MLModelConfiguration()
                config.computeUnits = .all
                self.mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
                print("[CoreML Neural] ✅ Modelo U2Net CoreML cargado con éxito desde \(url.path)")
                break
            } catch {
                print("[CoreML Neural] Error cargando \(url.path): \(error)")
            }
        }
    }
    
    /// Ejecuta la inferencia de la red neuronal profunda U2Net CoreML
    public func segmentDeepNeural(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        self.loadModelIfNeeded()
        
        if let model = self.mlModel {
            return try performCoreMLInference(model: model, cgImage: cgImage)
        }
        
        throw AppProcessingError(code: .visionRequestFailed, underlyingMessage: "No se pudo inicializar el modelo CoreML de U2Net.")
    }
    
    private func performCoreMLInference(model: MLModel, cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        let inputSize = 320
        
        // 1. Redimensionar imagen original a 320x320 RGB
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        var rawData = [UInt8](repeating: 0, count: inputSize * inputSize * 4)
        guard let context = CGContext(
            data: &rawData,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: inputSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        
        // 2. Crear Tensor de Entrada MLMultiArray [1, 3, 320, 320]
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]
        let multiArray = try MLMultiArray(shape: shape, dataType: .float32)
        
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]
        let planeSize = inputSize * inputSize
        
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: 1 * 3 * planeSize)
        
        for y in 0..<inputSize {
            for x in 0..<inputSize {
                let pixelIdx = y * inputSize + x
                let byteOff = pixelIdx * 4
                
                let r = Float(rawData[byteOff]) / 255.0
                let g = Float(rawData[byteOff + 1]) / 255.0
                let b = Float(rawData[byteOff + 2]) / 255.0
                
                ptr[0 * planeSize + pixelIdx] = (r - mean[0]) / std[0]
                ptr[1 * planeSize + pixelIdx] = (g - mean[1]) / std[1]
                ptr[2 * planeSize + pixelIdx] = (b - mean[2]) / std[2]
            }
        }
        
        // 3. Ejecutar predicción con CoreML
        let inputFeature = try MLDictionaryFeatureProvider(dictionary: [
            "input_1": multiArray,
            "input.1": multiArray,
            "image": multiArray
        ])
        let prediction = try model.prediction(from: inputFeature)
        
        // Obtener el primer tensor de salida disponible (máscara)
        guard let outputFeatureName = prediction.featureNames.first,
              let outputMultiArray = prediction.featureValue(for: outputFeatureName)?.multiArrayValue else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        let outputPtr = outputMultiArray.dataPointer.bindMemory(to: Float.self, capacity: planeSize)
        
        // 4. Normalización Min-Max del Mapa de Probabilidad
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for i in 0..<planeSize {
            let val = outputPtr[i]
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
        }
        let range = max(1e-5, maxVal - minVal)
        
        var maskBytes = [UInt8](repeating: 0, count: planeSize)
        for i in 0..<planeSize {
            let norm = (outputPtr[i] - minVal) / range
            maskBytes[i] = UInt8(max(0, min(255, norm * 255.0)))
        }
        
        // 5. Crear CGImage de la Máscara y Escalar a Dimensiones Originales
        guard let maskContext = CGContext(
            data: &maskBytes,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: inputSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let smallMaskCG = maskContext.makeImage() else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        let origWidth = cgImage.width
        let origHeight = cgImage.height
        let targetRect = CGRect(x: 0, y: 0, width: origWidth, height: origHeight)
        
        // Escalar la máscara suavemente con CoreImage
        var maskCI = CIImage(cgImage: smallMaskCG)
        let scaleX = CGFloat(origWidth) / CGFloat(inputSize)
        let scaleY = CGFloat(origHeight) / CGFloat(inputSize)
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // 6. Aplicar la máscara a la imagen original
        let originalCI = CIImage(cgImage: cgImage)
        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: targetRect)
        
        let filter = CIFilter.blendWithMask()
        filter.inputImage = originalCI
        filter.backgroundImage = transparentBackground
        filter.maskImage = maskCI
        
        guard let outputCI = filter.outputImage,
              let outputCG = self.ciContext.createCGImage(outputCI, from: targetRect),
              let finalMaskCG = self.ciContext.createCGImage(maskCI, from: targetRect) else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        return (isolatedImage: PlatformImage.from(cgImage: outputCG), mask: finalMaskCG)
    }
}

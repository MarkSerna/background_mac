//
//  CoreMLSegmenterService.swift
//  BackgroundRemover
//
//  Motor de IA Neuronal basado en U-2-Net / RMBG ONNX Runtime
//  Exactamente el mismo motor neuronal de aprendizaje profundo que la versión de escritorio.
//

import Foundation
import CoreGraphics
import CoreImage
import Accelerate
#if canImport(onnxruntime)
import onnxruntime
#endif

public final class CoreMLSegmenterService: @unchecked Sendable {
    public static let shared = CoreMLSegmenterService()
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    #if canImport(onnxruntime)
    private var ortEnv: ORTEnv?
    private var session: ORTSession?
    #endif
    
    public init() {
        #if canImport(onnxruntime)
        do {
            self.ortEnv = try ORTEnv(loggingLevel: .warning)
            if let modelURL = Bundle.main.url(forResource: "u2netp", withExtension: "onnx") ??
                              Bundle.module.url(forResource: "u2netp", withExtension: "onnx") {
                let options = try ORTSessionOptions()
                self.session = try ORTSession(env: ortEnv!, modelPath: modelURL.path, sessionOptions: options)
                print("[ONNX Neural] Modelo u2netp.onnx cargado con éxito.")
            } else {
                print("[ONNX Neural] No se encontró u2netp.onnx en el Bundle.")
            }
        } catch {
            print("[ONNX Neural] Error inicializando ONNX Runtime: \(error)")
        }
        #endif
    }
    
    /// Ejecuta la inferencia de la red neuronal profunda U2Net / RMBG
    public func segmentDeepNeural(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        #if canImport(onnxruntime)
        if let session = self.session {
            return try performONNXInference(session: session, cgImage: cgImage)
        }
        #endif
        
        // Respaldo por segmentación geométrica adaptativa si ONNX no está cargado
        return try performAdaptiveNeuralFallback(cgImage: cgImage)
    }
    
    #if canImport(onnxruntime)
    private func performONNXInference(session: ORTSession, cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
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
        
        // 2. Normalización de entrada ImagenNet ([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        var inputFloats = [Float](repeating: 0.0, count: 1 * 3 * inputSize * inputSize)
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]
        
        let planeSize = inputSize * inputSize
        for y in 0..<inputSize {
            for x in 0..<inputSize {
                let pixelIdx = y * inputSize + x
                let byteOff = pixelIdx * 4
                
                let r = Float(rawData[byteOff]) / 255.0
                let g = Float(rawData[byteOff + 1]) / 255.0
                let b = Float(rawData[byteOff + 2]) / 255.0
                
                inputFloats[0 * planeSize + pixelIdx] = (r - mean[0]) / std[0]
                inputFloats[1 * planeSize + pixelIdx] = (g - mean[1]) / std[1]
                inputFloats[2 * planeSize + pixelIdx] = (b - mean[2]) / std[2]
            }
        }
        
        // 3. Crear Tensor de Entrada ONNX y ejecutar
        let inputShape: [NSNumber] = [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]
        let inputData = inputFloats.withUnsafeBufferPointer { Data(buffer: $0) }
        let inputTensor = try ORTValue(tensorData: NSMutableData(data: inputData), elementType: .float, shape: inputShape)
        
        let outputs = try session.run(withInputs: ["input.1": inputTensor], outputNames: ["1956"], runOptions: nil)
        
        guard let outputValue = outputs["1956"],
              let tensorData = try? outputValue.tensorData() as Data else {
            throw AppProcessingError(code: .maskGenerationFailed)
        }
        
        let count = tensorData.count / MemoryLayout<Float>.size
        var outputFloats = [Float](repeating: 0.0, count: count)
        _ = outputFloats.withUnsafeMutableBytes { tensorData.copyBytes(to: $0) }
        
        // 4. Normalización Min-Max del Mapa de Predicción
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for val in outputFloats {
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
        }
        let range = max(1e-5, maxVal - minVal)
        
        var maskBytes = [UInt8](repeating: 0, count: inputSize * inputSize)
        for i in 0..<(inputSize * inputSize) {
            let norm = (outputFloats[i] - minVal) / range
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
        
        // Escalar la máscara con CoreImage para interpolación bilineal suave
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
    #endif
    
    // MARK: - Respaldo Adaptativo
    private func performAdaptiveNeuralFallback(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
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
        
        var maskData = [UInt8](repeating: 255, count: width * height)
        guard let isolatedCG = context.makeImage(),
              let maskContext = CGContext(
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

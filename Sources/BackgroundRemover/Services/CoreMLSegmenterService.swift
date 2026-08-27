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
        self.initializeSessionIfNeeded()
    }
    
    private func initializeSessionIfNeeded() {
        #if canImport(onnxruntime)
        if self.session != nil { return }
        
        do {
            if self.ortEnv == nil {
                self.ortEnv = try ORTEnv(loggingLevel: .warning)
            }
            
            // Buscar u2netp.onnx en todas las rutas posibles del bundle
            let candidateURLs = [
                Bundle.main.url(forResource: "u2netp", withExtension: "onnx"),
                Bundle.main.url(forResource: "Resources/u2netp", withExtension: "onnx"),
                Bundle.main.resourceURL?.appendingPathComponent("u2netp.onnx"),
                Bundle.main.resourceURL?.appendingPathComponent("Resources/u2netp.onnx"),
                Bundle.main.bundleURL.appendingPathComponent("u2netp.onnx"),
                Bundle.main.bundleURL.appendingPathComponent("Resources/u2netp.onnx")
            ].compactMap { $0 }
            
            var foundURL: URL?
            for url in candidateURLs {
                if FileManager.default.fileExists(atPath: url.path) {
                    foundURL = url
                    break
                }
            }
            
            if let modelURL = foundURL {
                let options = try ORTSessionOptions()
                self.session = try ORTSession(env: ortEnv!, modelPath: modelURL.path, sessionOptions: options)
                print("[ONNX Neural] ✅ u2netp.onnx cargado exitosamente desde: \(modelURL.path)")
            } else {
                print("[ONNX Neural] ⚠️ No se encontró el archivo u2netp.onnx en las rutas del bundle.")
            }
        } catch {
            print("[ONNX Neural] ❌ Error inicializando sesión de ONNX: \(error)")
        }
        #endif
    }
    
    /// Ejecuta la inferencia de la red neuronal profunda U2Net / RMBG
    public func segmentDeepNeural(cgImage: CGImage) throws -> (isolatedImage: PlatformImage, mask: CGImage) {
        self.initializeSessionIfNeeded()
        
        #if canImport(onnxruntime)
        if let session = self.session {
            return try performONNXInference(session: session, cgImage: cgImage)
        }
        #endif
        
        throw AppProcessingError(code: .visionRequestFailed, underlyingMessage: "El motor de IA U2Net no pudo inicializarse.")
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
        
        // Salida principal de fusión en u2netp es '1959'
        let outputs = try session.run(withInputs: ["input.1": inputTensor], outputNames: ["1959"], runOptions: nil)
        
        guard let outputValue = outputs["1959"],
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
}

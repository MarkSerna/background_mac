//
//  ImageCompositorService.swift
//  BackgroundRemover
//
//  Servicio de composición de fondo, recorte automático (auto-crop), padding y exportación.
//

import Foundation
import CoreGraphics
import CoreImage
import SwiftUI
import CoreImage.CIFilterBuiltins

public final class ImageCompositorService {
    public static let shared = ImageCompositorService()
    
    private let ciContext: CIContext
    
    public init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [.useSoftwareRenderer: false])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    /// Aplica el fondo, recorte automático y márgenes según la configuración proporcionada.
    public func composeFinalImage(
        isolatedImage: PlatformImage,
        config: ProcessingConfig,
        originalImage: PlatformImage? = nil
    ) throws -> PlatformImage {
        guard let isolatedCG = isolatedImage.cgImageRepresentation else {
            throw AppProcessingError(code: .fileCorrupted, underlyingMessage: "No se pudo obtener el CGImage de la imagen aislada.")
        }
        
        var workingCG = isolatedCG
        
        // 1. Auto-crop y Padding si está activado
        if config.autoCrop {
            workingCG = try autoCropAndPad(cgImage: workingCG, paddingPercent: config.paddingPercent, config: config)
        }
        
        // 2. Composición de fondo
        let finalCG: CGImage
        switch config.backgroundMode {
        case .transparent:
            finalCG = workingCG
        case .white:
            finalCG = try applySolidColor(workingCG, color: .white)
        case .customColor:
            let targetColor = Color(hexString: config.customColorHex)
            finalCG = try applySolidColor(workingCG, color: targetColor)
        }
        
        return PlatformImage.from(cgImage: finalCG)
    }
    
    /// Superpone la imagen con canal alfa sobre una capa de color sólido usando CoreGraphics
    private func applySolidColor(_ cgImage: CGImage, color: Color) throws -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: "No se pudo crear el CGContext para componer el color de fondo.")
        }
        
        // Extraer componentes del color
        #if os(iOS)
        let uiColor = UIColor(color)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif os(macOS)
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent
        let a = nsColor.alphaComponent
        #endif
        
        // Rellenar fondo sólido
        context.setFillColor(red: r, green: g, blue: b, alpha: a)
        context.fill(bounds)
        
        // Dibujar el sujeto recortado encima
        context.draw(cgImage, in: bounds)
        
        guard let result = context.makeImage() else {
            throw AppProcessingError(code: .maskGenerationFailed, underlyingMessage: "Fallo al rasterizar la imagen compuesta.")
        }
        
        return result
    }
    
    /// Recorta el espacio transparente sobrante y aplica el padding porcentual
    public func autoCropAndPad(cgImage: CGImage, paddingPercent: Double, config: ProcessingConfig) throws -> CGImage {
        guard let bbox = calculateNonTransparentBoundingBox(cgImage: cgImage) else {
            return cgImage
        }
        
        guard let cropped = cgImage.cropping(to: bbox) else {
            return cgImage
        }
        
        if paddingPercent <= 0 {
            return cropped
        }
        
        // Calcular tamaño del lienzo con padding
        let cropW = Double(cropped.width)
        let cropH = Double(cropped.height)
        let padW = cropW * (paddingPercent / 100.0)
        let padH = cropH * (paddingPercent / 100.0)
        
        let newWidth = Int(cropW + (padW * 2))
        let newHeight = Int(cropH + (padH * 2))
        
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return cropped
        }
        
        // Dibujar el recorte centrado en el nuevo lienzo
        let destRect = CGRect(x: padW, y: padH, width: cropW, height: cropH)
        context.draw(cropped, in: destRect)
        
        return context.makeImage() ?? cropped
    }
    
    /// Detecta el Bounding Box de los píxeles no transparentes examinando el canal alfa
    private func calculateNonTransparentBoundingBox(cgImage: CGImage) -> CGRect? {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundAny = false
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                let alpha = rawData[pixelIndex + 3]
                
                // Umbral de opacidad (ignorar residuos menores a 20)
                if alpha > 20 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    foundAny = true
                }
            }
        }
        
        guard foundAny, minX <= maxX, minY <= maxY else { return nil }
        
        // En CoreGraphics, el eje Y se invierte al recortar
        let boxWidth = maxX - minX + 1
        let boxHeight = maxY - minY + 1
        let correctedY = height - maxY - 1
        
        return CGRect(x: minX, y: max(0, correctedY), width: boxWidth, height: boxHeight)
    }
    
    /// Codifica la imagen final al formato de archivo y calidad especificados
    public func exportData(from image: PlatformImage, format: OutputImageFormat, quality: Double) throws -> Data {
        switch format {
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: CGFloat(quality)) else {
                throw AppProcessingError(code: .exportFailed, underlyingMessage: "No se pudo codificar la imagen en formato JPEG.")
            }
            return data
        case .png:
            guard let data = image.pngData() else {
                throw AppProcessingError(code: .exportFailed, underlyingMessage: "No se pudo codificar la imagen en formato PNG.")
            }
            return data
        case .heic:
            #if os(iOS)
            if #available(iOS 17.0, *), let cg = image.cgImageRepresentation {
                let mutableData = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(mutableData, "public.heic" as CFString, 1, nil) else {
                    return image.jpegData(compressionQuality: CGFloat(quality)) ?? Data()
                }
                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: quality
                ]
                CGImageDestinationAddImage(destination, cg, options as CFDictionary)
                if CGImageDestinationFinalize(destination) {
                    return mutableData as Data
                }
            }
            return image.jpegData(compressionQuality: CGFloat(quality)) ?? Data()
            #else
            return image.jpegData(compressionQuality: CGFloat(quality)) ?? Data()
            #endif
        }
    }
}

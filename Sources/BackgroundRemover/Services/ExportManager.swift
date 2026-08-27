//
//  ExportManager.swift
//  BackgroundRemover
//
//  Gestor de exportación a Carrete de Fotos, Portapapeles del sistema y Archivos locales.
//

import Foundation
import SwiftUI
import Photos

public final class ExportManager {
    public static let shared = ExportManager()
    private let compositor = ImageCompositorService.shared
    
    public init() {}
    
    // MARK: - Guardar en Fototeca (Carrete de Fotos)
    public func saveToPhotoLibrary(image: PlatformImage, format: OutputImageFormat, quality: Double) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppProcessingError(code: .photoLibraryAccessDenied)
        }
        
        let data = try compositor.exportData(from: image, format: format, quality: quality)
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: data, options: nil)
        }
    }
    
    // MARK: - Copiar al Portapapeles
    public func copyToClipboard(image: PlatformImage, transparentIfPossible: Bool = true) -> Bool {
        #if os(iOS)
        if transparentIfPossible, let pngData = image.pngData() {
            PlatformPasteboard.general.setData(pngData, forPasteboardType: "public.png")
            return true
        } else {
            PlatformPasteboard.general.image = image
            return true
        }
        #elseif os(macOS)
        let pasteboard = PlatformPasteboard.general
        pasteboard.clearContents()
        if transparentIfPossible, let pngData = image.pngData() {
            pasteboard.setData(pngData, forType: .png)
            return true
        } else if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
            return true
        }
        return false
        #endif
    }
    
    // MARK: - Generar URL Temporal para Compartir
    public func createTemporaryExportURL(
        item: ProcessedItem,
        format: OutputImageFormat,
        quality: Double
    ) throws -> URL {
        guard let processed = item.processedImage else {
            throw AppProcessingError(code: .exportFailed, underlyingMessage: "No hay imagen procesada para exportar.")
        }
        
        let data = try compositor.exportData(from: processed, format: format, quality: quality)
        
        let baseName = (item.filename as NSString).deletingPathExtension
        let finalFilename = "\(baseName)_no_bg.\(format.fileExtension)"
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundRemoverExports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent(finalFilename)
        try data.write(to: fileURL, options: .atomic)
        
        return fileURL
    }
    
    // MARK: - Exportar Lote Completo a Directorio
    public func exportBatchToDirectory(
        items: [ProcessedItem],
        destinationDirectory: URL,
        format: OutputImageFormat,
        quality: Double
    ) throws -> [URL] {
        var exportedURLs: [URL] = []
        
        for item in items where item.status == .completed {
            guard let processed = item.processedImage else { continue }
            let data = try compositor.exportData(from: processed, format: format, quality: quality)
            
            let baseName = (item.filename as NSString).deletingPathExtension
            let finalFilename = "\(baseName)_no_bg.\(format.fileExtension)"
            let targetURL = destinationDirectory.appendingPathComponent(finalFilename)
            
            try data.write(to: targetURL, options: .atomic)
            exportedURLs.append(targetURL)
        }
        
        return exportedURLs
    }
}

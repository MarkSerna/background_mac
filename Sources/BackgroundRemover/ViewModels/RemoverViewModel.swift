//
//  RemoverViewModel.swift
//  BackgroundRemover
//
//  ViewModel principal que orquesta el estado de la aplicación, interacción y flujos de trabajo.
//

import SwiftUI
import PhotosUI

public enum ViewDisplayMode: String, CaseIterable, Identifiable {
    case single = "Editor Individual"
    case batch = "Lote de Imágenes"
    
    public var id: String { self.rawValue }
    public var iconName: String {
        switch self {
        case .single: return "photo"
        case .batch: return "square.grid.2x2"
        }
    }
}

@MainActor
public final class RemoverViewModel: ObservableObject {
    // Configuración y Servicios
    @Published public var config: ProcessingConfig
    @Published public var stats: ProcessingStats
    
    private let segmenter = VisionSegmenterService.shared
    private let compositor = ImageCompositorService.shared
    private let batchProcessor = BatchProcessorService.shared
    private let exportManager = ExportManager.shared
    private let settingsManager = SettingsManager.shared
    
    // Estado de la Interfaz
    @Published public var displayMode: ViewDisplayMode = .single
    @Published public var items: [ProcessedItem] = []
    @Published public var selectedItemId: UUID?
    
    // Estado de Ejecución y Progreso
    @Published public var isProcessing: Bool = false
    @Published public var progressValue: Double = 0.0
    @Published public var statusMessage: String = "Listo para procesar"
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false
    @Published public var showStatsSheet: Bool = false
    
    // Visor Before/After (0.0 = Todo Original, 0.5 = Mitad/Mitad, 1.0 = Todo Resultado)
    @Published public var sliderPosition: CGFloat = 0.5
    
    public init() {
        self.config = settingsManager.config
        self.stats = settingsManager.stats
    }
    
    public var selectedItem: ProcessedItem? {
        if let id = selectedItemId {
            return items.first(where: { $0.id == id })
        }
        return items.first
    }
    
    // MARK: - Carga de Imágenes
    public func addImages(_ imagesWithNames: [(image: PlatformImage, name: String)]) {
        var newItems: [ProcessedItem] = []
        
        for (img, name) in imagesWithNames {
            let item = ProcessedItem(
                filename: name,
                originalImage: img
            )
            newItems.append(item)
        }
        
        self.items.append(contentsOf: newItems)
        
        // Auto-seleccionar primer elemento si no hay ninguno
        if self.selectedItemId == nil, let first = self.items.first {
            self.selectedItemId = first.id
        }
        
        // Si se añadieron varias, pasar a vista de lote; si es 1 sola, a vista individual
        if items.count > 1 {
            self.displayMode = .batch
        } else {
            self.displayMode = .single
        }
        
        self.statusMessage = "\(items.count) imagen(es) lista(s) para procesar."
    }
    
    public func remove(item: ProcessedItem) {
        items.removeAll(where: { $0.id == item.id })
        if selectedItemId == item.id {
            selectedItemId = items.first?.id
        }
        if items.isEmpty {
            statusMessage = "Listo"
        }
    }
    
    public func clearAll() {
        items.removeAll()
        selectedItemId = nil
        statusMessage = "Listo"
        progressValue = 0.0
    }
    
    // MARK: - Procesamiento Individual
    public func processCurrentItem() async {
        guard let current = selectedItem else { return }
        await processSingleItem(id: current.id)
    }
    
    public func processSingleItem(id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        isProcessing = true
        statusMessage = "Eliminando fondo con IA..."
        progressValue = 0.3
        
        let itemToProcess = items[index]
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let processed = (try? await batchProcessor.processSingle(item: itemToProcess, config: config)) ?? itemToProcess
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        if index < items.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.items[index] = processed
                // Ajustar posición del visor para que se vea el recorte de inmediato
                self.sliderPosition = 0.5
            }
        }
        
        isProcessing = false
        progressValue = 1.0
        
        if processed.status == .completed {
            statusMessage = "¡Fondo eliminado con éxito! (\(String(format: "%.2f", elapsed))s)"
            settingsManager.recordProcessing(success: true, duration: elapsed)
        } else {
            statusMessage = "Error: \(processed.errorMessage ?? "No se pudo procesar")"
            settingsManager.recordProcessing(success: false)
            alertMessage = processed.errorMessage ?? "No se pudo procesar la imagen seleccionada."
            showAlert = true
        }
        
        self.stats = settingsManager.stats
    }
    
    // MARK: - Recomposición Rápida (Sin re-ejecutar Vision)
    public func recomposeSelected() {
        guard let selected = selectedItem,
              let proc = selected.processedImage,
              let index = items.firstIndex(where: { $0.id == selected.id }) else { return }
        
        do {
            let composed = try compositor.composeFinalImage(
                isolatedImage: proc,
                config: config,
                originalImage: selected.originalImage
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                items[index].processedImage = composed
            }
        } catch {
            print("Error en recomposición rápida: \(error)")
        }
    }
    
    // MARK: - Procesamiento en Lote
    public func processBatch() async {
        guard !items.isEmpty else { return }
        
        if items.count > config.batchLimit {
            alertMessage = "El lote contiene \(items.count) imágenes. El límite configurado es \(config.batchLimit). Procesa en lotes más pequeños para evitar cierres inesperados por consumo de RAM."
            showAlert = true
            return
        }
        
        isProcessing = true
        progressValue = 0.0
        statusMessage = "Procesando lote de \(items.count) imágenes..."
        
        var completedCount = 0
        let totalCount = items.count
        
        _ = await batchProcessor.processBatch(items: items, config: config) { [weak self] updated in
            guard let self = self else { return }
            Task { @MainActor in
                if let idx = self.items.firstIndex(where: { $0.id == updated.id }) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.items[idx] = updated
                    }
                }
                completedCount += 1
                self.progressValue = Double(completedCount) / Double(totalCount)
                self.statusMessage = "Procesadas \(completedCount) de \(totalCount)..."
                
                if updated.status == .completed, let t = updated.processingTimeSeconds {
                    self.settingsManager.recordProcessing(success: true, duration: t)
                } else if updated.status == .failed {
                    self.settingsManager.recordProcessing(success: false)
                }
                self.stats = self.settingsManager.stats
            }
        }
        
        isProcessing = false
        progressValue = 1.0
        statusMessage = "Lote finalizado (\(completedCount) fotos procesadas)."
    }
    
    public func cancelProcessing() {
        Task {
            await batchProcessor.cancel()
            self.isProcessing = false
            self.statusMessage = "Procesamiento cancelado."
        }
    }
    
    // MARK: - Acciones de Exportación
    public func copySelectedToClipboard() {
        guard let selected = selectedItem, let proc = selected.processedImage else {
            alertMessage = "No hay imagen procesada para copiar."
            showAlert = true
            return
        }
        
        let success = exportManager.copyToClipboard(image: proc, transparentIfPossible: config.backgroundMode == .transparent)
        if success {
            statusMessage = "¡Imagen copiada al portapapeles!"
        }
    }
    
    public func saveSelectedToPhotos() async {
        guard let selected = selectedItem, let proc = selected.processedImage else {
            alertMessage = "No hay imagen procesada para guardar."
            showAlert = true
            return
        }
        
        do {
            try await exportManager.saveToPhotoLibrary(image: proc, format: config.outputFormat, quality: config.outputQuality)
            statusMessage = "¡Imagen guardada en el Carrete de Fotos!"
        } catch {
            alertMessage = "No se pudo guardar en Fotos: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    public func saveBatchToPhotos() async {
        let completed = items.filter { $0.status == .completed && $0.processedImage != nil }
        guard !completed.isEmpty else {
            alertMessage = "No hay imágenes procesadas exitosamente para guardar."
            showAlert = true
            return
        }
        
        var savedCount = 0
        for item in completed {
            if let proc = item.processedImage {
                do {
                    try await exportManager.saveToPhotoLibrary(image: proc, format: config.outputFormat, quality: config.outputQuality)
                    savedCount += 1
                } catch {
                    print("Error guardando \(item.filename): \(error)")
                }
            }
        }
        
        statusMessage = "¡\(savedCount) imágenes guardadas en el Carrete de Fotos!"
    }
    
    public func updateConfig(_ newConfig: ProcessingConfig) {
        self.config = newConfig
        self.settingsManager.config = newConfig
    }
}

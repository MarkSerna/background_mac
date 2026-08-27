//
//  DropZoneView.swift
//  BackgroundRemover
//
//  Área de arrastrar y soltar (Drag & Drop) táctil con soporte para Carrete y Archivos.
//

import SwiftUI
import PhotosUI

public struct DropZoneView: View {
    @ObservedObject var viewModel: RemoverViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isTargeted: Bool = false
    @State private var showFileImporter: Bool = false
    
    public init(viewModel: RemoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isTargeted ? Color.blue : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isTargeted ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
                    )
                
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.blue)
                        .scaleEffect(isTargeted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3), value: isTargeted)
                    
                    VStack(spacing: 6) {
                        Text("Arrastra imágenes o carpetas aquí")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Soporta JPG, PNG, HEIC, WEBP y TIFF")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 14) {
                        // Selector de Fototeca (Carrete de Fotos)
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: viewModel.config.batchLimit,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Seleccionar Fotos", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .onChange(of: selectedPhotos) { _, newItems in
                            Task {
                                await loadPhotos(newItems)
                                selectedPhotos.removeAll()
                            }
                        }
                        
                        // Selector de Archivos (App Archivos / Files)
                        Button(action: { showFileImporter = true }) {
                            Label("Abrir Archivos", systemImage: "folder")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(32)
            }
            .frame(minHeight: 280)
            .padding(.horizontal)
            .dropDestination(for: Data.self) { items, location in
                handleDroppedData(items)
                return true
            } isTargeted: { targeted in
                self.isTargeted = targeted
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
        }
    }
    
    // MARK: - Manejadores de Carga
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [(PlatformImage, String)] = []
        
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                #if os(iOS)
                if let uiImg = UIImage(data: data) {
                    loaded.append((uiImg, "Foto_\(idx + 1).jpg"))
                }
                #elseif os(macOS)
                if let nsImg = NSImage(data: data) {
                    loaded.append((nsImg, "Foto_\(idx + 1).jpg"))
                }
                #endif
            }
        }
        
        if !loaded.isEmpty {
            viewModel.addImages(loaded)
        }
    }
    
    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var loaded: [(PlatformImage, String)] = []
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                if let data = try? Data(contentsOf: url) {
                    #if os(iOS)
                    if let uiImg = UIImage(data: data) {
                        loaded.append((uiImg, url.lastPathComponent))
                    }
                    #elseif os(macOS)
                    if let nsImg = NSImage(data: data) {
                        loaded.append((nsImg, url.lastPathComponent))
                    }
                    #endif
                }
            }
            if !loaded.isEmpty {
                viewModel.addImages(loaded)
            }
        case .failure(let error):
            viewModel.alertMessage = "Error al abrir archivos: \(error.localizedDescription)"
            viewModel.showAlert = true
        }
    }
    
    private func handleDroppedData(_ items: [Data]) {
        var loaded: [(PlatformImage, String)] = []
        for (idx, data) in items.enumerated() {
            #if os(iOS)
            if let uiImg = UIImage(data: data) {
                loaded.append((uiImg, "Arrastrado_\(idx + 1).png"))
            }
            #elseif os(macOS)
            if let nsImg = NSImage(data: data) {
                loaded.append((nsImg, "Arrastrado_\(idx + 1).png"))
            }
            #endif
        }
        if !loaded.isEmpty {
            viewModel.addImages(loaded)
        }
    }
}

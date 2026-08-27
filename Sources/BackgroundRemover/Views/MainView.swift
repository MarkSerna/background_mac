//
//  MainView.swift
//  BackgroundRemover
//
//  Vista principal adaptativa (NavigationSplitView) optimizada para iPad y Mac.
//

import SwiftUI
import PhotosUI
import Photos

public struct MainView: View {
    @StateObject private var viewModel = RemoverViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Barra Lateral de Controles
            ControlsSidebarView(viewModel: viewModel)
                .navigationTitle("Ajustes")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } detail: {
            // Área de Trabajo Principal
            VStack(spacing: 0) {
                // Barra de Estado y Progreso Superior
                if viewModel.isProcessing {
                    VStack(spacing: 4) {
                        ProgressView(value: viewModel.progressValue, total: 1.0)
                            .tint(.blue)
                        HStack {
                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Cancelar") {
                                viewModel.cancelProcessing()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
                
                // Contenido Central
                if viewModel.items.isEmpty {
                    VStack {
                        Spacer()
                        DropZoneView(viewModel: viewModel)
                        Spacer()
                    }
                } else {
                    if viewModel.displayMode == .single {
                        // Visor Individual Antes / Después
                        SingleEditorArea(viewModel: viewModel)
                    } else {
                        // Cuadrícula de Lote
                        BatchGridArea(viewModel: viewModel)
                    }
                }
            }
            .navigationTitle(viewModel.displayMode.rawValue)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Botón para añadir más imágenes
                    if !viewModel.items.isEmpty {
                        DropZoneMiniButton(viewModel: viewModel)
                    }
                    
                    // Estadísticas
                    Button(action: { viewModel.showStatsSheet = true }) {
                        Label("Estadísticas", systemImage: "chart.bar.xaxis")
                    }
                    
                    // Limpiar todo
                    if !viewModel.items.isEmpty {
                        Button(role: .destructive, action: { viewModel.clearAll() }) {
                            Label("Limpiar", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showStatsSheet) {
                StatsModalView(viewModel: viewModel)
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(
                    title: Text("Aviso"),
                    message: Text(viewModel.alertMessage ?? ""),
                    dismissButton: .default(Text("Entendido"))
                )
            }
        }
    }
}

// MARK: - Visor de Editor Individual
struct SingleEditorArea: View {
    @ObservedObject var viewModel: RemoverViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            if let selected = viewModel.selectedItem {
                BeforeAfterSliderView(
                    originalImage: selected.originalImage,
                    processedImage: selected.processedImage,
                    sliderPosition: $viewModel.sliderPosition
                )
                .padding()
                
                // Tira de miniaturas inferior si hay múltiples fotos
                if viewModel.items.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.items) { item in
                                ThumbnailItemView(
                                    item: item,
                                    isSelected: viewModel.selectedItemId == item.id
                                ) {
                                    viewModel.selectedItemId = item.id
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .frame(height: 75)
                }
            }
        }
    }
}

// MARK: - Área de Cuadrícula de Lotes
struct BatchGridArea: View {
    @ObservedObject var viewModel: RemoverViewModel
    
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.items) { item in
                    BatchGridCardView(
                        item: item,
                        isSelected: viewModel.selectedItemId == item.id,
                        onSelect: {
                            viewModel.selectedItemId = item.id
                        },
                        onProcessSingle: {
                            Task {
                                await viewModel.processSingleItem(id: item.id)
                            }
                        },
                        onDelete: {
                            viewModel.remove(item: item)
                        }
                    )
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Miniatura para la Tira Inferior
struct ThumbnailItemView: View {
    let item: ProcessedItem
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if let proc = item.processedImage {
                    Image(platformImage: proc)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(platformImage: item.originalImage)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
            )
        }
    }
}

// MARK: - Botón Miniatura para Añadir Imágenes
struct DropZoneMiniButton: View {
    @ObservedObject var viewModel: RemoverViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    var body: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: viewModel.config.batchLimit,
            matching: .images
        ) {
            Image(systemName: "plus")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                var loaded: [(PlatformImage, String)] = []
                for (idx, item) in newItems.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        #if os(iOS)
                        if let img = UIImage(data: data) {
                            loaded.append((img, "Foto_\(viewModel.items.count + idx + 1).jpg"))
                        }
                        #elseif os(macOS)
                        if let img = NSImage(data: data) {
                            loaded.append((img, "Foto_\(viewModel.items.count + idx + 1).jpg"))
                        }
                        #endif
                    }
                }
                if !loaded.isEmpty {
                    viewModel.addImages(loaded)
                }
                selectedPhotos.removeAll()
            }
        }
    }
}

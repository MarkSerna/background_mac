//
//  ControlsSidebarView.swift
//  BackgroundRemover
//
//  Barra lateral de ajustes y controles táctiles para iPadOS / macOS.
//

import SwiftUI

public struct ControlsSidebarView: View {
    @ObservedObject var viewModel: RemoverViewModel
    
    public init(viewModel: RemoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Selector de Modo de Vista (Individual vs Lote)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODO DE TRABAJO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Picker("Modo", selection: $viewModel.displayMode) {
                        ForEach(ViewDisplayMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider()
                
                // Color y Modo de Fondo
                VStack(alignment: .leading, spacing: 10) {
                    Text("FONDO DE SALIDA")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    ColorPalettePicker(
                        backgroundMode: $viewModel.config.backgroundMode,
                        customColorHex: $viewModel.config.customColorHex
                    ) {
                        viewModel.recomposeSelected()
                    }
                }
                
                Divider()
                
                // Formato y Calidad
                VStack(alignment: .leading, spacing: 12) {
                    Text("FORMATO DE EXPORTACIÓN")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Picker("Formato", selection: $viewModel.config.outputFormat) {
                        ForEach(OutputImageFormat.allCases) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if viewModel.config.outputFormat != .png {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Calidad de Compresión")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(viewModel.config.outputQuality * 100))%")
                                    .font(.caption.weight(.semibold))
                            }
                            
                            Slider(value: $viewModel.config.outputQuality, in: 0.5...1.0, step: 0.05)
                                .tint(.blue)
                        }
                    }
                }
                
                Divider()
                
                // Ajustes Geométricos (Auto-Crop y Padding)
                VStack(alignment: .leading, spacing: 12) {
                    Text("AJUSTES GEOMÉTRICOS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Toggle(isOn: $viewModel.config.autoCrop) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recorte Automático")
                                .font(.subheadline)
                            Text("Ajusta el lienzo al sujeto")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: viewModel.config.autoCrop) { _, _ in
                        viewModel.recomposeSelected()
                    }
                    
                    if viewModel.config.autoCrop {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Margen (Padding)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(viewModel.config.paddingPercent))%")
                                    .font(.caption.weight(.semibold))
                            }
                            
                            Slider(value: $viewModel.config.paddingPercent, in: 0...30, step: 1)
                                .tint(.blue)
                                .onChange(of: viewModel.config.paddingPercent) { _, _ in
                                    viewModel.recomposeSelected()
                                }
                        }
                    }
                }
                
                Divider()
                
                // Límite de Lote
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("LÍMITE POR LOTE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(viewModel.config.batchLimit) fotos")
                            .font(.caption.weight(.semibold))
                    }
                    
                    Stepper("Límite: \(viewModel.config.batchLimit)", value: $viewModel.config.batchLimit, in: 5...50, step: 5)
                        .labelsHidden()
                    
                    Text("Recomendado 20 fotos para optimizar el uso de memoria.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 20)
                
                // Botones de Acción Primaria
                VStack(spacing: 10) {
                    if viewModel.displayMode == .single {
                        // Procesar Individual
                        Button(action: {
                            Task {
                                await viewModel.processCurrentItem()
                            }
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text(viewModel.selectedItem?.processedImage != nil ? "Re-procesar Imagen" : "Eliminar Fondo")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
                        
                        // Copiar al Portapapeles
                        Button(action: {
                            viewModel.copySelectedToClipboard()
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copiar al Portapapeles")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.selectedItem?.processedImage == nil)
                        
                        // Guardar en Fotos
                        Button(action: {
                            Task {
                                await viewModel.saveSelectedToPhotos()
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Guardar en Fotos")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.selectedItem?.processedImage == nil)
                        
                    } else {
                        // Procesar Lote
                        Button(action: {
                            Task {
                                await viewModel.processBatch()
                            }
                        }) {
                            HStack {
                                Image(systemName: "sparkles.rectangle.stack")
                                Text("Procesar Todo el Lote (\(viewModel.items.count))")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
                        
                        // Guardar Lote en Fotos
                        Button(action: {
                            Task {
                                await viewModel.saveBatchToPhotos()
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.on.square")
                                Text("Guardar Lote en Fotos")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.items.filter { $0.status == .completed }.isEmpty)
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        .background(Color.primary.opacity(0.02))
    }
}

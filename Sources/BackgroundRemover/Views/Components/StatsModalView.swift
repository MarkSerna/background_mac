//
//  StatsModalView.swift
//  BackgroundRemover
//
//  Modal de estadísticas y métricas acumuladas de rendimiento.
//

import SwiftUI

public struct StatsModalView: View {
    @ObservedObject var viewModel: RemoverViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: RemoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Tarjetas de Métricas Principales
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    MetricCard(
                        title: "Total Procesadas",
                        value: "\(viewModel.stats.totalProcessedCount)",
                        icon: "photo.stack",
                        color: .blue
                    )
                    
                    MetricCard(
                        title: "Tasa de Éxito",
                        value: String(format: "%.1f%%", viewModel.stats.successRatePercent),
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                    
                    MetricCard(
                        title: "Completadas",
                        value: "\(viewModel.stats.successCount)",
                        icon: "hand.thumbsup.fill",
                        color: .teal
                    )
                    
                    MetricCard(
                        title: "Velocidad Media",
                        value: String(format: "%.2fs", viewModel.stats.averageTimePerImage),
                        icon: "bolt.fill",
                        color: .orange
                    )
                }
                .padding(.horizontal)
                
                // Resumen
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detalles de Rendimiento")
                        .font(.headline)
                    
                    HStack {
                        Text("Tiempo total acumulado:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f segundos", viewModel.stats.totalProcessingTimeSeconds))
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Última ejecución:")
                            .foregroundColor(.secondary)
                        Spacer()
                        if let lastDate = viewModel.stats.lastProcessedDate {
                            Text(lastDate, style: .date)
                                .fontWeight(.semibold)
                        } else {
                            Text("Sin registros")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(16)
                .padding(.horizontal)
                
                Spacer()
                
                // Botón Restablecer Estadísticas
                Button(role: .destructive, action: {
                    SettingsManager.shared.resetStats()
                    viewModel.stats = SettingsManager.shared.stats
                }) {
                    Label("Restablecer Historial", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.top, 16)
            .navigationTitle("Estadísticas y Métricas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(color.opacity(0.08))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

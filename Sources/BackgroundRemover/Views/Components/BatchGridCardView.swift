//
//  BatchGridCardView.swift
//  BackgroundRemover
//
//  Tarjeta de previsualización para la cuadrícula del lote con estado en tiempo real.
//

import SwiftUI

public struct BatchGridCardView: View {
    let item: ProcessedItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onProcessSingle: () -> Void
    let onDelete: () -> Void
    
    public init(
        item: ProcessedItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onProcessSingle: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onProcessSingle = onProcessSingle
        self.onDelete = onDelete
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Miniatura
                ZStack {
                    CheckerboardBackground()
                        .opacity(0.12)
                    
                    if let processed = item.processedImage {
                        Image(platformImage: processed)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(platformImage: item.originalImage)
                            .resizable()
                            .scaledToFit()
                    }
                    
                    // Indicador de carga
                    if item.status == .processing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.3)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Botón eliminar flotante
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .background(Circle().fill(Color.white))
                }
                .padding(6)
            }
            
            // Metadatos
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    // Badge de Estado
                    HStack(spacing: 4) {
                        Image(systemName: item.status.iconName)
                            .font(.system(size: 9))
                        Text(item.status.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.badgeColor.opacity(0.15))
                    .foregroundColor(item.status.badgeColor)
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    if let time = item.processingTimeSeconds {
                        Text(String(format: "%.2fs", time))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(action: onProcessSingle) {
                Label("Procesar esta imagen", systemImage: "sparkles")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Eliminar del lote", systemImage: "trash")
            }
        }
    }
}

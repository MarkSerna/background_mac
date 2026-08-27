//
//  ColorPalettePicker.swift
//  BackgroundRemover
//
//  Selector de color rápido con presets populares, selector nativo y modo transparente.
//

import SwiftUI

public struct ColorPalettePicker: View {
    @Binding var backgroundMode: BackgroundMode
    @Binding var customColorHex: String
    var onColorChanged: (() -> Void)?
    
    let presets: [(name: String, hex: String)] = [
        ("Blanco Puro", "#FFFFFF"),
        ("Gris Estudio", "#F3F4F6"),
        ("Gris Claro", "#E5E7EB"),
        ("Crema Suave", "#FEF3C7"),
        ("Azul Pastel", "#E0F2FE"),
        ("Negro Profundo", "#000000")
    ]
    
    public init(
        backgroundMode: Binding<BackgroundMode>,
        customColorHex: Binding<String>,
        onColorChanged: (() -> Void)? = nil
    ) {
        self._backgroundMode = backgroundMode
        self._customColorHex = customColorHex
        self.onColorChanged = onColorChanged
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Modos principales: Blanco / Color / Transparente
            Picker("Modo de Fondo", selection: $backgroundMode) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: backgroundMode) { _, _ in
                onColorChanged?()
            }
            
            // Si está en modo Color, mostrar presets y ColorPicker nativo
            if backgroundMode == .customColor {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preajustes de Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.hex) { preset in
                                Button(action: {
                                    customColorHex = preset.hex
                                    onColorChanged?()
                                }) {
                                    Circle()
                                        .fill(Color(hexString: preset.hex))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(customColorHex.uppercased() == preset.hex.uppercased() ? Color.blue : Color.gray.opacity(0.3), lineWidth: customColorHex.uppercased() == preset.hex.uppercased() ? 2.5 : 1)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .help(preset.name)
                            }
                            
                            // ColorPicker personalizado de iOS / macOS
                            ColorPicker("", selection: Binding(
                                get: { Color(hexString: customColorHex) },
                                set: { newColor in
                                    customColorHex = newColor.toHex()
                                    onColorChanged?()
                                }
                            ))
                            .labelsHidden()
                            .scaleEffect(1.1)
                            .padding(.leading, 4)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

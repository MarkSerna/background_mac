//
//  BeforeAfterSliderView.swift
//  BackgroundRemover
//
//  Visor táctil interactivo con comparación Antes/Después mediante deslizador divisor.
//

import SwiftUI

public struct BeforeAfterSliderView: View {
    let originalImage: PlatformImage
    let processedImage: PlatformImage?
    @Binding var sliderPosition: CGFloat // 0.0 a 1.0
    
    @State private var dragOffset: CGFloat = 0
    @State private var currentZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    
    public init(
        originalImage: PlatformImage,
        processedImage: PlatformImage?,
        sliderPosition: Binding<CGFloat>
    ) {
        self.originalImage = originalImage
        self.processedImage = processedImage
        self._sliderPosition = sliderPosition
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let splitX = width * sliderPosition
            
            ZStack {
                // Fondo cuadriculado para visualizar transparencias
                CheckerboardBackground()
                    .opacity(0.15)
                
                // Imagen Original (Lado Izquierdo / Fondo Completo)
                Image(platformImage: originalImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                
                // Imagen Procesada (Lado Derecho / Recortada por máscara de split)
                if let processed = processedImage {
                    Image(platformImage: processed)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: height)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: max(0, splitX))
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: max(0, width - splitX))
                            }
                        )
                }
                
                // Línea divisoria y tirador táctil
                if processedImage != nil {
                    // Línea vertical
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 0)
                        .position(x: splitX, y: height / 2)
                    
                    // Botón Circular de Arrastre Táctil
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                        )
                        .position(x: splitX, y: height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newPos = value.location.x / width
                                    sliderPosition = min(max(newPos, 0.0), 1.0)
                                }
                        )
                    
                    // Etiquetas flotantes 'Original' y 'Resultado'
                    VStack {
                        HStack {
                            Text("ORIGINAL")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(.leading, 12)
                            
                            Spacer()
                            
                            Text("RESULTADO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(.trailing, 12)
                        }
                        .padding(.top, 12)
                        
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Patrón de Tablero para Transparencia
struct CheckerboardBackground: View {
    let squareSize: CGFloat = 16
    
    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / squareSize) + 1
            let rows = Int(size.height / squareSize) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    if (row + col) % 2 == 0 {
                        let rect = CGRect(
                            x: CGFloat(col) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )
                        context.fill(Path(rect), with: .color(.gray))
                    }
                }
            }
        }
    }
}

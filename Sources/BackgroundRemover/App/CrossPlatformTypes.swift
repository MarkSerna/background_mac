//
//  CrossPlatformTypes.swift
//  BackgroundRemover
//
//  Capa de compatibilidad multiplataforma unificada para iOS, iPadOS y macOS.
//

import SwiftUI
import CoreGraphics
import CoreImage

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
public typealias PlatformPasteboard = UIPasteboard

extension Image {
    public init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension PlatformImage {
    /// Extrae de forma 100% confiable un CGImage normalizado y orientado en posición .up
    public var cgImageRepresentation: CGImage? {
        if let cg = self.cgImage, self.imageOrientation == .up {
            return cg
        }
        
        // Si tiene orientación distinta a .up o proviene de CIImage / PhotosUI
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Trabajar en píxeles reales 1:1
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        let normalizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
        
        if let cg = normalizedImage.cgImage {
            return cg
        }
        
        if let ci = self.ciImage {
            let ctx = CIContext(options: nil)
            return ctx.createCGImage(ci, from: ci.extent)
        }
        
        return self.cgImage
    }
    
    public static func from(cgImage: CGImage) -> PlatformImage {
        return UIImage(cgImage: cgImage)
    }
    
    public static func from(ciImage: CIImage, context: CIContext) -> PlatformImage? {
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
public typealias PlatformPasteboard = NSPasteboard

extension Image {
    public init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension PlatformImage {
    public var cgImageRepresentation: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    
    public static func from(cgImage: CGImage) -> PlatformImage {
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    public static func from(ciImage: CIImage, context: CIContext) -> PlatformImage? {
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    public func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
    
    public func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

// MARK: - Color Parsing Helpers
extension Color {
    public init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    public func toHex() -> String {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #elseif os(macOS)
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(rgbColor.redComponent * 255), Int(rgbColor.greenComponent * 255), Int(rgbColor.blueComponent * 255))
        #endif
    }
}

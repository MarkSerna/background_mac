//
//  ErrorCatalog.swift
//  BackgroundRemover
//
//  Catálogo formal de errores y excepciones estructuradas del sistema.
//

import Foundation

public enum AppErrorCode: String, CaseIterable, Identifiable {
    // 1000 - Configuración & Parámetros
    case invalidColorFormat = "ERR_1001"
    case invalidPaddingValue = "ERR_1002"
    case batchLimitExceeded = "ERR_1003"
    
    // 1100 - Archivos & Entrada/Salida
    case unsupportedImageFormat = "ERR_1101"
    case fileReadPermissionDenied = "ERR_1102"
    case fileCorrupted = "ERR_1103"
    case exportFailed = "ERR_1104"
    case photoLibraryAccessDenied = "ERR_1105"
    
    // 1200 - Inferencia de IA & Vision
    case visionRequestFailed = "ERR_1201"
    case maskGenerationFailed = "ERR_1202"
    case neuralEngineUnavailable = "ERR_1203"
    case emptyForegroundDetected = "ERR_1204"
    case imageTooLargeForMemory = "ERR_1205"
    
    // 1300 - Procesamiento & Concurrencia
    case processingCancelled = "ERR_1301"
    case workerTimeout = "ERR_1302"
    case circuitBreakerOpen = "ERR_1303"
    
    public var id: String { self.rawValue }
    
    public var description: String {
        switch self {
        case .invalidColorFormat:
            return "Formato de color hexadecimal no válido."
        case .invalidPaddingValue:
            return "El valor de padding debe estar entre 0% y 50%."
        case .batchLimitExceeded:
            return "Se superó el límite de imágenes simultáneas en lote para proteger la memoria RAM."
        case .unsupportedImageFormat:
            return "Formato de imagen no soportado. Usa JPG, PNG, HEIC, WEBP o TIFF."
        case .fileReadPermissionDenied:
            return "Permiso denegado para leer el archivo seleccionado."
        case .fileCorrupted:
            return "El archivo de imagen está dañado o no contiene datos decodificables."
        case .exportFailed:
            return "Error al guardar o exportar la imagen procesada."
        case .photoLibraryAccessDenied:
            return "Acceso denegado a la Fototeca (Carrete). Activa el permiso en Ajustes."
        case .visionRequestFailed:
            return "Fallo en el servicio de segmentación de Apple Vision Framework."
        case .maskGenerationFailed:
            return "No se pudo extraer la máscara alfa de primer plano."
        case .neuralEngineUnavailable:
            return "El motor de inferencia neuronal no pudo responder a tiempo."
        case .emptyForegroundDetected:
            return "No se detectó ningún sujeto en primer plano para aislar."
        case .imageTooLargeForMemory:
            return "La resolución de la imagen supera el límite seguro de memoria del dispositivo."
        case .processingCancelled:
            return "El procesamiento fue cancelado por el usuario."
        case .workerTimeout:
            return "El tiempo de procesamiento excedió el límite máximo."
        case .circuitBreakerOpen:
            return "Múltiples fallos consecutivos detectados; pausa de seguridad activa."
        }
    }
}

public struct AppProcessingError: LocalizedError, Equatable {
    public let code: AppErrorCode
    public let underlyingMessage: String?
    
    public init(code: AppErrorCode, underlyingMessage: String? = nil) {
        self.code = code
        self.underlyingMessage = underlyingMessage
    }
    
    public var errorDescription: String? {
        if let underlying = underlyingMessage, !underlying.isEmpty {
            return "[\(code.rawValue)] \(code.description) (\(underlying))"
        }
        return "[\(code.rawValue)] \(code.description)"
    }
}

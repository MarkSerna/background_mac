//
//  BackgroundRemoverTests.swift
//  BackgroundRemoverTests
//
//  Pruebas unitarias para la lógica de configuración, errores y estadísticas.
//

import XCTest
@testable import BackgroundRemover
import SwiftUI

final class BackgroundRemoverTests: XCTestCase {
    
    func testDefaultConfigInitialization() {
        let config = ProcessingConfig()
        XCTAssertEqual(config.backgroundMode, .white)
        XCTAssertEqual(config.outputFormat, .jpeg)
        XCTAssertEqual(config.outputQuality, 0.95)
        XCTAssertFalse(config.autoCrop)
        XCTAssertEqual(config.paddingPercent, 5.0)
        XCTAssertEqual(config.batchLimit, 20)
    }
    
    func testHexColorParsing() {
        let whiteHex = "#FFFFFF"
        let color = Color(hexString: whiteHex)
        XCTAssertEqual(color.toHex().uppercased(), "#FFFFFF")
        
        let blackHex = "#000000"
        let blackColor = Color(hexString: blackHex)
        XCTAssertEqual(blackColor.toHex().uppercased(), "#000000")
    }
    
    func testStatsRecording() {
        var stats = ProcessingStats()
        XCTAssertEqual(stats.totalProcessedCount, 0)
        XCTAssertEqual(stats.successRatePercent, 100.0)
        
        stats.recordSuccess(duration: 0.15)
        stats.recordSuccess(duration: 0.25)
        stats.recordFailure()
        
        XCTAssertEqual(stats.totalProcessedCount, 3)
        XCTAssertEqual(stats.successCount, 2)
        XCTAssertEqual(stats.failureCount, 1)
        XCTAssertEqual(stats.averageTimePerImage, 0.20, accuracy: 0.001)
        XCTAssertEqual(stats.successRatePercent, (2.0 / 3.0) * 100.0, accuracy: 0.01)
    }
    
    func testErrorCodeCatalog() {
        let err = AppProcessingError(code: .batchLimitExceeded, underlyingMessage: "35 > 20")
        XCTAssertTrue(err.errorDescription?.contains("ERR_1003") == true)
        XCTAssertTrue(err.errorDescription?.contains("memoria RAM") == true)
    }
}

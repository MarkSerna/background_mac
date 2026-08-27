//
//  BackgroundRemoverApp.swift
//  BackgroundRemover
//
//  Punto de entrada principal para la aplicación SwiftUI en iPadOS, iOS y macOS.
//

import SwiftUI

@main
public struct BackgroundRemoverApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainView()
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 650)
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #endif
    }
}

# AGENTS.md — Background Remover (iPadOS & macOS)

Este documento sirve como memoria técnica, contexto operativo y guía de desarrollo para cualquier IA o desarrollador que continúe el trabajo en este repositorio.

---

## 📌 1. Identidad y Propósito del Proyecto

* **Repositorio GitHub:** [https://github.com/MarkSerna/background_mac.git](https://github.com/MarkSerna/background_mac.git)
* **Objetivo:** Port nativo oficial en Swift/SwiftUI para **iPadOS (17.0+)** y **macOS (14.0+)** basado en la funcionalidad del proyecto de escritorio en Python (`background_remover`).
* **Entorno de Desarrollo del Usuario:** Windows PC (sin Mac física directa). El desarrollo y las compilaciones nativas se realizan mediante **GitHub Actions** en runners `macos-14` y las pruebas interactivas se ejecutan en el simulador web de **Appetize.io**.

---

## 🧠 2. Arquitectura de IA y Motores de Segmentación (Híbrido)

La aplicación utiliza una arquitectura de IA dual e inteligente para garantizar recorte perfecto en cualquier condición:

### A. Motor Nativo Apple Vision (`VisionSegmenterService.swift`)
* Utiliza `VNGenerateForegroundInstanceMaskRequest` y `VNGeneratePersonSegmentationRequest`.
* **Dispositivo destino:** iPad físico y Mac con chip Apple Silicon (M1/M2/M4/A14+).
* **Rendimiento:** Ultrarrápido (< 50 ms) procesado directamente por el **Apple Neural Engine (ANE)**.

### B. Motor Deep Neural CoreML (`CoreMLSegmenterService.swift`)
* Utiliza la red neuronal profunda **U-2-Net (`u2netp.mlmodelc`)** preentrenada para segmentación de objetos complejos, productos transparentes, vidrio, cabello y joyería.
* **Manejo de Unidades de Cómputo (`computeUnits`):**
  * En **Simulador / Appetize.io**: Utiliza `config.computeUnits = .cpuOnly` y `CIContext(options: [.useSoftwareRenderer: true])` para evitar errores de contexto GPU en entornos virtualizados sin Metal físico (`Could not create inference context`).
  * En **iPad Físico**: Utiliza `config.computeUnits = .all` para aprovechar el Neural Engine.

### C. Selector de IA en la Interfaz (`AIEngineMode`)
* `.auto`: Intenta Apple Vision nativo y conmuta a CoreML Deep Neural si es necesario.
* `.appleVision`: Fuerza inferencia por Apple Neural Engine.
* `.coreML`: Fuerza inferencia por la red neuronal U-2-Net.

---

## 🛠️ 3. Estructura del Código Fuente

```
background_mac/
├── .github/workflows/
│   └── build_appetize.yml     # CI/CD: Compilación en macOS-14, generación de CoreML y artefacto .zip para Appetize.io
├── Sources/BackgroundRemover/
│   ├── App/
│   │   ├── BackgroundRemoverApp.swift   # Entrypoint @main de SwiftUI
│   │   └── CrossPlatformTypes.swift     # Abstracción UIImage/NSImage, normalización de rotación y CGImage
│   ├── Models/
│   │   ├── ProcessingConfig.swift       # AIEngineMode, BackgroundMode (Blanco, Color, Transparente), Formatos, AutoCrop
│   │   ├── ProcessedItem.swift          # Estado individual de cada imagen en lote
│   │   └── AppProcessingError.swift     # Errores tipados con códigos de diagnóstico
│   ├── Services/
│   │   ├── VisionSegmenterService.swift # Orquestador de IA Apple Vision + CoreML
│   │   ├── CoreMLSegmenterService.swift # Inferencia profunda U-2-Net con MLModel nativo
│   │   ├── ImageCompositorService.swift # Composición sobre blanco/color, detección de límites y Auto-Crop con padding
│   │   ├── BatchProcessorService.swift  # Procesamiento concurrente de lotes con throttling de memoria RAM
│   │   ├── ExportManager.swift          # Guardado en Carrete de Fotos (PhotosUI/PHPhotoLibrary) y Portapapeles
│   │   └── SettingsManager.swift        # Persistencia en UserDefaults y estadísticas
│   ├── ViewModels/
│   │   └── RemoverViewModel.swift       # ViewModel principal con @MainActor y estado reactivo
│   ├── Views/
│   │   ├── MainView.swift               # Vista principal NavigationSplitView (Sidebar + Canvas)
│   │   ├── Components/
│   │   │   ├── BeforeAfterSliderView.swift  # Deslizador interactivo táctil Antes/Después con fondo cuadriculado
│   │   │   ├── DropZoneView.swift           # Zona Drag & Drop y selector PhotosPicker
│   │   │   ├── BatchGridCardView.swift      # Tarjetas de estado en cuadrícula de lotes
│   │   │   └── ColorPalettePicker.swift     # Selector de fondo Blanco / Color / Transparente
│   │   └── Sidebars/
│   │       └── ControlsSidebarView.swift    # Barra lateral con controles táctiles de iPadOS
│   └── Resources/
│       ├── Info.plist                   # Permisos de Carrete (NSPhotoLibraryAddUsageDescription)
│       └── u2netp.onnx                  # Modelo de red neuronal base
├── convert_model.py                     # Script Python para compilar ONNX a CoreML (.mlpackage / .mlmodelc)
├── project.yml                          # Especificación XcodeGen (objectVersion: 56 para Xcode 15/16)
└── Package.swift                        # Swift Package Manager manifest
```

---

## ⚙️ 4. Reglas Críticas de Compilación y Empaquetado

1. **Compatibilidad con XcodeGen y Xcode 16:**
   * En `project.yml`, mantener siempre `objectVersion: 56`.
   * En `sources`, excluir `Info.plist` (`excludes: ["Info.plist"]`) y apuntar `INFOPLIST_FILE: Sources/BackgroundRemover/Info.plist` con `GENERATE_INFOPLIST_FILE: NO` para evitar errores de comandos duplicados (`Multiple commands produce ... Info.plist`).
2. **Cero Dependencias Dinámicas Externas en Simulador:**
   * No usar `.dylib` o frameworks dinámicos externos no firmados en Appetize. Toda la inferencia debe ser a través de **`import CoreML` nativo de Apple**.
3. **Estructura del Artefacto para Appetize.io:**
   * `actions/upload-artifact@v4` debe recibir directamente la ruta de la carpeta `.app` (`path: build/DerivedData/Build/Products/Release-iphonesimulator/BackgroundRemoverApp.app`).
   * GitHub Actions empaqueta automáticamente esa carpeta en un `.zip` que al descargarse contiene `BackgroundRemoverApp.app` directamente en la raíz, cumpliendo la exigencia de Appetize.io.

---

## 🧪 5. Flujo de Trabajo para Nuevos Cambios

1. Modificar o añadir código en `Sources/BackgroundRemover/...`.
2. Hacer commit y push a la rama `main`:
   ```bash
   git add .
   git commit -m "feat/fix: descripción del cambio"
   git push origin main
   ```
3. GitHub Actions compilará automáticamente en ~1-2 minutos.
4. Descargar el archivo `BackgroundRemover-Simulator.zip` desde la pestaña **Actions $\rightarrow$ Artifacts**.
5. Subir el archivo descargado a [Appetize.io/upload](https://appetize.io/upload) y probar en el iPad virtual.

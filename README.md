# 📱 Background Remover para iPadOS / macOS

Aplicación nativa de alto rendimiento desarrollada en **Swift y SwiftUI** para **iPadOS 17+**, **iOS 17+** y **macOS 14+**. Reemplaza y elimina fondos de imágenes automáticamente utilizando el **Apple Neural Engine (ANE)** y **Apple Vision Framework** para inferencias ultra-rápidas directamente en el dispositivo (100% *On-Device* y *Offline*).

---

## ✨ Características Principales

* 🧠 **Inferencia Neural On-Device (< 100 ms):** Utiliza `VNGenerateForegroundInstanceMaskRequest` de Apple Vision para recortar sujetos con máxima fidelidad sin consumir servidores externos ni requerir conexión a internet.
* 🎨 **Fondos Flexibles:**
  * **Blanco Puro** (`#FFFFFF`) ideal para catálogos y e-commerce.
  * **Color Personalizado** con paleta de preajustes y selector nativo de iOS.
  * **Transparencia Total** con exportación en formato PNG.
* ✂️ **Recorte Automático Inteligente (*Auto-Crop*):** Ajusta el lienzo eliminando el espacio sobrante y añade un margen porcentual uniforme (*Padding* de 0% a 30%).
* 👆 **Visor Táctil Interactivo (*Before / After*):** Control deslizante táctil con divisor para comparar en tiempo real la foto original y el resultado recortado.
* ⚡ **Procesamiento por Lotes Concurrente:** Procesamiento de múltiples imágenes en paralelo utilizando `TaskGroup` con límite de seguridad (por defecto 20 fotos) para garantizar la estabilidad de la memoria RAM del iPad.
* 📱 **Integración Total con iPadOS:**
  * **Drag & Drop Táctil:** Arrastra fotos directamente desde Safari, Archivos u otra app con multitarea (Split View / Slide Over).
  * **Carrete de Fotos (`PhotosUI`):** Selector múltiple y guardado en 1 toque en la Fototeca.
  * **Portapapeles del Sistema:** Copia la imagen sin fondo para pegarla al instante en Keynote, Pages, Procreate, Canva o WhatsApp.
  * **App Archivos:** Selector nativo para importar o exportar directorios.
* 📊 **Métricas y Estadísticas:** Registro histórico de fotos procesadas, velocidad media y tasa de éxito.
* ⚙️ **Persistencia en `UserDefaults`:** Recuerda automáticamente tus preferencias de color, formato y calidad.

---

## 🏗️ Arquitectura del Proyecto

```
background_mac/
├── Package.swift                                # Manifiesto Swift Package Manager (Xcode / Playgrounds)
├── README.md                                    # Documentación técnica general
├── docs/
│   └── GUIA_IPAD.md                            # Guía de usuario paso a paso para iPad
├── Sources/
│   └── BackgroundRemover/
│       ├── App/
│       │   ├── BackgroundRemoverApp.swift      # Punto de entrada de la aplicación SwiftUI
│       │   └── CrossPlatformTypes.swift        # Puente multiplataforma unificado (iOS / macOS)
│       ├── Models/
│       │   ├── ProcessingConfig.swift          # Dataclasses de configuración tipada
│       │   ├── ProcessedItem.swift             # Estado de cada imagen (Pendiente, Éxito, Error)
│       │   ├── ErrorCatalog.swift              # Catálogo formal de errores (ERR_1001 a ERR_1303)
│       │   └── ProcessingStats.swift           # Métricas acumuladas y tiempos de inferencia
│       ├── Services/
│       │   ├── VisionSegmenterService.swift    # Inferencia con Apple Vision Framework (Neural Engine)
│       │   ├── ImageCompositorService.swift    # Composición CoreImage/CoreGraphics, Auto-Crop y Padding
│       │   ├── BatchProcessorService.swift     # Concurrencia asíncrona (TaskGroup con throttling)
│       │   ├── SettingsManager.swift           # Persistencia en UserDefaults
│       │   └── ExportManager.swift             # Exportación a Carrete, Archivos y Portapapeles
│       ├── ViewModels/
│       │   └── RemoverViewModel.swift          # Orquestador del estado y lógica reactiva
│       └── Views/
│           ├── MainView.swift                  # Vista raíz adaptativa (NavigationSplitView)
│           ├── Components/
│           │   ├── BeforeAfterSliderView.swift # Deslizador táctil interactivo Antes/Después
│           │   ├── DropZoneView.swift          # Área visual para Drag & Drop y selección
│           │   ├── BatchGridCardView.swift     # Tarjetas de lote con miniaturas y badges de estado
│           │   ├── ColorPalettePicker.swift    # Selector de colores con presets rápidos
│           │   └── StatsModalView.swift        # Hoja modal de métricas y rendimiento
│           └── Sidebars/
│               └── ControlsSidebarView.swift   # Panel lateral de ajustes y acciones
└── Tests/
    └── BackgroundRemoverTests/
        └── BackgroundRemoverTests.swift        # Suite de pruebas unitarias
```

---

## 🚀 Cómo Abrir y Ejecutar el Proyecto

### Opción 1: En un Mac con Xcode
1. Abre la carpeta `background_mac` en **Xcode** haciendo doble clic sobre `Package.swift` o seleccionando *File > Open*.
2. Selecciona el destino de ejecución (por ejemplo: **iPad Pro (11-inch)** en el Simulador o tu propio **iPad físico** conectado por cable/Wi-Fi).
3. Presiona `Cmd + R` para compilar y ejecutar.

### Opción 2: Directamente en el iPad con Swift Playgrounds
1. Copia la carpeta del proyecto a la app **Archivos** de tu iPad o vía **iCloud Drive**.
2. Abre la app **Swift Playgrounds** en tu iPad y selecciona *Abrir Proyecto de App*.
3. Ejecuta la app directamente en pantalla completa.

---

## 🧪 Pruebas Unitarias

Para ejecutar las pruebas en Mac o terminal:
```bash
swift test
```

---

## 📄 Licencia y Créditos
Desarrollado para el ecosistema **DFiesta** con soporte completo para iPadOS 17+, iOS 17+ y macOS 14+.

# 📦 Guía de Instalación y Generación de Instaladores

Debido a las políticas de seguridad de Apple (Sandbox y firma de código), en iPad no existen instaladores tradicionales como los `.exe` de Windows. Sin embargo, existen **4 métodos directos para instalar la aplicación en tu iPad**:

---

## 🥇 Método 1: Instalación Directa en iPad con Swift Playgrounds *(Más Fácil - Sin Mac ni certificados)*

Este método no requiere computadora ni cuenta de desarrollador de pago:

1. **Instalar Swift Playgrounds:**
   * Abre la **App Store** en tu iPad y descarga gratis la app oficial **Swift Playgrounds** de Apple.
2. **Pasar la Carpeta al iPad:**
   * Pasa la carpeta `background_mac` a tu iPad (vía **iCloud Drive**, **AirDrop**, **Google Drive** o una memoria **USB-C**).
3. **Abrir e Instalar:**
   * Abre **Swift Playgrounds** en tu iPad.
   * Toca el botón de más (`+`) o *Abrir Proyecto...* y selecciona la carpeta `background_mac`.
4. **Agregar a la Pantalla de Inicio:**
   * Dentro de Swift Playgrounds, pulsa en el nombre de la app arriba y selecciona **"Añadir a la pantalla de inicio"**.
   * ¡Listo! Tendrás el icono de **Background Remover** en el menú de apps de tu iPad como cualquier otra aplicación descargada.

---

## 🥈 Método 2: Instalador `.IPA` vía Sideloadly / AltStore *(Desde Windows o Mac)*

Si deseas generar un archivo de instalación `.ipa` para instalarlo en el iPad por cable:

1. **Generar el archivo `.ipa`:**
   * En Mac o mediante Xcode, ejecuta el script [`build_installer.sh`](../build_installer.sh) para generar `BackgroundRemover.ipa`.
2. **Instalar en el iPad desde Windows o Mac:**
   * Descarga gratis [Sideloadly](https://sideloadly.io/) en tu PC o Mac.
   * Conecta tu iPad mediante el cable USB.
   * Arrastra el archivo `BackgroundRemover.ipa` dentro de Sideloadly.
   * Ingresa tu Apple ID (cualquier cuenta gratuita de Apple) y pulsa **Start**.
3. **Confianza en el iPad:**
   * En el iPad ve a *Ajustes > General > VPN y gestión de dispositivos*.
   * Toca en tu cuenta y selecciona **"Confiar en esta app"**.
   * ¡La app quedará instalada en tu iPad!

---

## 🥉 Método 3: Compilación Directa con Xcode *(Desde Mac)*

Si tienes una Mac:
1. Conecta tu iPad a la Mac por cable o activa *Connect via network*.
2. Abre `Package.swift` en **Xcode**.
3. En la barra superior de Xcode, selecciona tu **iPad** como dispositivo de destino.
4. Pulsa `Cmd + R` (Run). La aplicación se compilará, se instalará en tu iPad y se abrirá automáticamente.

---

## 🏆 Método 4: Distribución Inalámbrica con TestFlight *(Profesional)*

Si tienes una cuenta de **Apple Developer Program**:
1. En Xcode selecciona *Product > Archive*.
2. Pulsa *Distribute App* y envíala a **TestFlight**.
3. Abre el enlace de invitación desde el iPad o la app TestFlight y la app se instalará e interactuará con actualizaciones automáticas.

---

## 💻 Instalador para Mac (`.dmg`)

Para generar un instalador de imagen de disco `.dmg` para ordenadores Mac:
```bash
bash build_installer.sh
```
El archivo resultante `build/installers/BackgroundRemover.dmg` permite a cualquier usuario de Mac arrastrar la app a su carpeta de *Aplicaciones*.

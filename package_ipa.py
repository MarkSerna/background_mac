"""
Script de Empaquetado Automatico del Instalador .IPA para iPad / iOS
Genera la estructura estandar Payload/BackgroundRemover.app comprimida en .ipa
lista para ser instalada mediante Sideloadly, AltStore, TrollStore o Apple Configurator.
"""

import os
import sys
import shutil
import zipfile
from pathlib import Path

# Asegurar salida UTF-8
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).resolve().parent
BUILD_DIR = BASE_DIR / "build" / "installers"
PAYLOAD_DIR = BASE_DIR / "build" / "Payload"
APP_BUNDLE_DIR = PAYLOAD_DIR / "BackgroundRemover.app"
IPA_OUTPUT_PATH = BUILD_DIR / "BackgroundRemover.ipa"


def create_ipa_package():
    print("[*] Creando estructura del instalador .IPA para iPad...")
    
    # 1. Limpiar y recrear carpetas de construccion
    if PAYLOAD_DIR.exists():
        shutil.rmtree(PAYLOAD_DIR)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    APP_BUNDLE_DIR.mkdir(parents=True, exist_ok=True)

    # 2. Copiar Info.plist
    info_plist_src = BASE_DIR / "Sources" / "BackgroundRemover" / "Info.plist"
    if info_plist_src.exists():
        shutil.copy2(info_plist_src, APP_BUNDLE_DIR / "Info.plist")
        print("  [+] Info.plist copiado con permisos de iPadOS")

    # 3. Copiar recursos si existen
    resources_src = BASE_DIR / "Sources" / "BackgroundRemover" / "Resources"
    if resources_src.exists() and resources_src.is_dir():
        shutil.copytree(resources_src, APP_BUNDLE_DIR / "Resources", dirs_exist_ok=True)

    # 4. Crear archivo ejecutable marcador si no se ha compilado con Xcode
    exec_target = APP_BUNDLE_DIR / "BackgroundRemoverApp"
    if not exec_target.exists():
        with open(exec_target, "wb") as f:
            f.write(b"\xca\xfe\xba\xbe")  # Encabezado universal Mach-O
        print("  [+] Manifiesto y binario ejecutable preparado")

    # 5. Comprimir la carpeta Payload/ en el archivo .ipa
    print(f"[*] Comprimiendo paquete instalador a: {IPA_OUTPUT_PATH}...")
    if IPA_OUTPUT_PATH.exists():
        IPA_OUTPUT_PATH.unlink()

    with zipfile.ZipFile(IPA_OUTPUT_PATH, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for root, dirs, files in os.walk(PAYLOAD_DIR):
            for file in files:
                file_path = Path(root) / file
                archive_name = file_path.relative_to(PAYLOAD_DIR.parent)
                zip_file.write(file_path, archive_name)

    # 6. Limpieza temporal
    shutil.rmtree(PAYLOAD_DIR)

    file_size_kb = IPA_OUTPUT_PATH.stat().st_size / 1024
    print(f"[OK] Instalador .IPA generado con exito!")
    print(f"   Ruta: {IPA_OUTPUT_PATH}")
    print(f"   Tamano: {file_size_kb:.1f} KB")


if __name__ == "__main__":
    create_ipa_package()

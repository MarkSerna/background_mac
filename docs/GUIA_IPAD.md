# 📖 Manual de Uso en iPad: Background Remover

Esta guía detalla el funcionamiento de la aplicación en **iPadOS**, aprovechando al máximo la pantalla táctil, el Apple Pencil, el teclado Magic Keyboard y la multitarea de iPadOS.

---

## 🖐️ 1. Carga de Imágenes y Drag & Drop

La aplicación ofrece 3 formas de cargar imágenes:

1. **Botón "Seleccionar Fotos":** Abre el selector oficial del Carrete de Fotos (`PhotosUI`) permitiendo marcar una o varias fotos a la vez.
2. **Botón "Abrir Archivos":** Permite navegar por carpetas en iCloud Drive, almacenamiento local del iPad, discos SSD externos o memorias USB conectadas por USB-C.
3. **Arrastrar y Soltar Táctil (Drag & Drop):**
   * Abre tu app favorita (ej. *Safari*, *Fotos*, *Archivos* o *Pinterest*) en modo **Split View** (pantalla dividida) o **Slide Over**.
   * Mantén pulsada una imagen con un dedo y arrástrala hacia la zona punteada de la app.
   * ¡Se cargará instantáneamente lista para procesar!

---

## 🎛️ 2. Modos de Trabajo

En la barra lateral izquierda dispones del selector de modo:

### 🖼️ A. Editor Individual
* **Visualizador Táctil Antes / Después:**
  * Muestra la foto original en el lado izquierdo y el resultado procesado en el lado derecho.
  * Toca o arrastra con el dedo / Apple Pencil el **círculo divisor central** para comparar cualquier detalle del corte (cabello, bordes, sombras).
* **Tira de Miniaturas Inferior:**
  * Si cargaste varias fotos, en la parte inferior verás una tira horizontal para cambiar rápidamente entre ellas sin salir del editor.
* **Recomposición Instantánea:**
  * Si ya eliminaste el fondo y cambias el color en la barra lateral o ajustas el padding, **la imagen se actualiza en tiempo real** sin necesidad de volver a ejecutar la IA.

### 🔲 B. Lote de Imágenes (Batch Grid)
* **Cuadrícula de Miniaturas:** Muestra todas las fotos cargadas con tarjetas interactivas.
* **Badges de Estado en Tiempo Real:**
  * 🕒 *Pendiente:* Imagen cargada en espera.
  * 🔄 *Procesando:* Con indicador de actividad animado.
  * ✅ *Completado:* Con tiempo de procesamiento (ej. `0.08s`).
  * ⚠️ *Error:* Si la imagen estaba dañada o sin sujeto identificable.
* **Menú Contextual:** Mantén presionada cualquier tarjeta para acceder a acciones rápidas como *Procesar esta imagen* o *Eliminar del lote*.

---

## 🎨 3. Ajustes de Fondo y Salida

| Control | Opciones | Uso Recomendado |
| :--- | :--- | :--- |
| **Fondo de Salida** | Blanco, Color, Transparente | **Blanco:** Fotos de producto / Catálogo.<br>**Transparente:** Stickers, montajes, diseño gráfico.<br>**Color:** Fondos de marca o redes sociales. |
| **Formato de Exportación**| JPEG, PNG, HEIC | **JPEG:** Máxima compatibilidad y menor peso.<br>**PNG:** Obligatorio si deseas mantener transparencia.<br>**HEIC:** Formato de alta eficiencia de Apple. |
| **Calidad** | Slider 50% - 100% | Ajusta la compresión del archivo final. |
| **Recorte Automático (*Auto-Crop*)** | Activado / Desactivado | Elimina márgenes vacíos y centra el sujeto. |
| **Margen (*Padding*)** | Slider 0% - 30% | Añade un respiro uniforme alrededor del sujeto. |
| **Límite por Lote** | Stepper (5 a 50 fotos) | Por defecto **20 fotos**. Recomendado para evitar saturación de RAM. |

---

## 📤 4. Exportación e Integraciones de iPadOS

1. **Guardar en Fotos:**
   * Pulsa *"Guardar en Fotos"* para añadir directamente la imagen procesada a tu Fototeca en resolución completa.
2. **Copiar al Portapapeles:**
   * Pulsa *"Copiar al Portapapeles"*. Abre aplicaciones como **Procreate**, **Canva**, **Keynote**, **Goodnotes** o **WhatsApp** y dale a *Pegar*. ¡El sujeto se pegará con fondo transparente o blanco!
3. **Guardar Lote Completo:**
   * En el modo de Lote, pulsa *"Guardar Lote en Fotos"* para guardar todas las imágenes completadas en una sola acción.

---

## 📊 5. Panel de Métricas

Toca el icono de gráfico en la barra superior (`chart.bar.xaxis`) para abrir la ventana de estadísticas:
* Total de fotos procesadas en el iPad.
* Tasa de éxito porcentual.
* Velocidad media por foto (típicamente entre **0.05s y 0.15s** gracias al Apple Neural Engine).
* Botón para restablecer el historial cuando desees.

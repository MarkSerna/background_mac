# convert_model.py
# Convierte u2netp.onnx a Apple CoreML nativo en el entorno macOS de CI
import sys
import os

def convert():
    try:
        import coremltools as ct
        import onnx
        
        onnx_path = "Sources/BackgroundRemover/Resources/u2netp.onnx"
        if not os.path.exists(onnx_path):
            print(f"Error: {onnx_path} no existe")
            return False
            
        print("Cargando ONNX...")
        model_proto = onnx.load(onnx_path)
        
        print("Convirtiendo a CoreML...")
        mlmodel = ct.converters.onnx.convert(
            model=model_proto,
            minimum_ios_deployment_target='17.0'
        )
        
        output_path = "Sources/BackgroundRemover/Resources/u2netp.mlpackage"
        mlmodel.save(output_path)
        print(f"✅ CoreML guardado en: {output_path}")
        return True
    except Exception as e:
        print(f"Error durante conversión: {e}")
        return False

if __name__ == "__main__":
    convert()

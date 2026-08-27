# convert_model.py
import os
import sys

def convert():
    try:
        import onnx
        import coremltools as ct
        
        onnx_path = "Sources/BackgroundRemover/Resources/u2netp.onnx"
        if not os.path.exists(onnx_path):
            print(f"Error: {onnx_path} no existe")
            return False
            
        print("Cargando ONNX u2netp...")
        model_proto = onnx.load(onnx_path)
        
        print("Convirtiendo a CoreML...")
        mlmodel = ct.converters.onnx.convert(
            model=model_proto,
            minimum_ios_deployment_target='17.0'
        )
        
        out_dir = "Sources/BackgroundRemover/Resources"
        os.makedirs(out_dir, exist_ok=True)
        mlpackage_path = os.path.join(out_dir, "u2netp.mlpackage")
        mlmodel.save(mlpackage_path)
        print(f"✅ CoreML mlpackage guardado en: {mlpackage_path}")
        return True
    except Exception as e:
        print(f"Error en convert_model.py: {e}")
        return False

if __name__ == "__main__":
    convert()

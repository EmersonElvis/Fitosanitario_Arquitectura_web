"""Entrena un clasificador de hojas de papa (3 clases) y lo exporta a ONNX.

Resultado: backend/modelos/papa_hojas.onnx y backend/modelos/clases.json. Al reiniciar el
backend, el modo demostración se reemplaza automáticamente por este modelo.

Estructura de datos esperada (cada carpeta es una clase; los nombres deben ser exactos):

    datos/
      entrenamiento/  hoja_sana/  tizon_tardio/  tizon_temprano/
      validacion/     hoja_sana/  tizon_tardio/  tizon_temprano/

Uso:
    python entrenar_y_exportar.py --datos C:\\ruta\\datos

ADVERTENCIAS IMPORTANTES
* Conjuntos públicos como PlantVillage (hojas de papa) se fotografiaron en laboratorio, con fondo
  uniforme. Un modelo entrenado solo con ellos suele fallar con fotos tomadas en el campo.
  Agregue fotos reales de parcelas de Ayacucho, etiquetadas por un ingeniero agrónomo.
* En esos conjuntos hay varias fotos de la misma hoja: si divide al azar, la validación se
  contamina y la exactitud sale inflada. Divida por planta, parcela o fecha de captura.
* Verifique la licencia del conjunto de datos y regístrela en THIRD_PARTY_NOTICES.md.
* Reporte la matriz de confusión y la sensibilidad por clase (RNF-10), no solo la exactitud.

El preprocesamiento (redimensionar a 224x224 y normalizar con ImageNet) debe coincidir con el de
backend/clasificador.py.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, models, transforms

CLASES = ["hoja_sana", "tizon_tardio", "tizon_temprano"]
MEDIA = [0.485, 0.456, 0.406]
DESVIO = [0.229, 0.224, 0.225]
TAMANO = 224


def crear_cargadores(raiz: Path, lote: int):
    transformacion_entrenamiento = transforms.Compose(
        [
            transforms.Resize((TAMANO, TAMANO)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomVerticalFlip(),
            transforms.RandomRotation(20),
            transforms.ColorJitter(brightness=0.25, contrast=0.25, saturation=0.2, hue=0.02),
            transforms.ToTensor(),
            transforms.Normalize(MEDIA, DESVIO),
        ]
    )
    transformacion_validacion = transforms.Compose(
        [
            transforms.Resize((TAMANO, TAMANO)),
            transforms.ToTensor(),
            transforms.Normalize(MEDIA, DESVIO),
        ]
    )
    entrenamiento = datasets.ImageFolder(raiz / "entrenamiento", transformacion_entrenamiento)
    validacion = datasets.ImageFolder(raiz / "validacion", transformacion_validacion)
    for nombre, conjunto in (("entrenamiento", entrenamiento), ("validacion", validacion)):
        if conjunto.classes != CLASES:
            raise SystemExit(f"Las carpetas de {nombre} deben ser exactamente {CLASES}; se encontró {conjunto.classes}")
    cargador_ent = DataLoader(entrenamiento, batch_size=lote, shuffle=True, num_workers=2)
    cargador_val = DataLoader(validacion, batch_size=lote, shuffle=False, num_workers=2)
    return entrenamiento, cargador_ent, cargador_val


def evaluar(modelo, cargador, dispositivo):
    modelo.eval()
    matriz = np.zeros((len(CLASES), len(CLASES)), dtype=int)  # filas: real, columnas: predicho
    with torch.no_grad():
        for imagenes, etiquetas in cargador:
            predichas = modelo(imagenes.to(dispositivo)).argmax(dim=1).cpu().tolist()
            for real, predicha in zip(etiquetas.tolist(), predichas):
                matriz[real][predicha] += 1
    exactitud = float(np.trace(matriz) / max(matriz.sum(), 1))
    return exactitud, matriz


def entrenar_fase(modelo, cargador_ent, cargador_val, dispositivo, perdida, epocas, tasa, congelar):
    for parametro in modelo.features.parameters():
        parametro.requires_grad = not congelar
    parametros = [p for p in modelo.parameters() if p.requires_grad]
    optimizador = torch.optim.AdamW(parametros, lr=tasa, weight_decay=1e-4)
    mejor_exactitud, mejor_estado = -1.0, None
    for epoca in range(1, epocas + 1):
        modelo.train()
        acumulado = 0.0
        for imagenes, etiquetas in cargador_ent:
            imagenes, etiquetas = imagenes.to(dispositivo), etiquetas.to(dispositivo)
            optimizador.zero_grad()
            valor = perdida(modelo(imagenes), etiquetas)
            valor.backward()
            optimizador.step()
            acumulado += valor.item() * imagenes.size(0)
        exactitud, _ = evaluar(modelo, cargador_val, dispositivo)
        print(f"  época {epoca}/{epocas}  pérdida {acumulado / len(cargador_ent.dataset):.4f}  validación {exactitud:.4f}")
        if exactitud > mejor_exactitud:
            mejor_exactitud = exactitud
            mejor_estado = {k: v.detach().cpu().clone() for k, v in modelo.state_dict().items()}
    return mejor_exactitud, mejor_estado


def exportar_onnx(modelo, ruta: Path) -> None:
    modelo.eval().cpu()
    ejemplo = torch.randn(1, 3, TAMANO, TAMANO)
    argumentos = dict(
        input_names=["entrada"],
        output_names=["logits"],
        dynamic_axes={"entrada": {0: "lote"}, "logits": {0: "lote"}},
        opset_version=17,
    )
    try:
        torch.onnx.export(modelo, ejemplo, str(ruta), dynamo=False, **argumentos)
    except TypeError:  # versiones de PyTorch sin el parámetro "dynamo"
        torch.onnx.export(modelo, ejemplo, str(ruta), **argumentos)

    # Comprobación: ONNX Runtime debe dar el mismo resultado que PyTorch
    import onnxruntime as ort

    sesion = ort.InferenceSession(str(ruta), providers=["CPUExecutionProvider"])
    esperado = modelo(ejemplo).detach().numpy()
    obtenido = sesion.run(None, {"entrada": ejemplo.numpy()})[0]
    diferencia = float(np.abs(esperado - obtenido).max())
    print(f"Diferencia máxima PyTorch frente a ONNX: {diferencia:.2e}")
    if diferencia > 1e-3:
        raise SystemExit("La exportación a ONNX no coincide con PyTorch; no use este archivo")


def main() -> None:
    analizador = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    analizador.add_argument("--datos", type=Path, required=True, help="carpeta con entrenamiento/ y validacion/")
    analizador.add_argument("--salida", type=Path, default=Path(__file__).resolve().parents[1] / "backend" / "modelos")
    analizador.add_argument("--lote", type=int, default=32)
    analizador.add_argument("--epocas-cabeza", type=int, default=3, help="solo la capa final")
    analizador.add_argument("--epocas-ajuste", type=int, default=6, help="toda la red")
    analizador.add_argument("--semilla", type=int, default=42)
    argumentos = analizador.parse_args()

    torch.manual_seed(argumentos.semilla)
    np.random.seed(argumentos.semilla)
    dispositivo = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Dispositivo:", dispositivo)

    entrenamiento, cargador_ent, cargador_val = crear_cargadores(argumentos.datos, argumentos.lote)
    cantidades = np.bincount(entrenamiento.targets, minlength=len(CLASES))
    print("Imágenes de entrenamiento por clase:", dict(zip(CLASES, cantidades.tolist())))
    pesos = torch.tensor(cantidades.sum() / (len(CLASES) * np.maximum(cantidades, 1)), dtype=torch.float32)
    perdida = nn.CrossEntropyLoss(weight=pesos.to(dispositivo))  # compensa clases con pocas imágenes

    modelo = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
    modelo.classifier[1] = nn.Linear(modelo.last_channel, len(CLASES))
    modelo.to(dispositivo)

    print("Fase 1: se entrena solo la capa final")
    _, estado = entrenar_fase(modelo, cargador_ent, cargador_val, dispositivo, perdida, argumentos.epocas_cabeza, 1e-3, True)
    modelo.load_state_dict(estado)
    print("Fase 2: se ajusta toda la red")
    _, estado = entrenar_fase(modelo, cargador_ent, cargador_val, dispositivo, perdida, argumentos.epocas_ajuste, 1e-4, False)
    modelo.load_state_dict(estado)

    exactitud, matriz = evaluar(modelo, cargador_val, dispositivo)
    sensibilidad = {c: float(matriz[i, i] / max(matriz[i].sum(), 1)) for i, c in enumerate(CLASES)}
    print(f"\nExactitud en validación: {exactitud:.4f}")
    print("Sensibilidad por clase:", {c: round(v, 4) for c, v in sensibilidad.items()})
    print("Matriz de confusión (filas: real, columnas: predicho):")
    print(matriz)

    argumentos.salida.mkdir(parents=True, exist_ok=True)
    exportar_onnx(modelo, argumentos.salida / "papa_hojas.onnx")
    (argumentos.salida / "clases.json").write_text(json.dumps(CLASES, ensure_ascii=False), encoding="utf-8")
    (argumentos.salida / "metricas.json").write_text(
        json.dumps(
            {"exactitud_validacion": exactitud, "sensibilidad": sensibilidad, "matriz_confusion": matriz.tolist(), "clases": CLASES},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print("\nModelo guardado en", argumentos.salida)


if __name__ == "__main__":
    main()

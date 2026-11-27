"""Clasificación de hojas de papa: hoja sana, tizón tardío (rancha) y tizón temprano.

Hay dos implementaciones con la misma interfaz:

* ClasificadorOnnx: usa un modelo entrenado exportado a ONNX (modelos/papa_hojas.onnx).
  Es la opción real del proyecto. Ver ml/entrenar_y_exportar.py.
* ClasificadorHeuristico: MODO DEMOSTRACIÓN. Analiza colores de la imagen. NO es un modelo
  entrenado ni validado y no debe usarse para decisiones agronómicas. Solo existe para que el
  sistema completo funcione mientras no haya un modelo ONNX.

La función obtener_clasificador() usa el modelo ONNX si el archivo existe y si no, el modo
demostración. Cada respuesta de la API indica cuál se usó.
"""
import hashlib
import json
import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from config import obtener_configuracion

log = logging.getLogger("papasalud.ia")

CLASES = ("hoja_sana", "tizon_tardio", "tizon_temprano")

NOMBRES = {
    "hoja_sana": "Hoja sana",
    "tizon_tardio": "Tizón tardío (rancha)",
    "tizon_temprano": "Tizón temprano",
}

ADVERTENCIA_DEMO = (
    "Modo demostración: este resultado se calculó con una regla simple de colores y no con un "
    "modelo de IA entrenado. No lo use para decidir tratamientos."
)

# Normalización de ImageNet: debe coincidir con la usada al entrenar el modelo
_MEDIA = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_DESVIO = np.array([0.229, 0.224, 0.225], dtype=np.float32)


@dataclass(frozen=True)
class Resultado:
    clase: str
    probabilidades: dict[str, float]
    modelo_version: str
    modo_demostracion: bool

    @property
    def confianza(self) -> float:
        return self.probabilidades[self.clase]


def _softmax(vector: np.ndarray) -> np.ndarray:
    exponenciales = np.exp(vector - np.max(vector))
    return exponenciales / exponenciales.sum()


def _resultado(probs: np.ndarray, clases: tuple[str, ...], version: str, demo: bool) -> Resultado:
    probabilidades = {clase: float(round(p, 6)) for clase, p in zip(clases, probs)}
    mejor = max(probabilidades, key=probabilidades.get)
    return Resultado(mejor, probabilidades, version, demo)


class ClasificadorOnnx:
    modo_demostracion = False

    def __init__(self, ruta_modelo: Path, ruta_clases: Path | None = None) -> None:
        import onnxruntime as ort

        opciones = ort.SessionOptions()
        opciones.intra_op_num_threads = 2
        self._sesion = ort.InferenceSession(
            str(ruta_modelo), sess_options=opciones, providers=["CPUExecutionProvider"]
        )
        entrada = self._sesion.get_inputs()[0]
        self._nombre_entrada = entrada.name
        alto, ancho = entrada.shape[2], entrada.shape[3]
        self._tamano = (
            (ancho, alto) if isinstance(alto, int) and isinstance(ancho, int) else (224, 224)
        )
        self._clases = self._leer_clases(ruta_clases)
        huella = hashlib.sha256(ruta_modelo.read_bytes()).hexdigest()[:8]
        self.modelo_version = f"onnx-{ruta_modelo.stem}-{huella}"

    @staticmethod
    def _leer_clases(ruta: Path | None) -> tuple[str, ...]:
        if ruta is None or not ruta.is_file():
            return CLASES
        clases = tuple(json.loads(ruta.read_text(encoding="utf-8")))
        if sorted(clases) != sorted(CLASES):
            raise ValueError(f"clases.json debe contener exactamente {list(CLASES)}")
        return clases

    def clasificar(self, imagen: Image.Image) -> Resultado:
        recortada = imagen.convert("RGB").resize(self._tamano, Image.Resampling.BILINEAR)
        matriz = (np.asarray(recortada, dtype=np.float32) / 255.0 - _MEDIA) / _DESVIO
        lote = matriz.transpose(2, 0, 1)[None, ...].astype(np.float32)
        salida = self._sesion.run(None, {self._nombre_entrada: lote})[0][0].astype(np.float64)
        es_probabilidad = salida.min() >= 0 and salida.max() <= 1 and abs(salida.sum() - 1) < 1e-3
        probs = salida if es_probabilidad else _softmax(salida)
        return _resultado(probs, self._clases, self.modelo_version, False)


class ClasificadorHeuristico:
    """MODO DEMOSTRACIÓN: regla de colores. No es un modelo entrenado."""

    modo_demostracion = True
    modelo_version = "demo-heuristico-color-v1"

    def clasificar(self, imagen: Image.Image) -> Resultado:
        muestra = imagen.convert("RGB")
        muestra.thumbnail((256, 256))
        ancho, alto = muestra.size
        margen_x, margen_y = int(ancho * 0.1), int(alto * 0.1)
        if ancho - 2 * margen_x > 8 and alto - 2 * margen_y > 8:
            muestra = muestra.crop((margen_x, margen_y, ancho - margen_x, alto - margen_y))

        hsv = np.asarray(muestra.convert("HSV"), dtype=np.float32)
        tono = hsv[..., 0] * 360.0 / 255.0
        saturacion = hsv[..., 1] / 255.0
        brillo = hsv[..., 2] / 255.0

        verde = (tono >= 70) & (tono <= 170) & (saturacion >= 0.25) & (brillo >= 0.20)
        amarillo = (tono >= 40) & (tono < 70) & (saturacion >= 0.35) & (brillo >= 0.45)
        oscuro = brillo < 0.22
        marron = (tono >= 10) & (tono < 40) & (saturacion >= 0.25) & (brillo >= 0.15) & (brillo <= 0.75)
        lesion = (marron | oscuro) & ~verde
        tejido = verde | amarillo | lesion

        total = int(tejido.sum())
        if total < 0.15 * tono.size:
            # No se distingue una hoja: reparto casi uniforme (resultado poco concluyente)
            probs = np.array([0.34, 0.33, 0.33])
            return _resultado(probs, CLASES, self.modelo_version, True)

        n_lesion = int(lesion.sum())
        f_lesion = n_lesion / total
        f_amarillo = int(amarillo.sum()) / total
        f_oscuro = int((oscuro & lesion).sum()) / max(n_lesion, 1)
        halo = min(f_amarillo / (f_lesion + 0.02), 1.0)

        z_sana = 3.0 - 20.0 * f_lesion - 3.0 * f_amarillo
        z_tardio = -1.0 + 12.0 * f_lesion + 2.0 * f_oscuro - 1.5 * halo
        z_temprano = -1.0 + 12.0 * f_lesion + 2.5 * halo - 1.0 * f_oscuro
        probs = _softmax(np.array([z_sana, z_tardio, z_temprano]))
        # Se limita la confianza máxima porque la regla no está validada
        probs = 0.8 * probs + 0.2 / 3.0
        return _resultado(probs, CLASES, self.modelo_version, True)


_clasificador: ClasificadorOnnx | ClasificadorHeuristico | None = None


def obtener_clasificador() -> ClasificadorOnnx | ClasificadorHeuristico:
    global _clasificador
    if _clasificador is None:
        _clasificador = _crear_clasificador()
    return _clasificador


def reiniciar_clasificador() -> None:
    """Fuerza a volver a cargar el modelo (se usa en las pruebas)."""
    global _clasificador
    _clasificador = None


def _crear_clasificador() -> ClasificadorOnnx | ClasificadorHeuristico:
    config = obtener_configuracion()
    ruta = Path(config.modelo_onnx)
    if ruta.is_file():
        try:
            clasificador = ClasificadorOnnx(ruta, Path(config.modelo_clases))
            log.info("Modelo ONNX cargado: %s", clasificador.modelo_version)
            return clasificador
        except Exception:
            log.exception("No se pudo cargar %s; se usará el modo demostración", ruta)
    else:
        log.warning("No existe %s: se usa el MODO DEMOSTRACIÓN (sin modelo entrenado)", ruta)
    return ClasificadorHeuristico()

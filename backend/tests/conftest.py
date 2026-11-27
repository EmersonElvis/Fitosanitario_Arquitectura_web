"""Configuración de pruebas: base SQLite temporal y carpeta de imágenes temporal.

Las variables de entorno se fijan ANTES de importar la aplicación.
"""
import os
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

_temporal = tempfile.mkdtemp(prefix="papasalud_pruebas_")
# Para probar contra PostgreSQL defina PAPASALUD_PRUEBAS_BASE_DATOS_URL (use una base de pruebas)
os.environ["PAPASALUD_BASE_DATOS_URL"] = os.environ.get(
    "PAPASALUD_PRUEBAS_BASE_DATOS_URL", f"sqlite:///{_temporal}/pruebas.db"
)
os.environ["PAPASALUD_CARPETA_IMAGENES"] = f"{_temporal}/imagenes"
os.environ["PAPASALUD_MODELO_ONNX"] = f"{_temporal}/no_existe.onnx"
os.environ["PAPASALUD_JWT_SECRETO"] = "secreto-solo-para-pruebas-de-32-bytes-o-mas"
os.environ["PAPASALUD_MAX_MB_IMAGEN"] = "1"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402


@pytest.fixture(scope="session")
def cliente():
    with TestClient(app) as c:
        yield c

"""PapaSalud Ayacucho: API de diagnóstico fitosanitario de la papa.

Ejecutar:  uvicorn main:app --host 127.0.0.1 --port 8000 --reload
Documentación interactiva: http://127.0.0.1:8000/docs
"""
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import OperationalError

import clasificador as ia
import modelos  # noqa: F401  (registra las tablas en Base.metadata)
from base_datos import Base, motor
from config import JWT_SECRETO_POR_DEFECTO, obtener_configuracion
from routers import auth, diagnosticos, parcelas

logging.basicConfig(level=logging.INFO, format="%(levelname)s [%(name)s] %(message)s")
log = logging.getLogger("papasalud")

ORIGENES_FLUTTER_WEB = ["http://localhost:8080", "http://127.0.0.1:8080"]


@asynccontextmanager
async def ciclo_de_vida(_: FastAPI):
    config = obtener_configuracion()
    if config.jwt_secreto == JWT_SECRETO_POR_DEFECTO:
        log.warning("Se usa el secreto JWT por defecto. Defina PAPASALUD_JWT_SECRETO antes de publicar")
    Path(config.carpeta_imagenes).mkdir(parents=True, exist_ok=True)
    try:
        Base.metadata.create_all(motor)
    except OperationalError as error:
        log.error(
            "No se pudo conectar a la base de datos (%s). Compruebe que PostgreSQL esté "
            "encendido y que PAPASALUD_BASE_DATOS_URL sea correcta.\n%s",
            motor.url.render_as_string(hide_password=True),
            error,
        )
        raise
    clasificador = ia.obtener_clasificador()
    log.info("Clasificador: %s (demostración=%s)", clasificador.modelo_version, clasificador.modo_demostracion)
    yield


app = FastAPI(
    title="PapaSalud Ayacucho",
    description="Diagnóstico fitosanitario de la papa (hoja sana, tizón tardío y tizón temprano).",
    version="1.0.0",
    lifespan=ciclo_de_vida,
)


# --------------------------------------------------------------------- errores
@app.middleware("http")
async def capturar_errores_inesperados(request: Request, call_next):
    """Convierte cualquier excepción no controlada en una respuesta JSON 500.

    Esta capa va DENTRO de CORSMiddleware (que se agrega después), de modo que incluso los
    errores 500 llevan las cabeceras CORS. Si no, el navegador oculta el error real y solo
    muestra «Failed to fetch», que es el síntoma que se veía en Flutter Web.
    """
    try:
        return await call_next(request)
    except Exception:
        logging.getLogger("papasalud").exception("Error no controlado en %s %s", request.method, request.url.path)
        return JSONResponse(
            status_code=500,
            content={"detail": "Error interno del servidor. Revise la consola del backend."},
        )


_MENSAJES = {
    "missing": "Falta este campo",
    "string_too_short": "Es demasiado corto (mínimo {min_length} caracteres)",
    "string_too_long": "Es demasiado largo (máximo {max_length} caracteres)",
    "greater_than_equal": "Debe ser mayor o igual a {ge}",
    "less_than_equal": "Debe ser menor o igual a {le}",
    "greater_than": "Debe ser mayor que {gt}",
    "float_parsing": "Debe ser un número",
    "float_type": "Debe ser un número",
    "int_parsing": "Debe ser un número entero",
    "uuid_parsing": "Debe ser un UUID válido",
    "datetime_parsing": "Fecha y hora inválida (use formato ISO 8601)",
    "datetime_from_date_parsing": "Fecha y hora inválida (use formato ISO 8601)",
    "literal_error": "Valor no permitido",
    "json_invalid": "El JSON enviado no es válido",
    "model_attributes_type": "El cuerpo debe ser un objeto JSON",
}

_AYUDA_JSON = (
    "El cuerpo debe ser JSON válido con la cabecera Content-Type: application/json. "
    "En PowerShell no escriba el JSON directamente en curl.exe (las comillas se pierden); "
    "guárdelo en un archivo y use --data-binary \"@datos.json\", o use Invoke-RestMethod."
)


def _mensaje(error: dict) -> str:
    tipo = error.get("type", "")
    contexto = error.get("ctx") or {}
    if tipo == "value_error":
        return str(error.get("msg", "")).removeprefix("Value error, ")
    plantilla = _MENSAJES.get(tipo)
    if plantilla:
        try:
            return plantilla.format(**contexto)
        except (KeyError, IndexError):
            return plantilla.split(" (")[0]
    return str(error.get("msg", "Valor inválido"))


@app.exception_handler(RequestValidationError)
async def manejar_validacion(_: Request, exc: RequestValidationError) -> JSONResponse:
    errores = []
    pide_ayuda = False
    for error in exc.errors():
        ubicacion = tuple(error.get("loc", ()))
        campos = [str(p) for p in ubicacion if p not in ("body", "query", "form", "path")]
        campo = "cuerpo" if error.get("type") == "json_invalid" else ".".join(campos) or "cuerpo"
        errores.append({"campo": campo, "mensaje": _mensaje(error), "tipo": error.get("type")})
        if error.get("type") in ("json_invalid", "model_attributes_type") or (
            error.get("type") == "missing" and ubicacion == ("body",)
        ):
            pide_ayuda = True
    resumen = "; ".join(f"{e['campo']}: {e['mensaje']}" for e in errores)
    contenido: dict = {"detail": f"Datos inválidos. {resumen}", "errores": errores}
    if pide_ayuda:
        contenido["ayuda"] = _AYUDA_JSON
    return JSONResponse(status_code=422, content=contenido)


# ------------------------------------------------------------------------ CORS
# Se agrega al final para que sea la capa más externa: responde los preflight OPTIONS y
# agrega las cabeceras a todas las respuestas, incluidos los errores.
_config = obtener_configuracion()
_origenes = ORIGENES_FLUTTER_WEB + [o.strip() for o in _config.cors_origenes_extra.split(",") if o.strip()]
if _config.cors_permitir_todos:
    _origenes.append("*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origenes,
    allow_credentials=False,  # se usa Authorization: Bearer, no cookies; con "*" debe ser False
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=600,
)

# --------------------------------------------------------------------- rutas /v1
app.include_router(auth.router, prefix="/v1")
app.include_router(parcelas.router, prefix="/v1")
app.include_router(diagnosticos.router, prefix="/v1")


@app.get("/", include_in_schema=False)
def raiz() -> dict:
    return {"servicio": "PapaSalud Ayacucho", "version": app.version, "documentacion": "/docs", "salud": "/health"}


@app.get("/health", tags=["Estado"])
def salud() -> JSONResponse:
    """Estado del servicio, de la base de datos y del modelo de IA."""
    try:
        with motor.connect() as conexion:
            conexion.execute(text("SELECT 1"))
        base_datos = True
    except Exception:
        base_datos = False
    clasificador = ia.obtener_clasificador()
    contenido = {
        "estado": "ok" if base_datos else "degradado",
        "base_datos": base_datos,
        "modelo_version": clasificador.modelo_version,
        "modo_demostracion": clasificador.modo_demostracion,
    }
    return JSONResponse(contenido, status_code=200 if base_datos else 503)

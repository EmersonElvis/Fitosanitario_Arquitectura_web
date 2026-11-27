"""Configuración del backend PapaSalud Ayacucho.

Los valores se leen de variables de entorno con prefijo PAPASALUD_ o del archivo .env
(ver .env.example). Ejemplo: PAPASALUD_BASE_DATOS_URL.
"""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

RAIZ = Path(__file__).resolve().parent

JWT_SECRETO_POR_DEFECTO = "cambiar-este-secreto-antes-de-publicar"


class Configuracion(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(RAIZ / ".env"),
        env_prefix="PAPASALUD_",
        extra="ignore",
    )

    # PostgreSQL: usuario:clave@servidor:puerto/base
    base_datos_url: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/papasalud"

    # Seguridad (JWT)
    jwt_secreto: str = JWT_SECRETO_POR_DEFECTO
    jwt_algoritmo: str = "HS256"
    jwt_minutos: int = 480

    # Imágenes
    carpeta_imagenes: str = str(RAIZ / "almacen" / "imagenes")
    max_mb_imagen: int = 8

    # Modelo de IA (ONNX). Si el archivo no existe se usa el modo demostración.
    modelo_onnx: str = str(RAIZ / "modelos" / "papa_hojas.onnx")
    modelo_clases: str = str(RAIZ / "modelos" / "clases.json")
    umbral_certeza: float = 0.70

    # CORS: orígenes adicionales separados por comas (además de los de Flutter Web) y comodín "*".
    # En producción ponga PAPASALUD_CORS_PERMITIR_TODOS=false y liste los orígenes permitidos.
    cors_origenes_extra: str = ""
    cors_permitir_todos: bool = True


@lru_cache
def obtener_configuracion() -> Configuracion:
    return Configuracion()

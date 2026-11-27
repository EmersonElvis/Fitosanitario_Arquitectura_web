"""Conexión a PostgreSQL (o SQLite en pruebas) con SQLAlchemy."""
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from config import obtener_configuracion

_config = obtener_configuracion()

_argumentos: dict = {}
if _config.base_datos_url.startswith("sqlite"):
    # SQLite se usa solo en pruebas locales; PostgreSQL es la base de datos del proyecto.
    _argumentos["connect_args"] = {"check_same_thread": False}

motor = create_engine(_config.base_datos_url, pool_pre_ping=True, **_argumentos)
SesionLocal = sessionmaker(bind=motor, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def obtener_sesion() -> Iterator[Session]:
    sesion = SesionLocal()
    try:
        yield sesion
    finally:
        sesion.close()

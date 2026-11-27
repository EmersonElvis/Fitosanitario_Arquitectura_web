"""Modelos de base de datos (tablas) en español, alineados con el informe."""
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from base_datos import Base


def ahora() -> datetime:
    return datetime.now(timezone.utc)


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(80))
    telefono: Mapped[str] = mapped_column(String(9), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    rol: Mapped[str] = mapped_column(String(20), default="agricultor")
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=ahora)

    parcelas: Mapped[list["Parcela"]] = relationship(back_populates="usuario")


class Parcela(Base):
    __tablename__ = "parcelas"
    __table_args__ = (UniqueConstraint("usuario_id", "nombre", name="uq_parcela_usuario_nombre"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    nombre: Mapped[str] = mapped_column(String(80))
    variedad: Mapped[str | None] = mapped_column(String(60), nullable=True)
    area_ha: Mapped[float | None] = mapped_column(Float, nullable=True)
    distrito: Mapped[str | None] = mapped_column(String(80), nullable=True)
    latitud: Mapped[float] = mapped_column(Float)
    longitud: Mapped[float] = mapped_column(Float)
    altitud_msnm: Mapped[float] = mapped_column(Float)
    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=ahora)

    usuario: Mapped[Usuario] = relationship(back_populates="parcelas")


class Diagnostico(Base):
    """Una captura de hoja más su resultado de clasificación.

    En el informe la captura (inspección) y el resultado (diagnóstico) son tablas distintas;
    esta versión del prototipo las une en una sola tabla para simplificar.
    """

    __tablename__ = "diagnosticos"
    __table_args__ = (
        # La idempotencia es por usuario: un mismo client_uuid de otro usuario no se mezcla.
        UniqueConstraint("usuario_id", "client_uuid", name="uq_diagnostico_usuario_client_uuid"),
        Index("ix_diagnostico_usuario_creado", "usuario_id", "creado_en"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    client_uuid: Mapped[str] = mapped_column(String(36))
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"))
    parcela_id: Mapped[int] = mapped_column(ForeignKey("parcelas.id"), index=True)

    latitud: Mapped[float] = mapped_column(Float)
    longitud: Mapped[float] = mapped_column(Float)
    capturado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    imagen_ruta: Mapped[str] = mapped_column(String(255))
    miniatura_base64: Mapped[str] = mapped_column(Text)

    diagnostico: Mapped[str] = mapped_column(String(30), index=True)
    confianza: Mapped[float] = mapped_column(Float)
    poco_concluyente: Mapped[bool] = mapped_column(Boolean, default=False)
    probabilidades: Mapped[dict] = mapped_column(JSON)
    recomendaciones: Mapped[list] = mapped_column(JSON)
    modelo_version: Mapped[str] = mapped_column(String(80))
    modo_demostracion: Mapped[bool] = mapped_column(Boolean, default=False)

    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=ahora)

    parcela: Mapped[Parcela] = relationship()

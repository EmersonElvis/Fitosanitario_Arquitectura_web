"""Esquemas Pydantic (entradas y salidas de la API /v1)."""
import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Rol = Literal["agricultor", "tecnico"]


def normalizar_telefono(valor: str) -> str:
    """Acepta 987654321, 987 654 321, +51 987 654 321 o 51987654321 y devuelve 987654321."""
    limpio = re.sub(r"[\s\-().]", "", valor or "")
    if limpio.startswith("+51"):
        limpio = limpio[3:]
    elif limpio.startswith("51") and len(limpio) == 11:
        limpio = limpio[2:]
    if not re.fullmatch(r"9\d{8}", limpio):
        raise ValueError("El teléfono debe ser un celular peruano de 9 dígitos que empiece con 9")
    return limpio


# ---------------------------------------------------------------- autenticación
class RegistroEntrada(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)
    telefono: str
    password: str = Field(min_length=8, max_length=64)
    rol: Rol = "agricultor"

    @field_validator("nombre")
    @classmethod
    def _limpiar_nombre(cls, v: str) -> str:
        v = " ".join(v.split())
        if len(v) < 2:
            raise ValueError("El nombre es demasiado corto")
        return v

    @field_validator("telefono")
    @classmethod
    def _validar_telefono(cls, v: str) -> str:
        return normalizar_telefono(v)


class LoginEntrada(BaseModel):
    telefono: str
    password: str = Field(min_length=1, max_length=64)

    @field_validator("telefono")
    @classmethod
    def _validar_telefono(cls, v: str) -> str:
        return normalizar_telefono(v)


class UsuarioSalida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nombre: str
    telefono: str
    rol: str
    creado_en: datetime


class TokenSalida(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expira_en_minutos: int
    usuario: UsuarioSalida


# ---------------------------------------------------------------------- parcelas
class ParcelaEntrada(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)
    variedad: str | None = Field(default=None, max_length=60)
    area_ha: float | None = Field(default=None, gt=0, le=10000)
    distrito: str | None = Field(default=None, max_length=80)
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)
    altitud_msnm: float = Field(ge=0, le=6500)

    @field_validator("nombre", "variedad", "distrito")
    @classmethod
    def _limpiar(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = " ".join(v.split())
        return v or None


class ParcelaSalida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nombre: str
    variedad: str | None
    area_ha: float | None
    distrito: str | None
    latitud: float
    longitud: float
    altitud_msnm: float
    creado_en: datetime


# ------------------------------------------------------------------ diagnósticos
class DiagnosticoSalida(BaseModel):
    id: int
    client_uuid: str
    parcela_id: int
    parcela_nombre: str
    latitud: float
    longitud: float
    capturado_en: datetime
    creado_en: datetime

    diagnostico: str = Field(description="hoja_sana | tizon_tardio | tizon_temprano")
    nombre_diagnostico: str
    semaforo: Literal["verde", "ambar", "rojo"]
    confianza: float = Field(ge=0, le=1)
    confianza_porcentaje: float
    poco_concluyente: bool
    probabilidades: dict[str, float]
    recomendaciones: list[str]
    aviso: str
    modelo_version: str
    modo_demostracion: bool
    advertencia_modelo: str | None = None
    miniatura_base64: str | None = None
    duplicado: bool = False

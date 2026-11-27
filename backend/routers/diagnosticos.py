"""POST /v1/diagnosticos (multipart con imagen) y GET /v1/diagnosticos (historial)."""
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, File, Form, HTTPException, Query, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import joinedload

import clasificador as ia
from config import obtener_configuracion
from dependencias import SesionDep, UsuarioDep
from esquemas import DiagnosticoSalida
from imagenes import ImagenInvalida, abrir_imagen, guardar_jpeg, miniatura_base64
from modelos import Diagnostico, Parcela
from recomendaciones import AVISO, obtener_recomendaciones

log = logging.getLogger("papasalud.diagnosticos")
router = APIRouter(prefix="/diagnosticos", tags=["Diagnósticos"])


def _semaforo(clase: str, poco_concluyente: bool) -> str:
    if poco_concluyente:
        return "ambar"
    return "verde" if clase == "hoja_sana" else "rojo"


def _a_salida(d: Diagnostico, duplicado: bool = False) -> DiagnosticoSalida:
    return DiagnosticoSalida(
        id=d.id,
        client_uuid=d.client_uuid,
        parcela_id=d.parcela_id,
        parcela_nombre=d.parcela.nombre,
        latitud=d.latitud,
        longitud=d.longitud,
        capturado_en=d.capturado_en,
        creado_en=d.creado_en,
        diagnostico=d.diagnostico,
        nombre_diagnostico=ia.NOMBRES[d.diagnostico],
        semaforo=_semaforo(d.diagnostico, d.poco_concluyente),
        confianza=d.confianza,
        confianza_porcentaje=round(d.confianza * 100, 1),
        poco_concluyente=d.poco_concluyente,
        probabilidades=d.probabilidades,
        recomendaciones=d.recomendaciones,
        aviso=AVISO,
        modelo_version=d.modelo_version,
        modo_demostracion=d.modo_demostracion,
        advertencia_modelo=ia.ADVERTENCIA_DEMO if d.modo_demostracion else None,
        miniatura_base64=d.miniatura_base64,
        duplicado=duplicado,
    )


def _leer_limitado(archivo: UploadFile, limite_bytes: int) -> bytes:
    contenido = archivo.file.read(limite_bytes + 1)
    if len(contenido) > limite_bytes:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            f"La imagen supera el máximo de {limite_bytes // (1024 * 1024)} MB",
        )
    return contenido


def _buscar_previo(sesion, usuario_id: int, identificador: str) -> Diagnostico | None:
    return sesion.scalar(
        select(Diagnostico)
        .options(joinedload(Diagnostico.parcela))
        .where(Diagnostico.usuario_id == usuario_id, Diagnostico.client_uuid == identificador)
    )


@router.post("", response_model=DiagnosticoSalida, status_code=status.HTTP_201_CREATED)
def crear_diagnostico(
    respuesta: Response,
    usuario: UsuarioDep,
    sesion: SesionDep,
    client_uuid: Annotated[UUID, Form(description="UUID v4 generado por el cliente (idempotencia)")],
    parcela_id: Annotated[int, Form(ge=1)],
    latitud: Annotated[float, Form(ge=-90, le=90)],
    longitud: Annotated[float, Form(ge=-180, le=180)],
    capturado_en: Annotated[datetime, Form(description="Fecha y hora de captura en formato ISO 8601")],
    imagen: Annotated[UploadFile, File(description="Foto de la hoja (JPG, PNG o WEBP)")],
) -> DiagnosticoSalida:
    """Clasifica la hoja y guarda el resultado.

    Si el mismo usuario reenvía el mismo client_uuid, no se crea un registro nuevo: se devuelve
    el resultado anterior con duplicado=true y código 200.
    """
    config = obtener_configuracion()
    identificador = str(client_uuid)

    parcela = sesion.scalar(
        select(Parcela).where(Parcela.id == parcela_id, Parcela.usuario_id == usuario.id)
    )
    if parcela is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "La parcela no existe o no es suya")

    previo = _buscar_previo(sesion, usuario.id, identificador)
    if previo is not None:
        respuesta.status_code = status.HTTP_200_OK
        return _a_salida(previo, duplicado=True)

    contenido = _leer_limitado(imagen, config.max_mb_imagen * 1024 * 1024)
    try:
        foto = abrir_imagen(contenido)
    except ImagenInvalida as error:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(error)) from None

    try:
        resultado = ia.obtener_clasificador().clasificar(foto)
    except Exception:
        log.exception("Falló la clasificación de la imagen")
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "El servicio de diagnóstico no está disponible. Intente de nuevo en unos minutos",
        ) from None

    poco_concluyente = resultado.confianza < config.umbral_certeza
    ruta = Path(config.carpeta_imagenes) / f"{usuario.id}_{identificador}.jpg"
    guardar_jpeg(foto, ruta)

    if capturado_en.tzinfo is None:
        capturado_en = capturado_en.replace(tzinfo=timezone.utc)

    diagnostico = Diagnostico(
        client_uuid=identificador,
        usuario_id=usuario.id,
        parcela_id=parcela.id,
        latitud=latitud,
        longitud=longitud,
        capturado_en=capturado_en,
        imagen_ruta=str(ruta),
        miniatura_base64=miniatura_base64(foto),
        diagnostico=resultado.clase,
        confianza=resultado.confianza,
        poco_concluyente=poco_concluyente,
        probabilidades=resultado.probabilidades,
        recomendaciones=obtener_recomendaciones(resultado.clase, poco_concluyente),
        modelo_version=resultado.modelo_version,
        modo_demostracion=resultado.modo_demostracion,
    )
    sesion.add(diagnostico)
    try:
        sesion.commit()
    except IntegrityError:
        # Dos envíos simultáneos con el mismo client_uuid: gana el primero
        sesion.rollback()
        existente = _buscar_previo(sesion, usuario.id, identificador)
        if existente is None:
            raise HTTPException(status.HTTP_409_CONFLICT, "No se pudo guardar el diagnóstico") from None
        respuesta.status_code = status.HTTP_200_OK
        return _a_salida(existente, duplicado=True)

    diagnostico.parcela = parcela
    return _a_salida(diagnostico)


@router.get("", response_model=list[DiagnosticoSalida])
def listar_diagnosticos(
    usuario: UsuarioDep,
    sesion: SesionDep,
    limite: Annotated[int, Query(ge=1, le=100)] = 20,
    antes_de_id: Annotated[int | None, Query(ge=1, description="Paginación: devuelve los anteriores a este id")] = None,
    parcela_id: Annotated[int | None, Query(ge=1)] = None,
    diagnostico: Annotated[Literal["hoja_sana", "tizon_tardio", "tizon_temprano"] | None, Query()] = None,
) -> list[DiagnosticoSalida]:
    """Historial del usuario, del más reciente al más antiguo."""
    consulta = (
        select(Diagnostico)
        .options(joinedload(Diagnostico.parcela))
        .where(Diagnostico.usuario_id == usuario.id)
        .order_by(Diagnostico.id.desc())
        .limit(limite)
    )
    if antes_de_id is not None:
        consulta = consulta.where(Diagnostico.id < antes_de_id)
    if parcela_id is not None:
        consulta = consulta.where(Diagnostico.parcela_id == parcela_id)
    if diagnostico is not None:
        consulta = consulta.where(Diagnostico.diagnostico == diagnostico)
    return [_a_salida(d) for d in sesion.scalars(consulta).unique()]

"""GET /v1/parcelas y POST /v1/parcelas."""
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from dependencias import SesionDep, UsuarioDep
from esquemas import ParcelaEntrada, ParcelaSalida
from modelos import Parcela

router = APIRouter(prefix="/parcelas", tags=["Parcelas"])


@router.get("", response_model=list[ParcelaSalida])
def listar_parcelas(usuario: UsuarioDep, sesion: SesionDep) -> list[Parcela]:
    """Parcelas del usuario autenticado, ordenadas por nombre."""
    consulta = select(Parcela).where(Parcela.usuario_id == usuario.id).order_by(Parcela.nombre)
    return list(sesion.scalars(consulta))


@router.post("", response_model=ParcelaSalida, status_code=status.HTTP_201_CREATED)
def crear_parcela(datos: ParcelaEntrada, usuario: UsuarioDep, sesion: SesionDep) -> Parcela:
    """Registra una parcela con sus coordenadas (grados decimales) y altitud en m s. n. m."""
    repetida = sesion.scalar(
        select(Parcela.id).where(
            Parcela.usuario_id == usuario.id,
            func.lower(Parcela.nombre) == datos.nombre.lower(),
        )
    )
    if repetida is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ya tiene una parcela con ese nombre")

    parcela = Parcela(usuario_id=usuario.id, **datos.model_dump())
    sesion.add(parcela)
    try:
        sesion.commit()
    except IntegrityError:
        sesion.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Ya tiene una parcela con ese nombre") from None
    return parcela

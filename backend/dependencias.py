"""Dependencias compartidas de los endpoints: sesión de base de datos y usuario autenticado."""
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from base_datos import obtener_sesion
from modelos import Usuario
from seguridad import decodificar_token

esquema_bearer = HTTPBearer(auto_error=False, description="Pegue el access_token obtenido en /v1/auth/login")

SesionDep = Annotated[Session, Depends(obtener_sesion)]


def _no_autorizado(detalle: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detalle,
        headers={"WWW-Authenticate": "Bearer"},
    )


def usuario_actual(
    credenciales: Annotated[HTTPAuthorizationCredentials | None, Depends(esquema_bearer)],
    sesion: SesionDep,
) -> Usuario:
    if credenciales is None:
        raise _no_autorizado("Falta iniciar sesión")
    try:
        carga = decodificar_token(credenciales.credentials)
    except jwt.ExpiredSignatureError:
        raise _no_autorizado("La sesión venció. Inicie sesión de nuevo") from None
    except jwt.InvalidTokenError:
        raise _no_autorizado("Sesión inválida. Inicie sesión de nuevo") from None

    try:
        usuario_id = int(carga.get("sub", 0))
    except (TypeError, ValueError):
        raise _no_autorizado("Sesión inválida. Inicie sesión de nuevo") from None
    usuario = sesion.get(Usuario, usuario_id)
    if usuario is None or not usuario.activo:
        raise _no_autorizado("La cuenta no existe o está desactivada")
    return usuario


UsuarioDep = Annotated[Usuario, Depends(usuario_actual)]

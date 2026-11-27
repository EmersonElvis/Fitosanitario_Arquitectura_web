"""POST /v1/auth/register, POST /v1/auth/login y GET /v1/auth/yo."""
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from config import obtener_configuracion
from dependencias import SesionDep, UsuarioDep
from esquemas import LoginEntrada, RegistroEntrada, TokenSalida, UsuarioSalida
from modelos import Usuario
from seguridad import HASH_FICTICIO, crear_token, generar_hash, verificar_password

router = APIRouter(prefix="/auth", tags=["Autenticación"])


@router.post("/register", response_model=UsuarioSalida, status_code=status.HTTP_201_CREATED)
def registrar(datos: RegistroEntrada, sesion: SesionDep) -> Usuario:
    """Crea una cuenta. El teléfono (9 dígitos) es el identificador de inicio de sesión."""
    existente = sesion.scalar(select(Usuario).where(Usuario.telefono == datos.telefono))
    if existente is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ya existe una cuenta con ese teléfono")

    usuario = Usuario(
        nombre=datos.nombre,
        telefono=datos.telefono,
        password_hash=generar_hash(datos.password),
        rol=datos.rol,
    )
    sesion.add(usuario)
    try:
        sesion.commit()
    except IntegrityError:
        sesion.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Ya existe una cuenta con ese teléfono") from None
    return usuario


@router.post("/login", response_model=TokenSalida)
def iniciar_sesion(datos: LoginEntrada, sesion: SesionDep) -> TokenSalida:
    """Devuelve un access_token JWT (usar como Authorization: Bearer <token>)."""
    usuario = sesion.scalar(select(Usuario).where(Usuario.telefono == datos.telefono))
    # Se verifica siempre un hash para que la respuesta tarde igual si el usuario no existe
    hash_guardado = usuario.password_hash if usuario else HASH_FICTICIO
    correcto = verificar_password(datos.password, hash_guardado)
    if usuario is None or not correcto or not usuario.activo:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Teléfono o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    config = obtener_configuracion()
    return TokenSalida(
        access_token=crear_token(usuario.id, usuario.rol),
        expira_en_minutos=config.jwt_minutos,
        usuario=UsuarioSalida.model_validate(usuario),
    )


@router.get("/yo", response_model=UsuarioSalida)
def perfil(usuario: UsuarioDep) -> Usuario:
    """Devuelve el usuario del token; sirve para comprobar que la sesión sigue vigente."""
    return usuario

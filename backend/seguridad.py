"""Contraseñas (PBKDF2-SHA256 de la biblioteca estándar) y tokens JWT."""
import base64
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt

from config import obtener_configuracion

_ITERACIONES = 600_000  # recomendación de OWASP para PBKDF2-HMAC-SHA256


def _b64(datos: bytes) -> str:
    return base64.b64encode(datos).decode("ascii")


def generar_hash(password: str) -> str:
    sal = os.urandom(16)
    derivada = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), sal, _ITERACIONES)
    return f"pbkdf2_sha256${_ITERACIONES}${_b64(sal)}${_b64(derivada)}"


def verificar_password(password: str, hash_guardado: str) -> bool:
    try:
        algoritmo, iteraciones, sal_b64, hash_b64 = hash_guardado.split("$")
        if algoritmo != "pbkdf2_sha256":
            return False
        sal = base64.b64decode(sal_b64)
        esperado = base64.b64decode(hash_b64)
        derivada = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), sal, int(iteraciones))
        return hmac.compare_digest(derivada, esperado)
    except (ValueError, TypeError):
        return False


# Hash ficticio para que el inicio de sesión tarde lo mismo exista o no el usuario
HASH_FICTICIO = generar_hash("contraseña-ficticia-no-usar")


def crear_token(usuario_id: int, rol: str) -> str:
    config = obtener_configuracion()
    ahora = datetime.now(timezone.utc)
    carga = {
        "sub": str(usuario_id),
        "rol": rol,
        "iat": ahora,
        "exp": ahora + timedelta(minutes=config.jwt_minutos),
    }
    return jwt.encode(carga, config.jwt_secreto, algorithm=config.jwt_algoritmo)


def decodificar_token(token: str) -> dict:
    config = obtener_configuracion()
    return jwt.decode(token, config.jwt_secreto, algorithms=[config.jwt_algoritmo])

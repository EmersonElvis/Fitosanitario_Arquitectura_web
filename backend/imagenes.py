"""Validación y procesamiento seguro de las imágenes recibidas."""
import base64
import io
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

# Protección contra "bombas de descompresión": imágenes enormes que agotan la memoria
Image.MAX_IMAGE_PIXELS = 40_000_000

FORMATOS_PERMITIDOS = {"JPEG", "PNG", "WEBP"}
LADO_MINIMO = 64
LADO_MAXIMO_GUARDADO = 1600


class ImagenInvalida(ValueError):
    """La imagen no se puede usar; el mensaje se muestra al usuario."""


def abrir_imagen(contenido: bytes) -> Image.Image:
    if not contenido:
        raise ImagenInvalida("El archivo de imagen está vacío")
    try:
        with Image.open(io.BytesIO(contenido)) as prueba:
            formato = prueba.format
            prueba.verify()
        if formato not in FORMATOS_PERMITIDOS:
            raise ImagenInvalida("Formato no admitido. Use una imagen JPG, PNG o WEBP")
        imagen = Image.open(io.BytesIO(contenido))
        imagen.load()
    except ImagenInvalida:
        raise
    except Image.DecompressionBombError:
        raise ImagenInvalida("La imagen tiene una resolución demasiado grande") from None
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError):
        raise ImagenInvalida("El archivo no es una imagen válida o está dañado") from None

    transpuesta = ImageOps.exif_transpose(imagen)
    imagen = (transpuesta or imagen).convert("RGB")
    if min(imagen.size) < LADO_MINIMO:
        raise ImagenInvalida(f"La imagen es muy pequeña (mínimo {LADO_MINIMO} píxeles por lado)")
    return imagen


def guardar_jpeg(imagen: Image.Image, ruta: Path) -> None:
    """Guarda una copia reducida en JPEG. Al reescribirla se eliminan los metadatos EXIF
    (por ejemplo, la ubicación GPS incrustada por el teléfono)."""
    copia = imagen.copy()
    copia.thumbnail((LADO_MAXIMO_GUARDADO, LADO_MAXIMO_GUARDADO))
    ruta.parent.mkdir(parents=True, exist_ok=True)
    copia.save(ruta, "JPEG", quality=90, optimize=True)


def miniatura_base64(imagen: Image.Image, lado: int = 160) -> str:
    copia = imagen.copy()
    copia.thumbnail((lado, lado))
    memoria = io.BytesIO()
    copia.save(memoria, "JPEG", quality=70)
    return base64.b64encode(memoria.getvalue()).decode("ascii")

"""Pruebas de la API /v1 de PapaSalud Ayacucho."""
import io
import json
import uuid
from datetime import datetime, timezone

import numpy as np
import pytest
from PIL import Image, ImageDraw

ORIGEN_FLUTTER = "http://localhost:8080"


# ------------------------------------------------------------------ utilidades
def png_bytes(imagen: Image.Image, formato: str = "JPEG") -> bytes:
    memoria = io.BytesIO()
    imagen.save(memoria, formato)
    return memoria.getvalue()


def hoja_sana(lado: int = 300) -> Image.Image:
    rng = np.random.default_rng(1)
    base = np.zeros((lado, lado, 3), dtype=np.uint8)
    base[..., 0] = 40 + rng.integers(0, 15, (lado, lado))
    base[..., 1] = 140 + rng.integers(0, 25, (lado, lado))
    base[..., 2] = 45 + rng.integers(0, 15, (lado, lado))
    return Image.fromarray(base)


def hoja_con_manchas(lado: int = 300) -> Image.Image:
    imagen = hoja_sana(lado)
    dibujo = ImageDraw.Draw(imagen)
    for x, y in [(80, 90), (180, 120), (120, 200), (210, 210), (70, 170)]:
        dibujo.ellipse((x - 30, y - 30, x + 30, y + 30), fill=(70, 45, 25))
    return imagen


@pytest.fixture(scope="session")
def telefono_base() -> str:
    return "9" + str(uuid.uuid4().int)[:8]


@pytest.fixture(scope="session")
def sesion_agricultor(cliente, telefono_base):
    r = cliente.post(
        "/v1/auth/register",
        json={"nombre": "Juan Quispe", "telefono": telefono_base, "password": "Clave12345", "rol": "agricultor"},
    )
    assert r.status_code == 201, r.text
    r = cliente.post("/v1/auth/login", json={"telefono": telefono_base, "password": "Clave12345"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture(scope="session")
def parcela(cliente, sesion_agricultor):
    r = cliente.post(
        "/v1/parcelas",
        headers=sesion_agricultor,
        json={
            "nombre": "Chacra Norte",
            "variedad": "Huayro",
            "area_ha": 1.5,
            "distrito": "Ayacucho",
            "latitud": -13.1588,
            "longitud": -74.2232,
            "altitud_msnm": 2746,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def enviar_diagnostico(cliente, cabeceras, parcela_id, imagen_bytes, client_uuid=None, nombre="hoja.jpg", tipo="image/jpeg"):
    return cliente.post(
        "/v1/diagnosticos",
        headers=cabeceras,
        data={
            "client_uuid": client_uuid or str(uuid.uuid4()),
            "parcela_id": str(parcela_id),
            "latitud": "-13.1588",
            "longitud": "-74.2232",
            "capturado_en": datetime.now(timezone.utc).isoformat(),
        },
        files={"imagen": (nombre, imagen_bytes, tipo)},
    )


# ------------------------------------------------------------------ estado y CORS
def test_salud(cliente):
    r = cliente.get("/health")
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["base_datos"] is True
    assert cuerpo["modo_demostracion"] is True  # en pruebas no hay modelo ONNX


def test_preflight_cors_desde_flutter_web(cliente):
    r = cliente.options(
        "/v1/auth/register",
        headers={
            "Origin": ORIGEN_FLUTTER,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,authorization",
        },
    )
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] in ("*", ORIGEN_FLUTTER)
    permitidas = r.headers["access-control-allow-headers"].lower()
    assert "authorization" in permitidas and "content-type" in permitidas
    assert "POST" in r.headers["access-control-allow-methods"]


def test_cabeceras_cors_en_respuestas_normales_y_de_error(cliente):
    ok = cliente.get("/health", headers={"Origin": ORIGEN_FLUTTER})
    assert "access-control-allow-origin" in ok.headers
    error = cliente.get("/v1/parcelas", headers={"Origin": ORIGEN_FLUTTER})  # sin token
    assert error.status_code == 401
    assert "access-control-allow-origin" in error.headers


def test_error_500_devuelve_json_con_cabeceras_cors(cliente):
    from main import app

    @app.get("/__error_de_prueba", include_in_schema=False)
    def _falla():
        raise RuntimeError("fallo simulado")

    r = cliente.get("/__error_de_prueba", headers={"Origin": ORIGEN_FLUTTER})
    assert r.status_code == 500
    assert r.json()["detail"].startswith("Error interno")
    assert "access-control-allow-origin" in r.headers


# --------------------------------------------------------------------- registro
def test_registro_exitoso_no_expone_la_contrasena(cliente):
    telefono = "9" + str(uuid.uuid4().int)[:8]
    r = cliente.post(
        "/v1/auth/register",
        json={"nombre": "María  Huamán", "telefono": f"+51 {telefono[:3]} {telefono[3:6]} {telefono[6:]}", "password": "OtraClave99", "rol": "tecnico"},
    )
    assert r.status_code == 201, r.text
    cuerpo = r.json()
    assert cuerpo["telefono"] == telefono
    assert cuerpo["nombre"] == "María Huamán"
    assert cuerpo["rol"] == "tecnico"
    assert "password" not in cuerpo and "password_hash" not in cuerpo


def test_registro_duplicado_409(cliente, telefono_base, sesion_agricultor):
    r = cliente.post(
        "/v1/auth/register",
        json={"nombre": "Otro", "telefono": telefono_base, "password": "Clave12345", "rol": "agricultor"},
    )
    assert r.status_code == 409


@pytest.mark.parametrize(
    "cuerpo, campo",
    [
        ({"nombre": "Ana", "telefono": "12345", "password": "Clave12345", "rol": "agricultor"}, "telefono"),
        ({"nombre": "Ana", "telefono": "987654321", "password": "corta", "rol": "agricultor"}, "password"),
        ({"nombre": "Ana", "telefono": "987654321", "password": "Clave12345", "rol": "administrador"}, "rol"),
        ({"telefono": "987654321", "password": "Clave12345"}, "nombre"),
    ],
)
def test_registro_422_indica_el_campo(cliente, cuerpo, campo):
    r = cliente.post("/v1/auth/register", json=cuerpo)
    assert r.status_code == 422
    assert campo in [e["campo"] for e in r.json()["errores"]]


def test_registro_con_json_roto_da_422_con_ayuda_para_powershell(cliente):
    # Lo que llega cuando PowerShell se come las comillas: {nombre:Juan,telefono:987654321}
    r = cliente.post(
        "/v1/auth/register",
        content=b"{nombre:Juan,telefono:987654321}",
        headers={"Content-Type": "application/json"},
    )
    assert r.status_code == 422
    assert "ayuda" in r.json()


def test_registro_sin_content_type_json_da_422_con_ayuda(cliente):
    r = cliente.post(
        "/v1/auth/register",
        content=b'{"nombre":"Juan","telefono":"987654321","password":"Clave12345"}',
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    assert r.status_code == 422
    assert "ayuda" in r.json()


# ------------------------------------------------------------------------ login
def test_login_devuelve_jwt(cliente, telefono_base, sesion_agricultor):
    r = cliente.post("/v1/auth/login", json={"telefono": telefono_base, "password": "Clave12345"})
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["token_type"] == "bearer"
    assert cuerpo["access_token"].count(".") == 2
    assert cuerpo["usuario"]["telefono"] == telefono_base


def test_login_incorrecto_401_mismo_mensaje_si_no_existe(cliente, telefono_base, sesion_agricultor):
    mal = cliente.post("/v1/auth/login", json={"telefono": telefono_base, "password": "incorrecta1"})
    inexistente = cliente.post("/v1/auth/login", json={"telefono": "900000000", "password": "incorrecta1"})
    assert mal.status_code == inexistente.status_code == 401
    assert mal.json()["detail"] == inexistente.json()["detail"]


def test_endpoints_protegidos_exigen_token(cliente):
    assert cliente.get("/v1/parcelas").status_code == 401
    assert cliente.get("/v1/diagnosticos").status_code == 401
    assert cliente.get("/v1/parcelas", headers={"Authorization": "Bearer abc.def.ghi"}).status_code == 401


def test_perfil(cliente, sesion_agricultor, telefono_base):
    r = cliente.get("/v1/auth/yo", headers=sesion_agricultor)
    assert r.status_code == 200 and r.json()["telefono"] == telefono_base


# --------------------------------------------------------------------- parcelas
def test_parcelas_crear_y_listar(cliente, sesion_agricultor, parcela):
    assert parcela["altitud_msnm"] == 2746
    r = cliente.get("/v1/parcelas", headers=sesion_agricultor)
    assert r.status_code == 200
    assert [p["nombre"] for p in r.json()] == ["Chacra Norte"]


def test_parcela_duplicada_409_sin_importar_mayusculas(cliente, sesion_agricultor, parcela):
    r = cliente.post(
        "/v1/parcelas",
        headers=sesion_agricultor,
        json={"nombre": "chacra norte", "latitud": -13.1, "longitud": -74.2, "altitud_msnm": 3000},
    )
    assert r.status_code == 409


@pytest.mark.parametrize(
    "cambio",
    [{"latitud": 95}, {"longitud": -200}, {"altitud_msnm": -5}, {"altitud_msnm": 9000}, {"area_ha": 0}],
)
def test_parcela_valores_fuera_de_rango_422(cliente, sesion_agricultor, cambio):
    cuerpo = {"nombre": "Prueba rango", "latitud": -13.1, "longitud": -74.2, "altitud_msnm": 3000, **cambio}
    r = cliente.post("/v1/parcelas", headers=sesion_agricultor, json=cuerpo)
    assert r.status_code == 422


# ------------------------------------------------------------------ diagnósticos
def test_diagnostico_hoja_sana(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], png_bytes(hoja_sana()))
    assert r.status_code == 201, r.text
    d = r.json()
    assert d["diagnostico"] == "hoja_sana"
    assert d["semaforo"] == "verde"
    assert 0 <= d["confianza"] <= 1
    assert d["confianza_porcentaje"] == round(d["confianza"] * 100, 1)
    assert abs(sum(d["probabilidades"].values()) - 1) < 1e-3
    assert len(d["recomendaciones"]) >= 3
    assert d["modo_demostracion"] is True and d["advertencia_modelo"]
    assert d["parcela_nombre"] == "Chacra Norte"
    assert d["miniatura_base64"]


def test_diagnostico_con_manchas_no_sale_sano(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], png_bytes(hoja_con_manchas()))
    assert r.status_code == 201, r.text
    assert r.json()["diagnostico"] in ("tizon_tardio", "tizon_temprano")


def test_diagnostico_es_idempotente_por_client_uuid(cliente, sesion_agricultor, parcela):
    identificador = str(uuid.uuid4())
    imagen = png_bytes(hoja_sana())
    primero = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], imagen, identificador)
    segundo = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], imagen, identificador)
    assert primero.status_code == 201 and segundo.status_code == 200
    assert primero.json()["id"] == segundo.json()["id"]
    assert primero.json()["duplicado"] is False and segundo.json()["duplicado"] is True


def test_diagnostico_acepta_png(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], png_bytes(hoja_sana(), "PNG"), nombre="hoja.png", tipo="image/png")
    assert r.status_code == 201, r.text


def test_diagnostico_imagen_invalida_400(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], b"esto no es una imagen")
    assert r.status_code == 400


def test_diagnostico_imagen_muy_pequena_400(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], png_bytes(Image.new("RGB", (20, 20), (0, 120, 0))))
    assert r.status_code == 400


def test_diagnostico_imagen_demasiado_grande_413(cliente, sesion_agricultor, parcela):
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], b"\xff\xd8" + b"0" * (2 * 1024 * 1024))
    assert r.status_code == 413


def test_diagnostico_parcela_ajena_404(cliente, sesion_agricultor, parcela):
    telefono = "9" + str(uuid.uuid4().int)[:8]
    cliente.post("/v1/auth/register", json={"nombre": "Otro Usuario", "telefono": telefono, "password": "Clave12345"})
    token = cliente.post("/v1/auth/login", json={"telefono": telefono, "password": "Clave12345"}).json()["access_token"]
    ajeno = {"Authorization": f"Bearer {token}"}
    r = enviar_diagnostico(cliente, ajeno, parcela["id"], png_bytes(hoja_sana()))
    assert r.status_code == 404
    # y no ve el historial de otros
    assert cliente.get("/v1/diagnosticos", headers=ajeno).json() == []


def test_diagnostico_campos_invalidos_422(cliente, sesion_agricultor, parcela):
    r = cliente.post(
        "/v1/diagnosticos",
        headers=sesion_agricultor,
        data={"client_uuid": "no-es-uuid", "parcela_id": str(parcela["id"]), "latitud": "200", "longitud": "-74", "capturado_en": "ayer"},
        files={"imagen": ("hoja.jpg", png_bytes(hoja_sana()), "image/jpeg")},
    )
    assert r.status_code == 422
    campos = {e["campo"] for e in r.json()["errores"]}
    assert {"client_uuid", "latitud", "capturado_en"} <= campos


def test_diagnostico_sin_imagen_422(cliente, sesion_agricultor, parcela):
    r = cliente.post(
        "/v1/diagnosticos",
        headers=sesion_agricultor,
        data={"client_uuid": str(uuid.uuid4()), "parcela_id": str(parcela["id"]), "latitud": "-13.1", "longitud": "-74.2", "capturado_en": "2026-11-25T10:00:00-05:00"},
    )
    assert r.status_code == 422


def test_historial_orden_paginacion_y_filtros(cliente, sesion_agricultor, parcela):
    completo = cliente.get("/v1/diagnosticos", headers=sesion_agricultor, params={"limite": 100})
    assert completo.status_code == 200
    ids = [d["id"] for d in completo.json()]
    assert ids == sorted(ids, reverse=True) and len(ids) >= 3

    pagina = cliente.get("/v1/diagnosticos", headers=sesion_agricultor, params={"limite": 2})
    assert [d["id"] for d in pagina.json()] == ids[:2]
    siguiente = cliente.get("/v1/diagnosticos", headers=sesion_agricultor, params={"limite": 2, "antes_de_id": ids[1]})
    assert [d["id"] for d in siguiente.json()] == ids[2:4]

    sanas = cliente.get("/v1/diagnosticos", headers=sesion_agricultor, params={"diagnostico": "hoja_sana"}).json()
    assert sanas and all(d["diagnostico"] == "hoja_sana" for d in sanas)
    assert cliente.get("/v1/diagnosticos", headers=sesion_agricultor, params={"diagnostico": "otra"}).status_code == 422


def test_el_exif_con_gps_no_se_conserva_en_la_copia_guardada(cliente, sesion_agricultor, parcela):
    imagen = hoja_sana()
    exif = Image.Exif()
    exif[0x8825] = {1: "S", 2: (13.0, 9.0, 31.0)}  # bloque GPS
    memoria = io.BytesIO()
    imagen.save(memoria, "JPEG", exif=exif)
    r = enviar_diagnostico(cliente, sesion_agricultor, parcela["id"], memoria.getvalue())
    assert r.status_code == 201
    from config import obtener_configuracion
    from pathlib import Path

    guardadas = list(Path(obtener_configuracion().carpeta_imagenes).glob("*.jpg"))
    assert guardadas
    with Image.open(guardadas[0]) as copia:
        assert not copia.getexif().get(0x8825)


# ------------------------------------------------------------- clasificador ONNX
def crear_modelo_onnx_de_prueba(ruta, clase_ganadora: int):
    """Modelo mínimo: promedia los canales y los pasa por una capa lineal con sesgo fijo."""
    import onnx
    from onnx import TensorProto, helper, numpy_helper

    pesos = numpy_helper.from_array(np.zeros((3, 3), dtype=np.float32), "pesos")
    sesgo_valores = np.zeros(3, dtype=np.float32)
    sesgo_valores[clase_ganadora] = 5.0
    sesgo = numpy_helper.from_array(sesgo_valores, "sesgo")
    nodos = [
        helper.make_node("ReduceMean", ["entrada"], ["promedio"], axes=[2, 3], keepdims=0),
        helper.make_node("MatMul", ["promedio", "pesos"], ["lineal"]),
        helper.make_node("Add", ["lineal", "sesgo"], ["logits"]),
    ]
    grafo = helper.make_graph(
        nodos,
        "modelo_prueba",
        [helper.make_tensor_value_info("entrada", TensorProto.FLOAT, ["lote", 3, 224, 224])],
        [helper.make_tensor_value_info("logits", TensorProto.FLOAT, ["lote", 3])],
        initializer=[pesos, sesgo],
    )
    modelo = helper.make_model(grafo, opset_imports=[helper.make_opsetid("", 13)])
    modelo.ir_version = 8
    onnx.save(modelo, str(ruta))


def test_clasificador_onnx_usa_el_modelo_y_el_orden_de_clases(tmp_path):
    from clasificador import ClasificadorOnnx

    ruta = tmp_path / "papa_hojas.onnx"
    crear_modelo_onnx_de_prueba(ruta, clase_ganadora=1)
    clases = tmp_path / "clases.json"
    clases.write_text(json.dumps(["hoja_sana", "tizon_temprano", "tizon_tardio"]), encoding="utf-8")

    resultado = ClasificadorOnnx(ruta, clases).clasificar(hoja_sana())
    assert resultado.clase == "tizon_temprano"  # índice 1 según clases.json
    assert resultado.modo_demostracion is False
    assert resultado.confianza > 0.95
    assert abs(sum(resultado.probabilidades.values()) - 1) < 1e-4
    assert resultado.modelo_version.startswith("onnx-papa_hojas-")


def test_clasificador_onnx_rechaza_clases_incorrectas(tmp_path):
    from clasificador import ClasificadorOnnx

    ruta = tmp_path / "m.onnx"
    crear_modelo_onnx_de_prueba(ruta, 0)
    clases = tmp_path / "clases.json"
    clases.write_text(json.dumps(["a", "b", "c"]), encoding="utf-8")
    with pytest.raises(ValueError):
        ClasificadorOnnx(ruta, clases)

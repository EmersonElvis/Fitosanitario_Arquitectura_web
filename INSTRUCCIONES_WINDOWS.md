# PapaSalud Ayacucho: instrucciones de ejecución en Windows (PowerShell)

Backend FastAPI en el puerto **8000** y cliente Flutter Web en el puerto **8080**.

## 0. Contenido

```text
papasalud/
├── INSTRUCCIONES_WINDOWS.md
├── probar_api.ps1                # prueba de extremo a extremo desde PowerShell
├── backend/                      # FastAPI + PostgreSQL
│   ├── main.py                   # aplicación, CORS y manejo de errores
│   ├── config.py  base_datos.py  modelos.py  esquemas.py  seguridad.py
│   ├── dependencias.py  imagenes.py  clasificador.py  recomendaciones.py
│   ├── routers/                  # auth.py, parcelas.py, diagnosticos.py
│   ├── modelos/                  # aquí va papa_hojas.onnx (opcional)
│   ├── tests/                    # 37 pruebas automáticas
│   ├── requirements.txt  requirements-dev.txt  .env.example
├── frontend/                     # solo pubspec.yaml y lib/main.dart de Flutter
└── ml/                           # entrenamiento y exportación del modelo a ONNX
```

## 1. Requisitos

| Programa | Versión | Comprobación |
|---|---|---|
| Python | 3.10 o superior (probado con 3.12). Al instalar, marque *Add python.exe to PATH* | `python --version` |
| PostgreSQL | 14 o superior, con la contraseña del usuario `postgres` que definió al instalar | `psql --version` (si no se reconoce, use la ruta completa, ver sección 2) |
| Flutter SDK | Canal estable, con soporte web | `flutter --version` y `flutter doctor` |
| Google Chrome | Reciente | |

Si PowerShell bloquea los scripts (`Activate.ps1`, `probar_api.ps1`), ejecute una vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## 2. Base de datos PostgreSQL

Cree la base (cambie `16` por su versión de PostgreSQL). Le pedirá la contraseña de `postgres`:

```powershell
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE papasalud;"
```

Las tablas (`usuarios`, `parcelas`, `diagnosticos`) se crean solas la primera vez que inicia el backend.

## 3. Backend (puerto 8000)

```powershell
cd papasalud\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
Copy-Item .env.example .env
notepad .env
```

En `.env` cambie dos valores:

- `PAPASALUD_BASE_DATOS_URL`: reemplace `CAMBIAR_CLAVE` por su contraseña de PostgreSQL. Si la contraseña tiene caracteres como `@`, `:` o `/`, escríbalos codificados (`@` es `%40`, `:` es `%3A`, `/` es `%2F`).
- `PAPASALUD_JWT_SECRETO`: genere uno con este comando y péguelo:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Inicie el servidor (siempre desde la carpeta `backend`):

```powershell
uvicorn main:app --host 127.0.0.1 --port 8000
```

Debe ver líneas como estas (el aviso del modo demostración es normal mientras no haya un modelo ONNX):

```text
WARNING [papasalud.ia] No existe ...papa_hojas.onnx: se usa el MODO DEMOSTRACIÓN (sin modelo entrenado)
INFO [papasalud] Clasificador: demo-heuristico-color-v1 (demostración=True)
INFO:     Uvicorn running on http://127.0.0.1:8000
```

Compruebe que responde (en otra ventana de PowerShell) y abra la documentación interactiva en <http://127.0.0.1:8000/docs>:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Use siempre **127.0.0.1** y no `localhost`: en Windows `localhost` puede resolverse a IPv6 (`::1`) mientras uvicorn escucha en IPv4.

## 4. Probar el backend desde PowerShell

### 4.1 Prueba automática (recomendada)

Con el backend encendido, desde la carpeta `papasalud`:

```powershell
.\probar_api.ps1
.\probar_api.ps1 -Imagen "C:\fotos\hoja.jpg"      # con su propia foto
```

Registra un usuario de prueba, inicia sesión, crea una parcela, envía una foto, repite el envío para comprobar la idempotencia y lista el historial. Termina con `TODO CORRECTO` en verde.

### 4.2 Por qué fallaba el registro con 422

`curl.exe` recibe el JSON tal como PowerShell se lo entrega, y **el manejo de las comillas dobles depende de la versión de PowerShell**:

| Forma de enviar el JSON | PowerShell 7.3 o superior | Windows PowerShell 5.1 (el que trae Windows) |
|---|---|---|
| `-d '{"a":"b"}'` (comillas simples por fuera) | Funciona (probado en 7.7) | Se pierden las comillas dobles: llega `{a:b}` y la API responde 422 |
| `-d '{\"a\":\"b\"}'` (con barras invertidas) | Rompe: llegan las barras y la API responde 422 (probado en 7.7) | Funciona |
| Archivo `.json` con `--data-binary "@archivo.json"` | Funciona (probado) | Funciona |
| `Invoke-RestMethod` con `ConvertTo-Json` | Funciona (probado) | Funciona |

El comportamiento de la versión 5.1 es el documentado de ese motor; no pude ejecutarlo en mi entorno de pruebas. Por eso los comandos de esta guía usan **un archivo JSON**, que funciona igual en todas las versiones. También es obligatorio enviar `Content-Type: application/json`; sin él, `curl` usa `application/x-www-form-urlencoded` y la API responde 422.

El backend ahora responde estos casos con un mensaje claro y un campo `ayuda`, por ejemplo: *"El cuerpo debe ser JSON válido con la cabecera Content-Type: application/json..."*.

### 4.3 Comandos con `curl.exe` (uno por endpoint)

Escriba el JSON en un archivo **sin BOM** (con `Set-Content -Encoding UTF8` en Windows PowerShell 5.1 se agrega un BOM; este método no lo agrega):

```powershell
$sinBom = New-Object System.Text.UTF8Encoding $false
$url = "http://127.0.0.1:8000"
```

**Registro** (`POST /v1/auth/register`):

```powershell
[System.IO.File]::WriteAllText("$PWD\registro.json", '{"nombre":"Juan Quispe","telefono":"987654321","password":"Clave12345","rol":"agricultor"}', $sinBom)
curl.exe -i -X POST "$url/v1/auth/register" -H "Content-Type: application/json" --data-binary "@registro.json"
```

Respuesta esperada: `HTTP/1.1 201 Created`. Si el teléfono ya existe: `409`.

**Inicio de sesión** (`POST /v1/auth/login`), guardando el token JWT:

```powershell
[System.IO.File]::WriteAllText("$PWD\login.json", '{"telefono":"987654321","password":"Clave12345"}', $sinBom)
$respuesta = curl.exe -s -X POST "$url/v1/auth/login" -H "Content-Type: application/json" --data-binary "@login.json"
$token = ($respuesta | ConvertFrom-Json).access_token
$token
```

**Crear parcela** (`POST /v1/parcelas`):

```powershell
[System.IO.File]::WriteAllText("$PWD\parcela.json", '{"nombre":"Chacra Norte","variedad":"Huayro","area_ha":1.5,"distrito":"Ayacucho","latitud":-13.1588,"longitud":-74.2232,"altitud_msnm":2746}', $sinBom)
curl.exe -i -X POST "$url/v1/parcelas" -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data-binary "@parcela.json"
```

**Listar parcelas** (`GET /v1/parcelas`):

```powershell
curl.exe -s "$url/v1/parcelas" -H "Authorization: Bearer $token"
```

**Diagnóstico** (`POST /v1/diagnosticos`, `multipart/form-data`). Cambie la ruta de la foto y el `parcela_id` por el de su parcela:

```powershell
$uuid = [guid]::NewGuid().ToString()
$fecha = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
curl.exe -i -X POST "$url/v1/diagnosticos" `
  -H "Authorization: Bearer $token" `
  -F "client_uuid=$uuid" `
  -F "parcela_id=1" `
  -F "latitud=-13.1588" `
  -F "longitud=-74.2232" `
  -F "capturado_en=$fecha" `
  -F "imagen=@C:\fotos\hoja.jpg;type=image/jpeg"
```

Respuesta esperada: `201 Created` con el diagnóstico, la confianza y las recomendaciones. Si repite **el mismo comando con el mismo `$uuid`**, la respuesta es `200` con `"duplicado": true` y el mismo `id` (no se crea un registro nuevo).

**Historial** (`GET /v1/diagnosticos`):

```powershell
curl.exe -s "$url/v1/diagnosticos?limite=5" -H "Authorization: Bearer $token"
```

Parámetros opcionales: `antes_de_id` (paginación), `parcela_id` y `diagnostico` (`hoja_sana`, `tizon_tardio` o `tizon_temprano`).

### 4.4 Comprobar CORS (el preflight que hace el navegador)

```powershell
curl.exe -i -X OPTIONS "$url/v1/auth/register" -H "Origin: http://localhost:8080" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
```

Debe responder `200 OK` con `access-control-allow-origin`, `access-control-allow-methods` y `access-control-allow-headers`.

## 5. Cliente Flutter Web (puerto 8080)

Con el backend ya encendido, abra **otra** ventana de PowerShell.

**Si todavía no tiene un proyecto Flutter para web**, créelo y copie encima los dos archivos entregados (desde la carpeta `papasalud`):

```powershell
flutter config --enable-web
flutter create --platforms=web --project-name papasalud_ayacucho web_app
Copy-Item .\frontend\pubspec.yaml .\web_app\pubspec.yaml -Force
Copy-Item .\frontend\lib\main.dart .\web_app\lib\main.dart -Force
cd web_app
flutter pub get
flutter run -d chrome --web-port 8080
```

**Si ya tiene un proyecto Flutter**, haga una copia de su `pubspec.yaml` y de `lib/main.dart`, reemplácelos por los entregados (el nombre del paquete no importa) y ejecute:

```powershell
flutter pub get
flutter run -d chrome --web-port 8080
```

La primera compilación tarda unos minutos. La app queda en <http://localhost:8080>. Si Chrome no se abre solo, use el servidor web de Flutter y abra la dirección manualmente:

```powershell
flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1
```

Para probar una versión compilada (sin recarga en caliente):

```powershell
flutter build web
python -m http.server 8080 --directory build\web
```

### Uso de la aplicación

1. En la pantalla de acceso, compruebe la **dirección del servidor** (`http://127.0.0.1:8000`) y pulse **Probar conexión**. Debe aparecer *Conectado*.
2. Pulse **Crear cuenta**: nombre, teléfono de 9 dígitos, contraseña de 8 o más caracteres y rol. Entra directamente.
3. Pestaña **Diagnóstico IA**: cree una parcela (se prellenan las coordenadas y la altitud de Ayacucho), elija o tome una foto de una hoja y pulse **Diagnosticar hoja**. Se muestra el resultado con semáforo, porcentaje de confianza y consejos.
4. Pestaña **Historial**: lista las consultas con miniatura, fecha, parcela, diagnóstico y consejos (toque una para ver los consejos). Arrastre hacia abajo para actualizar.

En un navegador de escritorio, *Tomar foto* y *Elegir imagen* abren el selector de archivos; en un teléfono, *Tomar foto* abre la cámara.

## 6. Solución de problemas

### «ClientException: Failed to fetch» en la aplicación

Revise en este orden:

1. **¿Está encendido el backend?** Abra <http://127.0.0.1:8000/health> en el navegador.
2. **¿La dirección del servidor de la app es exactamente `http://127.0.0.1:8000`?** Evite `localhost`.
3. **Mire la ventana donde corre uvicorn.** Un `Traceback` significa que el backend falló con un error 500 (casi siempre, PostgreSQL apagado o con contraseña incorrecta). Cuando el servidor no agrega cabeceras CORS a un error 500, el navegador lo muestra como *Failed to fetch* y oculta la causa real. Este backend ya responde los 500 con cabeceras CORS y un mensaje JSON, pero el error de fondo sigue figurando en la consola.
4. **Pruebe el preflight** con el comando de la sección 4.4.
5. **Revise que la página y el servidor usen el mismo esquema.** Si la web se sirve por `https` y el backend por `http`, el navegador bloquea la llamada (contenido mixto).
6. **Puerto ocupado o firewall.** Para ver qué usa el puerto 8000:

```powershell
Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess
Stop-Process -Id <OwningProcess>
```

### Códigos de error de la API

| Código | Significado | Qué hacer |
|---|---|---|
| 400 | Imagen inválida o dañada | Use una foto JPG, PNG o WEBP de al menos 64 píxeles por lado |
| 401 | Credenciales incorrectas o sesión vencida | Inicie sesión de nuevo |
| 404 | La parcela no existe o no es suya | Elija una parcela de su lista |
| 409 | Teléfono o nombre de parcela repetido | Use otro valor |
| 413 | Imagen mayor a 8 MB | Reduzca la foto |
| 422 | Datos inválidos | La respuesta indica el campo y el motivo (campo `errores`) |
| 500 | Error interno | Revise la consola del backend |
| 503 | El servicio de diagnóstico falló | Revise la consola del backend |

### Otros

| Problema | Solución |
|---|---|
| `password authentication failed for user "postgres"` | La contraseña de `PAPASALUD_BASE_DATOS_URL` no coincide con la de PostgreSQL |
| `database "papasalud" does not exist` | Cree la base (sección 2) |
| `connection refused` al iniciar | PostgreSQL está apagado: inícielo desde *Servicios* de Windows |
| `ModuleNotFoundError: No module named 'config'` | Ejecute `uvicorn` desde la carpeta `backend` |
| `Activate.ps1 no se puede cargar` | Ejecute el `Set-ExecutionPolicy` de la sección 1 |
| Error al instalar `psycopg2-binary` | Verifique que usa Python 3.10 o superior de 64 bits y actualice `pip` |

## 7. Pasar del modo demostración a un modelo real

Mientras no exista `backend\modelos\papa_hojas.onnx`, el backend usa el **modo demostración**: una regla de colores, **no un modelo de IA entrenado ni validado**. Cada respuesta lo indica (`modo_demostracion: true`) y la app muestra una advertencia. No la use para decidir tratamientos.

Para usar un modelo real:

```powershell
cd papasalud\ml
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-ml.txt
python entrenar_y_exportar.py --datos C:\ruta\datos
```

Los datos deben estar en carpetas `entrenamiento\` y `validacion\`, cada una con `hoja_sana`, `tizon_tardio` y `tizon_temprano` (ver el encabezado del script). El script guarda el modelo y `clases.json` en `backend\modelos\`, muestra la matriz de confusión y comprueba que ONNX Runtime dé el mismo resultado que PyTorch. Reinicie el backend y verifique:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health      # modo_demostracion debe ser False
```

Un modelo entrenado solo con fotos de laboratorio (por ejemplo PlantVillage) suele rendir mucho peor con fotos de campo. Agregue fotos reales de Ayacucho etiquetadas por un ingeniero agrónomo y divida entrenamiento y validación por planta o parcela, no al azar.

## 8. Pruebas automáticas del backend

```powershell
cd papasalud\backend
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
python -m pytest -q
```

Usan una base SQLite temporal. Para ejecutarlas contra PostgreSQL, cree antes una base `papasalud_pruebas` y use:

```powershell
$env:PAPASALUD_PRUEBAS_BASE_DATOS_URL = "postgresql+psycopg2://postgres:SU_CLAVE@localhost:5432/papasalud_pruebas"
python -m pytest -q
```

## 9. Diferencias con el informe (alcance de este prototipo)

| Informe | Este prototipo |
|---|---|
| Inspección y diagnóstico en tablas separadas; ruta `/v1/inspecciones` | Una sola tabla y ruta `/v1/diagnosticos`, como en su backend actual |
| PostGIS (`geography`) | Latitud y longitud como números; no requiere extensiones |
| Inicio de sesión con correo | Inicio de sesión con teléfono (celular peruano de 9 dígitos) |
| JWT de 15 minutos con *refresh token* | JWT de 480 minutos configurables; sin *refresh token* |
| Cola de sincronización offline en SQLite | No incluida: la app necesita conexión. La API ya es idempotente por `client_uuid` |
| Microservicio de IA independiente, Redis, CDN, CI/CD | La clasificación corre dentro del backend; sin Redis ni CDN |
| Rol analista y administrador | El registro público admite `agricultor` y `tecnico` |

## 10. Antes de publicar o entregar

- Defina un `PAPASALUD_JWT_SECRETO` propio y no suba `.env` a GitHub.
- En producción use HTTPS, ponga `PAPASALUD_CORS_PERMITIR_TODOS=false` y liste los orígenes en `PAPASALUD_CORS_ORIGENES_EXTRA`. Hoy el comodín `*` está activo para facilitar el desarrollo.
- Las recomendaciones de `recomendaciones.py` son medidas generales sin productos ni dosis. Deben ser revisadas por un ingeniero agrónomo o contrastadas con las guías de SENASA o INIA antes de mostrarse a agricultores reales.
- No hay límite de intentos de inicio de sesión ni bloqueo de cuentas; agréguelo antes de exponer el servicio a internet.
- Las fotos se guardan en `backend\almacen\imagenes` sin los metadatos EXIF (se elimina la ubicación GPS incrustada). Los datos de ubicación de parcelas pueden ser datos personales: trátelos según la normativa aplicable.

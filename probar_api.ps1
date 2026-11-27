<#
.SYNOPSIS
  Prueba de extremo a extremo de la API PapaSalud Ayacucho desde PowerShell.

.DESCRIPTION
  Registra un usuario de prueba, inicia sesión, crea una parcela, envía una foto a
  /v1/diagnosticos (multipart), repite el envío para comprobar la idempotencia y lista el
  historial. Funciona en Windows PowerShell 5.1 y en PowerShell 7+.

.EXAMPLE
  .\probar_api.ps1
  .\probar_api.ps1 -Imagen "C:\fotos\hoja.jpg"
  .\probar_api.ps1 -Url "http://127.0.0.1:8000"
#>
param(
    [string]$Url = 'http://127.0.0.1:8000',
    [string]$Imagen = '',
    [string]$Password = 'Clave12345'
)

$ErrorActionPreference = 'Stop'

# En Windows hay que llamar a curl.exe (en PowerShell 5.1 "curl" es un alias de Invoke-WebRequest)
$curl = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'curl.exe' } else { 'curl' }

function Escribir-Paso($texto) { Write-Host "`n=== $texto" -ForegroundColor Cyan }

# Envía JSON como bytes UTF-8 para que las tildes y la ñ lleguen bien en cualquier versión
function Invocar-Json($metodo, $ruta, $cuerpo, $token) {
    $parametros = @{
        Method      = $metodo
        Uri         = "$Url$ruta"
        ContentType = 'application/json; charset=utf-8'
    }
    if ($token) { $parametros.Headers = @{ Authorization = "Bearer $token" } }
    if ($null -ne $cuerpo) {
        $json = $cuerpo | ConvertTo-Json -Depth 5
        $parametros.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    Invoke-RestMethod @parametros
}

# --- Imagen: usa la indicada o una de muestra (jpeg de 160x160) incluida en el script ---
$archivoTemporal = $false
if (-not $Imagen) {
    $muestraBase64 = (
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYn' +
    'KSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo' +
    'KCgoKCgoKCj/wAARCACgAKADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF' +
    'BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVW' +
    'V1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi' +
    '4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAEC' +
    'AxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm' +
    'Z2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq' +
    '8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDJAp44qMNRur5pxPjIq48n61Gx4ppemFqagaqIrGm0A0tXykyDAp4H0poo3UrHNIdRmo2e' +
    'ml6FAUYjyfejNR7s05TT5bHRFEijNSKvFMXmpFqGjQcBSnGKTPrTHalymbVwY9ahdqHaoWarjAjlHE80gHNN608VfKSx+/1pN9Vj' +
    'IcU3fVcp2wgWC3PWlDVBup6nv60GjiSg04Gos0hfFSYTRKWxTDJz1qFpKiaSrUTHkJ2emb/eoN/NKrEmqsUoWLKtUqGqqHmp1aok' +
    'aJFhT70/dioN1I0npUWuUo3Jmeoneomk61Ez5zVKJXsyVmz1NN3cVEWzQDznNWZyiTA8U8NzUO6nbsd6TMGipv6U5WqAVItDZ6aR' +
    'OpFSA1CtO3YqGxNEheo2kqNnHrULvn6U0Q4EjP1qIvUbNmkzWiIcbEob3qRT0qFakWhsmxOrVIG96rhsUu/GKzZUY3JzJTWeoS9M' +
    'LUJHRGBMXzTS1R5pR0qrjkiQGlBpmaCaVzmmrkm6ml/eomeo2cU0ZKA5R61Mopqr6VJioZ2JhTSaU1G3tSSLSGsaiY8080m2tErC' +
    'Yw9aAOKeF70oWmYSkCinClxikNSZrUM4pC1ITSYp2OiCFzSjNAHNPVaRtewgGacB7U8LSsKkzkxh4HSo2PY09qhY1UUZNDGNMJzx' +
    'StyaADWiQjRC8UpHBqQjHFJis7BBkJFMIqcr7UbKqxtzWK2z0pdlWQlL5fbFFzKcyuE9qNtWClMYUbnM5XICDTCKmYU3bVJFRZFj' +
    'rTlU1KEzUqJSZtGZEqcVIqetTLHTwvFZtlc5BimsMVOw4qJxQkK5XcdfWomWrDLTdhzWqRLkV9vtTgnYiplj9qkWOhsycyyRSbak' +
    'xmnKuTWdxxlYiCZpwTJ5qZU74qQJipcxuZBs+lIUqwRUbCkpGMpEDCoXHFWHqIjNaJkXISOaAvNTbKeiD8qbkHNYjWOplT0qRVqQ' +
    'LWcplKZGFxjigjAqUjmmHmpuaxZCwqJhU7D8qTbk1aZTkV9nrQI/arASnBKfOYzmQCOlCcc1PtppHpS5jDmuKo55qVVpEFSgVzuZ' +
    'smKBS44opGNRzBuNaoWNPdqiJzVxYWGNTQOKd1NOAq+cyk7CKtSquKQCnipczO4o6Uv86bnsKQtk1NzWCHMfWmGgnmgc0+Y6IoOv' +
    'SlC04CnDrRzkyYwLQQBT+lMZuaXMc8tRpqNjSs+KjLVaZKRZWnhqhVsUb6waOiMbkxbAqNn96jZ6jZs01E2UB7Nmm5pm6lzmrsTJ' +
    'WH/WnCmdutG6kc0kSbqQtxUZfmmb6FEUYk2/35pN1QbsmnK3anax0RjYnBp4qJTUoNSzSxIOgpSeKjzTWeptczauOZhioWakZ/eo' +
    'Wf3q1EhwHls0maizTl61dibWJC/p1pC+O9QF+KaX9K19mdsIE5ejdUIbIpwNHIaOJKDTs1GDQTS5DCaHlsdaYz4zzUZfH0qJpOKp' +
    'UzHkJWemhuetQl6AxNX7MtQsWAeetSKfeq6deamQ4qHAtIsL24p+7HNQ7sUhas+QpRuTM9RM/FRs9RFznOapUyuQez03cc1GW96U' +
    'GtOQzlGw/NSA4qEGnA4pOBg0Qbs0qnNRipFFdLSR6KViQdaeKao/KndqhoTFJqNmxQzcVC7e9NRM3EVnqItmkY5pvOa0USXEcDk1' +
    'ItRrmpVHShoklSpAaiB4pd1ZtXKiiXdTGbioy1NLcc0KBvGI8vTc5pp5FKBVWQ5Kwo9hTqQcUdKVjnmKTgdaQtTCfSmFs+1NRMuU' +
    '/9k='
    )
    $Imagen = Join-Path ([System.IO.Path]::GetTempPath()) 'hoja_muestra_papasalud.jpg'
    [System.IO.File]::WriteAllBytes($Imagen, [Convert]::FromBase64String($muestraBase64))
    $archivoTemporal = $true
}
if (-not (Test-Path $Imagen)) { throw "No existe la imagen: $Imagen" }

# --- 1. Estado ---
Escribir-Paso '1. Estado del servidor (GET /health)'
$salud = Invoke-RestMethod -Uri "$Url/health"
$salud | ConvertTo-Json

# --- 2. Registro ---
Escribir-Paso '2. Registro (POST /v1/auth/register)'
$telefono = '9' + (Get-Random -Minimum 10000000 -Maximum 99999999)
$registro = Invocar-Json 'Post' '/v1/auth/register' @{
    nombre   = 'Juan Quispe Huamán'
    telefono = $telefono
    password = $Password
    rol      = 'agricultor'
} $null
"Usuario creado: id=$($registro.id) telefono=$($registro.telefono) rol=$($registro.rol)"

# --- 3. Login ---
Escribir-Paso '3. Inicio de sesión (POST /v1/auth/login)'
$login = Invocar-Json 'Post' '/v1/auth/login' @{ telefono = $telefono; password = $Password } $null
$token = $login.access_token
"Token JWT recibido ($($token.Length) caracteres), expira en $($login.expira_en_minutos) minutos"

# --- 4. Parcelas ---
Escribir-Paso '4. Crear y listar parcelas'
$parcela = Invocar-Json 'Post' '/v1/parcelas' @{
    nombre       = 'Chacra Norte'
    variedad     = 'Huayro'
    area_ha      = 1.5
    distrito     = 'Ayacucho'
    latitud      = -13.1588
    longitud     = -74.2232
    altitud_msnm = 2746
} $token
"Parcela creada: id=$($parcela.id) nombre=$($parcela.nombre) altitud=$($parcela.altitud_msnm) m"
$parcelas = @(Invocar-Json 'Get' '/v1/parcelas' $null $token)
"Parcelas del usuario: $($parcelas.Count)"

# --- 5. Diagnóstico (multipart con curl) ---
function Enviar-Diagnostico($uuid) {
    $fecha = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $argumentos = @(
        '-s', '-w', "`n%{http_code}",
        '-X', 'POST', "$Url/v1/diagnosticos",
        '-H', "Authorization: Bearer $token",
        '-F', "client_uuid=$uuid",
        '-F', "parcela_id=$($parcela.id)",
        '-F', 'latitud=-13.1588',
        '-F', 'longitud=-74.2232',
        '-F', "capturado_en=$fecha",
        '-F', "imagen=@$Imagen;type=image/jpeg"
    )
    $salida = & $curl @argumentos
    $texto = ($salida -join "`n")
    $corte = $texto.LastIndexOf("`n")
    [pscustomobject]@{
        Codigo = [int]$texto.Substring($corte + 1).Trim()
        Cuerpo = $texto.Substring(0, $corte) | ConvertFrom-Json
    }
}

Escribir-Paso '5. Diagnóstico (POST /v1/diagnosticos, multipart/form-data)'
$uuid = [guid]::NewGuid().ToString()
$primero = Enviar-Diagnostico $uuid
$d = $primero.Cuerpo
"HTTP $($primero.Codigo)  ->  $($d.nombre_diagnostico) | confianza $($d.confianza_porcentaje) % | semáforo $($d.semaforo) | poco concluyente: $($d.poco_concluyente)"
"Modelo: $($d.modelo_version) (modo demostración: $($d.modo_demostracion))"
"Recomendaciones:"
$d.recomendaciones | ForEach-Object { "  - $_" }

Escribir-Paso '6. Idempotencia: mismo client_uuid otra vez'
$segundo = Enviar-Diagnostico $uuid
"HTTP $($segundo.Codigo)  ->  duplicado=$($segundo.Cuerpo.duplicado)  mismo id: $($segundo.Cuerpo.id -eq $d.id)"

# --- 7. Historial ---
Escribir-Paso '7. Historial (GET /v1/diagnosticos)'
$historial = @(Invocar-Json 'Get' '/v1/diagnosticos?limite=5' $null $token)
$historial | ForEach-Object { "{0}  {1}  ({2} %)  parcela {3}" -f $_.id, $_.nombre_diagnostico, $_.confianza_porcentaje, $_.parcela_nombre }

# --- Resumen ---
Escribir-Paso 'Resumen'
$correcto = ($primero.Codigo -eq 201) -and ($segundo.Codigo -eq 200) -and $segundo.Cuerpo.duplicado -and ($historial.Count -ge 1)
if ($correcto) { Write-Host 'TODO CORRECTO' -ForegroundColor Green } else { Write-Host 'HAY PROBLEMAS: revise los pasos anteriores' -ForegroundColor Red }
if ($archivoTemporal) { Remove-Item $Imagen -ErrorAction SilentlyContinue }

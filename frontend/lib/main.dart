// PapaSalud Ayacucho: diagnóstico fitosanitario de la papa (Flutter Web).
//
// Ejecutar:  flutter run -d chrome --web-port 8080
// Requiere el backend FastAPI encendido (por defecto http://127.0.0.1:8000).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String urlPorDefecto = 'http://127.0.0.1:8000';

void main() {
  runApp(const PapaSaludApp());
}

// ============================================================================
// Identidad visual
// ============================================================================

/// Paleta pensada para uso al aire libre: fondo claro, texto casi negro y un
/// semáforo (verde, ámbar, rojo) que siempre va acompañado de ícono y texto.
class Paleta {
  static const Color fondo = Color(0xFFF1F5EE);
  static const Color superficie = Color(0xFFFFFFFF);
  static const Color tinta = Color(0xFF1B2B21);
  static const Color tintaSuave = Color(0xFF55645A);
  static const Color borde = Color(0xFFCCD8C8);

  static const Color verde = Color(0xFF2D6A3E);
  static const Color verdeClaro = Color(0xFFDDEDDF);

  static const Color papa = Color(0xFFE9AE2F);
  static const Color papaClaro = Color(0xFFFFF1CE);
  static const Color papaTexto = Color(0xFF5E4300);

  static const Color rojo = Color(0xFFA8261D);
  static const Color rojoClaro = Color(0xFFFBE2DE);

  static const Color ambar = Color(0xFF8A5A00);
  static const Color ambarClaro = Color(0xFFFFEBC2);
}

ThemeData construirTema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Paleta.verde,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Paleta.fondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Paleta.verde,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        foregroundColor: Paleta.verde,
        side: const BorderSide(color: Paleta.verde, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

InputDecoration decoracion(String etiqueta, {String? ayuda, String? prefijo, Widget? sufijo}) {
  return InputDecoration(
    labelText: etiqueta,
    helperText: ayuda,
    helperMaxLines: 2,
    prefixText: prefijo,
    suffixIcon: sufijo,
    filled: true,
    fillColor: Paleta.superficie,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Paleta.borde),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Paleta.borde),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Paleta.verde, width: 2),
    ),
  );
}

// ============================================================================
// Modelos
// ============================================================================

class Usuario {
  Usuario({required this.id, required this.nombre, required this.telefono, required this.rol});

  final int id;
  final String nombre;
  final String telefono;
  final String rol;

  factory Usuario.desdeJson(Map<String, dynamic> json) {
    return Usuario(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre'] as String,
      telefono: json['telefono'] as String,
      rol: json['rol'] as String,
    );
  }
}

class Parcela {
  Parcela({
    required this.id,
    required this.nombre,
    required this.latitud,
    required this.longitud,
    required this.altitudMsnm,
    this.variedad,
    this.distrito,
  });

  final int id;
  final String nombre;
  final double latitud;
  final double longitud;
  final double altitudMsnm;
  final String? variedad;
  final String? distrito;

  factory Parcela.desdeJson(Map<String, dynamic> json) {
    return Parcela(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      altitudMsnm: (json['altitud_msnm'] as num).toDouble(),
      variedad: json['variedad'] as String?,
      distrito: json['distrito'] as String?,
    );
  }
}

class Diagnostico {
  Diagnostico({
    required this.id,
    required this.parcelaNombre,
    required this.capturadoEn,
    required this.nombreDiagnostico,
    required this.semaforo,
    required this.confianza,
    required this.pocoConcluyente,
    required this.recomendaciones,
    required this.aviso,
    required this.modoDemostracion,
    required this.duplicado,
    this.advertenciaModelo,
    this.miniatura,
  });

  final int id;
  final String parcelaNombre;
  final DateTime capturadoEn;
  final String nombreDiagnostico;
  final String semaforo; // verde | ambar | rojo
  final double confianza; // 0 a 1
  final bool pocoConcluyente;
  final List<String> recomendaciones;
  final String aviso;
  final bool modoDemostracion;
  final bool duplicado;
  final String? advertenciaModelo;
  final Uint8List? miniatura;

  int get porcentaje => (confianza * 100).round();

  factory Diagnostico.desdeJson(Map<String, dynamic> json) {
    final miniaturaBase64 = json['miniatura_base64'] as String?;
    return Diagnostico(
      id: (json['id'] as num).toInt(),
      parcelaNombre: json['parcela_nombre'] as String,
      capturadoEn: DateTime.parse(json['capturado_en'] as String),
      nombreDiagnostico: json['nombre_diagnostico'] as String,
      semaforo: json['semaforo'] as String,
      confianza: (json['confianza'] as num).toDouble(),
      pocoConcluyente: json['poco_concluyente'] as bool,
      recomendaciones: (json['recomendaciones'] as List<dynamic>).map((e) => e.toString()).toList(),
      aviso: json['aviso'] as String,
      modoDemostracion: json['modo_demostracion'] as bool,
      duplicado: (json['duplicado'] as bool?) ?? false,
      advertenciaModelo: json['advertencia_modelo'] as String?,
      miniatura: (miniaturaBase64 == null || miniaturaBase64.isEmpty) ? null : base64Decode(miniaturaBase64),
    );
  }
}

// ============================================================================
// Cliente HTTP del backend FastAPI
// ============================================================================

class ErrorApi implements Exception {
  ErrorApi(this.mensaje, {this.codigo, this.ayuda});

  final String mensaje;
  final int? codigo;
  final String? ayuda;

  bool get sesionVencida => codigo == 401;

  @override
  String toString() => mensaje;
}

class SesionIniciada {
  SesionIniciada({required this.token, required this.usuario});

  final String token;
  final Usuario usuario;
}

class ClienteApi {
  ClienteApi({required String urlBase, this.token}) : urlBase = normalizarUrl(urlBase);

  final String urlBase;
  final String? token;

  static const Duration _tiempoEspera = Duration(seconds: 30);
  static const Duration _tiempoEsperaImagen = Duration(seconds: 90);

  static String normalizarUrl(String valor) {
    var url = valor.trim();
    if (url.isEmpty) return urlPorDefecto;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Uri _uri(String ruta, [Map<String, String>? consulta]) {
    final base = Uri.parse('$urlBase$ruta');
    if (consulta == null || consulta.isEmpty) return base;
    return base.replace(queryParameters: consulta);
  }

  Map<String, String> _cabeceras({bool json = false}) {
    final cabeceras = <String, String>{'Accept': 'application/json'};
    if (json) cabeceras['Content-Type'] = 'application/json; charset=utf-8';
    final t = token;
    if (t != null) cabeceras['Authorization'] = 'Bearer $t';
    return cabeceras;
  }

  Future<dynamic> _ejecutar(Future<http.Response> Function() peticion, {Duration? limite}) async {
    http.Response respuesta;
    try {
      respuesta = await peticion().timeout(limite ?? _tiempoEspera);
    } on TimeoutException {
      throw ErrorApi(
        'El servidor tardó demasiado en responder.',
        ayuda: 'Revise su conexión e intente de nuevo.',
      );
    } on http.ClientException {
      throw ErrorApi(
        'No se pudo conectar con el servidor.',
        ayuda: 'Compruebe que: (1) el backend esté encendido en $urlBase (abra $urlBase/health '
            'en el navegador), (2) la dirección sea la correcta y (3) el backend permita el origen '
            'de esta página (CORS). Si el backend responde con un error 500, el navegador lo '
            'muestra como "Failed to fetch": revise la ventana donde corre uvicorn.',
      );
    } catch (e) {
      throw ErrorApi('Error inesperado de red: $e');
    }
    return _procesar(respuesta);
  }

  dynamic _procesar(http.Response respuesta) {
    final texto = utf8.decode(respuesta.bodyBytes, allowMalformed: true);
    dynamic cuerpo;
    if (texto.isNotEmpty) {
      try {
        cuerpo = jsonDecode(texto);
      } on FormatException {
        cuerpo = null;
      }
    }
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }
    throw _errorHttp(respuesta.statusCode, cuerpo);
  }

  static const Map<String, String> _etiquetasCampos = {
    'nombre': 'Nombre',
    'telefono': 'Teléfono',
    'password': 'Contraseña',
    'rol': 'Rol',
    'latitud': 'Latitud',
    'longitud': 'Longitud',
    'altitud_msnm': 'Altitud',
    'area_ha': 'Área',
    'parcela_id': 'Parcela',
    'client_uuid': 'Identificador',
    'capturado_en': 'Fecha de captura',
    'imagen': 'Imagen',
    'cuerpo': 'Datos enviados',
  };

  ErrorApi _errorHttp(int codigo, dynamic cuerpo) {
    String? detalle;
    String? ayuda;
    final lineas = <String>[];

    if (cuerpo is Map) {
      final d = cuerpo['detail'];
      if (d is String) {
        detalle = d;
      } else if (d is List) {
        detalle = d.map((e) => e is Map ? '${e['msg']}' : '$e').join('; ');
      }
      final a = cuerpo['ayuda'];
      if (a is String) ayuda = a;
      final errores = cuerpo['errores'];
      if (errores is List) {
        for (final e in errores) {
          if (e is Map) {
            final campo = '${e['campo']}';
            lineas.add('• ${_etiquetasCampos[campo] ?? campo}: ${e['mensaje']}');
          }
        }
      }
    }

    if (codigo == 400) {
      return ErrorApi(detalle ?? 'La solicitud no es válida.', codigo: codigo, ayuda: ayuda);
    }
    if (codigo == 401) {
      return ErrorApi(detalle ?? 'Credenciales incorrectas o sesión vencida.', codigo: codigo);
    }
    if (codigo == 403) {
      return ErrorApi(detalle ?? 'No tiene permiso para hacer esta acción.', codigo: codigo);
    }
    if (codigo == 404) {
      return ErrorApi(detalle ?? 'No se encontró lo solicitado.', codigo: codigo);
    }
    if (codigo == 409) {
      return ErrorApi(detalle ?? 'Ya existe un registro igual.', codigo: codigo);
    }
    if (codigo == 413) {
      return ErrorApi(detalle ?? 'El archivo es demasiado grande.', codigo: codigo);
    }
    if (codigo == 415) {
      return ErrorApi(detalle ?? 'El tipo de archivo no es admitido.', codigo: codigo);
    }
    if (codigo == 422) {
      final texto = lineas.isNotEmpty ? 'Revise estos datos:\n${lineas.join('\n')}' : 'Los datos enviados no son válidos. ${detalle ?? ''}';
      return ErrorApi(texto.trim(), codigo: codigo, ayuda: ayuda);
    }
    if (codigo >= 500) {
      return ErrorApi(
        'Error del servidor ($codigo). ${detalle ?? ''}'.trim(),
        codigo: codigo,
        ayuda: 'Intente de nuevo. Si el problema continúa, revise la consola del backend.',
      );
    }
    return ErrorApi('Error $codigo. ${detalle ?? ''}'.trim(), codigo: codigo, ayuda: ayuda);
  }

  // ------------------------------------------------------------------ estado
  Future<String> comprobarSalud() async {
    final cuerpo = await _ejecutar(() => http.get(_uri('/health'), headers: _cabeceras()));
    if (cuerpo is Map) {
      final demo = cuerpo['modo_demostracion'] == true;
      return 'Conectado. Base de datos: ${cuerpo['base_datos'] == true ? 'correcta' : 'con problemas'}. '
          'Modelo de IA: ${cuerpo['modelo_version']}${demo ? ' (modo demostración)' : ''}.';
    }
    return 'Conectado.';
  }

  // ---------------------------------------------------------- autenticación
  Future<Usuario> registrar({
    required String nombre,
    required String telefono,
    required String password,
    required String rol,
  }) async {
    final cuerpo = await _ejecutar(
      () => http.post(
        _uri('/v1/auth/register'),
        headers: _cabeceras(json: true),
        body: jsonEncode({'nombre': nombre, 'telefono': telefono, 'password': password, 'rol': rol}),
      ),
    );
    return Usuario.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<SesionIniciada> iniciarSesion({required String telefono, required String password}) async {
    final cuerpo = await _ejecutar(
      () => http.post(
        _uri('/v1/auth/login'),
        headers: _cabeceras(json: true),
        body: jsonEncode({'telefono': telefono, 'password': password}),
      ),
    ) as Map<String, dynamic>;
    return SesionIniciada(
      token: cuerpo['access_token'] as String,
      usuario: Usuario.desdeJson(cuerpo['usuario'] as Map<String, dynamic>),
    );
  }

  Future<Usuario> perfil() async {
    final cuerpo = await _ejecutar(() => http.get(_uri('/v1/auth/yo'), headers: _cabeceras()));
    return Usuario.desdeJson(cuerpo as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- parcelas
  Future<List<Parcela>> listarParcelas() async {
    final cuerpo = await _ejecutar(() => http.get(_uri('/v1/parcelas'), headers: _cabeceras()));
    return (cuerpo as List<dynamic>).map((e) => Parcela.desdeJson(e as Map<String, dynamic>)).toList();
  }

  Future<Parcela> crearParcela({
    required String nombre,
    required double latitud,
    required double longitud,
    required double altitudMsnm,
    String? variedad,
  }) async {
    final datos = <String, dynamic>{
      'nombre': nombre,
      'latitud': latitud,
      'longitud': longitud,
      'altitud_msnm': altitudMsnm,
    };
    if (variedad != null && variedad.trim().isNotEmpty) datos['variedad'] = variedad.trim();
    final cuerpo = await _ejecutar(
      () => http.post(_uri('/v1/parcelas'), headers: _cabeceras(json: true), body: jsonEncode(datos)),
    );
    return Parcela.desdeJson(cuerpo as Map<String, dynamic>);
  }

  // ------------------------------------------------------------ diagnósticos
  Future<Diagnostico> diagnosticar({
    required Parcela parcela,
    required Uint8List imagen,
  }) async {
    final tipo = tipoDeImagen(imagen);
    final cliente = http.Client();
    try {
      final solicitud = http.MultipartRequest('POST', _uri('/v1/diagnosticos'));
      // No se define Content-Type a mano: MultipartRequest lo agrega con su "boundary".
      solicitud.headers.addAll(_cabeceras());
      solicitud.fields['client_uuid'] = const Uuid().v4();
      solicitud.fields['parcela_id'] = '${parcela.id}';
      solicitud.fields['latitud'] = '${parcela.latitud}';
      solicitud.fields['longitud'] = '${parcela.longitud}';
      solicitud.fields['capturado_en'] = DateTime.now().toUtc().toIso8601String();
      solicitud.files.add(
        http.MultipartFile.fromBytes(
          'imagen',
          imagen,
          filename: 'hoja.${tipo.extension}',
          contentType: MediaType('image', tipo.subtipo),
        ),
      );
      final cuerpo = await _ejecutar(
        () async {
          final flujo = await cliente.send(solicitud);
          return http.Response.fromStream(flujo);
        },
        limite: _tiempoEsperaImagen,
      );
      return Diagnostico.desdeJson(cuerpo as Map<String, dynamic>);
    } finally {
      cliente.close();
    }
  }

  Future<List<Diagnostico>> listarDiagnosticos({int limite = 20, int? antesDeId}) async {
    final consulta = <String, String>{'limite': '$limite'};
    if (antesDeId != null) consulta['antes_de_id'] = '$antesDeId';
    final cuerpo = await _ejecutar(
      () => http.get(_uri('/v1/diagnosticos', consulta), headers: _cabeceras()),
    );
    return (cuerpo as List<dynamic>).map((e) => Diagnostico.desdeJson(e as Map<String, dynamic>)).toList();
  }
}

class TipoImagen {
  const TipoImagen(this.subtipo, this.extension);
  final String subtipo;
  final String extension;
}

/// Detecta el formato por los primeros bytes (el nombre del archivo no es fiable en la web).
TipoImagen tipoDeImagen(Uint8List bytes) {
  if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return const TipoImagen('png', 'png');
  }
  if (bytes.length > 11 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    // P
    return const TipoImagen('webp', 'webp');
  }
  return const TipoImagen('jpeg', 'jpg');
}

// ============================================================================
// Persistencia local de la sesión (localStorage en la web)
// ============================================================================

class AlmacenSesion {
  static const String _claveUrl = 'papasalud_url_servidor';
  static const String _claveToken = 'papasalud_token';

  static Future<String> leerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveUrl) ?? urlPorDefecto;
  }

  static Future<String?> leerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveToken);
  }

  static Future<void> guardar({required String url, required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrl, url);
    await prefs.setString(_claveToken, token);
  }

  static Future<void> guardarUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrl, url);
  }

  static Future<void> borrarToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);
  }
}

// ============================================================================
// Utilidades de interfaz
// ============================================================================

String formatearFecha(DateTime fecha) {
  final l = fecha.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)}/${l.year} ${dos(l.hour)}:${dos(l.minute)}';
}

class EstiloSemaforo {
  const EstiloSemaforo({
    required this.fondo,
    required this.acento,
    required this.icono,
    required this.etiqueta,
  });

  final Color fondo;
  final Color acento;
  final IconData icono;
  final String etiqueta;

  static EstiloSemaforo de(String semaforo) {
    if (semaforo == 'verde') {
      return const EstiloSemaforo(
        fondo: Paleta.verdeClaro,
        acento: Paleta.verde,
        icono: Icons.check_circle,
        etiqueta: 'Sin señales de enfermedad',
      );
    }
    if (semaforo == 'rojo') {
      return const EstiloSemaforo(
        fondo: Paleta.rojoClaro,
        acento: Paleta.rojo,
        icono: Icons.warning_amber_rounded,
        etiqueta: 'Posible enfermedad',
      );
    }
    return const EstiloSemaforo(
      fondo: Paleta.ambarClaro,
      acento: Paleta.ambar,
      icono: Icons.help_outline,
      etiqueta: 'Resultado poco concluyente',
    );
  }
}

class BannerMensaje extends StatelessWidget {
  const BannerMensaje({
    super.key,
    required this.texto,
    this.ayuda,
    this.fondo = Paleta.rojoClaro,
    this.acento = Paleta.rojo,
    this.icono = Icons.error_outline,
  });

  final String texto;
  final String? ayuda;
  final Color fondo;
  final Color acento;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: acento, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: acento),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  texto,
                  style: const TextStyle(color: Paleta.tinta, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
                ),
                if (ayuda != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    ayuda!,
                    style: const TextStyle(color: Paleta.tintaSuave, fontSize: 13, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InsigniaSemaforo extends StatelessWidget {
  const InsigniaSemaforo({super.key, required this.semaforo, this.compacta = false});

  final String semaforo;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final estilo = EstiloSemaforo.de(semaforo);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacta ? 8 : 10, vertical: compacta ? 3 : 5),
      decoration: BoxDecoration(
        color: estilo.fondo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: estilo.acento),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estilo.icono, size: compacta ? 14 : 16, color: estilo.acento),
          const SizedBox(width: 5),
          Text(
            estilo.etiqueta,
            style: TextStyle(color: estilo.acento, fontSize: compacta ? 12 : 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class ListaRecomendaciones extends StatelessWidget {
  const ListaRecomendaciones({super.key, required this.recomendaciones});

  final List<String> recomendaciones;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final texto in recomendaciones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.arrow_right_alt, size: 20, color: Paleta.verde),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(texto, style: const TextStyle(color: Paleta.tinta, fontSize: 15, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ContenedorCentrado extends StatelessWidget {
  const ContenedorCentrado({super.key, required this.child, this.ancho = 720});

  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child),
    );
  }
}

// ============================================================================
// Aplicación y raíz (restaura la sesión guardada)
// ============================================================================

class PapaSaludApp extends StatelessWidget {
  const PapaSaludApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PapaSalud Ayacucho',
      debugShowCheckedModeBanner: false,
      theme: construirTema(),
      home: const RaizApp(),
    );
  }
}

class RaizApp extends StatefulWidget {
  const RaizApp({super.key});

  @override
  State<RaizApp> createState() => _RaizAppState();
}

class _RaizAppState extends State<RaizApp> {
  bool _iniciando = true;
  String _urlServidor = urlPorDefecto;
  String? _token;
  Usuario? _usuario;
  String? _avisoAcceso;

  @override
  void initState() {
    super.initState();
    _restaurarSesion();
  }

  Future<void> _restaurarSesion() async {
    final url = await AlmacenSesion.leerUrl();
    final token = await AlmacenSesion.leerToken();
    Usuario? usuario;
    String? aviso;
    if (token != null) {
      try {
        usuario = await ClienteApi(urlBase: url, token: token).perfil();
      } on ErrorApi catch (e) {
        if (e.sesionVencida) {
          await AlmacenSesion.borrarToken();
          aviso = 'Su sesión venció. Inicie sesión de nuevo.';
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _urlServidor = url;
      _token = usuario == null ? null : token;
      _usuario = usuario;
      _avisoAcceso = aviso;
      _iniciando = false;
    });
  }

  Future<void> _alAutenticar(String url, SesionIniciada sesion) async {
    await AlmacenSesion.guardar(url: url, token: sesion.token);
    if (!mounted) return;
    setState(() {
      _urlServidor = url;
      _token = sesion.token;
      _usuario = sesion.usuario;
      _avisoAcceso = null;
    });
  }

  Future<void> _cerrarSesion({String? aviso}) async {
    await AlmacenSesion.borrarToken();
    if (!mounted) return;
    setState(() {
      _token = null;
      _usuario = null;
      _avisoAcceso = aviso;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_iniciando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final usuario = _usuario;
    final token = _token;
    if (usuario == null || token == null) {
      return PantallaAcceso(
        urlInicial: _urlServidor,
        aviso: _avisoAcceso,
        alAutenticar: _alAutenticar,
      );
    }
    return PantallaPrincipal(
      api: ClienteApi(urlBase: _urlServidor, token: token),
      usuario: usuario,
      alCerrarSesion: () => _cerrarSesion(),
      alSesionVencida: () => _cerrarSesion(aviso: 'Su sesión venció. Inicie sesión de nuevo.'),
    );
  }
}

// ============================================================================
// Pantalla de inicio de sesión y registro
// ============================================================================

class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({
    super.key,
    required this.urlInicial,
    required this.alAutenticar,
    this.aviso,
  });

  final String urlInicial;
  final String? aviso;
  final Future<void> Function(String url, SesionIniciada sesion) alAutenticar;

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  late final TextEditingController _url;
  final TextEditingController _nombre = TextEditingController();
  final TextEditingController _telefono = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _modoRegistro = false;
  String _rol = 'agricultor';
  bool _verPassword = false;
  bool _cargando = false;
  bool _probando = false;
  ErrorApi? _error;
  String? _resultadoConexion;
  bool _conexionCorrecta = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.urlInicial);
  }

  @override
  void dispose() {
    _url.dispose();
    _nombre.dispose();
    _telefono.dispose();
    _password.dispose();
    super.dispose();
  }

  String _soloDigitosTelefono(String texto) {
    var limpio = texto.replaceAll(RegExp(r'[\s\-().]'), '');
    if (limpio.startsWith('+51')) {
      limpio = limpio.substring(3);
    } else if (limpio.startsWith('51') && limpio.length == 11) {
      limpio = limpio.substring(2);
    }
    return limpio;
  }

  String? _validar() {
    final telefono = _soloDigitosTelefono(_telefono.text);
    if (!RegExp(r'^9\d{8}$').hasMatch(telefono)) {
      return 'El teléfono debe tener 9 dígitos y empezar con 9. Ejemplo: 987654321';
    }
    if (_modoRegistro && _nombre.text.trim().length < 2) {
      return 'Escriba su nombre completo.';
    }
    if (_password.text.isEmpty) {
      return 'Escriba su contraseña.';
    }
    if (_modoRegistro && _password.text.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres.';
    }
    return null;
  }

  Future<void> _enviar() async {
    final problema = _validar();
    if (problema != null) {
      setState(() => _error = ErrorApi(problema));
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final api = ClienteApi(urlBase: _url.text);
    final telefono = _soloDigitosTelefono(_telefono.text);
    try {
      if (_modoRegistro) {
        await api.registrar(
          nombre: _nombre.text.trim(),
          telefono: telefono,
          password: _password.text,
          rol: _rol,
        );
      }
      final sesion = await api.iniciarSesion(telefono: telefono, password: _password.text);
      await widget.alAutenticar(api.urlBase, sesion);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _probarConexion() async {
    setState(() {
      _probando = true;
      _resultadoConexion = null;
    });
    final api = ClienteApi(urlBase: _url.text);
    try {
      final mensaje = await api.comprobarSalud();
      await AlmacenSesion.guardarUrl(api.urlBase);
      if (!mounted) return;
      setState(() {
        _resultadoConexion = mensaje;
        _conexionCorrecta = true;
      });
    } on ErrorApi catch (e) {
      if (!mounted) return;
      setState(() {
        _resultadoConexion = e.ayuda == null ? e.mensaje : '${e.mensaje}\n${e.ayuda}';
        _conexionCorrecta = false;
      });
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.displaySmall;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'PapaSalud',
                    style: titulo?.copyWith(color: Paleta.verde, fontWeight: FontWeight.w900, letterSpacing: -1),
                  ),
                  const Text(
                    'Ayacucho',
                    style: TextStyle(color: Paleta.papaTexto, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fotografíe una hoja de papa y conozca su estado en segundos.',
                    style: TextStyle(color: Paleta.tintaSuave, fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Iniciar sesión')),
                      ButtonSegment<bool>(value: true, label: Text('Crear cuenta')),
                    ],
                    selected: {_modoRegistro},
                    onSelectionChanged: (seleccion) {
                      setState(() {
                        _modoRegistro = seleccion.first;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  if (widget.aviso != null) ...[
                    BannerMensaje(
                      texto: widget.aviso!,
                      fondo: Paleta.papaClaro,
                      acento: Paleta.papa,
                      icono: Icons.info_outline,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_modoRegistro) ...[
                    TextField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: decoracion('Nombre completo'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _telefono,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: decoracion('Teléfono', prefijo: '+51  ', ayuda: '9 dígitos. Ejemplo: 987654321'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !_verPassword,
                    onSubmitted: (_) => _cargando ? null : _enviar(),
                    decoration: decoracion(
                      'Contraseña',
                      ayuda: _modoRegistro ? 'Mínimo 8 caracteres' : null,
                      sufijo: IconButton(
                        tooltip: _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _verPassword = !_verPassword),
                      ),
                    ),
                  ),
                  if (_modoRegistro) ...[
                    const SizedBox(height: 14),
                    const Text('Soy', style: TextStyle(color: Paleta.tintaSuave, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(value: 'agricultor', label: Text('Agricultor')),
                        ButtonSegment<String>(value: 'tecnico', label: Text('Técnico agrícola')),
                      ],
                      selected: {_rol},
                      onSelectionChanged: (seleccion) => setState(() => _rol = seleccion.first),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_error != null) ...[
                    BannerMensaje(texto: _error!.mensaje, ayuda: _error!.ayuda),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: _cargando ? null : _enviar,
                    child: _cargando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(_modoRegistro ? 'Crear cuenta y entrar' : 'Entrar'),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Paleta.superficie,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Paleta.borde),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Servidor',
                          style: TextStyle(color: Paleta.tinta, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          decoration: decoracion('Dirección del servidor', ayuda: 'Ejemplo: http://127.0.0.1:8000'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _probando ? null : _probarConexion,
                          icon: _probando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: const Text('Probar conexión'),
                        ),
                        if (_resultadoConexion != null) ...[
                          const SizedBox(height: 10),
                          BannerMensaje(
                            texto: _resultadoConexion!,
                            fondo: _conexionCorrecta ? Paleta.verdeClaro : Paleta.rojoClaro,
                            acento: _conexionCorrecta ? Paleta.verde : Paleta.rojo,
                            icono: _conexionCorrecta ? Icons.check_circle_outline : Icons.error_outline,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Pantalla principal con pestañas
// ============================================================================

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({
    super.key,
    required this.api,
    required this.usuario,
    required this.alCerrarSesion,
    required this.alSesionVencida,
  });

  final ClienteApi api;
  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final VoidCallback alSesionVencida;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indice = 0;
  final GlobalKey<_PestanaHistorialState> _claveHistorial = GlobalKey<_PestanaHistorialState>();

  @override
  Widget build(BuildContext context) {
    final servidor = Uri.tryParse(widget.api.urlBase)?.authority ?? widget.api.urlBase;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PapaSalud Ayacucho', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            Text(
              '${widget.usuario.nombre}  ·  $servidor',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: widget.alCerrarSesion,
          ),
        ],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          PestanaDiagnostico(
            api: widget.api,
            alSesionVencida: widget.alSesionVencida,
            alDiagnosticar: () => _claveHistorial.currentState?.recargar(),
          ),
          PestanaHistorial(
            key: _claveHistorial,
            api: widget.api,
            alSesionVencida: widget.alSesionVencida,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) {
          setState(() => _indice = i);
          if (i == 1) _claveHistorial.currentState?.recargar();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Diagnóstico IA',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history_toggle_off),
            label: 'Historial',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Pestaña: Diagnóstico IA
// ============================================================================

class PestanaDiagnostico extends StatefulWidget {
  const PestanaDiagnostico({
    super.key,
    required this.api,
    required this.alSesionVencida,
    required this.alDiagnosticar,
  });

  final ClienteApi api;
  final VoidCallback alSesionVencida;
  final VoidCallback alDiagnosticar;

  @override
  State<PestanaDiagnostico> createState() => _PestanaDiagnosticoState();
}

class _PestanaDiagnosticoState extends State<PestanaDiagnostico> {
  final ImagePicker _selector = ImagePicker();
  final GlobalKey _claveResultado = GlobalKey();

  List<Parcela> _parcelas = [];
  int? _parcelaId;
  bool _cargandoParcelas = true;
  ErrorApi? _errorParcelas;

  Uint8List? _imagen;
  bool _enviando = false;
  ErrorApi? _error;
  Diagnostico? _resultado;

  @override
  void initState() {
    super.initState();
    _cargarParcelas();
  }

  Parcela? get _parcelaSeleccionada {
    for (final p in _parcelas) {
      if (p.id == _parcelaId) return p;
    }
    return null;
  }

  Future<void> _cargarParcelas({int? seleccionar}) async {
    setState(() {
      _cargandoParcelas = true;
      _errorParcelas = null;
    });
    try {
      final parcelas = await widget.api.listarParcelas();
      if (!mounted) return;
      setState(() {
        _parcelas = parcelas;
        if (seleccionar != null) {
          _parcelaId = seleccionar;
        } else if (_parcelaId == null || !parcelas.any((p) => p.id == _parcelaId)) {
          _parcelaId = parcelas.isEmpty ? null : parcelas.first.id;
        }
      });
    } on ErrorApi catch (e) {
      if (e.sesionVencida) {
        widget.alSesionVencida();
        return;
      }
      if (!mounted) return;
      setState(() => _errorParcelas = e);
    } finally {
      if (mounted) setState(() => _cargandoParcelas = false);
    }
  }

  Future<void> _nuevaParcela() async {
    final creada = await showDialog<Parcela>(
      context: context,
      builder: (contexto) => DialogoNuevaParcela(api: widget.api),
    );
    if (creada != null) {
      await _cargarParcelas(seleccionar: creada.id);
    }
  }

  Future<void> _elegirImagen(ImageSource fuente) async {
    try {
      final archivo = await _selector.pickImage(
        source: fuente,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imagen = bytes;
        _resultado = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorApi('No se pudo abrir la imagen. Intente con otra foto.', ayuda: '$e'));
    }
  }

  Future<void> _diagnosticar() async {
    final parcela = _parcelaSeleccionada;
    final imagen = _imagen;
    if (parcela == null || imagen == null) return;
    setState(() {
      _enviando = true;
      _error = null;
      _resultado = null;
    });
    try {
      final resultado = await widget.api.diagnosticar(parcela: parcela, imagen: imagen);
      if (!mounted) return;
      setState(() => _resultado = resultado);
      widget.alDiagnosticar();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final contexto = _claveResultado.currentContext;
        if (contexto != null) {
          Scrollable.ensureVisible(contexto, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        }
      });
    } on ErrorApi catch (e) {
      if (e.sesionVencida) {
        widget.alSesionVencida();
        return;
      }
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _nuevaConsulta() {
    setState(() {
      _imagen = null;
      _resultado = null;
      _error = null;
    });
  }

  Widget _seccion(String titulo, Widget contenido) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: const TextStyle(color: Paleta.tinta, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        contenido,
      ],
    );
  }

  Widget _selectorParcela() {
    if (_cargandoParcelas) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorParcelas != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BannerMensaje(texto: _errorParcelas!.mensaje, ayuda: _errorParcelas!.ayuda),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _cargarParcelas(),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    if (_parcelas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Aún no tiene parcelas. Cree la primera para poder diagnosticar.',
            style: TextStyle(color: Paleta.tintaSuave, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _nuevaParcela,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Crear parcela'),
          ),
        ],
      );
    }
    final seleccionada = _parcelaSeleccionada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: decoracion('Parcela'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: _parcelaId,
              items: [
                for (final p in _parcelas)
                  DropdownMenuItem<int>(
                    value: p.id,
                    child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _enviando ? null : (valor) => setState(() => _parcelaId = valor),
            ),
          ),
        ),
        if (seleccionada != null) ...[
          const SizedBox(height: 6),
          Text(
            '${seleccionada.altitudMsnm.round()} m s. n. m.  ·  '
            '${seleccionada.latitud.toStringAsFixed(4)}, ${seleccionada.longitud.toStringAsFixed(4)}',
            style: const TextStyle(color: Paleta.tintaSuave, fontSize: 13),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _enviando ? null : _nuevaParcela,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Nueva parcela'),
          ),
        ),
      ],
    );
  }

  Widget _zonaFoto() {
    final imagen = _imagen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: Paleta.superficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Paleta.borde, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: imagen == null
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.eco_outlined, size: 44, color: Paleta.verde),
                          SizedBox(height: 10),
                          Text(
                            'Una sola hoja, con buena luz y bien enfocada',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Paleta.tintaSuave, fontSize: 15, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  )
                : Image.memory(imagen, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : () => _elegirImagen(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar foto'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : () => _elegirImagen(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Elegir imagen'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tarjetaResultado(Diagnostico d) {
    final estilo = EstiloSemaforo.de(d.semaforo);
    return Container(
      key: _claveResultado,
      decoration: BoxDecoration(
        color: Paleta.superficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: estilo.acento, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: estilo.fondo,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(estilo.icono, color: estilo.acento, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        estilo.etiqueta,
                        style: TextStyle(color: estilo.acento, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  d.nombreDiagnostico,
                  style: const TextStyle(color: Paleta.tinta, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${d.porcentaje} %',
                      style: TextStyle(color: estilo.acento, fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text('de confianza', style: TextStyle(color: Paleta.tintaSuave, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: d.confianza.clamp(0.0, 1.0).toDouble(),
                    minHeight: 12,
                    backgroundColor: Paleta.superficie,
                    valueColor: AlwaysStoppedAnimation<Color>(estilo.acento),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.duplicado) ...[
                  const BannerMensaje(
                    texto: 'Esta foto ya se había enviado. Se muestra el resultado anterior.',
                    fondo: Paleta.verdeClaro,
                    acento: Paleta.verde,
                    icono: Icons.info_outline,
                  ),
                  const SizedBox(height: 12),
                ],
                if (d.modoDemostracion && d.advertenciaModelo != null) ...[
                  BannerMensaje(
                    texto: d.advertenciaModelo!,
                    fondo: Paleta.papaClaro,
                    acento: Paleta.papa,
                    icono: Icons.science_outlined,
                  ),
                  const SizedBox(height: 14),
                ],
                const Text(
                  'Qué hacer',
                  style: TextStyle(color: Paleta.tinta, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ListaRecomendaciones(recomendaciones: d.recomendaciones),
                const SizedBox(height: 6),
                Text(
                  d.aviso,
                  style: const TextStyle(color: Paleta.tintaSuave, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  'Parcela ${d.parcelaNombre}  ·  ${formatearFecha(d.capturadoEn)}',
                  style: const TextStyle(color: Paleta.tintaSuave, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _nuevaConsulta,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Nueva consulta'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeDiagnosticar = !_enviando && _parcelaSeleccionada != null && _imagen != null;
    final resultado = _resultado;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: ContenedorCentrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _seccion('Parcela', _selectorParcela()),
            const SizedBox(height: 22),
            _seccion('Foto de la hoja', _zonaFoto()),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: puedeDiagnosticar ? _diagnosticar : null,
              icon: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(_enviando ? 'Analizando la hoja…' : 'Diagnosticar hoja'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              BannerMensaje(texto: _error!.mensaje, ayuda: _error!.ayuda),
            ],
            if (resultado != null) ...[
              const SizedBox(height: 22),
              _tarjetaResultado(resultado),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Diálogo: crear parcela rápida
// ============================================================================

class DialogoNuevaParcela extends StatefulWidget {
  const DialogoNuevaParcela({super.key, required this.api});

  final ClienteApi api;

  @override
  State<DialogoNuevaParcela> createState() => _DialogoNuevaParcelaState();
}

class _DialogoNuevaParcelaState extends State<DialogoNuevaParcela> {
  // Valores iniciales: ciudad de Ayacucho (Huamanga)
  final TextEditingController _nombre = TextEditingController();
  final TextEditingController _variedad = TextEditingController();
  final TextEditingController _latitud = TextEditingController(text: '-13.1588');
  final TextEditingController _longitud = TextEditingController(text: '-74.2232');
  final TextEditingController _altitud = TextEditingController(text: '2746');

  bool _guardando = false;
  ErrorApi? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _variedad.dispose();
    _latitud.dispose();
    _longitud.dispose();
    _altitud.dispose();
    super.dispose();
  }

  double? _numero(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final latitud = _numero(_latitud);
    final longitud = _numero(_longitud);
    final altitud = _numero(_altitud);
    String? problema;
    if (nombre.length < 2) {
      problema = 'Escriba un nombre para la parcela.';
    } else if (latitud == null || latitud < -90 || latitud > 90) {
      problema = 'La latitud debe ser un número entre -90 y 90.';
    } else if (longitud == null || longitud < -180 || longitud > 180) {
      problema = 'La longitud debe ser un número entre -180 y 180.';
    } else if (altitud == null || altitud < 0 || altitud > 6500) {
      problema = 'La altitud debe estar entre 0 y 6500 metros.';
    }
    if (problema != null) {
      setState(() => _error = ErrorApi(problema!));
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final parcela = await widget.api.crearParcela(
        nombre: nombre,
        latitud: latitud!,
        longitud: longitud!,
        altitudMsnm: altitud!,
        variedad: _variedad.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(parcela);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const tecladoNumerico = TextInputType.numberWithOptions(decimal: true, signed: true);
    return AlertDialog(
      title: const Text('Nueva parcela'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.sentences,
                decoration: decoracion('Nombre de la parcela', ayuda: 'Ejemplo: Chacra Norte'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _variedad,
                decoration: decoracion('Variedad (opcional)', ayuda: 'Ejemplo: Huayro, Yungay'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latitud,
                      keyboardType: tecladoNumerico,
                      decoration: decoracion('Latitud'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _longitud,
                      keyboardType: tecladoNumerico,
                      decoration: decoracion('Longitud'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _altitud,
                keyboardType: tecladoNumerico,
                decoration: decoracion('Altitud (m s. n. m.)', ayuda: 'Puede copiar las coordenadas desde Google Maps.'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                BannerMensaje(texto: _error!.mensaje, ayuda: _error!.ayuda),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 46)),
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : const Text('Guardar parcela'),
        ),
      ],
    );
  }
}

// ============================================================================
// Pestaña: Historial
// ============================================================================

class PestanaHistorial extends StatefulWidget {
  const PestanaHistorial({super.key, required this.api, required this.alSesionVencida});

  final ClienteApi api;
  final VoidCallback alSesionVencida;

  @override
  State<PestanaHistorial> createState() => _PestanaHistorialState();
}

class _PestanaHistorialState extends State<PestanaHistorial> {
  static const int _tamanoPagina = 20;

  final List<Diagnostico> _items = [];
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = false;
  ErrorApi? _error;

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final pagina = await widget.api.listarDiagnosticos(limite: _tamanoPagina);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(pagina);
        _hayMas = pagina.length == _tamanoPagina;
      });
    } on ErrorApi catch (e) {
      if (e.sesionVencida) {
        widget.alSesionVencida();
        return;
      }
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarMas() async {
    if (_items.isEmpty || _cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      final pagina = await widget.api.listarDiagnosticos(limite: _tamanoPagina, antesDeId: _items.last.id);
      if (!mounted) return;
      setState(() {
        _items.addAll(pagina);
        _hayMas = pagina.length == _tamanoPagina;
      });
    } on ErrorApi catch (e) {
      if (e.sesionVencida) {
        widget.alSesionVencida();
        return;
      }
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Widget _tarjeta(Diagnostico d) {
    final estilo = EstiloSemaforo.de(d.semaforo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Paleta.superficie,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Paleta.borde),
        ),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: d.miniatura == null
                  ? Container(color: estilo.fondo, child: Icon(Icons.eco, color: estilo.acento))
                  : Image.memory(d.miniatura!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          title: Text(
            d.nombreDiagnostico,
            style: const TextStyle(color: Paleta.tinta, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d.porcentaje} % de confianza  ·  ${d.parcelaNombre}',
                  style: const TextStyle(color: Paleta.tintaSuave, fontSize: 13),
                ),
                Text(
                  formatearFecha(d.capturadoEn),
                  style: const TextStyle(color: Paleta.tintaSuave, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: InsigniaSemaforo(semaforo: d.semaforo, compacta: true)),
              ],
            ),
          ),
          children: [
            if (d.modoDemostracion && d.advertenciaModelo != null) ...[
              BannerMensaje(
                texto: d.advertenciaModelo!,
                fondo: Paleta.papaClaro,
                acento: Paleta.papa,
                icono: Icons.science_outlined,
              ),
              const SizedBox(height: 12),
            ],
            const Text('Consejos', style: TextStyle(color: Paleta.tinta, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ListaRecomendaciones(recomendaciones: d.recomendaciones),
            Text(d.aviso, style: const TextStyle(color: Paleta.tintaSuave, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          BannerMensaje(texto: _error!.mensaje, ayuda: _error!.ayuda),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: recargar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.history, size: 54, color: Paleta.verde),
          SizedBox(height: 12),
          Text(
            'Todavía no hay consultas',
            textAlign: TextAlign.center,
            style: TextStyle(color: Paleta.tinta, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Haga su primer diagnóstico en la pestaña Diagnóstico IA y aparecerá aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Paleta.tintaSuave, fontSize: 15, height: 1.4),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        if (_error != null) ...[
          BannerMensaje(texto: _error!.mensaje, ayuda: _error!.ayuda),
          const SizedBox(height: 12),
        ],
        for (final d in _items) _tarjeta(d),
        if (_hayMas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton(
              onPressed: _cargandoMas ? null : _cargarMas,
              child: _cargandoMas
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : const Text('Ver consultas anteriores'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContenedorCentrado(
      child: RefreshIndicator(
        onRefresh: recargar,
        child: _contenido(),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF05070D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const VelocimetroApp());
}

class VelocimetroApp extends StatelessWidget {
  const VelocimetroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Velocímetro GPS Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05070D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  StreamSubscription<Position>? _sub;
  bool _midiendo = false;
  bool _permisoOtorgado = false;
  String _estado = 'Listo';
  double _velocidadKmh = 0.0;
  double _velocidadKmhSuavizada = 0.0;
  double _velocidadMaxima = 0.0;
  double _velocidadPromedio = 0.0;
  double _altitud = 0.0;
  double _rumboGrados = 0.0;
  String _direccionBr = 'Norte';
  double _distanciaTotal = 0.0;
  Duration _duracionViaje = Duration.zero;
  bool _mostrarMph = false;
  final Stopwatch _stopwatch = Stopwatch();
  Position? _ultimaPosicion;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _verificarPermisos();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _verificarPermisos() async {
    final bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      setState(() {
        _estado = 'Activa el GPS en tu celular';
        _permisoOtorgado = false;
      });
      return;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      setState(() {
        _permisoOtorgado = false;
        _estado = 'Permiso de ubicación denegado';
      });
      return;
    }

    setState(() {
      _permisoOtorgado = true;
      _estado = 'Listo para medir';
    });
  }

  void _iniciar() {
    if (!_permisoOtorgado) {
      _verificarPermisos();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _midiendo = true;
      _velocidadKmh = 0.0;
      _velocidadKmhSuavizada = 0.0;
      _velocidadMaxima = 0.0;
      _velocidadPromedio = 0.0;
      _distanciaTotal = 0.0;
      _duracionViaje = Duration.zero;
      _ultimaPosicion = null;
      _estado = 'Midiendo velocidad GPS...';
    });
    _stopwatch
      ..reset()
      ..start();

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Velocímetro GPS en medición activa',
          notificationTitle: 'Velocímetro Pro',
          enableWakeLock: true,
        ),
      ),
    ).listen(_onPosicion, onError: (dynamic e) {
      setState(() => _estado = 'Error GPS: $e');
    });
  }

  void _detener() {
    HapticFeedback.heavyImpact();
    _sub?.cancel();
    _sub = null;
    _stopwatch.stop();
    setState(() {
      _midiendo = false;
      _duracionViaje = _stopwatch.elapsed;
      _estado = 'Detenido';
    });
  }

  void _onPosicion(Position p) {
    double velocidadKmh = p.speed * 3.6;
    if (velocidadKmh < 0) velocidadKmh = 0;

    // Suavizado exponencial para lecturas estables y fluidas
    final double suavizada = _velocidadKmhSuavizada == 0.0
        ? velocidadKmh
        : (_velocidadKmhSuavizada * 0.65 + velocidadKmh * 0.35);

    double distancia = 0;
    if (_ultimaPosicion != null) {
      distancia = Geolocator.distanceBetween(
        _ultimaPosicion!.latitude,
        _ultimaPosicion!.longitude,
        p.latitude,
        p.longitude,
      );
    }
    _ultimaPosicion = p;

    setState(() {
      _velocidadKmh = suavizada < 0.4 ? 0.0 : suavizada;
      _velocidadKmhSuavizada = _velocidadKmh;
      if (_velocidadKmh > _velocidadMaxima) {
        _velocidadMaxima = _velocidadKmh;
      }
      _altitud = p.altitude;
      _rumboGrados = p.heading;
      _direccionBr = _convertirDireccion(p.heading);
      _distanciaTotal += distancia;
      _duracionViaje = _stopwatch.elapsed;

      if (_duracionViaje.inSeconds > 5 && _distanciaTotal > 0.01) {
        final horas = _duracionViaje.inSeconds / 3600.0;
        _velocidadPromedio = _distanciaTotal / horas;
      }
      _estado = 'Midiendo con precisión ±${p.accuracy.toStringAsFixed(0)} m';
    });
  }

  String _convertirDireccion(double grados) {
    if (grados < 0 || grados >= 360) return 'Norte';
    int indice = ((grados + 22.5) % 360 / 45).floor();
    switch (indice) {
      case 0: return 'Norte';
      case 1: return 'NE';
      case 2: return 'Este';
      case 3: return 'SE';
      case 4: return 'Sur';
      case 5: return 'SO';
      case 6: return 'Oeste';
      case 7: return 'NO';
      default: return 'Norte';
    }
  }

  String _formatearDuracion(Duration d) {
    String dosDigitos(int n) => n.toString().padLeft(2, '0');
    return '${dosDigitos(d.inHours)}:${dosDigitos(d.inMinutes % 60)}:${dosDigitos(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final double velocidadVisual = _mostrarMph
        ? _velocidadKmh * 0.621371
        : _velocidadKmh;
    final double maxVis = _mostrarMph ? 124.0 : 200.0;
    final double progreso = (velocidadVisual / maxVis).clamp(0.0, 1.0);

    final Color colorActual = progreso > 0.8
        ? const Color(0xFFF43F5E)
        : progreso > 0.5
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF05070D),
              const Color(0xFF090D16),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double availableW = constraints.maxWidth;
              final double availableH = constraints.maxHeight;
              final double maxGaugeH = (availableH * 0.44).clamp(170.0, 260.0);
              final double maxGaugeW = (availableW * 0.75).clamp(180.0, 270.0);
              final double gaugeSize = maxGaugeH < maxGaugeW ? maxGaugeH : maxGaugeW;
              final double speedFontSize = (gaugeSize * 0.22).clamp(38.0, 58.0);

              return Column(
                children: [
                  // Barra superior
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.speed,
                                color: Color(0xFF38BDF8),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Velocímetro Pro',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'GPS de Alta Precisión',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _permisoOtorgado
                                    ? const Color(0xFF064E3B)
                                    : const Color(0xFF7F1D1D),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _permisoOtorgado
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF43F5E),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _permisoOtorgado
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFFF87171),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _permisoOtorgado ? 'GPS OK' : 'GPS Off',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _mostrarMph ? Icons.swap_horiz : Icons.speed,
                                color: Colors.white70,
                                size: 22,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _mostrarMph = !_mostrarMph);
                              },
                              tooltip: 'Cambiar a ${_mostrarMph ? 'km/h' : 'mph'}',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Velocímetro Circular
                  SizedBox(
                    width: gaugeSize,
                    height: gaugeSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_midiendo)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: (gaugeSize * 0.85) + (_pulseController.value * 18),
                                height: (gaugeSize * 0.85) + (_pulseController.value * 18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorActual.withValues(alpha: 0.12 + (_pulseController.value * 0.12)),
                                      blurRadius: 24,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        CustomPaint(
                          painter: _ModernGaugePainter(
                            progreso: progreso,
                            color: colorActual,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: Text(
                                    velocidadVisual.toStringAsFixed(0),
                                    key: ValueKey(velocidadVisual.toStringAsFixed(0)),
                                    style: TextStyle(
                                      fontSize: speedFontSize,
                                      fontWeight: FontWeight.w900,
                                      color: colorActual,
                                      letterSpacing: -2,
                                      shadows: [
                                        Shadow(
                                          color: colorActual.withValues(alpha: 0.4),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _mostrarMph ? 'MPH' : 'KM/H',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tarjetas de Telemetría
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildCard(
                            icon: Icons.explore,
                            titulo: 'Dirección',
                            valor: '$_direccionBr (${_rumboGrados.toStringAsFixed(0)}°)',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildCard(
                            icon: Icons.flag,
                            titulo: 'Máxima',
                            valor: '${_velocidadMaxima.toStringAsFixed(0)} km/h',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildCard(
                            icon: Icons.social_distance,
                            titulo: 'Distancia',
                            valor: '${_distanciaTotal.toStringAsFixed(2)} km',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Fila secundaria de datos
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMiniCard(
                            titulo: 'Tiempo',
                            valor: _formatearDuracion(_duracionViaje),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMiniCard(
                            titulo: 'Promedio',
                            valor: '${_velocidadPromedio.toStringAsFixed(0)} km/h',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMiniCard(
                            titulo: 'Altitud',
                            valor: '${_altitud.toStringAsFixed(0)} m',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Estado del GPS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _midiendo ? Icons.gps_fixed : Icons.gps_not_fixed,
                          color: _midiendo ? const Color(0xFF10B981) : Colors.grey,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _estado,
                            style: TextStyle(
                              fontSize: 11,
                              color: _midiendo ? const Color(0xFF34D399) : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Botón Principal
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _midiendo ? _detener : _iniciar,
                        icon: Icon(
                          _midiendo ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          size: 25,
                        ),
                        label: Text(
                          _midiendo ? 'DETENER MEDICIÓN' : 'INICIAR VELOCÍMETRO',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _midiendo
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 6,
                          shadowColor: _midiendo
                              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                              : const Color(0xFF10B981).withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String titulo,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF38BDF8)),
              const SizedBox(width: 4),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard({required String titulo, required String valor}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ModernGaugePainter extends CustomPainter {
  final double progreso;
  final Color color;

  _ModernGaugePainter({required this.progreso, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 24;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    // Fondo de la pista
    final bgPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Arco de progreso dinámico
    if (progreso > 0) {
      final fgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progreso,
        false,
        fgPaint,
      );
    }

    // Marcas de velocidad y números (0, 20, 40, 60, 80, 100, 120)
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 2;

    for (int i = 0; i <= 20; i++) {
      final angle = startAngle + (sweepAngle * i / 20);
      final isMajor = i % 4 == 0;
      final inner = radius - (isMajor ? 20 : 14);
      final outer = radius - 8;
      canvas.drawLine(
        Offset(center.dx + inner * math.cos(angle),
            center.dy + inner * math.sin(angle)),
        Offset(center.dx + outer * math.cos(angle),
            center.dy + outer * math.sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModernGaugePainter oldDelegate) {
    return oldDelegate.progreso != progreso || oldDelegate.color != color;
  }
}

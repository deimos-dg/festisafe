import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../providers/location_provider.dart';
import '../../core/constants.dart';

class CompassScreen extends ConsumerStatefulWidget {
  final String targetUserId;
  const CompassScreen({super.key, required this.targetUserId});

  @override
  ConsumerState<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends ConsumerState<CompassScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _magnetometerSub;
  double _heading = 0;
  double _arrowAngle = 0;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _magnetometerSub = magnetometerEventStream().listen((event) {
      final angle = atan2(event.y, event.x) * (180 / pi);
      if (mounted) setState(() => _heading = (angle + 360) % 360);
    });
  }

  @override
  void dispose() {
    _magnetometerSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  double _bearingTo(double tLat, double tLng, double mLat, double mLng) {
    final dLng = (tLng - mLng) * pi / 180;
    final lat1 = mLat * pi / 180;
    final lat2 = tLat * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(memberLocationsProvider);
    final myPos = ref.watch(locationProvider).currentPosition;
    final target = locations[widget.targetUserId];

    if (target == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF030712),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Rastreo Táctico',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, size: 64, color: Colors.white24),
              SizedBox(height: 16),
              Text('Ubicación no disponible',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              SizedBox(height: 8),
              Text('El compañero no ha compartido su posición',
                  style: TextStyle(color: Colors.white30, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final isStale = DateTime.now().difference(target.updatedAt).inMinutes >=
        AppConstants.markerDimMinutes;

    double? distance;
    if (myPos != null) {
      distance = _distanceMeters(
        myPos.latitude, myPos.longitude,
        target.latitude, target.longitude,
      );
      final bearing = _bearingTo(
        target.latitude, target.longitude,
        myPos.latitude, myPos.longitude,
      );
      _arrowAngle = (bearing - _heading) * pi / 180;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(0.3),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                'RASTREO — ${target.name.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.indigoAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fondo con grid
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 20,
                ),
                itemBuilder: (_, __) => Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.indigoAccent, width: 0.3),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Advertencia de ubicación antigua
                if (isStale)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ubicación desactualizada (>${AppConstants.markerDimMinutes} min)',
                                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                const Spacer(),

                // Avatar + nombre + distancia
                Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 90 + 30 * _pulseCtrl.value,
                            height: 90 + 30 * _pulseCtrl.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.indigoAccent.withOpacity(
                                  0.15 * (1 - _pulseCtrl.value)),
                            ),
                          ),
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.indigoAccent.withOpacity(0.2),
                            child: Text(
                              target.initials,
                              style: const TextStyle(
                                color: Colors.indigoAccent,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      target.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (distance != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.indigoAccent.withOpacity(0.4)),
                        ),
                        child: Text(
                          _formatDistance(distance),
                          style: const TextStyle(
                            color: Colors.indigoAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                  ],
                ),

                const Spacer(),

                // Brújula
                if (myPos != null)
                  _CompassDial(angle: _arrowAngle, pulse: _pulseCtrl)
                else
                  const Column(
                    children: [
                      Icon(Icons.gps_not_fixed, size: 80, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('Esperando GPS...',
                          style: TextStyle(color: Colors.white38, fontSize: 14)),
                    ],
                  ),

                const Spacer(),

                // Instrucción
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Text(
                    'Mantén el teléfono horizontal · Sigue la flecha',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget de la brújula
// ---------------------------------------------------------------------------
class _CompassDial extends StatelessWidget {
  final double angle;
  final Animation<double> pulse;

  const _CompassDial({required this.angle, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillo exterior
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.indigoAccent.withOpacity(0.3), width: 1.5),
              color: Colors.indigoAccent.withOpacity(0.05),
            ),
          ),
          // Marcas cardinales
          ..._cardinalMarks(),
          // Flecha rotante
          Transform.rotate(
            angle: angle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Punta de flecha
                Container(
                  width: 0,
                  height: 0,
                  decoration: const BoxDecoration(),
                  child: CustomPaint(
                    size: const Size(24, 60),
                    painter: _ArrowPainter(color: Colors.indigoAccent),
                  ),
                ),
                const SizedBox(height: 4),
                // Cola de flecha
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          // Centro
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.indigoAccent,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cardinalMarks() {
    const labels = ['N', 'E', 'S', 'O'];
    const angles = [0.0, pi / 2, pi, 3 * pi / 2];
    const r = 95.0;
    return List.generate(4, (i) {
      final x = r * sin(angles[i]);
      final y = -r * cos(angles[i]);
      return Positioned(
        left: 110 + x - 10,
        top: 110 + y - 10,
        child: Text(
          labels[i],
          style: TextStyle(
            color: i == 0 ? Colors.redAccent : Colors.white38,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    });
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  const _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.7)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

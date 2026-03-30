import 'dart:async';
import 'dart:math';
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

class _CompassScreenState extends ConsumerState<CompassScreen> {
  StreamSubscription? _magnetometerSub;
  double _heading = 0; // grados norte magnético
  double _arrowAngle = 0; // ángulo hacia el objetivo

  @override
  void initState() {
    super.initState();
    _magnetometerSub = magnetometerEventStream().listen((event) {
      // Calcular heading desde el magnetómetro
      final angle = atan2(event.y, event.x) * (180 / pi);
      setState(() => _heading = (angle + 360) % 360);
    });
  }

  @override
  void dispose() {
    _magnetometerSub?.cancel();
    super.dispose();
  }

  double _bearingTo(double targetLat, double targetLng, double myLat, double myLng) {
    final dLng = (targetLng - myLng) * pi / 180;
    final lat1 = myLat * pi / 180;
    final lat2 = targetLat * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(memberLocationsProvider);
    final myPos = ref.watch(locationProvider).currentPosition;
    final target = locations[widget.targetUserId];

    if (target == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Brújula')),
        body: const Center(child: Text('Ubicación del compañero no disponible')),
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
      appBar: AppBar(
        title: Text('Hacia ${target.name.split(' ').first}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Advertencia si la ubicación es antigua
            if (isStale)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La ubicación de ${target.name.split(' ').first} tiene más de ${AppConstants.markerDimMinutes} minutos',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),

            // Nombre y avatar
            CircleAvatar(
              radius: 32,
              child: Text(
                target.initials,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(target.name, style: Theme.of(context).textTheme.titleLarge),

            // Distancia
            if (distance != null) ...[
              const SizedBox(height: 4),
              Text(
                distance < 1000
                    ? '${distance.toStringAsFixed(0)} m'
                    : '${(distance / 1000).toStringAsFixed(1)} km',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],

            const SizedBox(height: 48),

            // Flecha de brújula
            if (myPos != null)
              Transform.rotate(
                angle: _arrowAngle,
                child: Icon(
                  Icons.navigation,
                  size: 120,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else
              const Column(
                children: [
                  Icon(Icons.gps_off, size: 64, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Esperando GPS...', style: TextStyle(color: Colors.grey)),
                ],
              ),

            const SizedBox(height: 32),
            Text(
              'Mantén el teléfono horizontal y sigue la flecha',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

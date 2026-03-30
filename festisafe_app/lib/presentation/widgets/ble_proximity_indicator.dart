import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ble_provider.dart';
import '../../data/services/ble_service.dart';

/// Indicador de miembros cercanos detectados por BLE.
/// Se muestra en el AppBar del mapa cuando hay miembros a <15m.
class BleProximityIndicator extends ConsumerWidget {
  const BleProximityIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleProvider);

    if (!bleState.isActive) return const SizedBox.shrink();

    final nearby = bleState.nearbyMembers;
    if (nearby.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: '${nearby.length} miembro(s) cerca via Bluetooth',
      child: GestureDetector(
        onTap: () => _showNearbySheet(context, nearby),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.bluetooth, color: Colors.lightBlueAccent, size: 20),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${nearby.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNearbySheet(BuildContext context, List<BleDevice> devices) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth, color: Colors.lightBlueAccent),
                const SizedBox(width: 8),
                Text(
                  'Miembros cercanos (Bluetooth)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Detectados a menos de 15 metros',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...devices.map((d) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.lightBlue.shade100,
                    child: const Icon(Icons.person, color: Colors.lightBlue, size: 18),
                  ),
                  title: Text(d.userId.substring(0, 8)),
                  subtitle: Text(
                    '~${d.estimatedMeters.toStringAsFixed(0)} m · ${d.rssi} dBm',
                  ),
                  trailing: Icon(
                    Icons.circle,
                    color: d.estimatedMeters < 5
                        ? Colors.green
                        : d.estimatedMeters < 10
                            ? Colors.orange
                            : Colors.red,
                    size: 12,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

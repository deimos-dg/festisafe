import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/battery_provider.dart';
import '../../core/constants.dart';

/// Indicador de batería baja que aparece en la barra superior del mapa.
class BatteryIndicator extends ConsumerWidget {
  const BatteryIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryProvider);

    return battery.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (level) {
        if (level >= AppConstants.batteryLowThreshold) return const SizedBox.shrink();

        final isCritical = level < AppConstants.batteryCriticalThreshold;
        final color = isCritical ? Colors.red : Colors.orange;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCritical ? Icons.battery_alert : Icons.battery_2_bar,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                '$level%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

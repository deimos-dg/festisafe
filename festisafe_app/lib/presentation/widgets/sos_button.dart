import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/sos_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/battery_provider.dart';
import '../../data/services/sos_service.dart';

/// Botón SOS con un solo tap + confirmación.
class SosButton extends ConsumerStatefulWidget {
  final String eventId;
  const SosButton({super.key, required this.eventId});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;

    final sosState = ref.read(sosProvider);

    if (sosState.isSosActive) {
      // Desactivar SOS — confirmar
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cancelar SOS'),
          content: const Text('¿Estás seguro de que ya estás bien?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, estoy bien')),
          ],
        ),
      );
      if (confirm != true) return;
    } else {
      // Activar SOS — confirmar
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🆘 Activar SOS'),
          content: const Text(
            'Se enviará una alerta a tu grupo y a los organizadores con tu ubicación actual.\n\n¿Necesitas ayuda?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, necesito ayuda'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _executeSos();
  }

  Future<void> _executeSos() async {
    setState(() => _loading = true);

    final sosState = ref.read(sosProvider);
    final locationState = ref.read(locationProvider);
    final battery = ref.read(batteryProvider).value ?? 100;
    final service = SosService();

    try {
      if (sosState.isSosActive) {
        await service.deactivate(widget.eventId);
        if (mounted) ref.read(sosProvider.notifier).setSosActive(false);
      } else {
        final pos = locationState.currentPosition;
        await service.activate(
          eventId: widget.eventId,
          position: pos,
          batteryLevel: battery,
        );
        if (mounted) ref.read(sosProvider.notifier).setSosActive(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosProvider);
    final isActive = sosState.isSosActive;

    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.red : Colors.red.shade700,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4),
                  blurRadius: isActive ? 16 : 8,
                  spreadRadius: isActive ? 4 : 0,
                ),
              ],
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sos, color: Colors.white, size: 24),
                      if (isActive)
                        const Text(
                          'ACTIVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

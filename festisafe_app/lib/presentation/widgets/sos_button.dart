import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/sos_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/battery_provider.dart';
import '../../data/services/sos_service.dart';

/// Botón SOS con hold de 2 segundos y progreso circular.
class SosButton extends ConsumerStatefulWidget {
  final String eventId;
  const SosButton({super.key, required this.eventId});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressCtrl;
  bool _holding = false;
  bool _loading = false;

  static const _holdDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerSos();
      }
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (_loading) return;
    setState(() => _holding = true);
    _progressCtrl.forward(from: 0);
  }

  void _onTapUp(TapUpDetails _) => _cancelHold();
  void _onTapCancel() => _cancelHold();

  void _cancelHold() {
    if (!_holding) return;
    setState(() => _holding = false);
    _progressCtrl.stop();
    _progressCtrl.reset();
  }

  Future<void> _triggerSos() async {
    setState(() {
      _holding = false;
      _loading = true;
    });
    _progressCtrl.reset();

    final sosState = ref.read(sosProvider);
    final locationState = ref.read(locationProvider);
    final battery = ref.read(batteryProvider).value ?? 100;

    final service = SosService();

    try {
      if (sosState.isSosActive) {
        await service.deactivate(widget.eventId);
        ref.read(sosProvider.notifier).setSosActive(false);
      } else {
        final pos = locationState.currentPosition;
        await service.activate(
          eventId: widget.eventId,
          position: pos,
          batteryLevel: battery,
        );
        ref.read(sosProvider.notifier).setSosActive(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ${sosState.isSosActive ? 'cancelar' : 'activar'} SOS: $e'),
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
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _progressCtrl,
        builder: (_, __) {
          return SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progreso circular durante el hold
                if (_holding)
                  CircularProgressIndicator(
                    value: _progressCtrl.value,
                    strokeWidth: 4,
                    color: Colors.red,
                  ),
                // Botón principal
                Container(
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
              ],
            ),
          );
        },
      ),
    );
  }
}

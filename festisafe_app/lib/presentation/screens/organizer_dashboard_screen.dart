import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/event_provider.dart';
import '../../providers/sos_provider.dart';
import '../../providers/ws_provider.dart';
import '../../data/models/sos_alert.dart';
import '../../data/models/ws_message.dart';
import '../../data/services/sos_service.dart';
import '../../data/services/api_client.dart';
import '../widgets/create_event_form.dart';

class OrganizerDashboardScreen extends ConsumerStatefulWidget {
  final String eventId;
  const OrganizerDashboardScreen({super.key, required this.eventId});

  @override
  ConsumerState<OrganizerDashboardScreen> createState() =>
      _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState
    extends ConsumerState<OrganizerDashboardScreen> {
  Timer? _refreshTimer;
  int _participantCount = 0;
  bool _loadingParticipants = false;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
    _loadActiveSos();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadParticipants(),
    );
    // Escuchar SOS via WS
    _wsSub = ref.read(wsClientProvider).messageStream.listen(_onWsMessage);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  void _onWsMessage(WsMessage msg) {
    switch (msg.type) {
      case WsMessageType.sos:
        final alert = SosAlert.fromWsMessage(msg.payload);
        ref.read(sosProvider.notifier).onSosReceived(alert);
      case WsMessageType.sosCancelled:
        ref.read(sosProvider.notifier).onSosCancelled(msg.payload['user_id'] as String);
      default:
        break;
    }
  }

  Future<void> _loadParticipants() async {
    setState(() => _loadingParticipants = true);
    try {
      final participants =
          await ref.read(eventServiceProvider).getParticipants(widget.eventId);
      if (mounted) setState(() => _participantCount = participants.length);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  Future<void> _loadActiveSos() async {
    try {
      final alerts = await SosService().getActiveSos(widget.eventId);
      if (mounted) ref.read(sosProvider.notifier).setActiveAlerts(alerts);
    } catch (_) {}
  }

  Future<void> _toggleEvent(bool isActive) async {
    try {
      final service = ref.read(eventServiceProvider);
      if (isActive) {
        await service.deactivateEvent(widget.eventId);
      } else {
        await service.activateEvent(widget.eventId);
      }
      ref.invalidate(myEventsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isActive ? 'Evento desactivado' : 'Evento activado'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateGuestCode() async {
    context.push('/qr/${widget.eventId}');
  }

  Future<void> _showCreateEventDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Crear evento',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 20),
              CreateEventForm(
                onCreated: () {
                  Navigator.of(ctx).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Evento creado')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(eventServiceProvider).deleteEvent(widget.eventId);
      ref.invalidate(myEventsProvider);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _escalateSos(SosAlert alert) async {
    try {
      await SosService().escalateSos(widget.eventId, alert.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOS de ${alert.userName} escalado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setMeetingPoint() async {
    final nameCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Pre-cargar valores actuales si existen
    ref.read(myEventsProvider).whenData((events) {
      final event = events.where((e) => e.id == widget.eventId).firstOrNull;
      if (event != null) {
        nameCtrl.text = event.meetingPointName ?? '';
        latCtrl.text = event.meetingPointLat?.toString() ?? '';
        lngCtrl.text = event.meetingPointLng?.toString() ?? '';
      }
    });

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Punto de encuentro'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre (ej: Entrada principal)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Latitud',
                  border: OutlineInputBorder(),
                  hintText: 'ej: 41.3851',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < -90 || n > 90) return 'Inválida (-90 a 90)';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Longitud',
                  border: OutlineInputBorder(),
                  hintText: 'ej: 2.1734',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < -180 || n > 180) return 'Inválida (-180 a 180)';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);
              try {
                await ApiClient().dio.patch('/events/${widget.eventId}', data: {
                  'meeting_point_lat': double.parse(latCtrl.text),
                  'meeting_point_lng': double.parse(lngCtrl.text),
                  'meeting_point_name': nameCtrl.text.trim(),
                });
                ref.invalidate(myEventsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Punto de encuentro actualizado')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosProvider);
    final eventsAsync = ref.watch(myEventsProvider);

    final isActive = eventsAsync.whenOrNull(
          data: (events) =>
              events.where((e) => e.id == widget.eventId).firstOrNull?.isActive,
        ) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del organizador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Ver mapa',
            onPressed: () => context.push('/map/${widget.eventId}'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadParticipants,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Estadísticas
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.people,
                    label: 'Participantes activos',
                    value: _loadingParticipants ? '...' : '$_participantCount',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.sos,
                    label: 'SOS activos',
                    value: '${sosState.activeAlerts.length}',
                    color: sosState.activeAlerts.isNotEmpty ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Controles del evento
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Controles', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: isActive ? Colors.orange : Colors.green,
                            ),
                            onPressed: () => _toggleEvent(isActive),
                            icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                            label: Text(isActive ? 'Desactivar evento' : 'Activar evento'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _generateGuestCode,
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Generar código QR'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showCreateEventDialog,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Crear nuevo evento'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: _deleteEvent,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar evento'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _setMeetingPoint,
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Punto de encuentro'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/participants/${widget.eventId}'),
                            icon: const Icon(Icons.people_outlined),
                            label: const Text('Ver participantes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lista de SOS activos
            if (sosState.activeAlerts.isNotEmpty) ...[
              Text(
                'Alertas SOS activas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.red,
                    ),
              ),
              const SizedBox(height: 8),
              ...sosState.activeAlerts.map(
                (alert) => _SosAlertCard(
                  alert: alert,
                  onLocate: () => context.push('/map/${widget.eventId}'),
                  onEscalate: () => _escalateSos(alert),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SosAlertCard extends StatelessWidget {
  final SosAlert alert;
  final VoidCallback onLocate;
  final VoidCallback onEscalate;

  const _SosAlertCard({
    required this.alert,
    required this.onLocate,
    required this.onEscalate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.sos, color: Colors.white),
        ),
        title: Text(alert.userName),
        subtitle: Text(
          'Batería: ${alert.batteryLevel}%${alert.isEscalated ? ' · ESCALADO' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Localizar en mapa',
              onPressed: onLocate,
            ),
            if (!alert.isEscalated)
              IconButton(
                icon: const Icon(Icons.warning_amber, color: Colors.orange),
                tooltip: 'Escalar SOS',
                onPressed: onEscalate,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/event_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../data/models/event.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myEventsAsync = ref.watch(myEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del evento')),
      body: myEventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (myEvents) {
          final isParticipant = myEvents.any((e) => e.id == eventId);
          final event = myEvents.where((e) => e.id == eventId).firstOrNull;
          if (event == null) {
            return _EventDetailLoader(eventId: eventId, isParticipant: false);
          }
          return _EventDetailBody(event: event, isParticipant: isParticipant);
        },
      ),
    );
  }
}

/// Carga el evento directamente si no está en caché.
class _EventDetailLoader extends ConsumerWidget {
  final String eventId;
  final bool isParticipant;
  const _EventDetailLoader({required this.eventId, required this.isParticipant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allEvents = ref.watch(eventListProvider(null));
    return allEvents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (events) {
        final event = events.where((e) => e.id == eventId).firstOrNull;
        if (event == null) {
          return const Center(child: Text('Evento no encontrado'));
        }
        return _EventDetailBody(event: event, isParticipant: isParticipant);
      },
    );
  }
}

class _EventDetailBody extends ConsumerStatefulWidget {
  final EventModel event;
  final bool isParticipant;
  const _EventDetailBody({required this.event, required this.isParticipant});

  @override
  ConsumerState<_EventDetailBody> createState() => _EventDetailBodyState();
}

class _EventDetailBodyState extends ConsumerState<_EventDetailBody> {
  bool _joining = false;

  Future<void> _leaveEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salir del evento'),
        content: const Text('¿Estás seguro? Perderás acceso al mapa y al grupo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(eventServiceProvider).leaveEvent(widget.event.id);
      ref.invalidate(myEventsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saliste del evento')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await ref.read(eventServiceProvider).joinEvent(widget.event.id);
      ref.invalidate(myEventsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te uniste al evento')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      String msg = 'No se pudo unir al evento';
      if (e.toString().contains('403')) msg = 'Evento lleno o inactivo';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = widget.event;
    final authState = ref.watch(authProvider);
    final isOrganizer = authState is AuthAuthenticated && authState.user.isOrganizer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado
          Row(
            children: [
              Expanded(
                child: Text(event.name, style: theme.textTheme.headlineSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: event.isActive
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  event.isActive ? 'Activo' : 'Inactivo',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: event.isActive ? Colors.green : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (event.description != null) ...[
            Text(event.description!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],

          _InfoRow(icon: Icons.location_on_outlined, text: event.locationName ?? 'Sin ubicación'),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            text: '${_fmt(event.startDate)} – ${_fmt(event.endDate)}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.people_outlined,
            text: 'Máx. ${event.maxParticipants} participantes',
          ),

          if (event.hasMeetingPoint) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.flag_outlined,
              text: 'Punto de encuentro definido',
            ),
          ],

          const SizedBox(height: 32),

          // Acciones
          if (event.isActive) ...[
            // Unirse solo si no es participante aún
            if (!widget.isParticipant)
              FilledButton.icon(
                onPressed: _joining ? null : _join,
                icon: _joining
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add),
                label: const Text('Unirse al evento'),
              ),
            if (widget.isParticipant) ...[
              // Ya es participante
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text('Ya eres participante', style: TextStyle(color: Colors.green)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/map/${event.id}'),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Ver mapa'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/participants/${event.id}'),
                icon: const Icon(Icons.people_outlined),
                label: const Text('Ver participantes'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/event-groups/${event.id}'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Ver grupos disponibles'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showCreateGroupDialog(context),
                icon: const Icon(Icons.group_outlined),
                label: const Text('Crear grupo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _leaveEvent,
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Salir del evento'),
              ),
            ],
          ],

          if (isOrganizer) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/organizer/${event.id}'),
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Panel del organizador'),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear grupo'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre del grupo',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              try {
                await ref.read(groupProvider.notifier).createGroup(
                  widget.event.id,
                  nameCtrl.text.trim(),
                );
                final group = ref.read(groupProvider).group;
                if (!mounted) return;
                if (group != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Grupo creado')),
                  );
                  context.push('/groups/${group.id}');
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

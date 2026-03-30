import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../data/models/event.dart';
import '../widgets/guest_banner.dart';
import '../widgets/create_event_form.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isGuest = authState is AuthGuest;
    final isOrganizer = authState is AuthAuthenticated && authState.user.isOrganizer;
    final myEvents = ref.watch(myEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FestiSafe'),
        actions: [
          // Chip de rol visible
          if (authState is AuthAuthenticated)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Chip(
                label: Text(
                  authState.user.role == 'admin'
                      ? 'Admin'
                      : authState.user.role == 'organizer'
                          ? 'Organizador'
                          : 'Usuario',
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.person_outlined),
            tooltip: 'Perfil',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isGuest) const GuestBanner(),
          // Banner de organizador con acceso rápido
          if (isOrganizer)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => _showCreateEventDialog(context, ref),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Crear nuevo evento'),
              ),
            ),
          Expanded(
            child: myEvents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 8),
                    Text('Error al cargar eventos: $e'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => ref.invalidate(myEventsProvider),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (events) => events.isEmpty
                  ? _EmptyState(onBrowse: () => context.push('/events'))
                  : _EventList(events: events, isOrganizer: isOrganizer),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/events'),
        icon: const Icon(Icons.search),
        label: const Text('Buscar eventos'),
      ),
    );
  }

  Future<void> _showCreateEventDialog(BuildContext context, WidgetRef ref) async {
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
              // Handle
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Evento creado')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptyState({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.festival, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No estás en ningún evento todavía'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onBrowse,
            child: const Text('Explorar eventos'),
          ),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  final List<EventModel> events;
  final bool isOrganizer;
  const _EventList({required this.events, required this.isOrganizer});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final event = events[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.festival),
            ),
            title: Text(event.name),
            subtitle: Text(event.locationName ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (event.isActive)
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    tooltip: 'Ver mapa',
                    onPressed: () => context.push('/map/${event.id}'),
                  ),
                // Acceso rápido al dashboard para organizadores
                if (isOrganizer)
                  IconButton(
                    icon: const Icon(Icons.dashboard_outlined),
                    tooltip: 'Panel organizador',
                    onPressed: () => context.push('/organizer/${event.id}'),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push('/events/${event.id}'),
          ),
        );
      },
    );
  }
}

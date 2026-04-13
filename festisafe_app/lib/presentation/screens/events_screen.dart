import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/event_provider.dart';
import '../../data/models/event.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(eventListProvider(_query.isEmpty ? null : _query));
    ref.invalidate(myEventsProvider);
    // Esperar a que ambos terminen
    await Future.wait([
      ref.read(eventListProvider(_query.isEmpty ? null : _query).future),
      ref.read(myEventsProvider.future).catchError((_) => <EventModel>[]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventListProvider(_query.isEmpty ? null : _query));
    // IDs de eventos en los que el usuario ya participa
    final myIds = ref
        .watch(myEventsProvider)
        .whenOrNull(data: (list) => list.map((e) => e.id).toSet()) ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Eventos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Buscar eventos...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: eventsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 8),
                    Text('Error: $e'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'No hay eventos activos por el momento'
                            : 'Sin resultados para "$_query"',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _EventGridCard(
                          event: list[i],
                          isEnrolled: myIds.contains(list[i].id),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card cuadrícula
// ---------------------------------------------------------------------------
class _EventGridCard extends StatelessWidget {
  final EventModel event;
  final bool isEnrolled;
  const _EventGridCard({required this.event, required this.isEnrolled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primaryContainer;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/events/${event.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Stack(
              children: [
                Container(
                  height: 72,
                  width: double.infinity,
                  color: color,
                  child: Center(
                    child: Icon(
                      Icons.festival,
                      size: 36,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                // Badge "Inscrito"
                if (isEnrolled)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Inscrito',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (event.locationName != null)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              event.locationName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(isActive: event.isActive),
                        const Spacer(),
                        Text(
                          _fmt(event.startDate),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ---------------------------------------------------------------------------
// Chip de estado
// ---------------------------------------------------------------------------
class _StatusChip extends StatelessWidget {
  final bool isActive;
  const _StatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontSize: 10,
          color: isActive ? Colors.green : Colors.grey,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

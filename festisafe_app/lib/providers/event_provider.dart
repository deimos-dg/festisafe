import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/event.dart';
import '../data/services/event_service.dart';

final eventServiceProvider = Provider<EventService>((ref) => EventService());

final eventListProvider = FutureProvider.family<List<EventModel>, String?>(
  (ref, query) => ref.read(eventServiceProvider).searchEvents(query: query),
);

/// Combina eventos en los que el usuario participa + eventos que organiza,
/// eliminando duplicados. Así el organizador siempre ve sus propios eventos.
final myEventsProvider = FutureProvider<List<EventModel>>((ref) async {
  // watch en lugar de read para reaccionar a invalidaciones
  final service = ref.watch(eventServiceProvider);
  final results = await Future.wait([
    service.getMyEvents(),
    service.getOrganizedEvents().catchError((_) => <EventModel>[]),
  ]);
  final joined = results[0];
  final organized = results[1];
  // Merge sin duplicados
  final seen = <String>{};
  final merged = <EventModel>[];
  for (final e in [...joined, ...organized]) {
    if (seen.add(e.id)) merged.add(e);
  }
  return merged;
});

final organizedEventsProvider = FutureProvider<List<EventModel>>(
  (ref) => ref.read(eventServiceProvider).getOrganizedEvents(),
);

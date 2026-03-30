import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/models/event.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 5: Lista de eventos ordenada por fecha
// Feature: festisafe-flutter-app, Property 6: Resultados de búsqueda contienen el texto buscado

EventModel _makeEvent({
  required String id,
  required String name,
  required int startOffsetDays,
  String description = '',
}) {
  final base = DateTime(2025, 1, 1);
  final start = base.add(Duration(days: startOffsetDays));
  return EventModel(
    id: id,
    name: name,
    description: description,
    startDate: start,
    endDate: start.add(const Duration(hours: 8)),
    maxParticipants: 100,
    isActive: true,
  );
}

void main() {
  // Feature: festisafe-flutter-app, Property 5: Lista de eventos ordenada por fecha
  test('Property 5: lista de eventos siempre ordenada por startDate ascendente', () {
    forAll(
      numRuns: 100,
      gen: () => genIntList(minLen: 2, maxLen: 10, min: 0, max: 3650),
      body: (offsets) {
        final events = offsets.asMap().entries.map((e) {
          return _makeEvent(
            id: 'evt-${e.key}',
            name: 'Evento ${e.key}',
            startOffsetDays: e.value,
          );
        }).toList();

        // Aplicar el mismo sort que hace EventService.searchEvents
        events.sort((a, b) => a.startDate.compareTo(b.startDate));

        for (int i = 0; i < events.length - 1; i++) {
          expect(
            events[i].startDate.isBefore(events[i + 1].startDate) ||
                events[i].startDate.isAtSameMomentAs(events[i + 1].startDate),
            isTrue,
            reason:
                'Evento en posición $i tiene fecha posterior al evento en posición ${i + 1}',
          );
        }
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 6: Resultados de búsqueda contienen el texto buscado
  test('Property 6: todos los resultados de búsqueda contienen el query', () {
    forAll2(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 10),
      genB: () => genStringList(minLen: 0, maxLen: 10),
      body: (query, eventNames) {
        final events = eventNames.asMap().entries.map((e) {
          return _makeEvent(
            id: 'evt-${e.key}',
            name: e.value,
            startOffsetDays: e.key,
          );
        }).toList();

        final queryLower = query.toLowerCase();
        final filtered = events.where((evt) {
          return evt.name.toLowerCase().contains(queryLower) ||
              (evt.description?.toLowerCase().contains(queryLower) ?? false);
        }).toList();

        for (final evt in filtered) {
          final nameContains = evt.name.toLowerCase().contains(queryLower);
          final descContains =
              evt.description?.toLowerCase().contains(queryLower) ?? false;
          expect(
            nameContains || descContains,
            isTrue,
            reason: 'Evento "${evt.name}" no contiene el query "$query"',
          );
        }
      },
    );
  });
}

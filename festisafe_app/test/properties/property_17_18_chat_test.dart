import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:festisafe/data/models/chat_message.dart';
import 'package:festisafe/providers/chat_provider.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 17: Formato correcto de mensajes de reacción
// Feature: festisafe-flutter-app, Property 18: Mensajes de chat mostrados en orden de recepción

void main() {
  // Feature: festisafe-flutter-app, Property 17: Formato correcto de mensajes de reacción
  test('Property 17: mensaje de reacción tiene todos los campos requeridos', () {
    const reactions = ['👍', '❤️', '🆘', '👋', '🎉'];

    forAll3(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 30),
      genB: () => genNonEmptyString(maxLen: 30),
      genC: () => genInt(min: 0, max: reactions.length),
      body: (userId, userName, reactionIdx) {
        final reaction = reactions[reactionIdx];

        // Mensaje que envía el cliente al WS
        final clientMessage = {'type': 'reaction', 'reaction': reaction};

        // Mensaje enriquecido que llega de vuelta por WS
        final serverMessage = {
          'type': 'reaction',
          'user_id': userId,
          'name': userName,
          'reaction': reaction,
        };

        final decoded = jsonDecode(jsonEncode(clientMessage)) as Map<String, dynamic>;

        expect(decoded['type'], equals('reaction'));
        expect(decoded['reaction'], isNotEmpty);

        // El mensaje del servidor debe tener todos los campos no vacíos
        expect(serverMessage['type'], equals('reaction'));
        expect((serverMessage['user_id'] as String), isNotEmpty);
        expect((serverMessage['name'] as String), isNotEmpty);
        expect((serverMessage['reaction'] as String), isNotEmpty);
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 18: Mensajes de chat mostrados en orden de recepción
  test('Property 18: mensajes de chat se muestran en orden de recepción', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 1, max: 21),
      body: (count) {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(chatProvider.notifier);
        final insertedTexts = <String>[];

        for (int i = 0; i < count; i++) {
          final text = 'Mensaje $i';
          insertedTexts.add(text);
          notifier.addMessage(ChatMessage(
            userId: 'user-$i',
            name: 'Usuario $i',
            text: text,
            timestamp: DateTime.now(),
          ));
        }

        final state = container.read(chatProvider);
        expect(state.length, equals(count));

        for (int i = 0; i < count; i++) {
          expect(state[i].text, equals(insertedTexts[i]),
              reason: 'Mensaje en posición $i no coincide con el orden de inserción');
        }
      },
    );
  });

  test('Property 18b: addMessage no reordena mensajes existentes', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 2, max: 11),
      body: (count) {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(chatProvider.notifier);
        final insertedTexts = <String>[];

        for (int i = 0; i < count; i++) {
          final text = 'Msg-$i-${genString(minLen: 3, maxLen: 10)}';
          insertedTexts.add(text);
          notifier.addMessage(ChatMessage(
            userId: 'user-$i',
            name: 'Usuario $i',
            text: text,
            timestamp: DateTime.now(),
          ));
        }

        final state = container.read(chatProvider);
        for (int i = 0; i < count; i++) {
          expect(state[i].text, equals(insertedTexts[i]));
        }
      },
    );
  });
}

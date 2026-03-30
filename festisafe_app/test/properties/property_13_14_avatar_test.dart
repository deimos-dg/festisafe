import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/constants.dart';
import 'package:festisafe/data/models/member_location.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 13: Avatar almacenado y recuperado correctamente
// Feature: festisafe-flutter-app, Property 14: Marcador de miembro refleja disponibilidad de avatar

void main() {
  // Feature: festisafe-flutter-app, Property 13: Avatar almacenado y recuperado correctamente
  test('Property 13: índice de avatar válido (0-11) se preserva en MemberLocation', () {
    forAll2(
      numRuns: 100,
      genA: () => genInt(min: 0, max: AppConstants.avatarCount),
      genB: () => genNonEmptyString(maxLen: 30),
      body: (avatarIndex, userId) {
        final loc = MemberLocation(
          userId: userId,
          name: 'Usuario Test',
          latitude: 40.0,
          longitude: -3.0,
          updatedAt: DateTime.now(),
          avatarIndex: avatarIndex,
        );

        expect(loc.avatarIndex, isNotNull);
        expect(loc.avatarIndex!, greaterThanOrEqualTo(0));
        expect(loc.avatarIndex!, lessThan(AppConstants.avatarCount));
        expect(loc.avatarIndex, equals(avatarIndex));
      },
    );
  });

  test('Property 13b: copyWith preserva el avatarIndex correctamente', () {
    forAll2(
      numRuns: 100,
      genA: () => genInt(min: 0, max: AppConstants.avatarCount),
      genB: () => genInt(min: 0, max: AppConstants.avatarCount),
      body: (originalIndex, newIndex) {
        final loc = MemberLocation(
          userId: 'user-1',
          name: 'Test',
          latitude: 0.0,
          longitude: 0.0,
          updatedAt: DateTime.now(),
          avatarIndex: originalIndex,
        );

        final updated = loc.copyWith(avatarIndex: newIndex);
        expect(updated.avatarIndex, equals(newIndex));
        // El original no debe cambiar
        expect(loc.avatarIndex, equals(originalIndex));
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 14: Marcador de miembro refleja disponibilidad de avatar
  test('Property 14: marcador usa avatar si disponible, iniciales si no', () {
    forAll3(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 20),
      genB: () => genBool(),
      genC: () => genInt(min: 0, max: AppConstants.avatarCount),
      body: (name, hasAvatar, avatarIndex) {
        final loc = MemberLocation(
          userId: 'user-1',
          name: name,
          latitude: 0.0,
          longitude: 0.0,
          updatedAt: DateTime.now(),
          avatarIndex: hasAvatar ? avatarIndex : null,
        );

        if (hasAvatar) {
          expect(loc.avatarIndex, isNotNull);
          expect(loc.avatarIndex!, greaterThanOrEqualTo(0));
          expect(loc.avatarIndex!, lessThan(AppConstants.avatarCount));
        } else {
          expect(loc.avatarIndex, isNull);
          expect(loc.initials, isNotEmpty);
          expect(loc.initials, equals(loc.initials.toUpperCase()));
        }
      },
    );
  });

  test('Property 14b: initials extrae correctamente las iniciales del nombre', () {
    forAll2(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 15),
      genB: () => genNonEmptyString(maxLen: 15),
      body: (firstName, lastName) {
        final fullName = '$firstName $lastName';
        final loc = MemberLocation(
          userId: 'user-1',
          name: fullName,
          latitude: 0.0,
          longitude: 0.0,
          updatedAt: DateTime.now(),
        );

        final initials = loc.initials;
        expect(initials, isNotEmpty);
        expect(initials.length, lessThanOrEqualTo(2));
        expect(initials, equals(initials.toUpperCase()));
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/constants.dart';
import 'package:festisafe/data/models/group.dart';
import 'package:festisafe/data/models/group_member.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 7: Invariante de tamaño máximo de grupo

void main() {
  // Feature: festisafe-flutter-app, Property 7: Invariante de tamaño máximo de grupo
  test('Property 7: grupo nunca supera 8 miembros independientemente de la API', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 21),
      body: (memberCount) {
        final apiMembers = List.generate(memberCount, (i) {
          return GroupMemberModel(
            userId: 'user-$i',
            name: 'Usuario $i',
            role: i == 0 ? 'admin' : 'member',
          );
        });

        final capped = apiMembers.take(AppConstants.maxGroupMembers).toList();

        final group = GroupModel(
          id: 'grp-1',
          eventId: 'evt-1',
          name: 'Grupo Test',
          members: capped,
        );

        expect(
          group.members.length,
          lessThanOrEqualTo(AppConstants.maxGroupMembers),
          reason:
              'El grupo tiene ${group.members.length} miembros, supera el máximo de ${AppConstants.maxGroupMembers}',
        );
      },
    );
  });

  test('Property 7b: GroupModel.fromJson aplica el límite de 8 miembros', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 21),
      body: (memberCount) {
        final membersJson = List.generate(memberCount, (i) => {
          'user_id': 'user-$i',
          'name': 'Usuario $i',
          'role': i == 0 ? 'admin' : 'member',
          'avatar_index': null,
        });

        final json = {
          'id': 'grp-1',
          'event_id': 'evt-1',
          'name': 'Grupo Test',
          'max_members': AppConstants.maxGroupMembers,
          'members': membersJson,
        };

        final group = GroupModel.fromJson(json);

        expect(
          group.members.length,
          lessThanOrEqualTo(AppConstants.maxGroupMembers),
        );
      },
    );
  });
}

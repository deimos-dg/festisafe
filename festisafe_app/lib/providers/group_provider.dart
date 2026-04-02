import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';
import '../core/constants.dart';
import '../data/models/group.dart';
import '../data/services/group_service.dart';

class GroupState {
  final GroupModel? group;
  final bool isLoading;
  final String? error;

  const GroupState({this.group, this.isLoading = false, this.error});

  GroupState copyWith({GroupModel? group, bool? isLoading, String? error}) {
    return GroupState(
      group: group ?? this.group,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class GroupNotifier extends StateNotifier<GroupState> {
  final GroupService _service;

  GroupNotifier(this._service) : super(const GroupState());

  Future<void> createGroup(String eventId, String name) async {
    state = state.copyWith(isLoading: true);
    try {
      final group = await _service.createGroup(eventId, name);
      state = GroupState(group: group);
    } catch (e) {
      state = GroupState(error: e.toString());
    }
  }

  Future<void> loadMembers(String groupId) async {
    state = state.copyWith(isLoading: true);
    try {
      final members = await _service.getMembers(groupId);
      // Invariante: nunca mostrar más de MAX_GROUP_MEMBERS (Propiedad 7)
      final capped = members.take(AppConstants.maxGroupMembers).toList();
      if (state.group != null) {
        final updated = GroupModel(
          id: state.group!.id,
          eventId: state.group!.eventId,
          name: state.group!.name,
          members: capped,
        );
        state = GroupState(group: updated);
      }
    } catch (e) {
      state = GroupState(error: e.toString());
    }
  }

  Future<void> transferAdmin(String groupId, String newAdminId) async {
    await _service.transferAdmin(groupId, newAdminId);
    await loadMembers(groupId);
  }

  Future<void> leaveGroup(String groupId) async {
    await _service.leaveGroup(groupId);
    state = const GroupState();
  }

  Future<void> deleteGroup(String groupId) async {
    await _service.deleteGroup(groupId);
    state = const GroupState();
  }

  void setGroup(GroupModel group) {
    state = GroupState(group: group);
  }

  void clear() => state = const GroupState();
}

final groupProvider = StateNotifierProvider<GroupNotifier, GroupState>(
  (ref) => GroupNotifier(GroupService()),
);

import '../../core/constants.dart';
import 'group_member.dart';

/// Modelo de grupo dentro de un evento.
class GroupModel {
  final String id;
  final String eventId;
  final String name;
  final int maxMembers;
  final List<GroupMemberModel> members;

  const GroupModel({
    required this.id,
    required this.eventId,
    required this.name,
    this.maxMembers = AppConstants.maxGroupMembers,
    this.members = const [],
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      name: json['name'] as String,
      maxMembers: json['max_members'] as int? ?? AppConstants.maxGroupMembers,
      members: (json['members'] as List<dynamic>?)
              ?.map((m) => GroupMemberModel.fromJson(m as Map<String, dynamic>))
              .take(AppConstants.maxGroupMembers) // invariante: nunca > 8
              .toList() ??
          [],
    );
  }

  bool get isFull => members.length >= maxMembers;
}

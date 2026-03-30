import '../models/group.dart';
import '../models/group_member.dart';
import 'api_client.dart';

/// Servicio de grupos: creación, miembros y administración.
class GroupService {
  final ApiClient _client;

  GroupService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<GroupModel> createGroup(String eventId, String name) async {
    final response = await _client.dio.post(
      '/groups/',
      data: {'event_id': eventId, 'name': name},
    );
    // El backend devuelve {"message": ..., "group_id": "..."}
    final groupId = response.data['group_id'] as String;
    // Cargar el grupo completo
    final detail = await _client.dio.get('/groups/$groupId');
    final data = detail.data as Map<String, dynamic>;
    return GroupModel(
      id: data['group_id'] as String,
      eventId: data['event_id'] as String,
      name: data['name'] as String,
      maxMembers: data['max_members'] as int? ?? 8,
    );
  }

  Future<List<GroupMemberModel>> getMembers(String groupId) async {
    final response = await _client.dio.get('/groups/$groupId/members');
    final data = response.data as Map<String, dynamic>;
    // El endpoint devuelve {"group_id": ..., "members": [...]}
    final list = data['members'] as List<dynamic>? ?? [];
    return list
        .map((e) => GroupMemberModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> transferAdmin(String groupId, String newAdminUserId) async {
    await _client.dio.post(
      '/groups/$groupId/transfer-admin',
      queryParameters: {'new_admin_user_id': newAdminUserId},
    );
  }

  Future<void> leaveGroup(String groupId) async {
    await _client.dio.post('/groups/$groupId/leave');
  }

  Future<void> addMember(String groupId, String userId) async {
    await _client.dio.post('/group-members/add/$groupId', queryParameters: {'user_id': userId});
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _client.dio.delete('/group-members/remove/$groupId/$userId');
  }

  Future<void> deleteGroup(String groupId) async {
    await _client.dio.delete('/groups/$groupId');
  }
}

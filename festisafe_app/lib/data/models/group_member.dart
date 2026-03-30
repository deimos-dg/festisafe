/// Miembro de un grupo.
class GroupMemberModel {
  final String userId;
  final String name;

  /// "admin" | "member"
  final String role;

  /// Índice del avatar (0-11). null = mostrar iniciales.
  final int? avatarIndex;

  const GroupMemberModel({
    required this.userId,
    required this.name,
    required this.role,
    this.avatarIndex,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      userId: json['user_id'] as String,
      name: json['name'] as String,
      role: json['role'] as String? ?? 'member',
      avatarIndex: json['avatar_index'] as int?,
    );
  }

  bool get isAdmin => role == 'admin';

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

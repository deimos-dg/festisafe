/// Modelo de usuario autenticado.
class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phone;

  /// Rol: "user" | "organizer" | "admin"
  final String role;

  /// true si la cuenta fue creada automáticamente al canjear un Guest_Code.
  final bool isGuest;

  /// Índice del avatar seleccionado (0-11). null = mostrar iniciales.
  final int? avatarIndex;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.role = 'user',
    this.isGuest = false,
    this.avatarIndex,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'user',
      isGuest: json['is_guest'] as bool? ?? false,
      avatarIndex: json['avatar_index'] as int?,
    );
  }

  UserModel copyWith({
    String? name,
    String? phone,
    int? avatarIndex,
    bool clearAvatar = false,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      role: role,
      isGuest: isGuest,
      avatarIndex: clearAvatar ? null : (avatarIndex ?? this.avatarIndex),
    );
  }

  bool get isOrganizer => role == 'organizer' || role == 'admin';

  /// Iniciales para el marcador del mapa cuando no hay avatar.
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

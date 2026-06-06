/// Alerta SOS activa de un miembro del grupo.
class SosAlert {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final DateTime activatedAt;
  final bool isEscalated;
  final bool isActive;

  const SosAlert({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.activatedAt,
    this.isEscalated = false,
    this.isActive = true,
  });

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      userId: json['user_id'] as String? ?? '',
      userName: json['name'] as String? ?? 'Desconocido',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      batteryLevel: json['battery_level'] as int? ?? 0,
      activatedAt: json['activated_at'] != null
          ? DateTime.parse(json['activated_at'] as String)
          : (json['started_at'] != null
              ? DateTime.parse(json['started_at'] as String)
              : DateTime.now()),
      isEscalated: json['sos_escalated'] as bool? ?? json['is_escalated'] as bool? ?? false,
      isActive: json['sos_active'] as bool? ?? true,
    );
  }

  factory SosAlert.fromWsMessage(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      throw ArgumentError('Campo user_id faltante en payload WS SOS');
    }
    return SosAlert(
      userId: userId,
      userName: payload['name'] as String? ?? 'Desconocido',
      latitude: (payload['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (payload['longitude'] as num?)?.toDouble() ?? 0.0,
      batteryLevel: payload['battery_level'] as int? ?? 0,
      activatedAt: DateTime.now(),
      isEscalated: payload['is_escalated'] as bool? ?? false,
      isActive: true,
    );
  }

  SosAlert copyWith({bool? isEscalated, bool? isActive}) {
    return SosAlert(
      userId: userId,
      userName: userName,
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel,
      activatedAt: activatedAt,
      isEscalated: isEscalated ?? this.isEscalated,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Alerta SOS activa de un miembro del grupo.
class SosAlert {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final DateTime activatedAt;
  final bool isEscalated;

  const SosAlert({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.activatedAt,
    this.isEscalated = false,
  });

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      userId: json['user_id'] as String,
      userName: json['name'] as String? ?? 'Desconocido',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      batteryLevel: json['battery_level'] as int? ?? 0,
      activatedAt: json['activated_at'] != null
          ? DateTime.parse(json['activated_at'] as String)
          : DateTime.now(),
      isEscalated: json['is_escalated'] as bool? ?? false,
    );
  }

  factory SosAlert.fromWsMessage(Map<String, dynamic> payload) {
    return SosAlert(
      userId: payload['user_id'] as String,
      userName: payload['name'] as String? ?? 'Desconocido',
      latitude: (payload['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (payload['longitude'] as num?)?.toDouble() ?? 0.0,
      batteryLevel: payload['battery_level'] as int? ?? 0,
      activatedAt: DateTime.now(),
    );
  }

  SosAlert copyWith({bool? isEscalated}) {
    return SosAlert(
      userId: userId,
      userName: userName,
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel,
      activatedAt: activatedAt,
      isEscalated: isEscalated ?? this.isEscalated,
    );
  }
}

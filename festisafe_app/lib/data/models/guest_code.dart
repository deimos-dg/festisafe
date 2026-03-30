/// Código de invitado generado por un organizador.
class GuestCodeModel {
  final String code;
  final DateTime expiresAt;
  final int remainingUses;
  final String eventId;

  const GuestCodeModel({
    required this.code,
    required this.expiresAt,
    required this.remainingUses,
    required this.eventId,
  });

  factory GuestCodeModel.fromJson(Map<String, dynamic> json) {
    return GuestCodeModel(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      remainingUses: json['remaining_uses'] as int,
      eventId: json['event_id'] as String,
    );
  }

  bool get isExpired => expiresAt.isBefore(DateTime.now());
}

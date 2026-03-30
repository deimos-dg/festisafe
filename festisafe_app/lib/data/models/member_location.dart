import '../../core/constants.dart';

/// Estado visual del marcador de un miembro en el mapa.
enum MarkerState { normal, dimmed, noSignal }

/// Última ubicación conocida de un miembro del grupo.
class MemberLocation {
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final int? avatarIndex;

  const MemberLocation({
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.avatarIndex,
  });

  factory MemberLocation.fromWsMessage(Map<String, dynamic> payload) {
    return MemberLocation(
      userId: payload['user_id'] as String,
      name: payload['name'] as String,
      latitude: (payload['latitude'] as num).toDouble(),
      longitude: (payload['longitude'] as num).toDouble(),
      updatedAt: DateTime.now(),
      avatarIndex: payload['avatar_index'] as int?,
    );
  }

  MemberLocation copyWith({int? avatarIndex}) {
    return MemberLocation(
      userId: userId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      updatedAt: updatedAt,
      avatarIndex: avatarIndex ?? this.avatarIndex,
    );
  }

  /// Calcula el estado visual según el tiempo transcurrido desde la última actualización.
  MarkerState get markerState {
    final minutes = DateTime.now().difference(updatedAt).inMinutes;
    if (minutes >= AppConstants.markerNoSignalMinutes) return MarkerState.noSignal;
    if (minutes >= AppConstants.markerDimMinutes) return MarkerState.dimmed;
    return MarkerState.normal;
  }

  String get initials {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }
}

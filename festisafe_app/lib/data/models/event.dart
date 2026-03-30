/// Modelo de evento de festival.
class EventModel {
  final String id;
  final String name;
  final String? description;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime startDate;
  final DateTime endDate;
  final int maxParticipants;
  final bool isActive;
  final double? meetingPointLat;
  final double? meetingPointLng;
  final String? meetingPointName;

  const EventModel({
    required this.id,
    required this.name,
    this.description,
    this.locationName,
    this.latitude,
    this.longitude,
    required this.startDate,
    required this.endDate,
    required this.maxParticipants,
    required this.isActive,
    this.meetingPointLat,
    this.meetingPointLng,
    this.meetingPointName,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      locationName: json['location_name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      startDate: DateTime.parse(json['starts_at'] as String),
      endDate: DateTime.parse(json['ends_at'] as String),
      maxParticipants: json['max_participants'] as int? ?? 8,
      isActive: json['is_active'] as bool? ?? false,
      meetingPointLat: (json['meeting_point_lat'] as num?)?.toDouble(),
      meetingPointLng: (json['meeting_point_lng'] as num?)?.toDouble(),
      meetingPointName: json['meeting_point_name'] as String?,
    );
  }

  bool get hasMeetingPoint => meetingPointLat != null && meetingPointLng != null;
}

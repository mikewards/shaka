/// Model for a saved/favorited dive spot
class SavedSpot {
  final String spotId;
  final String name;
  final double lat;
  final double lon;
  final String access;
  final String region;
  final DateTime savedAt;

  const SavedSpot({
    required this.spotId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.access,
    required this.region,
    required this.savedAt,
  });

  factory SavedSpot.fromJson(Map<String, dynamic> json) {
    return SavedSpot(
      spotId: json['spotId'] ?? '',
      name: json['name'] ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      access: json['access'] ?? 'shore',
      region: json['region'] ?? '',
      savedAt: json['savedAt'] != null 
          ? DateTime.parse(json['savedAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'spotId': spotId,
    'name': name,
    'lat': lat,
    'lon': lon,
    'access': access,
    'region': region,
    'savedAt': savedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSpot &&
          runtimeType == other.runtimeType &&
          spotId == other.spotId;

  @override
  int get hashCode => spotId.hashCode;
}

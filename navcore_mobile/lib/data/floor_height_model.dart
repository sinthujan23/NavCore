/// Floor Height record data class representing height between consecutive floors
class FloorHeightData {
  final String mallId;
  final int floorNo;
  final double heightToNextM;
  final double baseAltitudeM;
  final String source; // 'admin' | 'barometer' | 'osm' | 'default'
  final double confidence; // 0.0 to 1.0
  final bool isLocked;
  final String updatedAt;

  const FloorHeightData({
    required this.mallId,
    required this.floorNo,
    required this.heightToNextM,
    required this.baseAltitudeM,
    required this.source,
    required this.confidence,
    this.isLocked = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'mall_id': mallId,
        'floor_no': floorNo,
        'height_to_next_m': heightToNextM,
        'base_altitude_m': baseAltitudeM,
        'source': source,
        'confidence': confidence,
        'is_locked': isLocked ? 1 : 0,
        'updated_at': updatedAt,
      };

  factory FloorHeightData.fromJson(Map<String, dynamic> json) {
    return FloorHeightData(
      mallId: json['mall_id'] ?? 'mall-one-galle-face',
      floorNo: (json['floor_no'] as num).toInt(),
      heightToNextM: (json['height_to_next_m'] as num).toDouble(),
      baseAltitudeM: (json['base_altitude_m'] as num).toDouble(),
      source: json['source'] ?? 'default',
      confidence: (json['confidence'] as num).toDouble(),
      isLocked: (json['is_locked'] == 1 || json['is_locked'] == true),
      updatedAt: json['updated_at'] ?? DateTime.now().toIso8601String(),
    );
  }

  FloorHeightData copyWith({
    String? mallId,
    int? floorNo,
    double? heightToNextM,
    double? baseAltitudeM,
    String? source,
    double? confidence,
    bool? isLocked,
    String? updatedAt,
  }) {
    return FloorHeightData(
      mallId: mallId ?? this.mallId,
      floorNo: floorNo ?? this.floorNo,
      heightToNextM: heightToNextM ?? this.heightToNextM,
      baseAltitudeM: baseAltitudeM ?? this.baseAltitudeM,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      isLocked: isLocked ?? this.isLocked,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

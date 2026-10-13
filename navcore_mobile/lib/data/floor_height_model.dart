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
        'mallId': mallId,
        'mall_id': mallId,
        'floorNo': floorNo,
        'floor_no': floorNo,
        'heightToNextM': heightToNextM,
        'height_to_next_m': heightToNextM,
        'baseAltitudeM': baseAltitudeM,
        'base_altitude_m': baseAltitudeM,
        'source': source,
        'confidence': confidence,
        'isLocked': isLocked,
        'is_locked': isLocked ? 1 : 0,
        'updatedAt': updatedAt,
        'updated_at': updatedAt,
      };

  factory FloorHeightData.fromJson(Map<String, dynamic> json) {
    num? parseNum(dynamic val) {
      if (val is num) return val;
      if (val is String) return num.tryParse(val);
      return null;
    }

    final fn = parseNum(json['floorNo'] ?? json['floor_no'])?.toInt() ?? 1;
    final hNext = parseNum(json['heightToNextM'] ?? json['height_to_next_m'])?.toDouble() ?? 4.5;
    final bAlt = parseNum(json['baseAltitudeM'] ?? json['base_altitude_m'])?.toDouble() ?? 0.0;
    final conf = parseNum(json['confidence'])?.toDouble() ?? 1.0;
    final locked = (json['isLocked'] == true || json['is_locked'] == 1 || json['is_locked'] == true);

    return FloorHeightData(
      mallId: (json['mallId'] ?? json['mall_id'] ?? '').toString(),
      floorNo: fn,
      heightToNextM: hNext,
      baseAltitudeM: bAlt,
      source: (json['source'] ?? 'default').toString(),
      confidence: conf,
      isLocked: locked,
      updatedAt: (json['updatedAt'] ?? json['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
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

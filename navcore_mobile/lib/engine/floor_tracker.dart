/// NexNav Geodetic Elevation Engine & Floor Level Manager in Dart
/// Implements Section 4 of NexNav Technical Spec
library;

class FloorLevelConfig {
  final String floorId;
  final int floorNumber;
  final String name;
  final double relativeVectorMeters;
  final double absoluteHeightMeters;
  final double bandMinMeters;
  final double bandMaxMeters;
  final int storesCount;
  final double floorWidthMeters;
  final double floorLengthMeters;
  final double ceilingHeightMeters;
  final int osmLevel;
  final double osmHeightMeters;

  const FloorLevelConfig({
    required this.floorId,
    required this.floorNumber,
    required this.name,
    required this.relativeVectorMeters,
    required this.absoluteHeightMeters,
    required this.bandMinMeters,
    required this.bandMaxMeters,
    required this.storesCount,
    this.floorWidthMeters = 120.0,
    this.floorLengthMeters = 85.0,
    this.ceilingHeightMeters = 4.5,
    int? osmLevel,
    double? osmHeightMeters,
  })  : osmLevel = osmLevel ?? floorNumber,
        osmHeightMeters = osmHeightMeters ?? relativeVectorMeters;

  /// Real-world floor surface area in square meters (m²)
  double get floorAreaSqMeters => floorWidthMeters * floorLengthMeters;

  /// Real-world floor perimeter in meters (m)
  double get perimeterMeters => 2 * (floorWidthMeters + floorLengthMeters);

  /// Height difference relative to another target floor
  double heightDeltaTo(FloorLevelConfig other) {
    return absoluteHeightMeters - other.absoluteHeightMeters;
  }

  /// Evaluates whether a barometric altitude reading falls within this floor's band
  bool isAltitudeWithinBand(double altitudeMeters) {
    return altitudeMeters >= bandMinMeters && altitudeMeters < bandMaxMeters;
  }
}

class BuildingElevationProfile {
  final String buildingId;
  final String name;
  final double entranceBaseAnchorHeight;
  final double floorGapMeters;
  final List<FloorLevelConfig> floors;

  const BuildingElevationProfile({
    required this.buildingId,
    required this.name,
    required this.entranceBaseAnchorHeight,
    required this.floorGapMeters,
    required this.floors,
  });
}

/// Default Unconfigured Reference Building Specification
final defaultBuildingProfile = BuildingElevationProfile(
  buildingId: '',
  name: '',
  entranceBaseAnchorHeight: 0.0,
  floorGapMeters: 4.5,
  floors: const [],
);

/// Automatically computes floor level matching absolute height
FloorLevelConfig resolveFloorByHeight(
  double currentHeightMeters, [
  BuildingElevationProfile? profile,
]) {
  final targetProfile = profile ?? defaultBuildingProfile;

  for (final floor in targetProfile.floors) {
    if (currentHeightMeters >= floor.bandMinMeters &&
        currentHeightMeters < floor.bandMaxMeters) {
      return floor;
    }
  }

  // Safe fallback to Ground Floor (floorNumber == 1) for outdoor / uncalibrated altitude
  return targetProfile.floors.firstWhere(
    (f) => f.floorNumber == 1,
    orElse: () => targetProfile.floors.isNotEmpty
        ? targetProfile.floors.first
        : const FloorLevelConfig(
            floorId: 'fl-1',
            floorNumber: 1,
            name: 'Level 1',
            relativeVectorMeters: 0.0,
            absoluteHeightMeters: 0.0,
            bandMinMeters: -5.0,
            bandMaxMeters: 5.0,
            storesCount: 0,
          ),
  );
}

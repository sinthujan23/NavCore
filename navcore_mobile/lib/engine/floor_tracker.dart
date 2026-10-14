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
  }) : osmLevel = osmLevel ?? floorNumber,
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
  floorGapMeters: 0.0,
  floors: const [],
);

/// Automatically computes floor level matching absolute or relative height dynamically
FloorLevelConfig resolveFloorByHeight(
  double currentHeightMeters, [
  BuildingElevationProfile? profile,
]) {
  final targetProfile = profile ?? defaultBuildingProfile;
  if (targetProfile.floors.isEmpty) {
    return const FloorLevelConfig(
      floorId: 'fl-1',
      floorNumber: 1,
      name: 'Level 1',
      relativeVectorMeters: 0.0,
      absoluteHeightMeters: 0.0,
      bandMinMeters: -5.0,
      bandMaxMeters: 5.0,
      storesCount: 0,
    );
  }

  // 1. Direct band matching
  for (final floor in targetProfile.floors) {
    if (currentHeightMeters >= floor.bandMinMeters &&
        currentHeightMeters < floor.bandMaxMeters) {
      return floor;
    }
  }

  // 2. Relative elevation matching (in case currentHeightMeters is ground-relative [0, gap, 2*gap...])
  final baseAnchor = targetProfile.entranceBaseAnchorHeight;
  if (baseAnchor > 0) {
    final absoluteEquivalent = currentHeightMeters + baseAnchor;
    for (final floor in targetProfile.floors) {
      if (absoluteEquivalent >= floor.bandMinMeters &&
          absoluteEquivalent < floor.bandMaxMeters) {
        return floor;
      }
    }
  }

  // 3. Nearest floor calculation by absolute or relative proximity (eliminates fallback to first floor)
  FloorLevelConfig? nearestFloor;
  double minDelta = double.infinity;

  for (final floor in targetProfile.floors) {
    final absDelta = (floor.absoluteHeightMeters - currentHeightMeters).abs();
    if (absDelta < minDelta) {
      minDelta = absDelta;
      nearestFloor = floor;
    }

    if (baseAnchor > 0) {
      final relDelta = (floor.relativeVectorMeters - currentHeightMeters).abs();
      if (relDelta < minDelta) {
        minDelta = relDelta;
        nearestFloor = floor;
      }
    }
  }

  if (nearestFloor != null) {
    return nearestFloor;
  }

  return targetProfile.floors.first;
}

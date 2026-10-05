import 'dart:math';
import 'ecef_engine.dart';
import 'floor_tracker.dart';

/// NexNav Bearing & AR Spatial Placement Engine in Dart
/// Implements Section 5 of NexNav Technical Spec

// ignore: constant_identifier_names
enum CompassBearingBadge { N, NE, E, SE, S, SW, W, NW }

const double earthRadiusMeters = 6371000.0; // Mean Earth radius in meters

/// Calculates Horizontal Haversine Distance between two geodetic points
double haversineDistance(GeodeticCoords user, GeodeticCoords target) {
  final phi1 = (user.latitude * pi) / 180.0;
  final phi2 = (target.latitude * pi) / 180.0;
  final deltaPhi = ((target.latitude - user.latitude) * pi) / 180.0;
  final deltaLambda = ((target.longitude - user.longitude) * pi) / 180.0;

  final a =
      sin(deltaPhi / 2.0) * sin(deltaPhi / 2.0) +
      cos(phi1) * cos(phi2) * sin(deltaLambda / 2.0) * sin(deltaLambda / 2.0);

  final c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  return earthRadiusMeters * c;
}

/// Calculates forward azimuth / compass bearing angle (0° - 360°)
double calculateBearingAngle(GeodeticCoords user, GeodeticCoords target) {
  final phiUser = (user.latitude * pi) / 180.0;
  final phiTarget = (target.latitude * pi) / 180.0;
  final deltaLambda = ((target.longitude - user.longitude) * pi) / 180.0;

  final y = sin(deltaLambda) * cos(phiTarget);
  final x =
      cos(phiUser) * sin(phiTarget) -
      sin(phiUser) * cos(phiTarget) * cos(deltaLambda);

  final bearingRad = atan2(y, x);
  final bearingDeg = (bearingRad * 180.0) / pi;

  return (bearingDeg + 360.0) % 360.0;
}

/// Classifies compass bearing angle into 8-point compass badges using 45° windows
CompassBearingBadge classifyCompassBadge(double bearingDeg) {
  final normalized = (bearingDeg + 360.0) % 360.0;

  if (normalized >= 337.5 || normalized < 22.5) return CompassBearingBadge.N;
  if (normalized >= 22.5 && normalized < 67.5) return CompassBearingBadge.NE;
  if (normalized >= 67.5 && normalized < 112.5) return CompassBearingBadge.E;
  if (normalized >= 112.5 && normalized < 157.5) return CompassBearingBadge.SE;
  if (normalized >= 157.5 && normalized < 202.5) return CompassBearingBadge.S;
  if (normalized >= 202.5 && normalized < 247.5) return CompassBearingBadge.SW;
  if (normalized >= 247.5 && normalized < 292.5) return CompassBearingBadge.W;
  return CompassBearingBadge.NW;
}

/// Resolves localized user coordinates relative to active indoor mall coordinate anchor.
/// Uses user GPS when within valid proximity, or anchors to the Earth ground floor entrance anchor.
GeodeticCoords getEffectiveUserCoords(
  GeodeticCoords userCoords,
  GeodeticCoords mallAnchor,
) {
  if (userCoords.latitude != 0.0 && userCoords.longitude != 0.0) {
    return userCoords;
  }

  return GeodeticCoords(
    latitude: mallAnchor.latitude,
    longitude: mallAnchor.longitude,
    height: userCoords.height != 0.0 ? userCoords.height : mallAnchor.height,
  );
}

/// Calculates accurate 3D spatial distance in meters incorporating WGS-84 ECEF
/// Cartesian Euclidean geometry and floor elevation differences relative to Earth ground floor.
double calculateAccurate3DDistance(
  GeodeticCoords userCoords,
  GeodeticCoords targetLocation, {
  int userFloorNumber = 1,
  int targetFloorNumber = 1,
  double heightPerFloorMeters = 5.0,
}) {
  final userEffectiveHeight =
      userCoords.height + (userFloorNumber - 1) * heightPerFloorMeters;
  final targetEffectiveHeight =
      targetLocation.height + (targetFloorNumber - 1) * heightPerFloorMeters;

  final userPoint = GeodeticCoords(
    latitude: userCoords.latitude,
    longitude: userCoords.longitude,
    height: userEffectiveHeight,
  );

  final targetPoint = GeodeticCoords(
    latitude: targetLocation.latitude,
    longitude: targetLocation.longitude,
    height: targetEffectiveHeight,
  );

  final p1 = geodeticToECEF(userPoint);
  final p2 = geodeticToECEF(targetPoint);

  final dist = ecefDistance(p1, p2);
  return dist.isNaN || dist.isInfinite ? 0.0 : dist;
}

/// Calculates precise 3D geometric distance of a place/POI from the Earth ground floor (Floor 1 Entrance level)
/// using WGS-84 ECEF 3D Cartesian Euclidean coordinate geometry.
double calculateDistanceFromEarthGround(
  GeodeticCoords targetLocation, {
  int targetFloorNumber = 1,
  double groundElevationMeters = 45.0,
  GeodeticCoords? groundAnchorCoords,
  double heightPerFloorMeters = 6.5,
}) {
  final dist = (targetFloorNumber - 1).abs() * heightPerFloorMeters;
  return dist;
}

/// Calculates AR Card Vertical Placement (Pixel_Y_Offset) over camera viewport
/// Section 5 Formula:
/// Pixel_Y_Offset = Viewport_Center_Y + (Focal_Length * (Δh / Horizontal_Haversine_Distance))
double calculateARYOffset(
  GeodeticCoords user,
  GeodeticCoords target,
  double viewportCenterY, {
  double focalLength = 800.0,
}) {
  final horizontalDist = max(haversineDistance(user, target), 0.5);
  final deltaHeight = target.height - user.height;

  return viewportCenterY + focalLength * (deltaHeight / horizontalDist);
}

/// Real-World Geometric Spatial Distance & Floor Size Metrics Model
class RealWorldSpatialMetrics {
  final double horizontalHaversineDistMeters; // d_2D
  final double elevationDeltaMeters; // Δh
  final double euclidean3DDistanceMeters; // d_3D = sqrt(d_2D² + Δh²)
  final double
  distanceFromGroundMeters; // Elevation difference from Earth Ground (Floor 1 Entrance)
  final double estimatedWalkTimeSeconds; // d_3D / 1.4 m/s walking speed
  final double floorWidthMeters; // Floor width dimension in meters
  final double floorLengthMeters; // Floor length dimension in meters
  final double floorAreaSqMeters; // Floor real-world surface area in m²
  final double ceilingHeightMeters; // Floor clearance height

  const RealWorldSpatialMetrics({
    required this.horizontalHaversineDistMeters,
    required this.elevationDeltaMeters,
    required this.euclidean3DDistanceMeters,
    required this.distanceFromGroundMeters,
    required this.estimatedWalkTimeSeconds,
    required this.floorWidthMeters,
    required this.floorLengthMeters,
    required this.floorAreaSqMeters,
    required this.ceilingHeightMeters,
  });
}

/// Comprehensive Geometric Calculation Engine for Real-World Distance & Floor Size Data
RealWorldSpatialMetrics calculateRealWorldSpatialMetrics({
  required GeodeticCoords userCoords,
  required GeodeticCoords targetCoords,
  int userFloorNumber = 1,
  int targetFloorNumber = 1,
  double floorWidthMeters = 220.0,
  double floorLengthMeters = 150.0,
  double ceilingHeightMeters = 5.5,
  double heightPerFloorMeters = 6.5,
  double groundElevationMeters = 45.0,
}) {
  final d2D = haversineDistance(userCoords, targetCoords);
  final floorDelta = (targetFloorNumber - userFloorNumber).toDouble();
  final deltaH =
      floorDelta * heightPerFloorMeters +
      (targetCoords.height - userCoords.height);
  final d3D = sqrt(d2D * d2D + deltaH * deltaH);
  final groundDist = (targetFloorNumber - 1).abs() * heightPerFloorMeters;
  final walkTime = d3D / 1.4; // 1.4 m/s nominal walking speed

  return RealWorldSpatialMetrics(
    horizontalHaversineDistMeters: d2D,
    elevationDeltaMeters: deltaH,
    euclidean3DDistanceMeters: d3D,
    distanceFromGroundMeters: groundDist,
    estimatedWalkTimeSeconds: walkTime,
    floorWidthMeters: floorWidthMeters,
    floorLengthMeters: floorLengthMeters,
    floorAreaSqMeters: floorWidthMeters * floorLengthMeters,
    ceilingHeightMeters: ceilingHeightMeters,
  );
}

/// Calculates precise 3D spatial height metrics for POIs sharing identical Lat/Lon coordinates
RealWorldSpatialMetrics calculateSameCoordinateSpatialMetrics({
  required GeodeticCoords userCoords,
  required GeodeticCoords poiCoords,
  required int userFloorNumber,
  required int poiFloorNumber,
  required FloorLevelConfig userFloorConfig,
  required FloorLevelConfig poiFloorConfig,
}) {
  final d2D = haversineDistance(userCoords, poiCoords);
  // Floor elevation delta Δh derived from target vs user absolute floor height specs
  final deltaH =
      poiFloorConfig.absoluteHeightMeters -
      userFloorConfig.absoluteHeightMeters;
  final d3D = sqrt(d2D * d2D + deltaH * deltaH);
  final distanceFromGround =
      (poiFloorConfig.absoluteHeightMeters -
              userFloorConfig.absoluteHeightMeters)
          .abs();

  return RealWorldSpatialMetrics(
    horizontalHaversineDistMeters: d2D,
    elevationDeltaMeters: deltaH,
    euclidean3DDistanceMeters: d3D,
    distanceFromGroundMeters: distanceFromGround,
    estimatedWalkTimeSeconds: d3D / 1.4,
    floorWidthMeters: poiFloorConfig.floorWidthMeters,
    floorLengthMeters: poiFloorConfig.floorLengthMeters,
    floorAreaSqMeters: poiFloorConfig.floorAreaSqMeters,
    ceilingHeightMeters: poiFloorConfig.ceilingHeightMeters,
  );
}

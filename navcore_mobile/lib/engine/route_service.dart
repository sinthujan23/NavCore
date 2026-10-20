import 'dart:math' as math;
import 'ecef_engine.dart';
import 'bearing_engine.dart';
import '../data/destinations.dart';

enum WaypointType {
  entrance,
  corridor,
  elevator,
  escalator,
  stairs,
  destination,
}

class WaypointNode {
  final String id;
  final String buildingId;
  final int floorNumber;
  final GeodeticCoords coords;
  final double localX;
  final double localY;
  final double localZ;
  final WaypointType type;
  final String instruction;
  final String? nextWaypointId;

  const WaypointNode({
    required this.id,
    required this.buildingId,
    required this.floorNumber,
    required this.coords,
    required this.localX,
    required this.localY,
    required this.localZ,
    required this.type,
    required this.instruction,
    this.nextWaypointId,
  });
}

class RoutePath {
  final String routeId;
  final String buildingId;
  final DestinationPOI startPOI;
  final DestinationPOI destinationPOI;
  final List<WaypointNode> waypoints;
  final double totalDistanceMeters;
  final int estimatedTimemilliseconds;
  final bool requiresFloorChange;

  const RoutePath({
    required this.routeId,
    required this.buildingId,
    required this.startPOI,
    required this.destinationPOI,
    required this.waypoints,
    required this.totalDistanceMeters,
    required this.estimatedTimemilliseconds,
    required this.requiresFloorChange,
  });
}

class RouteService {
  /// Generate indoor route from user location / start node to destination POI
  RoutePath calculateRoute({
    required String buildingId,
    required GeodeticCoords userCoords,
    required int currentFloor,
    required DestinationPOI destination,
  }) {
    final List<WaypointNode> nodes = [];
    final bool floorChange = currentFloor != destination.floorNumber;
    double accumulatedDistance = 0.0;

    // Node 1: Start Location
    nodes.add(
      WaypointNode(
        id: 'wp-0',
        buildingId: buildingId,
        floorNumber: currentFloor,
        coords: userCoords,
        localX: 0.0,
        localY: 0.0,
        localZ: (currentFloor - 1) * 4.5,
        type: WaypointType.corridor,
        instruction: 'Start walking down main corridor',
        nextWaypointId: floorChange ? 'wp-transition' : 'wp-dest',
      ),
    );

    // Node 2: Vertical Transition (if multi-floor navigation required)
    if (floorChange) {
      final transitionType = (destination.floorNumber > currentFloor)
          ? WaypointType.escalator
          : WaypointType.elevator;

      final transitionText = (transitionType == WaypointType.escalator)
          ? 'Take Escalator UP to Floor ${destination.floorNumber}'
          : 'Take Elevator to Floor ${destination.floorNumber}';

      // Intermediate corridor waypoint toward floor transition zone
      final latDelta = destination.location.latitude - userCoords.latitude;
      final lonDelta = destination.location.longitude - userCoords.longitude;

      nodes.add(
        WaypointNode(
          id: 'wp-1',
          buildingId: buildingId,
          floorNumber: currentFloor,
          coords: GeodeticCoords(
            latitude: userCoords.latitude + latDelta * 0.35,
            longitude: userCoords.longitude + lonDelta * 0.35,
            height: userCoords.height,
          ),
          localX: 15.0,
          localY: 10.0,
          localZ: (currentFloor - 1) * 4.5,
          type: WaypointType.corridor,
          instruction: 'Approach floor transition zone',
          nextWaypointId: 'wp-transition',
        ),
      );

      nodes.add(
        WaypointNode(
          id: 'wp-transition',
          buildingId: buildingId,
          floorNumber: currentFloor,
          coords: GeodeticCoords(
            latitude: userCoords.latitude + latDelta * 0.50,
            longitude: userCoords.longitude + lonDelta * 0.50,
            height: userCoords.height,
          ),
          localX: 20.0,
          localY: 15.0,
          localZ: (currentFloor - 1) * 4.5,
          type: transitionType,
          instruction: transitionText,
          nextWaypointId: 'wp-dest',
        ),
      );
    }

    // Final Node: Destination POI
    nodes.add(
      WaypointNode(
        id: 'wp-dest',
        buildingId: buildingId,
        floorNumber: destination.floorNumber,
        coords: destination.location,
        localX: 35.0,
        localY: 25.0,
        localZ: (destination.floorNumber - 1) * 4.5,
        type: WaypointType.destination,
        instruction: 'Arrive at ${destination.name}',
      ),
    );

    // Calculate total route distance incorporating 3D floor height differences
    for (int i = 0; i < nodes.length - 1; i++) {
      accumulatedDistance += calculateAccurate3DDistance(
        nodes[i].coords,
        nodes[i + 1].coords,
        userFloorNumber: nodes[i].floorNumber,
        targetFloorNumber: nodes[i + 1].floorNumber,
      );
    }
    if (accumulatedDistance < 10.0) {
      accumulatedDistance = calculateAccurate3DDistance(
        userCoords,
        destination.location,
        userFloorNumber: currentFloor,
        targetFloorNumber: destination.floorNumber,
      );
    }

    // Estimate walking speed at 1.2 m/s
    final estmilliseconds = math.max(10, (accumulatedDistance / 1.2).round());

    return RoutePath(
      routeId: 'route-${DateTime.now().millisecondsSinceEpoch}',
      buildingId: buildingId,
      startPOI: DestinationPOI(
        id: 'user-start',
        name: 'Current Location',
        category: 'USER',
        floorNumber: currentFloor,
        rating: 5.0,
        location: userCoords,
        description: 'User current position',
        openStatus: 'ACTIVE',
      ),
      destinationPOI: destination,
      waypoints: nodes,
      totalDistanceMeters: accumulatedDistance,
      estimatedTimemilliseconds: estmilliseconds,
      requiresFloorChange: floorChange,
    );
  }

  /// Calculates turn-by-turn guidance direction from relative bearing angle
  String getTurnGuidanceText(double relativeBearingDeg) {
    if (relativeBearingDeg >= -15.0 && relativeBearingDeg <= 15.0) {
      return 'Continue Straight';
    } else if (relativeBearingDeg > 15.0 && relativeBearingDeg <= 60.0) {
      return 'Turn Slightly Right';
    } else if (relativeBearingDeg > 60.0 && relativeBearingDeg <= 120.0) {
      return 'Turn Right';
    } else if (relativeBearingDeg > 120.0 && relativeBearingDeg <= 165.0) {
      return 'Turn Sharp Right';
    } else if (relativeBearingDeg < -15.0 && relativeBearingDeg >= -60.0) {
      return 'Turn Slightly Left';
    } else if (relativeBearingDeg < -60.0 && relativeBearingDeg >= -120.0) {
      return 'Turn Left';
    } else if (relativeBearingDeg < -120.0 && relativeBearingDeg >= -165.0) {
      return 'Turn Sharp Left';
    }
    return 'Turn Around';
  }
}

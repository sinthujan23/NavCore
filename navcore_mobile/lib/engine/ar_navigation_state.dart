import 'package:flutter/foundation.dart';
import 'ecef_engine.dart';
import '../data/destinations.dart';
import 'route_service.dart';

enum ARNavigationState {
  initializing,
  scanningReference,
  referenceLocked,
  tracking,
  navigating,
  approachingTransition,
  changingFloor,
  relocalizing,
  offRoute,
  arrived,
  error,
}

enum TrackingConfidence {
  high,
  medium,
  low,
  lost,
}

class ARNavigationStateManager extends ChangeNotifier {
  ARNavigationState _state = ARNavigationState.initializing;
  TrackingConfidence _confidence = TrackingConfidence.high;
  String _statusMessage = 'Initializing AR Navigation...';
  
  DestinationPOI? _activeDestination;
  RoutePath? _activeRoute;
  int _currentWaypointIndex = 0;
  
  int _currentFloorNumber = 1;
  double _distanceToDestinationMeters = 0.0;
  double _relativeBearingDegrees = 0.0;
  
  GeodeticCoords _userCoords = const GeodeticCoords(latitude: 0.0, longitude: 0.0, height: 0.0);
  double _compassHeading = 0.0;
  double _phonePitch = 0.0;
  
  bool _isOfflineMode = false;
  String? _errorMessage;

  // Getters
  ARNavigationState get state => _state;
  TrackingConfidence get confidence => _confidence;
  String get statusMessage => _statusMessage;
  DestinationPOI? get activeDestination => _activeDestination;
  RoutePath? get activeRoute => _activeRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  int get currentFloorNumber => _currentFloorNumber;
  double get distanceToDestinationMeters => _distanceToDestinationMeters;
  double get relativeBearingDegrees => _relativeBearingDegrees;
  GeodeticCoords get userCoords => _userCoords;
  double get compassHeading => _compassHeading;
  double get phonePitch => _phonePitch;
  bool get isOfflineMode => _isOfflineMode;
  String? get errorMessage => _errorMessage;

  void setState(ARNavigationState newState, {String? message}) {
    _state = newState;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  void setTrackingConfidence(TrackingConfidence confidence, {String? message}) {
    _confidence = confidence;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  void updateSensors({
    required GeodeticCoords coords,
    required double heading,
    required double pitch,
  }) {
    _userCoords = coords;
    _compassHeading = heading;
    _phonePitch = pitch;
    notifyListeners();
  }

  void startNavigation(DestinationPOI poi, RoutePath route) {
    _activeDestination = poi;
    _activeRoute = route;
    _currentWaypointIndex = 0;
    _state = ARNavigationState.navigating;
    _statusMessage = 'Navigating to ${poi.name}';
    notifyListeners();
  }

  void updateNavigationProgress({
    required double distanceMeters,
    required double relativeBearing,
    required int nextWaypointIdx,
  }) {
    _distanceToDestinationMeters = distanceMeters;
    _relativeBearingDegrees = relativeBearing;
    _currentWaypointIndex = nextWaypointIdx;

    if (distanceMeters <= 3.0 && _state == ARNavigationState.navigating) {
      _state = ARNavigationState.arrived;
      _statusMessage = "You've arrived at ${_activeDestination?.name ?? 'destination'}!";
    }
    notifyListeners();
  }

  void setCurrentFloor(int floor) {
    _currentFloorNumber = floor;
    notifyListeners();
  }

  void setOfflineMode(bool offline) {
    _isOfflineMode = offline;
    if (offline) {
      _statusMessage = 'Offline Navigation Mode Active';
    }
    notifyListeners();
  }

  void cancelNavigation() {
    _activeDestination = null;
    _activeRoute = null;
    _currentWaypointIndex = 0;
    _state = ARNavigationState.tracking;
    _statusMessage = 'AR Tracking Active';
    notifyListeners();
  }

  void setError(String message) {
    _state = ARNavigationState.error;
    _errorMessage = message;
    _statusMessage = message;
    notifyListeners();
  }
}

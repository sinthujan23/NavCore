import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../engine/ecef_engine.dart';
import '../engine/kalman_filter.dart';
import '../engine/pnp_engine.dart';

class TelemetryScreen extends StatelessWidget {
  final GeodeticCoords userCoords;
  final KalmanState kalmanState;
  final PnPResult? pnpResult;
  final double gpsAccuracyMeters;
  final double compassHeadingDegrees;

  const TelemetryScreen({
    super.key,
    required this.userCoords,
    required this.kalmanState,
    this.pnpResult,
    this.gpsAccuracyMeters = 3.5,
    this.compassHeadingDegrees = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final ecef = geodeticToECEF(userCoords);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'Sensor Fusion & Real Telemetry',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTile(
            'REAL MOBILE GPS LOCATION',
            'Lat: ${userCoords.latitude.toStringAsFixed(6)}° N\nLon: ${userCoords.longitude.toStringAsFixed(6)}° W\nAltitude: ${userCoords.height.toStringAsFixed(2)} m\nGPS Lock Accuracy: ±${gpsAccuracyMeters.toStringAsFixed(1)} m',
          ),
          const SizedBox(height: 12),
          _buildTile(
            'HARDWARE COMPASS & HEADING',
            'Magnetometer Heading: ${compassHeadingDegrees.toStringAsFixed(1)}° (${_getCardinalDirection(compassHeadingDegrees)})\nSensor Fusion: Active\nSampling Frequency: High 60Hz',
          ),
          const SizedBox(height: 12),
          _buildTile(
            'ECEF VECTOR (EARTH FIXED FRAME)',
            'X_ECEF: ${ecef.x.toStringAsFixed(2)} m\nY_ECEF: ${ecef.y.toStringAsFixed(2)} m\nZ_ECEF: ${ecef.z.toStringAsFixed(2)} m',
          ),
          const SizedBox(height: 12),
          _buildTile(
            'KALMAN FILTER POSITION VARIANCE',
            'Var Lat: ${kalmanState.varianceLat.toStringAsExponential(3)}\nVar Lon: ${kalmanState.varianceLon.toStringAsExponential(3)}\nVar Height: ${kalmanState.varianceHeight.toStringAsExponential(3)}',
          ),
        ],
      ),
    );
  }

  String _getCardinalDirection(double deg) {
    if (deg >= 337.5 || deg < 22.5) return 'N';
    if (deg >= 22.5 && deg < 67.5) return 'NE';
    if (deg >= 67.5 && deg < 112.5) return 'E';
    if (deg >= 112.5 && deg < 157.5) return 'SE';
    if (deg >= 157.5 && deg < 202.5) return 'S';
    if (deg >= 202.5 && deg < 247.5) return 'SW';
    if (deg >= 247.5 && deg < 292.5) return 'W';
    return 'NW';
  }

  Widget _buildTile(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.grey[500],
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.firaCode(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0F172A),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

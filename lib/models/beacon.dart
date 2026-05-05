// lib/models/beacon.dart

import 'dart:convert';

enum BeaconStatus { safe, warning, alarm, disconnected }

class Beacon {
  final String deviceId; // BLE MAC address
  String displayName;    // User-assigned name e.g. "Nico" or "Dog Max"
  BeaconStatus status;
  int rssi;
  double estimatedDistance; // meters
  DateTime? lastSeen;
  List<int> rssiHistory;    // Rolling window for averaging
  bool isActive;            // False = user marked as "not in use"; skips alarm

  Beacon({
    required this.deviceId,
    required this.displayName,
    this.status = BeaconStatus.disconnected,
    this.rssi = -100,
    this.estimatedDistance = 0,
    this.lastSeen,
    List<int>? rssiHistory,
    this.isActive = true,
  }) : rssiHistory = rssiHistory ?? [];

  // Entry thresholds (worsening direction) — tuned for 3 m / 10 m zones:
  //   SAFE → WARNING : avgRssi < -71 dBm  (~3 m)
  //   WARNING → ALARM: avgRssi < -84 dBm  (~10 m)
  //
  // Exit thresholds (improving direction — hysteresis prevents oscillation
  // when RSSI hovers near a boundary):
  //   ALARM → WARNING: avgRssi >= -78 dBm  (~5.75 m, 6 dBm above entry)
  //   WARNING → SAFE : avgRssi >= -66 dBm  (~1.9 m,  5 dBm above entry)
  BeaconStatus computeStatus(int avgRssi, BeaconStatus current) {
    switch (current) {
      case BeaconStatus.safe:
        if (avgRssi < -71) return BeaconStatus.warning;
        return BeaconStatus.safe;
      case BeaconStatus.warning:
        if (avgRssi >= -66) return BeaconStatus.safe;
        if (avgRssi < -84) return BeaconStatus.alarm;
        return BeaconStatus.warning;
      case BeaconStatus.alarm:
        if (avgRssi >= -78) return BeaconStatus.warning;
        return BeaconStatus.alarm;
      case BeaconStatus.disconnected:
        // First reading after reconnect — use entry thresholds to establish state
        if (avgRssi >= -71) return BeaconStatus.safe;
        if (avgRssi >= -84) return BeaconStatus.warning;
        return BeaconStatus.alarm;
    }
  }

  /// Add new RSSI reading to rolling window (max 8 samples).
  /// Fast-recovery flush: if the new reading is ≥20 dBm stronger than the
  /// current average the device has physically moved much closer — stale
  /// alarm readings are cleared so status recovers in 1–2 readings instead
  /// of being dragged down for 17+ seconds.
  void addRssiReading(int newRssi) {
    if (rssiHistory.length >= 4 && (newRssi - averageRssi) >= 20) {
      rssiHistory.clear();
    }
    rssiHistory.add(newRssi);
    if (rssiHistory.length > 8) {
      rssiHistory.removeAt(0);
    }
    rssi = newRssi;
    lastSeen = DateTime.now();

    final avg = averageRssi;
    status = computeStatus(avg, status);
    estimatedDistance = rssiToDistance(avg);
  }

  int get averageRssi {
    if (rssiHistory.isEmpty) return rssi;
    return rssiHistory.reduce((a, b) => a + b) ~/ rssiHistory.length;
  }

  /// Free-space path loss formula: d = 10^((TxPower - RSSI) / (10 * n))
  /// TxPower at 1m ≈ -59 dBm, n = 2.5 (indoor environment factor)
  double rssiToDistance(int rssi) {
    const txPower = -59;
    const n = 2.5;
    return (rssi == 0) ? -1.0 : pow10((txPower - rssi) / (10 * n));
  }

  double pow10(double exp) {
    return 1.0 * _pow(10.0, exp);
  }

  double _pow(double base, double exp) {
    if (exp == 0) return 1.0;
    double result = 1.0;
    bool negative = exp < 0;
    double absExp = negative ? -exp : exp;
    int intPart = absExp.toInt();
    double fracPart = absExp - intPart;
    for (int i = 0; i < intPart; i++) {
      result *= base;
    }
    if (fracPart > 0) result *= _approxPow(base, fracPart);
    return negative ? 1.0 / result : result;
  }

  double _approxPow(double base, double frac) {
    // Use ln approximation: base^frac = e^(frac * ln(base))
    double lnBase = _ln(base);
    return _exp(frac * lnBase);
  }

  double _ln(double x) {
    // Taylor series approximation of ln
    if (x <= 0) return double.negativeInfinity;
    double result = 0;
    double term = (x - 1) / (x + 1);
    double termSq = term * term;
    double current = term;
    for (int i = 0; i < 20; i++) {
      result += current / (2 * i + 1);
      current *= termSq;
    }
    return 2 * result;
  }

  double _exp(double x) {
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  void markDisconnected() {
    status = BeaconStatus.disconnected;
    rssiHistory.clear();
  }

  // Serialization for SharedPreferences
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'displayName': displayName,
        'isActive': isActive,
      };

  factory Beacon.fromJson(Map<String, dynamic> json) => Beacon(
        deviceId: json['deviceId'],
        displayName: json['displayName'],
        isActive: json['isActive'] as bool? ?? true,
      );

  static String encodeList(List<Beacon> beacons) =>
      jsonEncode(beacons.map((b) => b.toJson()).toList());

  static List<Beacon> decodeList(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((j) => Beacon.fromJson(j)).toList();
  }
}
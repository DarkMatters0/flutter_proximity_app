// lib/services/ble_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/beacon.dart';

class BleService extends ChangeNotifier {
  // All registered (saved) beacons
  final List<Beacon> _registeredBeacons = [];

  // Devices found during a scan (not yet registered)
  final List<ScanResult> _scanResults = [];

  bool _isScanning = false;
  bool _isMonitoring = false;
  String _statusMessage = 'Ready';

  // How long before a beacon is considered disconnected (seconds)
  static const int _disconnectTimeoutSec = 8;

  StreamSubscription? _scanSubscription;
  Timer? _monitorTimer;
  Timer? _disconnectWatchdog;

  List<Beacon> get registeredBeacons => List.unmodifiable(_registeredBeacons);
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get isMonitoring => _isMonitoring;
  String get statusMessage => _statusMessage;

  // True if any registered beacon is in ALARM state
  bool get hasActiveAlarm =>
      _registeredBeacons.any((b) => b.status == BeaconStatus.alarm);

  BleService() {
    _loadSavedBeacons();
  }

  // ─── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadSavedBeacons() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('saved_beacons');
    if (jsonStr != null) {
      final loaded = Beacon.decodeList(jsonStr);
      _registeredBeacons.addAll(loaded);
      notifyListeners();
    }
  }

  Future<void> _saveBeacons() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_beacons', Beacon.encodeList(_registeredBeacons));
  }

  // ─── Scanning (for discovering new devices to register) ─────────────────────

  Future<void> startScan() async {
    _scanResults.clear();
    _isScanning = true;
    _statusMessage = 'Scanning for nearby devices...';
    notifyListeners();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: true,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults.clear();
      // Only show devices with a name (filters out noise)
      _scanResults.addAll(results.where((r) =>
          r.device.platformName.isNotEmpty ||
          r.advertisementData.localName.isNotEmpty));
      notifyListeners();
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning) {
        _isScanning = false;
        _statusMessage = _scanResults.isEmpty
            ? 'No devices found. Make sure beacon is powered on.'
            : 'Scan complete. ${_scanResults.length} device(s) found.';
        notifyListeners();
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  // ─── Registration ────────────────────────────────────────────────────────────

  void registerDevice(ScanResult result, String displayName) {
    final deviceId = result.device.remoteId.str;

    // Prevent duplicates
    if (_registeredBeacons.any((b) => b.deviceId == deviceId)) {
      return;
    }

    _registeredBeacons.add(Beacon(
      deviceId: deviceId,
      displayName: displayName.isEmpty
          ? (result.device.platformName.isNotEmpty
              ? result.device.platformName
              : deviceId)
          : displayName,
    ));

    _saveBeacons();
    notifyListeners();
  }

  void removeBeacon(String deviceId) {
    _registeredBeacons.removeWhere((b) => b.deviceId == deviceId);
    _saveBeacons();
    notifyListeners();
  }

  void renameBeacon(String deviceId, String newName) {
    final beacon =
        _registeredBeacons.firstWhere((b) => b.deviceId == deviceId);
    beacon.displayName = newName;
    _saveBeacons();
    notifyListeners();
  }

  // ─── Monitoring ──────────────────────────────────────────────────────────────

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _statusMessage = 'Monitoring ${_registeredBeacons.length} beacon(s)...';
    notifyListeners();

    // Continuously scan in background
    await FlutterBluePlus.startScan(
      androidUsesFineLocation: true,
      // No timeout = continuous
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        final beacon = _registeredBeacons
            .where((b) => b.deviceId == id)
            .firstOrNull;
        if (beacon != null) {
          beacon.addRssiReading(result.rssi);
        }
      }
      notifyListeners();
    });

    // Watchdog: mark beacons as disconnected if not seen recently
    _disconnectWatchdog =
        Timer.periodic(const Duration(seconds: 3), (_) {
      final now = DateTime.now();
      bool changed = false;
      for (final beacon in _registeredBeacons) {
        if (beacon.lastSeen != null) {
          final elapsed = now.difference(beacon.lastSeen!).inSeconds;
          if (elapsed > _disconnectTimeoutSec &&
              beacon.status != BeaconStatus.disconnected) {
            beacon.markDisconnected();
            changed = true;
          }
        }
      }
      if (changed) notifyListeners();
    });
  }

  Future<void> stopMonitoring() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _disconnectWatchdog?.cancel();
    _monitorTimer?.cancel();
    _isMonitoring = false;
    _statusMessage = 'Monitoring stopped.';
    for (final b in _registeredBeacons) {
      b.markDisconnected();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
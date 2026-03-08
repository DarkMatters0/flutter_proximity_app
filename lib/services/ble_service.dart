// lib/services/ble_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../models/beacon.dart';

class BleService extends ChangeNotifier {
  // All registered (saved) beacons
  final List<Beacon> _registeredBeacons = [];

  // Devices found during a scan (not yet registered)
  final List<ScanResult> _scanResults = [];

  bool _isScanning = false;
  bool _isMonitoring = false;
  bool _alarmActive = false;
  String _statusMessage = 'Ready';

  // Increased disconnect timeout from 8s to 15s to reduce false disconnects.
  // BLE advertisements + OS scan throttling can easily introduce 8-12s gaps.
  static const int _disconnectTimeoutSec = 15;

  // How often to restart the background monitoring scan (in seconds).
  // Android silently kills continuous scans after ~25-30s, so we restart before that.
  static const int _scanRestartIntervalSec = 20;

  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription? _monitorScanSubscription;
  StreamSubscription? _discoveryScanSubscription;
  StreamSubscription? _scanningStateSubscription;
  Timer? _disconnectWatchdog;
  Timer? _scanRestartTimer;

  List<Beacon> get registeredBeacons => List.unmodifiable(_registeredBeacons);
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get isMonitoring => _isMonitoring;
  String get statusMessage => _statusMessage;

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

  // ─── Alarm & Vibration ───────────────────────────────────────────────────────

  Future<void> _triggerAlarm() async {
    if (_alarmActive) return; // already alarming, don't restart
    _alarmActive = true;

    // Play alarm sound on loop
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));

    // Vibrate in a repeating pattern: vibrate, pause, vibrate, pause...
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(
        pattern: [0, 800, 400, 800, 400, 800],
        repeat: 0, // repeat from index 0 = loops forever
      );
    }
  }

  Future<void> _stopAlarm() async {
    if (!_alarmActive) return;
    _alarmActive = false;
    await _audioPlayer.stop();
    Vibration.cancel();
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
      androidScanMode: AndroidScanMode.lowLatency,
    );

    _discoveryScanSubscription =
        FlutterBluePlus.scanResults.listen((results) {
      _scanResults.clear();
      _scanResults.addAll(results.where((r) =>
          r.device.platformName.isNotEmpty ||
          r.advertisementData.localName.isNotEmpty));
      notifyListeners();
    });

    _scanningStateSubscription?.cancel();
    _scanningStateSubscription =
        FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _isScanning && !_isMonitoring) {
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
    await _discoveryScanSubscription?.cancel();
    _discoveryScanSubscription = null;
    _isScanning = false;
    notifyListeners();
  }

  // ─── Registration ────────────────────────────────────────────────────────────

  void registerDevice(ScanResult result, String displayName) {
    final deviceId = result.device.remoteId.str;
    if (_registeredBeacons.any((b) => b.deviceId == deviceId)) return;

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

    // Start the first monitoring scan cycle
    await _startMonitoringScan();

    // Periodically restart the BLE scan before Android throttles/kills it.
    // This is the KEY fix for the "goes offline after minutes" issue.
    _scanRestartTimer?.cancel();
    _scanRestartTimer =
        Timer.periodic(Duration(seconds: _scanRestartIntervalSec), (_) async {
      if (!_isMonitoring) return;
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await _startMonitoringScan();
    });

    // Watchdog: mark beacons as disconnected if not seen recently
    _disconnectWatchdog?.cancel();
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
      if (changed) {
        notifyListeners();
        // Check alarm state after watchdog marks beacons disconnected
        if (hasActiveAlarm) {
          _triggerAlarm();
        } else {
          _stopAlarm();
        }
      }
    });
  }

  /// Internal: starts a single BLE scan cycle for monitoring.
  /// Uses lowPower mode to be battery-friendly during continuous background use.
  Future<void> _startMonitoringScan() async {
    await _monitorScanSubscription?.cancel();
    _monitorScanSubscription = null;

    try {
      await FlutterBluePlus.startScan(
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowPower,
      );

      _monitorScanSubscription =
          FlutterBluePlus.scanResults.listen((results) {
        bool changed = false;
        for (final result in results) {
          final id = result.device.remoteId.str;
          final beacon = _registeredBeacons
              .where((b) => b.deviceId == id)
              .firstOrNull;
          if (beacon != null) {
            beacon.addRssiReading(result.rssi);
            changed = true;
          }
        }
        if (changed) {
          notifyListeners();
          // Trigger or stop alarm based on current beacon states
          if (hasActiveAlarm) {
            _triggerAlarm();
          } else {
            _stopAlarm();
          }
        }
      });
    } catch (e) {
      // If scan fails (e.g., BT briefly off), retry on next timer tick
      debugPrint('[BleService] _startMonitoringScan error: $e');
    }
  }

  Future<void> stopMonitoring() async {
    await _stopAlarm(); // stop alarm first before cleaning up
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    _disconnectWatchdog?.cancel();
    _disconnectWatchdog = null;

    await FlutterBluePlus.stopScan();
    await _monitorScanSubscription?.cancel();
    _monitorScanSubscription = null;

    _isMonitoring = false;
    _statusMessage = 'Monitoring stopped.';
    for (final b in _registeredBeacons) {
      b.markDisconnected();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAlarm();
    _audioPlayer.dispose();
    stopMonitoring();
    _discoveryScanSubscription?.cancel();
    _scanningStateSubscription?.cancel();
    super.dispose();
  }
}
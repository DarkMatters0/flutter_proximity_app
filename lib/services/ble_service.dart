// lib/services/ble_service.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../models/beacon.dart';

class BleService extends ChangeNotifier with WidgetsBindingObserver {
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
      _isMonitoring &&
      _registeredBeacons.any((b) =>
          b.status == BeaconStatus.alarm ||
          b.status == BeaconStatus.disconnected);

  // ─── GATT remote buzzer control ─────────────────────────────────────────────

  static const String _gattServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String _alarmCharUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  // Tracks what was last successfully sent to each beacon's buzzer.
  // null = never sent, true = 0x01 (ON) sent, false = 0x00 (OFF) sent.
  final Map<String, bool?> _lastBuzzerSent = {};

  // ─── Background / notification fields ───────────────────────────────────────

  bool _isAppInBackground = false;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const MethodChannel _methodChannel =
      MethodChannel('com.example.flutter_app1/foreground_service');

  static const String _alertChannelId = 'guardian_alerts';
  static const String _alertChannelName = 'GuardianBLE Alerts';

  // Tracks last status for which a notification was shown per beacon.
  // null means no notification has been fired yet for this beacon.
  final Map<String, BeaconStatus?> _lastNotifiedStatus = {};

  // Stable notification IDs per beacon (starting at 2000; 1001 = foreground service)
  final Map<String, int> _beaconNotificationIds = {};
  int _nextNotificationId = 2000;

  // ─── Constructor ─────────────────────────────────────────────────────────────

  BleService() {
    WidgetsBinding.instance.addObserver(this);
    _loadSavedBeacons();
    _initNotifications();
  }

  // ─── App lifecycle observer ──────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
  }

  // ─── Notification initialisation ────────────────────────────────────────────

  Future<void> _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
    );

    // High-importance channel for beacon warning/alarm alerts.
    // Must be created before any notification is posted.
    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: 'Alerts when a tracked beacon goes out of range',
      importance: Importance.high,
      playSound: true,
      enableVibration: false, // vibration is handled by the Vibration package
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alertChannel);

    // Request POST_NOTIFICATIONS permission (Android 13+).
    // permission_handler is already a dependency — reuse it.
    await Permission.notification.request();
  }

  // ─── Show a beacon alert notification ───────────────────────────────────────

  Future<void> _showBeaconNotification(
      Beacon beacon, BeaconStatus status) async {
    final int notifId = _beaconNotificationIds.putIfAbsent(
      beacon.deviceId,
      () => _nextNotificationId++,
    );

    final String name = beacon.displayName;
    final String title = status == BeaconStatus.warning
        ? '⚠️ $name is getting far away!'
        : '🚨 $name is out of range!';
    final String body = status == BeaconStatus.warning
        ? 'Move closer to $name.'
        : '$name may be lost!';

    await _notifications.show(
      notifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannelId,
          _alertChannelName,
          importance: Importance.high,
          priority: Priority.high,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public, // show content on lock screen
          ongoing: false,
          autoCancel: false,
        ),
      ),
    );
  }

  // ─── Dismiss a beacon notification ──────────────────────────────────────────

  Future<void> _dismissBeaconNotification(Beacon beacon) async {
    final id = _beaconNotificationIds[beacon.deviceId];
    if (id != null) await _notifications.cancel(id);
  }

  Future<void> _dismissAllBeaconNotifications() async {
    for (final id in _beaconNotificationIds.values) {
      await _notifications.cancel(id);
    }
    _lastNotifiedStatus.clear();
  }

  // ─── Notification state machine ──────────────────────────────────────────────
  // Called after every status change (scan result or watchdog).
  // Fires a notification only when:
  //   - Status has changed (no duplicate spam)
  //   - App is in background (screen off or app backgrounded)
  // Dismisses notification automatically when beacon recovers to SAFE.

  Future<void> _checkAndNotify() async {
    for (final beacon in _registeredBeacons) {
      final newStatus = beacon.status;
      final prevNotified = _lastNotifiedStatus[beacon.deviceId];

      if (newStatus == BeaconStatus.safe) {
        if (prevNotified != null && prevNotified != BeaconStatus.safe) {
          await _dismissBeaconNotification(beacon);
          _lastNotifiedStatus[beacon.deviceId] = BeaconStatus.safe;
        }
      } else {
        if (newStatus != prevNotified && _isAppInBackground) {
          await _showBeaconNotification(beacon, newStatus);
          _lastNotifiedStatus[beacon.deviceId] = newStatus;
        } else if (prevNotified == null) {
          // Record the baseline even if app is in foreground so we
          // detect future transitions correctly.
          _lastNotifiedStatus[beacon.deviceId] = newStatus;
        }
      }
    }
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
    if (await Vibration.hasVibrator()) {
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

  // ─── Remote buzzer control via BLE GATT write ───────────────────────────────

  Future<void> _sendBuzzerCommand(Beacon beacon, bool alarmOn) async {
    if (_lastBuzzerSent[beacon.deviceId] == alarmOn) return;
    _lastBuzzerSent[beacon.deviceId] = alarmOn; // optimistic — blocks concurrent calls

    try {
      final device = BluetoothDevice.fromId(beacon.deviceId);
      await device.connect(
          timeout: const Duration(seconds: 8), autoConnect: false);
      final services = await device.discoverServices();
      final service = services
          .where((s) =>
              s.serviceUuid.toString().toLowerCase() == _gattServiceUuid)
          .firstOrNull;
      if (service == null) {
        debugPrint('[BleService] GATT service not found on ${beacon.displayName}');
        await device.disconnect();
        return;
      }
      final char = service.characteristics
          .where((c) =>
              c.characteristicUuid.toString().toLowerCase() == _alarmCharUuid)
          .firstOrNull;
      if (char == null) {
        debugPrint('[BleService] Alarm characteristic not found on ${beacon.displayName}');
        await device.disconnect();
        return;
      }
      await char.write([alarmOn ? 0x01 : 0x00]);
      await device.disconnect();
      debugPrint(
          '[BleService] Buzzer ${alarmOn ? "ON" : "OFF"} → ${beacon.displayName}');
    } catch (e) {
      _lastBuzzerSent[beacon.deviceId] = null; // reset so retry is possible
      debugPrint('[BleService] GATT write error for ${beacon.displayName}: $e');
    }
  }

  void _syncBuzzerCommands() {
    for (final beacon in _registeredBeacons) {
      if (beacon.status == BeaconStatus.alarm) {
        _sendBuzzerCommand(beacon, true); // fire-and-forget
      } else if (beacon.status == BeaconStatus.safe ||
          beacon.status == BeaconStatus.warning) {
        _sendBuzzerCommand(beacon, false); // fire-and-forget
      }
      // DISCONNECTED: skip — device is unreachable; buzzer holds its last state
    }
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
    _lastBuzzerSent.remove(deviceId);
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

    // Start the Android foreground service so the process stays alive when
    // the screen is off. Non-fatal if it fails (monitoring still works in foreground).
    try {
      await _methodChannel.invokeMethod('startService');
    } catch (e) {
      debugPrint('[BleService] startService error: $e');
    }

    // Request battery optimization exemption so Android does not Doze the app
    // and suspend Dart timers / BLE scan callbacks while the screen is off.
    await Permission.ignoreBatteryOptimizations.request();

    // Start the first monitoring scan cycle
    await _startMonitoringScan();

    // Periodically restart the BLE scan before Android throttles/kills it.
    // This is the KEY fix for the "goes offline after minutes" issue.
    _scanRestartTimer?.cancel();
    _scanRestartTimer =
        Timer.periodic(const Duration(seconds: _scanRestartIntervalSec), (_) async {
      if (!_isMonitoring) return;
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await _startMonitoringScan();
    });

    // Watchdog: mark beacons as disconnected if not seen recently
    _disconnectWatchdog?.cancel();
    _disconnectWatchdog =
        Timer.periodic(const Duration(seconds: 3), (_) async {
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
        if (hasActiveAlarm) {
          _triggerAlarm();
        } else {
          _stopAlarm();
        }
        _syncBuzzerCommands(); // send ON/OFF to ESP32 buzzer when state changes
        await _checkAndNotify();
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
          FlutterBluePlus.scanResults.listen((results) async {
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
          if (hasActiveAlarm) {
            _triggerAlarm();
          } else {
            _stopAlarm();
          }
          _syncBuzzerCommands(); // send ON/OFF to ESP32 buzzer when state changes
          await _checkAndNotify();
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

    // Send buzzer OFF to any beacons that were actively alarmed, then clear state.
    for (final beacon in _registeredBeacons) {
      if (_lastBuzzerSent[beacon.deviceId] == true) {
        _sendBuzzerCommand(beacon, false); // fire-and-forget
      }
    }
    _lastBuzzerSent.clear();

    // Dismiss all beacon notifications and stop the foreground service.
    await _dismissAllBeaconNotifications();
    try {
      await _methodChannel.invokeMethod('stopService');
    } catch (e) {
      debugPrint('[BleService] stopService error: $e');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAlarm();
    _audioPlayer.dispose();
    stopMonitoring();
    _discoveryScanSubscription?.cancel();
    _scanningStateSubscription?.cancel();
    super.dispose();
  }
}

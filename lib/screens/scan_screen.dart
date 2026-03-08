// lib/screens/scan_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _permissionsGranted = false;
  bool _hasCheckedPermissions = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request all required BLE + location permissions
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final granted = statuses.values.every((s) =>
        s == PermissionStatus.granted || s == PermissionStatus.limited);

    setState(() {
      _permissionsGranted = granted;
      _hasCheckedPermissions = true;
    });

    if (granted) {
      if (mounted) {
        context.read<BleService>().startScan();
      }
    }
  }

  void _showAddDialog(BuildContext context, ScanResult result) {
    final ble = context.read<BleService>();
    final deviceName = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : 'Unknown Device';

    // Check if already registered
    final alreadyAdded = ble.registeredBeacons
        .any((b) => b.deviceId == result.device.remoteId.str);

    if (alreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This beacon is already in your list.'),
          backgroundColor: const Color(0xFF0F3460),
        ),
      );
      return;
    }

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Beacon',
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_rounded,
                      color: Color(0xFF00D4FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(deviceName,
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text(result.device.remoteId.str,
                            style: GoogleFonts.robotoMono(
                                color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                  ),
                  Text('${result.rssi} dBm',
                      style: GoogleFonts.robotoMono(
                          color: const Color(0xFF00FF9F), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Display name',
                style: GoogleFonts.inter(
                    color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Nico, Dog Max, Lola...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF0F3460),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<BleService>().registerDevice(
                    result,
                    controller.text.trim().isEmpty
                        ? deviceName
                        : controller.text.trim(),
                  );
              Navigator.pop(ctx);
              Navigator.pop(context); // Go back to dashboard
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Beacon added! Tap "Start Monitoring" to begin tracking.',
                  ),
                  backgroundColor: const Color(0xFF00FF9F).withOpacity(0.8),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D4FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Add Beacon',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, ble, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A1A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F3460),
            foregroundColor: Colors.white,
            title: Text('Scan for Beacons',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            actions: [
              if (!ble.isScanning && _permissionsGranted)
                TextButton.icon(
                  onPressed: () => ble.startScan(),
                  icon: const Icon(Icons.refresh_rounded,
                      color: Color(0xFF00D4FF), size: 18),
                  label: Text('Rescan',
                      style: GoogleFonts.inter(
                          color: const Color(0xFF00D4FF),
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          body: !_hasCheckedPermissions
              ? _buildLoading('Checking permissions...')
              : !_permissionsGranted
                  ? _buildPermissionDenied()
                  : Column(
                      children: [
                        // Scanning indicator
                        if (ble.isScanning)
                          Container(
                            padding: const EdgeInsets.all(14),
                            color: const Color(0xFF0F3460).withOpacity(0.5),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: const Color(0xFF00D4FF),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Scanning for BLE devices...',
                                  style: GoogleFonts.inter(
                                      color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                        // Instructions
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Tap a device to set its name and add it as a beacon. Make sure your ESP32 beacon is powered on and advertising.',
                            style: GoogleFonts.inter(
                                color: Colors.white38, fontSize: 12, height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        // Results
                        Expanded(
                          child: ble.scanResults.isEmpty
                              ? _buildLoading(ble.isScanning
                                  ? 'Looking for devices nearby...'
                                  : 'No devices found. Make sure your beacon is on.')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: ble.scanResults.length,
                                  itemBuilder: (context, i) {
                                    final result = ble.scanResults[i];
                                    return _buildScanResultTile(
                                        context, result, ble);
                                  },
                                ),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildScanResultTile(
      BuildContext context, ScanResult result, BleService ble) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : 'Unnamed Device';

    final isRegistered = ble.registeredBeacons
        .any((b) => b.deviceId == result.device.remoteId.str);

    final rssiColor = result.rssi > -65
        ? const Color(0xFF00FF9F)
        : result.rssi > -80
            ? const Color(0xFFFFD166)
            : const Color(0xFFFF4B6E);

    return GestureDetector(
      onTap: () => _showAddDialog(context, result),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1B35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRegistered
                ? const Color(0xFF00D4FF).withOpacity(0.4)
                : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bluetooth_rounded,
                  color: Color(0xFF00D4FF), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(result.device.remoteId.str,
                      style: GoogleFonts.robotoMono(
                          color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${result.rssi} dBm',
                    style: GoogleFonts.robotoMono(
                        color: rssiColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                if (isRegistered)
                  Text('Added',
                      style: GoogleFonts.inter(
                          color: const Color(0xFF00D4FF),
                          fontSize: 10)),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              isRegistered
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              color: isRegistered
                  ? const Color(0xFF00D4FF)
                  : Colors.white38,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00D4FF)),
          const SizedBox(height: 16),
          Text(message,
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled_rounded,
                color: Color(0xFFFF4B6E), size: 52),
            const SizedBox(height: 20),
            Text('Permissions Required',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Bluetooth and Location permissions are required to scan for beacons. Please grant them in your device settings.',
              style:
                  GoogleFonts.inter(color: Colors.white38, fontSize: 13, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Open Settings',
                  style:
                      GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
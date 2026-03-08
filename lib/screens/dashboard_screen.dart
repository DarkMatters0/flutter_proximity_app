// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ble_service.dart';
import '../models/beacon.dart';
import 'scan_screen.dart';
import '../widgets/beacon_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleMonitoring(BleService ble) async {
    if (ble.isMonitoring) {
      await ble.stopMonitoring();
    } else {
      await ble.startMonitoring();
    }
  }

  void _goToScan(BuildContext context) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ScanScreen()));
  }

  void _showRenameDialog(BuildContext context, Beacon beacon) {
    final controller = TextEditingController(text: beacon.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rename Beacon',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter name (e.g. Nico, Dog Max)',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0F3460),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context
                    .read<BleService>()
                    .renameBeacon(beacon.deviceId, controller.text.trim());
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D4FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, Beacon beacon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Beacon',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove "${beacon.displayName}" from your tracking list?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<BleService>().removeBeacon(beacon.deviceId);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4B6E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Remove',
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
        final hasAlarm = ble.hasActiveAlarm;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A1A),
          body: SafeArea(
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────────────────
                _buildHeader(ble, hasAlarm),

                // ── Status bar ───────────────────────────────────────────────
                _buildStatusBar(ble),

                // ── Beacon list ──────────────────────────────────────────────
                Expanded(
                  child: ble.registeredBeacons.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: ble.registeredBeacons.length,
                          itemBuilder: (context, i) {
                            final beacon = ble.registeredBeacons[i];
                            return BeaconCard(
                              beacon: beacon,
                              pulseAnimation: _pulseController,
                              onRename: () =>
                                  _showRenameDialog(context, beacon),
                              onDelete: () =>
                                  _showDeleteConfirm(context, beacon),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── FAB: Add beacon ────────────────────────────────────────────────
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Monitor toggle button
              if (ble.registeredBeacons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FloatingActionButton.extended(
                    heroTag: 'monitor',
                    onPressed: () => _toggleMonitoring(ble),
                    backgroundColor: ble.isMonitoring
                        ? const Color(0xFFFF4B6E)
                        : const Color(0xFF00FF9F),
                    foregroundColor: Colors.black,
                    icon: Icon(ble.isMonitoring
                        ? Icons.stop_rounded
                        : Icons.radar_rounded),
                    label: Text(
                      ble.isMonitoring ? 'Stop' : 'Start Monitoring',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // Add beacon button
              FloatingActionButton(
                heroTag: 'scan',
                onPressed: () => _goToScan(context),
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: Colors.black,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BleService ble, bool hasAlarm) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hasAlarm
                  ? [
                      Color.lerp(const Color(0xFF2D0A1A),
                          const Color(0xFF4D0A1A), _pulseController.value)!,
                      const Color(0xFF1A0A2E),
                    ]
                  : [
                      const Color(0xFF0F3460),
                      const Color(0xFF0A0A1A),
                    ],
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasAlarm
                      ? const Color(0xFFFF4B6E).withOpacity(0.2)
                      : const Color(0xFF00D4FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasAlarm
                      ? Icons.warning_amber_rounded
                      : Icons.shield_rounded,
                  color: hasAlarm
                      ? const Color(0xFFFF4B6E)
                      : const Color(0xFF00D4FF),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GuardianBLE',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      hasAlarm
                          ? '⚠ ALARM — Check your beacons!'
                          : '${ble.registeredBeacons.length} beacon(s) registered',
                      style: GoogleFonts.inter(
                        color: hasAlarm
                            ? const Color(0xFFFF4B6E)
                            : Colors.white38,
                        fontSize: 12,
                        fontWeight: hasAlarm ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              // Monitoring indicator
              if (ble.isMonitoring)
                _buildPulsingDot(_pulseController.value),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPulsingDot(double pulse) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(
          const Color(0xFF00FF9F).withOpacity(0.1),
          const Color(0xFF00FF9F).withOpacity(0.3),
          pulse,
        ),
      ),
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF00FF9F),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BleService ble) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3460).withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ble.statusMessage,
              style: GoogleFonts.inter(
                  color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bluetooth_searching_rounded,
                  color: Color(0xFF00D4FF), size: 38),
            ),
            const SizedBox(height: 24),
            Text(
              'No beacons yet',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to scan for nearby ESP32 beacon devices and add them to your tracking list.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _goToScan(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text('Scan & Add Beacon',
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
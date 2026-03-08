// lib/widgets/beacon_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/beacon.dart';

class BeaconCard extends StatelessWidget {
  final Beacon beacon;
  final Animation<double> pulseAnimation;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const BeaconCard({
    super.key,
    required this.beacon,
    required this.pulseAnimation,
    required this.onRename,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (beacon.status) {
      case BeaconStatus.safe:
        return const Color(0xFF00FF9F);
      case BeaconStatus.warning:
        return const Color(0xFFFFD166);
      case BeaconStatus.alarm:
        return const Color(0xFFFF4B6E);
      case BeaconStatus.disconnected:
        return Colors.white24;
    }
  }

  String get _statusLabel {
    switch (beacon.status) {
      case BeaconStatus.safe:
        return 'SAFE';
      case BeaconStatus.warning:
        return 'WARNING';
      case BeaconStatus.alarm:
        return 'ALARM';
      case BeaconStatus.disconnected:
        return 'OFFLINE';
    }
  }

  IconData get _statusIcon {
    switch (beacon.status) {
      case BeaconStatus.safe:
        return Icons.check_circle_rounded;
      case BeaconStatus.warning:
        return Icons.warning_rounded;
      case BeaconStatus.alarm:
        return Icons.crisis_alert_rounded;
      case BeaconStatus.disconnected:
        return Icons.bluetooth_disabled_rounded;
    }
  }

  String get _distanceText {
    if (beacon.status == BeaconStatus.disconnected) return '— m';
    final d = beacon.estimatedDistance;
    if (d < 1) return '<1 m';
    if (d > 50) return '>50 m';
    return '~${d.toStringAsFixed(1)} m';
  }

  @override
  Widget build(BuildContext context) {
    final isAlarm = beacon.status == BeaconStatus.alarm;
    final isDisconnected = beacon.status == BeaconStatus.disconnected;

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, _) {
        final pulseGlow = isAlarm ? pulseAnimation.value : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isAlarm
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF4B6E)
                          .withOpacity(0.15 + 0.2 * pulseGlow),
                      blurRadius: 20 + 10 * pulseGlow,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDisconnected
                    ? [
                        const Color(0xFF111124),
                        const Color(0xFF0D0D1E),
                      ]
                    : isAlarm
                        ? [
                            Color.lerp(
                              const Color(0xFF2D0A1A),
                              const Color(0xFF3D0A1A),
                              pulseGlow,
                            )!,
                            const Color(0xFF1A0D2E),
                          ]
                        : [
                            const Color(0xFF0F1E40),
                            const Color(0xFF0A1428),
                          ],
              ),
              border: Border.all(
                color: isAlarm
                    ? Color.lerp(
                        const Color(0xFFFF4B6E).withOpacity(0.3),
                        const Color(0xFFFF4B6E).withOpacity(0.7),
                        pulseGlow,
                      )!
                    : _statusColor.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                // ── Top row: name, status, menu ──────────────────────────────
                Row(
                  children: [
                    // Avatar / icon
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_statusIcon,
                          color: _statusColor, size: 24),
                    ),
                    const SizedBox(width: 12),

                    // Name + device ID
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            beacon.displayName,
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            beacon.deviceId,
                            style: GoogleFonts.robotoMono(
                                color: Colors.white24, fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Options menu
                    PopupMenuButton<String>(
                      color: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white38, size: 20),
                      onSelected: (val) {
                        if (val == 'rename') onRename();
                        if (val == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              const Icon(Icons.edit_rounded,
                                  color: Color(0xFF00D4FF), size: 16),
                              const SizedBox(width: 8),
                              Text('Rename',
                                  style: GoogleFonts.inter(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline_rounded,
                                  color: Color(0xFFFF4B6E), size: 16),
                              const SizedBox(width: 8),
                              Text('Remove',
                                  style: GoogleFonts.inter(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),

                // ── Bottom row: stats ──────────────────────────────────────
                Row(
                  children: [
                    _statChip(
                      icon: Icons.cell_tower_rounded,
                      label: 'RSSI',
                      value: isDisconnected
                          ? '—'
                          : '${beacon.averageRssi} dBm',
                      color: _statusColor,
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      icon: Icons.straighten_rounded,
                      label: 'Distance',
                      value: _distanceText,
                      color: _statusColor,
                    ),
                    const SizedBox(width: 8),
                    // Status badge
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          _statusLabel,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Last seen ───────────────────────────────────────────────
                if (beacon.lastSeen != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Last seen: ${_formatTime(beacon.lastSeen!)}',
                      style: GoogleFonts.inter(
                          color: Colors.white24, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white38, size: 11),
                const SizedBox(width: 4),
                Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 9,
                        letterSpacing: 0.8)),
              ],
            ),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.robotoMono(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt).inSeconds;
    if (diff < 5) return 'just now';
    if (diff < 60) return '${diff}s ago';
    return '${diff ~/ 60}m ago';
  }
}
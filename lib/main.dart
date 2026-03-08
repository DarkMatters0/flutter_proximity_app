// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/ble_service.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set BLE log level
  FlutterBluePlus.setLogLevel(LogLevel.warning);

  runApp(
    ChangeNotifierProvider(
      create: (_) => BleService(),
      child: const GuardianBleApp(),
    ),
  );
}

class GuardianBleApp extends StatelessWidget {
  const GuardianBleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuardianBLE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00D4FF),
          secondary: const Color(0xFF00FF9F),
          error: const Color(0xFFFF4B6E),
          surface: const Color(0xFF0F1B35),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        useMaterial3: true,
      ),
      home: const BluetoothGate(),
    );
  }
}

/// Checks if Bluetooth adapter is on before showing the app
class BluetoothGate extends StatelessWidget {
  const BluetoothGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BluetoothAdapterState>(
      stream: FlutterBluePlus.adapterState,
      initialData: BluetoothAdapterState.unknown,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == BluetoothAdapterState.on) {
          return const DashboardScreen();
        }
        return _BluetoothOffScreen(state: state);
      },
    );
  }
}

class _BluetoothOffScreen extends StatelessWidget {
  final BluetoothAdapterState? state;
  const _BluetoothOffScreen({this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4B6E).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bluetooth_disabled_rounded,
                      color: Color(0xFFFF4B6E), size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bluetooth is Off',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'GuardianBLE needs Bluetooth to track your beacons. Please turn on Bluetooth to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () async {
                    // On Android, try to turn on BT programmatically
                    await FlutterBluePlus.turnOn();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D4FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bluetooth_rounded),
                  label: const Text('Turn On Bluetooth',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
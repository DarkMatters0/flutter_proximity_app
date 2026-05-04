# ES 130 — Embedded Systems Project Documentation

# GuardianBLE: Child & Pet Anti-Lost Alarm System
### Updated Documentation — IoT Version

**Course:** ES 130 — Embedded Systems  
**Section:** BSCS-3A  
**Date:** May 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Objectives](#2-objectives)
3. [Scope](#3-scope)
4. [System Design](#4-system-design)
5. [Technical Requirements](#5-technical-requirements)
6. [Methodology](#6-methodology)
7. [Features & Capabilities](#7-features--capabilities)
8. [Applications](#8-applications)
9. [Timeline](#9-timeline)
10. [Budget](#10-budget)
11. [Risk Analysis and Mitigation](#11-risk-analysis-and-mitigation)
12. [Evaluation Criteria](#12-evaluation-criteria)
13. [Conclusion](#13-conclusion)
14. [References](#14-references)

---

## 1. Introduction

In busy public environments — parks, shopping malls, carnivals, and busy streets — parents and pet owners frequently face moments where a brief distraction can result in a child or animal wandering out of sight. This is not merely an inconvenience; child separation and pet loss carry significant safety, emotional, and financial consequences. The increasing density of public spaces and the prevalence of smartphone distractions have made this problem more acute in recent years.

The **GuardianBLE** system addresses this problem through a combination of embedded systems and Internet of Things (IoT) technology. The system consists of two main components:

- A **wearable ESP32 beacon device** attached to the child or pet
- A **GuardianBLE Android application** installed on the parent's or owner's smartphone

By continuously measuring the Bluetooth Low Energy (BLE) signal strength between these two components, the system monitors the physical separation in real time. When that separation exceeds a configurable threshold, both units immediately trigger an audible and haptic alarm — providing actionable alerts before separation becomes critical.

> **IoT Update Note:** The original proposal described two identical standalone ESP32 hardware units. The system has been updated to an IoT architecture where the **owner/parent unit is replaced by an Android smartphone** running the GuardianBLE Flutter application. This significantly reduces hardware cost, improves user experience through a visual dashboard, enables multiple beacon tracking, and allows future cloud integration without changing the child/pet device hardware.

### 1.1 Existing Solutions and Their Limitations

Several product categories attempt to address child and pet safety, but each carries significant limitations:

| Solution | Limitation |
|---|---|
| Physical leashes | Restrictive, impractical for older children, socially inappropriate |
| ID tags & microchips | Entirely passive — no real-time alert, only assists after loss |
| GPS trackers | Requires cellular subscription, internet, and drains battery quickly |
| Smartphone-only apps | Both parties need a smartphone; not suitable for young children or pets |
| Standalone BLE units | No visual dashboard, limited to basic buzzer feedback |

GuardianBLE fills this gap with a **low-cost, real-time proximity alarm** that requires no internet connection for core operation, no subscription, and responds within seconds of a threshold breach.

---

## 2. Objectives

The primary objectives of this project are as follows:

- To design and build a **BLE beacon device** using the ESP32 DevKit V1 as the child/pet wearable unit
- To develop a **Flutter-based Android application** (GuardianBLE) for the parent/owner's smartphone that performs real-time RSSI monitoring and distance estimation
- To implement **RSSI-based distance estimation** using a rolling average algorithm capable of detecting separation beyond approximately 10 meters
- To trigger **multi-modal alerts** — audible buzzer on the ESP32 device and alarm sound plus vibration on the smartphone — when the distance threshold is exceeded
- To enable the **ESP32 beacon to receive alarm commands** from the smartphone via BLE GATT, triggering its physical buzzer remotely
- To support **multiple beacon tracking** so one parent can monitor more than one child or pet simultaneously
- To operate as a **standalone system** with no internet connectivity required for proximity monitoring

---

## 3. Scope

### Included in This Project

- Design and assembly of the **ESP32 DevKit V1 beacon device** (child/pet unit) with active buzzer and latching push button
- **GuardianBLE Android application** (Flutter) for the parent/owner's smartphone with full BLE scanning, distance estimation, alarm management, and beacon registration UI
- BLE RSSI-based proximity monitoring with **three-state alert logic** (SAFE, WARNING, ALARM)
- **Remote buzzer control** — the smartphone sends alarm ON/OFF commands to the ESP32 via BLE GATT write
- **Persistent beacon storage** — registered beacons are saved across app restarts using SharedPreferences
- Audible alarm output via **active buzzer on the ESP32** and **alarm audio on the smartphone**
- **Haptic feedback** via smartphone vibration when alarm is triggered
- **Latching button** on the ESP32 device for manual local buzzer silence

### Excluded from This Project

- GPS or real-time location tracking
- Cloud connectivity, server infrastructure, or remote data logging
- Cellular communication (SIM card module)
- iOS application support (Android only)
- Li-Po battery integration (USB/power bank used for current prototype)
- Production-grade weatherproof enclosure

---

## 4. System Design

### 4.1 System Architecture

The updated IoT architecture consists of two nodes connected wirelessly via Bluetooth Low Energy:

```
┌──────────────────────────────────────────────────────────────┐
│                    PARENT / OWNER DEVICE                      │
│                                                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │              GuardianBLE Android App                 │  │
│   │                   (Flutter)                          │  │
│   │                                                      │  │
│   │  • Continuous BLE scan (RSSI measurement)            │  │
│   │  • Rolling 8-sample RSSI average                     │  │
│   │  • Distance estimation (path loss formula)           │  │
│   │  • SAFE / WARNING / ALARM state machine              │  │
│   │  • Phone alarm: looping sound + vibration            │  │
│   │  • Sends ALARM command to ESP32 via BLE GATT write   │  │
│   │  • Multi-beacon dashboard with rename/remove         │  │
│   └──────────────────────────────────────────────────────┘  │
└──────────────────────────────┬───────────────────────────────┘
                               │
                  Bluetooth Low Energy (BLE)
                  ← RSSI signal measured →
                  → ALARM command written →
                               │
┌──────────────────────────────▼───────────────────────────────┐
│                   CHILD / PET DEVICE                          │
│                                                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │              ESP32 DevKit V1 Beacon                  │  │
│   │                                                      │  │
│   │  • Continuously advertises BLE signal "GuardianBLE"  │  │
│   │  • Exposes BLE GATT alarm characteristic             │  │
│   │  • Activates buzzer on ALARM command (write 0x01)    │  │
│   │  • Deactivates buzzer on CLEAR command (write 0x00)  │  │
│   │  • Latching button silences buzzer locally           │  │
│   │  • Status LED: slow blink=standby, fast=alarm        │  │
│   └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 Process Flow

```
ESP32 powers on → starts BLE advertising ("GuardianBLE")
        │
        ▼
Parent opens app → scans → adds beacon → taps Start Monitoring
        │
        ▼
App continuously reads RSSI signal strength
        │
        ├──► RSSI > -65 dBm   (0–3m)    → 🟢 SAFE     — no action
        ├──► RSSI -65 to -80  (3–10m)   → 🟡 WARNING  — visual alert only
        ├──► RSSI < -80 dBm   (10m+)    → 🔴 ALARM    ──► phone alarms
        │                                          └──► ESP32 buzzer ON
        └──► No signal 15 sec            → ⚫ OFFLINE  ──► treated as alarm
                    │
        Child/pet comes back in range
                    │
                    ▼
        App writes 0x00 to ESP32 → buzzer OFF → phone alarm stops
                    │
                    ▼
        Back to monitoring loop
```

### 4.3 Hardware Description

**ESP32 DevKit V1 (38-pin)** serves as the child/pet beacon microcontroller, selected for its built-in BLE 4.2/5.0, dual-core 240 MHz processor, and micro-USB interface for power and programming.

**Active Buzzer** — driven directly by GPIO 25. Produces an audible alarm tone at 3.3V logic when the smartphone sends an alarm command via BLE.

**Latching Push Button** — connected to GPIO 26 with internal pull-up resistor. When pressed and latched ON, it mutes the buzzer locally on the child/pet device without stopping the alarm on the parent's phone.

**Built-in LED (GPIO 2)** — blinks slowly during normal standby operation and rapidly during an active alarm, providing visual feedback without additional components.

### 4.4 Wiring Diagram

```
ESP32 DevKit V1 (hold USB port facing down, left column)
┌─────────────────────────────┐
│                             │
│  GPIO 25 (6th pin left) ───►│──── Buzzer (+) positive
│  GND     (8th pin left) ───►│──── Buzzer (–) negative
│                             │
│  GPIO 26 (7th pin left) ───►│──── Button leg 1
│  GND     (8th pin left) ───►│──── Button leg 2
│                             │
│  GPIO 2  (built-in)        │──── Status LED (no wiring needed)
│                             │
│  Micro-USB                 │──── Power (laptop / power bank)
└─────────────────────────────┘
```

> No resistors needed. GPIO pins output 3.3V which is sufficient for a small active buzzer, and the ESP32's internal pull-up resistor handles the button.

### 4.5 BLE GATT Profile

| Attribute | Value |
|---|---|
| Device Name | `GuardianBLE` |
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Alarm Characteristic UUID | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Characteristic Properties | READ, WRITE |
| Write value `0x01` | Alarm ON — activate buzzer |
| Write value `0x00` | Alarm OFF — deactivate buzzer |

### 4.6 Distance Estimation Formula

The app uses the free-space path loss formula to estimate distance from RSSI:

```
distance (meters) = 10 ^ ((TxPower - RSSI) / (10 × n))

TxPower = -59 dBm   (calibrated signal strength at 1 meter)
n       = 2.5       (indoor environment path loss exponent)
```

A rolling 8-sample RSSI average is applied before distance estimation to smooth out momentary signal fluctuations and prevent false alarms.

### 4.7 Distance Threshold States

| State | RSSI Range | Estimated Distance | Action |
|---|---|---|---|
| 🟢 SAFE | Above -65 dBm | 0 – 3 meters | No action |
| 🟡 WARNING | -65 to -80 dBm | 3 – 10 meters | Visual alert on phone only |
| 🔴 ALARM | Below -80 dBm | 10+ meters | Phone alarm + ESP32 buzzer ON |
| ⚫ OFFLINE | No signal for 15 seconds | Out of range | Treated as alarm |

---

## 5. Technical Requirements

### 5.1 Hardware

| Component | Specification |
|---|---|
| Microcontroller | ESP32 DevKit V1 38-pin (built-in BLE 4.2/5.0) |
| Alarm Actuator | Active buzzer, 3.3V, driven from GPIO 25 |
| Silence Control | Latching push button, GPIO 26, internal pull-up |
| Status Indicator | Built-in LED GPIO 2 |
| Power | Micro-USB (laptop or 5V power bank) |
| Parent Device | Android smartphone (Android 8.0+) |

### 5.2 Software

| Component | Specification |
|---|---|
| ESP32 IDE | Arduino IDE 2.x |
| ESP32 Board Package | esp32 by Espressif Systems |
| ESP32 Language | C/C++ (Arduino framework) |
| BLE Libraries | `BLEDevice.h`, `BLEServer.h`, `BLEUtils.h`, `BLE2902.h` |
| App Framework | Flutter (Dart) |
| BLE Library | `flutter_blue_plus ^1.32.12` |
| State Management | Provider `^6.1.2` |
| Storage | SharedPreferences `^2.2.3` |
| Audio | audioplayers `^6.0.0` |
| Vibration | vibration `^2.0.0` |
| Fonts | google_fonts `^6.2.1` |

### 5.3 Tools

| Tool | Purpose |
|---|---|
| Arduino IDE 2.x | ESP32 firmware development and upload |
| Serial Monitor | RSSI logging and firmware debugging (115200 baud) |
| Flutter SDK | Android app development and deployment |
| Android Debug Bridge (ADB) | App installation via USB |
| Wokwi | Online ESP32 simulator for initial firmware testing |
| Git | Version control for firmware and app source code |

---

## 6. Methodology

### Phase 1 — Literature Review and Requirement Analysis
Review of BLE RSSI-based proximity detection methods, path loss models, and existing child/pet safety systems. Finalize hardware component selection and system architecture.

### Phase 2 — ESP32 Firmware Development
Write and test the BLE advertising firmware. Implement the GATT server with the alarm characteristic. Test buzzer control via BLE write commands. Validate with Serial Monitor.

### Phase 3 — Flutter App Development
Build the GuardianBLE Android application. Implement BLE scanning, RSSI reading, rolling average filtering, state machine logic, alarm triggering, and the GATT write for remote buzzer control.

### Phase 4 — Hardware Assembly
Wire the active buzzer and latching button to the ESP32 DevKit V1. Test wiring with continuity checks before powering on.

### Phase 5 — System Integration
Pair the Flutter app with the ESP32 beacon. Test the full chain: phone detects beacon → walks out of range → phone alarms → ESP32 buzzer activates → walks back → all alarms clear.

### Phase 6 — Testing and Evaluation
Conduct distance accuracy testing at 1m, 3m, 5m, and 10m intervals. Test alarm response time. Test in different environments (open space vs. indoor with walls). Run extended reliability tests.

---

## 7. Features & Capabilities

### 📱 Android App (Parent/Owner Device)

| Feature | Description |
|---|---|
| Real-time BLE scanning | Continuously monitors RSSI signal strength from the beacon |
| Distance estimation | Calculates approximate distance in meters using path loss formula |
| Rolling RSSI average | 8-sample window smooths fluctuations and prevents false alarms |
| Three proximity states | SAFE 🟢, WARNING 🟡, ALARM 🔴 with color-coded visual indicators |
| Phone-side alarm | Looping alarm sound + repeating vibration pattern when triggered |
| Remote buzzer control | Sends BLE GATT write to activate/deactivate ESP32 buzzer wirelessly |
| Multiple beacon support | Track more than one child or pet simultaneously |
| Persistent storage | Registered beacons saved and restored across app restarts |
| Rename & manage beacons | Assign custom names (e.g., "Nico", "Dog Max") to each beacon |
| Bluetooth gate | Handles Bluetooth being off with a prompt to enable it |
| Scan restart timer | Restarts BLE scan every 20 seconds to prevent Android throttling |
| Disconnect watchdog | Marks beacons offline if not seen for 15 seconds |

### 📡 ESP32 Beacon (Child/Pet Device)

| Feature | Description |
|---|---|
| BLE advertising | Continuously broadcasts signal named "GuardianBLE" |
| GATT server | Exposes alarm characteristic for the phone to write commands to |
| Remote buzzer | Activates buzzer when phone writes 0x01, deactivates on 0x00 |
| Latching button silence | Press to mute buzzer locally without stopping the phone alarm |
| Auto-reconnect | Restarts advertising automatically after phone disconnects |
| Status LED | Slow blink = standby, fast blink = alarm active |

### 🔒 System-Wide

| Feature | Description |
|---|---|
| No internet required | Operates entirely over BLE — no Wi-Fi or mobile data needed |
| No subscription | Free to operate after hardware purchase |
| Instant response | Alarm triggers within seconds of threshold breach |
| Low power BLE | Uses BLE low-power scan mode during monitoring |
| Standalone beacon | Child/pet device requires no smartphone of its own |

---

## 8. Applications

- **Child safety in public spaces** — parks, playgrounds, shopping malls, supermarkets, and public transportation
- **Pet management** — dog walking, outdoor exercise areas, and off-leash parks
- **Crowded event safety** — carnivals, festivals, concerts, and street markets
- **Elderly care** — monitoring wandering risk for elderly individuals with cognitive impairments in care facilities
- **School and daycare field trips** — alerting teachers when a student moves out of range
- **Educational demonstration** — practical embedded systems and IoT project demonstrating BLE communication, RSSI sensing, real-time firmware, and mobile app development

---

## 9. Timeline

| Period | Phase | Activities |
|---|---|---|
| Weeks 1–2 | Requirement Analysis | Literature review, component selection, architecture finalization |
| Weeks 3–4 | Firmware Development | ESP32 BLE advertising, GATT server, buzzer control |
| Weeks 5–7 | App Development | Flutter app BLE scanning, state machine, alarm, GATT write |
| Week 8 | Hardware Assembly | Wiring buzzer and button, breadboard assembly |
| Week 9 | System Integration | End-to-end testing of full alarm chain |
| Week 10 | Testing & Evaluation | Distance accuracy, response time, reliability, and user testing |

---

## 10. Budget (Estimated)

| Item | Qty | Unit Cost (₱) | Total (₱) | Notes |
|---|---|---|---|---|
| ESP32 DevKit V1 38-pin | 1 | 250 | 250 | Child/pet beacon device |
| Active Buzzer (3.3V) | 1 | 30 | 30 | On ESP32 device |
| Latching Push Button | 1 | 25 | 25 | Silence button on ESP32 device |
| Breadboard | 1 | 80 | 80 | For prototyping |
| Jumper Wires | 1 set | 50 | 50 | Connecting components |
| Android Smartphone | — | — | — | Parent already owns device |
| Miscellaneous | — | — | 200 | USB cables, soldering, etc. |
| **Total** | | | **₱635** | |

> **Cost comparison:** The original two-unit standalone ESP32 design was estimated at ₱2,375. The IoT architecture (one ESP32 + smartphone app) reduces hardware cost to approximately ₱635 — a **73% cost reduction** — while adding a full visual dashboard, multi-beacon support, and remote buzzer control.

---

## 11. Risk Analysis and Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| Inaccurate RSSI due to signal interference (walls, crowds, metal) | False alarms or missed alerts | Rolling 8-sample RSSI average; calibration testing in multiple environments |
| BLE signal instability or drops | System fails to detect distance | Advertising/scanning model with no persistent connection; 15-second disconnect watchdog |
| Android BLE scan throttling (OS kills scan after ~25s) | Beacon appears offline falsely | Scan restart timer every 20 seconds to refresh before OS throttles |
| ESP32 buzzer not activating (GATT write fails) | No physical alarm on device | GATT write wrapped in try/catch; error logged; phone alarm still sounds |
| Battery drain on smartphone | Reduced monitoring duration | BLE low-power scan mode; user advised to keep phone charged |
| User forgets to tap Start Monitoring | No proximity monitoring active | Persistent status bar message; clear UI state indication |
| Accidental button press on ESP32 | Alarm silenced unintentionally | Latching button requires deliberate press; phone alarm continues regardless |
| Component failure (buzzer, button) | Partial alarm functionality | Pre-deployment hardware test; phone alarm still functions independently |

---

## 12. Evaluation Criteria

| Evaluation Area | Measurement Method | Success Indicator |
|---|---|---|
| RSSI Distance Accuracy | Compare estimated vs. actual distance at 1m, 3m, 5m, 10m | Threshold triggers within ±20% of actual distance |
| Alarm Response Time | Time from threshold breach to alarm activation | Alarm activates within 1–3 seconds |
| Remote Buzzer Activation | Time from alarm trigger to ESP32 buzzer ON | Buzzer activates within 5 seconds of alarm state |
| System Reliability | 2-hour continuous operation test indoors and outdoors | No unexpected crashes or missed alarms |
| Signal Stability | Test with obstacles (walls, crowds) | Minimal false alarms from rolling average smoothing |
| Multi-Beacon Support | Register 2+ beacons and monitor simultaneously | Each beacon tracked and alarmed independently |
| Button Silence | Press latching button during alarm | Buzzer mutes locally; phone alarm continues |
| App Persistence | Close and reopen app | Registered beacons restored from storage |
| User Usability | 3–5 user testing sessions | Users can add and monitor a beacon without instructions |

---

## 13. Conclusion

GuardianBLE demonstrates the practical integration of **embedded systems and IoT technology** to address a genuine real-world safety problem. By combining a low-cost ESP32 BLE beacon with a feature-rich Android monitoring application, the system delivers real-time proximity alerts without requiring internet connectivity, a subscription service, or specialized hardware for the parent/owner.

The IoT update significantly improves upon the original standalone hardware proposal — replacing one ESP32 unit with a smartphone application reduces cost by over 70%, adds a visual monitoring dashboard, enables multiple beacon tracking, and opens a path for future cloud integration for remote monitoring and alert history logging.

The system covers core embedded systems competencies including microcontroller programming, BLE wireless communication, RSSI-based signal processing, real-time state machine firmware, and cross-platform mobile development — making it both a practical safety product and a comprehensive educational embedded systems project.

---

## 14. References

- Espressif Systems. (2023). *ESP32 Technical Reference Manual*. https://www.espressif.com/sites/default/files/documentation/esp32_technical_reference_manual_en.pdf
- Bluetooth SIG. (2023). *Bluetooth Core Specification 5.4*. https://www.bluetooth.com/specifications/specs/
- Flutter. (2024). *Flutter Documentation*. https://docs.flutter.dev
- flutter_blue_plus. (2024). *flutter_blue_plus pub.dev package*. https://pub.dev/packages/flutter_blue_plus
- Rappaport, T. S. (2002). *Wireless Communications: Principles and Practice* (2nd ed.). Prentice Hall.
- Arduino. (2024). *Arduino IDE 2 Documentation*. https://docs.arduino.cc/software/ide-v2

---

*GuardianBLE — Child & Pet Anti-Lost Alarm System | ES 130 Embedded Systems | BSCS-3A | 2026*

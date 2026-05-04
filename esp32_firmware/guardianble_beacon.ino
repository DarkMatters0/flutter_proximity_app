// GuardianBLE — ESP32 Beacon Firmware
// Board  : ESP32 DevKit V1 (38-pin)
// IDE    : Arduino IDE 2.x with "esp32 by Espressif Systems" board package
//
// Wiring:
//   GPIO 25  → Active buzzer (+); GND → buzzer (-)
//   GPIO 26  → Latching push button leg 1; GND → leg 2  (internal pull-up used)
//   GPIO 2   → Built-in LED (no external wiring needed)
//   Micro-USB → Power (laptop or 5V power bank)
//
// BLE GATT profile:
//   Device name     : GuardianBLE
//   Service UUID    : 4fafc201-1fb5-459e-8fcc-c5c9c331914b
//   Characteristic  : beb5483e-36e1-4688-b7f5-ea07361b26a8  (READ + WRITE)
//   Write 0x01      → Alarm ON  (buzzer sounds, LED fast blink)
//   Write 0x00      → Alarm OFF (buzzer silent, LED slow blink)

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ─── Pin definitions ─────────────────────────────────────────────────────────

#define BUZZER_PIN 25
#define LED_PIN    2
#define BUTTON_PIN 26

// ─── BLE UUIDs — must match Flutter app constants exactly ────────────────────

#define SERVICE_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define ALARM_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ─── State ───────────────────────────────────────────────────────────────────

bool alarmActive = false;
BLEServer*         pServer    = nullptr;
BLECharacteristic* pAlarmChar = nullptr;

unsigned long lastBlink = 0;
bool          ledState  = false;

// ─── BLE server callbacks ────────────────────────────────────────────────────

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    Serial.println("[BLE] Phone connected");
  }

  void onDisconnect(BLEServer* pServer) override {
    Serial.println("[BLE] Phone disconnected — restarting advertising");
    // Short delay prevents rapid reconnect storms on some Android stacks
    delay(500);
    BLEDevice::startAdvertising();
  }
};

// ─── Characteristic callbacks ─────────────────────────────────────────────────

class AlarmCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = pChar->getValue();
    if (val.length() == 0) return;

    if (val[0] == 0x01) {
      alarmActive = true;
      Serial.println("[ALARM] ON — buzzer activated by phone");
    } else if (val[0] == 0x00) {
      alarmActive = false;
      Serial.println("[ALARM] OFF — buzzer deactivated by phone");
    }
  }
};

// ─── Setup ───────────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_PIN,    OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_PIN,    LOW);

  // Initialise BLE with the advertised device name
  BLEDevice::init("GuardianBLE");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create the alarm service and characteristic
  BLEService* pService = pServer->createService(SERVICE_UUID);

  pAlarmChar = pService->createCharacteristic(
    ALARM_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );
  pAlarmChar->setCallbacks(new AlarmCallbacks());
  pAlarmChar->setValue(std::vector<uint8_t>{0x00}); // initial value = OFF

  pService->start();

  // Start advertising so the Flutter app can discover and connect to this device
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("[GuardianBLE] Beacon started — advertising...");
}

// ─── Main loop ───────────────────────────────────────────────────────────────

void loop() {
  // Latching button: LOW = button is latched in the pressed position → mute buzzer
  bool buttonLatched = (digitalRead(BUTTON_PIN) == LOW);

  // Buzzer: sound only when alarm is active AND button has not silenced it locally
  digitalWrite(BUZZER_PIN, (alarmActive && !buttonLatched) ? HIGH : LOW);

  // LED blink: fast (100 ms) during alarm, slow (1000 ms) during standby
  unsigned long now          = millis();
  unsigned long blinkInterval = alarmActive ? 100UL : 1000UL;
  if (now - lastBlink >= blinkInterval) {
    lastBlink = now;
    ledState  = !ledState;
    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
  }

  delay(10);
}

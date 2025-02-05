ESP8266 & Flutter LED Controller

Опис проєкту

Цей проєкт поєднує Flutter-додаток та ESP8266 (Arduino) для віддаленого керування світлодіодом і моніторингу сенсорних даних через WebSocket та HTTP-запити.

Функціонал:

- Керування світлодіодом через WebSocket-з'єднання.
- Отримання даних з аналогового датчика через HTTP.
- Отримання температури та вологості з датчика DHT через HTTP.
- Відображення поточних значень та історії вимірювань у додатку.
- Різні режими роботи світлодіода: Manual, Pulse, Strobe, Gradient.

Використані технології:

Flutter (інтерфейс користувача)
Provider (менеджмент стану)
WebSocket (керування світлодіодом у реальному часі)
HTTP-запити (отримання даних із сенсорів)
ESP8266 (Arduino) (виконання команд та передача даних)

Код для Arduino ide

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <WebSocketsServer.h>
#include <DHT.h>

#define DHTPIN D4     // Пін, до якого підключено DHT
#define DHTTYPE DHT22 // DHT 22 (AM2302)

const char* ssid = "";
const char* password = "";

ESP8266WebServer server(80);
WebSocketsServer webSocket = WebSocketsServer(81);
DHT dht(DHTPIN, DHTTYPE);

// Змінні для керування LED
enum LedMode { MANUAL, PULSE, STROBE, GRADIENT };
LedMode currentMode = MANUAL;
unsigned long lastUpdate = 0;
int pwmValue = 0;
bool increasing = true;

void handleAdcRead() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET");
  
  int sensorValue = analogRead(A0);
  server.send(200, "text/plain", String(sensorValue));
}

void handleDhtRead() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET");
  
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  
  if (isnan(h) || isnan(t)) {
    server.send(500, "text/plain", "Error reading DHT");
    return;
  }
  
  String data = String(t) + "," + String(h);
  server.send(200, "text/plain", data);
}

void webSocketEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_TEXT:
      String message = (char*)payload;
      
      if (message.startsWith("MODE:")) {
        String mode = message.substring(5);
        if (mode == "Manual") currentMode = MANUAL;
        else if (mode == "Pulse") currentMode = PULSE;
        else if (mode == "Strobe") currentMode = STROBE;
        else if (mode == "Gradient") currentMode = GRADIENT;
        
        String response = "MODE_SET:" + mode;
webSocket.sendTXT(num, response);
      }
      else if (message == "ON" && currentMode == MANUAL) {
        digitalWrite(LED_BUILTIN, LOW);
        webSocket.sendTXT(num, "LED_ON");
      }
      else if (message == "OFF" && currentMode == MANUAL) {
        digitalWrite(LED_BUILTIN, HIGH);
        webSocket.sendTXT(num, "LED_OFF");
      }
      break;
  }
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
  Serial.begin(115200);
  dht.begin();
  
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connecting to WiFi...");
  }

  Serial.println("Connected to WiFi");
  Serial.println(WiFi.localIP());

  server.on("/adcread", handleAdcRead);
  server.on("/dhtread", handleDhtRead);
  server.begin();

  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
}

void loop() {
  server.handleClient();
  webSocket.loop();
  
  // Керування LED залежно від режиму
  unsigned long now = millis();
  
  switch(currentMode) {
    case PULSE:
      if (now - lastUpdate > 20) {
        if (increasing) {
          pwmValue += 5;
          if (pwmValue >= 1023) increasing = false;
        } else {
          pwmValue -= 5;
          if (pwmValue <= 0) increasing = true;
        }
        analogWrite(LED_BUILTIN, 1023 - pwmValue);
        lastUpdate = now;
      }
      break;
      
    case STROBE:
      if (now - lastUpdate > 100) {
        digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
        lastUpdate = now;
      }
      break;
      
    case GRADIENT:
      // Додати логіку для RGB світлодіода
      break;
      
    case MANUAL:
    default:
      break;
  }
}

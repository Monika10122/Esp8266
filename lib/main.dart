import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => LedController(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: LedControlScreen(),
    );
  }
}

class LedController extends ChangeNotifier {
  final String wsUrl = "ws://192.168.0.20:81";
  final String httpUrl = "http://192.168.0.20/adcread";
  final String dhtUrl = "http://192.168.0.20/dhtread"; // URL для даних з DHT

  WebSocketChannel? webSocketChannel;
  bool isConnected = false;
  bool ledState = false;
  double sensorValue = 0;
  double temperature = 0;
  double humidity = 0;
  List<double> sensorHistory = [];
  String ledMode = "Manual"; // Режими: Manual, Pulse, Strobe, Gradient

  LedController() {
    _connect();
  }

  Future<void> _connect() async {
    try {
      webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      isConnected = true;
      notifyListeners();

      webSocketChannel!.stream.listen(
        (message) => _handleMessage(message),
        onError: (_) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );

      _startFetchingSensorData();
      _startFetchingDhtData();
    } catch (e) {
      print("Connection error: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    isConnected = false;
    notifyListeners();
  }

  void _handleMessage(String message) {
    if (message == "LED_ON") {
      ledState = true;
    } else if (message == "LED_OFF") {
      ledState = false;
    }
    notifyListeners();
  }

  void _updateLedState(bool newState) {
    if (isConnected && webSocketChannel != null) {
      final command = newState ? "ON" : "OFF";
      webSocketChannel!.sink.add(command);
      ledState = newState;
      print('LED $command');
      notifyListeners();
    }
  }

  void setLedMode(String mode) {
    ledMode = mode;
    notifyListeners();
    if (isConnected && webSocketChannel != null) {
      webSocketChannel!.sink.add("MODE:$mode");
    }
  }

  void _startFetchingSensorData() {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isConnected) return;

      try {
        final response = await http.get(Uri.parse(httpUrl))
            .timeout(const Duration(seconds: 5), onTimeout: () {
          print("Request timed out");
          return http.Response('Timeout', 408);
        });

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200) {
          final newValue = double.tryParse(response.body) ?? 0.0;
          sensorValue = newValue;

          // Додаємо значення в історію (зберігаємо останні 10 значень)
          sensorHistory.insert(0, newValue);
          if (sensorHistory.length > 10) sensorHistory.removeLast();

          // Автоматичне керування світлодіодом (якщо режим Manual)
          if (ledMode == "Manual") {
            if (newValue >= 100) {
              _updateLedState(false);
            } else {
              _updateLedState(true);
            }
          }
        } else {
          print('HTTP Error: ${response.statusCode}');
        }
      } catch (e) {
        print("Sensor error details: $e");
        sensorValue = -1.0;
      }
      notifyListeners();
    });
  }

  void _startFetchingDhtData() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!isConnected) return;

      try {
        final response = await http.get(Uri.parse(dhtUrl))
            .timeout(const Duration(seconds: 5), onTimeout: () {
          print("DHT Request timed out");
          return http.Response('Timeout', 408);
        });

        print('DHT Response status: ${response.statusCode}');
        print('DHT Response body: ${response.body}');

        if (response.statusCode == 200) {
          final data = response.body.split(',');
          temperature = double.tryParse(data[0]) ?? 0.0;
          humidity = double.tryParse(data[1]) ?? 0.0;
        } else {
          print('DHT HTTP Error: ${response.statusCode}');
        }
      } catch (e) {
        print("DHT error details: $e");
        temperature = -1.0;
        humidity = -1.0;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    webSocketChannel?.sink.close(status.goingAway);
    super.dispose();
  }
}

class LedControlScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ledController = Provider.of<LedController>(context);

    return Scaffold(
      backgroundColor: Colors.blueGrey,
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 69, 90, 101),
        title: const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "ESP8266 Functionality",
            style: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => ledController.setLedMode(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "Manual",
                child: Text("Manual"),
              ),
              const PopupMenuItem(
                value: "Pulse",
                child: Text("Pulse"),
              ),
              const PopupMenuItem(
                value: "Strobe",
                child: Text("Strobe"),
              ),
              const PopupMenuItem(
                value: "Gradient",
                child: Text("Gradient"),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildConnectionStatus(ledController),
            const SizedBox(height: 16),
            _buildLedSwitch(ledController),
            const SizedBox(height: 16),
            _buildSensorCard(ledController),
            const SizedBox(height: 16),
            _buildDhtCard(ledController),
            const SizedBox(height: 16),
            _buildSensorHistory(ledController),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(LedController controller) {
    return Text(
      controller.isConnected 
          ? "Connected to ESP8266" 
          : "Disconnected from ESP8266",
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: controller.isConnected 
            ? const Color.fromARGB(255, 35, 82, 37) 
            : const Color.fromARGB(255, 113, 28, 22),
      ),
    );
  }

  Widget _buildLedSwitch(LedController controller) {
    return SwitchListTile(
      title: const Text("LED State"),
      value: controller.ledState,
      onChanged: controller.isConnected && controller.ledMode == "Manual"
          ? (value) => controller._updateLedState(value) 
          : null,
    );
  }

  Widget _buildSensorCard(LedController controller) {
    return Card(
      color: Colors.white,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              "Current Sensor Value:",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (controller.sensorValue >= 0)
                  ? controller.sensorValue.toStringAsFixed(2)
                  : "Error",
              style: TextStyle(
                fontSize: 24,
                color: controller.sensorValue >= 100 
                    ? Colors.red 
                    : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDhtCard(LedController controller) {
    return Card(
      color: Colors.white,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              "Temperature & Humidity:",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Temp: ${controller.temperature.toStringAsFixed(2)}°C",
              style: const TextStyle(
                fontSize: 20,
                color: Colors.blue,
              ),
            ),
            Text(
              "Humidity: ${controller.humidity.toStringAsFixed(2)}%",
              style: const TextStyle(
                fontSize: 20,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorHistory(LedController controller) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Sensor History:",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: controller.sensorHistory.length,
                  itemBuilder: (context, index) {
                    final value = controller.sensorHistory[index];
                    return ListTile(
                      title: Text(
                        value.toStringAsFixed(2),
                        style: TextStyle(
                          color: value >= 100 ? Colors.red : Colors.blue,
                        ),
                      ),
                      trailing: Text(
                        value >= 100 ? "⚡ OFF" : "💡 ON",
                        style: TextStyle(
                          color: value >= 100 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
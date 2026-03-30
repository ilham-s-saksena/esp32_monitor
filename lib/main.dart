import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 IoT Monitor',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF05070D),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF101522),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white.withOpacity(0.92),
              displayColor: Colors.white,
            ),
      ),
      home: SetupPage(),
    );
  }
}

class SetupPage extends StatefulWidget {
  @override
  _SetupPageState createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {

  String ssid = "Unknown";
  String ip = "Unknown";

  List<String> devices = [];

  @override
  void initState() {
    super.initState();
    loadWifiInfo();
  }

  Future<void> loadWifiInfo() async {

    await Permission.location.request();

    final info = NetworkInfo();

    final wifiName = await info.getWifiName();
    final wifiIP = await info.getWifiIP();

    print("SSID: $wifiName");
    print("IP: $wifiIP");

    setState(() {
      ssid = wifiName ?? "Hotspot";
      ip = wifiIP ?? "192.168.43.1";
    });

  }

  void openHotspotSettings() async {

    try {
      final intent = AndroidIntent(
        action: 'android.settings.TETHER_SETTINGS',
      );

      await intent.launch();
    } catch (e) {
      final fallback = AndroidIntent(
        action: 'android.settings.SETTINGS',
      );

      await fallback.launch();
    }
  }

  bool isScanning = false;

  Future<void> scanNetwork() async {

    if (isScanning) return;

    setState(() {
      isScanning = true;
      devices.clear();
    });

    try {

      RawDatagramSocket socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      socket.broadcastEnabled = true;

      socket.listen((event) {

        if (event == RawSocketEvent.read) {

          Datagram? dg = socket.receive();

          if (dg != null) {

            String msg = String.fromCharCodes(dg.data);

            if (msg.startsWith("ESP32")) {

              String ip = dg.address.address;

              if (!devices.contains(ip)) {

                setState(() {
                  devices.add(ip);
                });

              }

            }

          }

        }

      });

      // broadcast ke subnet hotspot
      final broadcast = InternetAddress("192.168.43.255");

      for (int i = 0; i < 3; i++) {

        socket.send(
          "DISCOVER_ESP32".codeUnits,
          broadcast,
          4210,
        );

        await Future.delayed(Duration(milliseconds: 200));

      }

      await Future.delayed(Duration(seconds: 2));

      socket.close();

    } catch (e) {

      print("Discovery error: $e");

    }

    setState(() {
      isScanning = false;
    });

  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "ESP32 Setup",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF05070D), Color(0xFF0C1220)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                Text(
                  "Instruksi Setup",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Nyalakan hotspot dengan konfigurasi berikut:",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 14),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.wifi_tethering,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Hotspot Mobile",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                "SSID : IOT\nPassword : 12345678",
                                style: TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: openHotspotSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text("Buka Pengaturan Hotspot"),
                  ),
                ),

                const SizedBox(height: 18),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.lightBlueAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.wifi,
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "WiFi Saat Ini",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "SSID : $ssid",
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                "IP : $ip",
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isScanning ? null : scanNetwork,
                          child: isScanning
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Scan"),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  "Perangkat Ditemukan",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: devices.isEmpty
                      ? Center(
                          child: Text(
                            "Belum ada perangkat ditemukan",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (context, index) {

                            if (index >= devices.length) return const SizedBox();

                            final deviceIP = devices[index];

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.15),
                                  child: Icon(
                                    Icons.memory,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  deviceIP,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  "ESP32 Device",
                                  style: TextStyle(fontSize: 13),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white54,
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MonitorPage(ip: deviceIP),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                )

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MonitorPage extends StatefulWidget {

  final String ip;

  MonitorPage({required this.ip});

  @override
  _MonitorPageState createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {

  double distance = 0;
  double weight = 0;
  double temperature = 0;

  Future<void> openWeb() async {
    final url = Uri.parse("http://${widget.ip}/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> fetchData() async {

    try{

      final response = await http.get(
        Uri.parse("http://${widget.ip}/data")
      );

      if(response.statusCode == 200){

        final data = json.decode(response.body);

        setState(() {
          distance = data['distance'].toDouble();
          weight = data['weight'].toDouble();
          temperature = data['temperature'].toDouble();
        });

      }

    }catch(e){}

  }

  late Timer timer;

  @override
  void initState() {
    super.initState();

    fetchData();

    timer = Timer.periodic(
      Duration(seconds: 1),
      (timer) => fetchData(),
    );
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Widget sensorCard(String title,String value){

    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
              ),
            ),

            SizedBox(height:10),

            Text(
              value,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            )

          ],
        ),
      ),
    );

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "ESP32 Monitor",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF05070D), Color(0xFF0C1220)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [

              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      "Distance",
                      "${distance.toStringAsFixed(1)} cm",
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      "Weight",
                      "${weight.toStringAsFixed(2)} kg",
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      "Temperature",
                      "${temperature.toStringAsFixed(1)} °C",
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: openWeb,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text("Lihat di Web"),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

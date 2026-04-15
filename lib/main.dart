import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white.withValues(alpha: 0.92),
          displayColor: Colors.white,
        ),
      ),
      home: const SetupPage(),
    );
  }
}

class NetworkDetails {
  const NetworkDetails({
    required this.ssid,
    required this.ip,
    this.subnet,
    this.broadcast,
  });

  final String ssid;
  final String ip;
  final String? subnet;
  final InternetAddress? broadcast;
}

class DiscoveryConfig {
  const DiscoveryConfig({
    this.port = 4210,
    this.message = 'DISCOVER_ESP32',
    this.responsePrefix = 'ESP32',
    this.timeout = const Duration(seconds: 4),
    this.batchSize = 24,
    this.batchPause = const Duration(milliseconds: 30),
    this.broadcastRepeats = 2,
  });

  final int port;
  final String message;
  final String responsePrefix;
  final Duration timeout;
  final int batchSize;
  final Duration batchPause;
  final int broadcastRepeats;
}

class Esp32DiscoveryService {
  Esp32DiscoveryService({
    NetworkInfo? networkInfo,
    DiscoveryConfig config = const DiscoveryConfig(),
  }) : _networkInfo = networkInfo ?? NetworkInfo(),
       _config = config;

  final NetworkInfo _networkInfo;
  final DiscoveryConfig _config;

  Future<NetworkDetails?> getNetworkInfo() async {
    final permission = await Permission.location.request();
    if (!permission.isGranted) {
      debugPrint('[DISCOVERY] Location permission denied');
      return null;
    }

    final ssid = _sanitizeSsid(await _networkInfo.getWifiName());
    final ip = await _networkInfo.getWifiIP();
    final subnet = await _networkInfo.getWifiSubmask();

    if (!_isValidIpv4(ip)) {
      debugPrint('[DISCOVERY] No active WiFi IPv4 address');
      return null;
    }

    final deviceIp = ip!;
    final broadcast = calculateBroadcast(deviceIp, subnet);
    debugPrint(
      '[DISCOVERY] SSID=$ssid IP=$deviceIp SUBNET=${subnet ?? "unknown"}',
    );
    debugPrint('[DISCOVERY] Broadcast=${broadcast?.address ?? "unavailable"}');

    return NetworkDetails(
      ssid: ssid ?? 'Unknown',
      ip: deviceIp,
      subnet: subnet,
      broadcast: broadcast,
    );
  }

  InternetAddress? calculateBroadcast(String ip, String? subnet) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(subnet)) {
      return null;
    }

    final ipParts = _parseIpv4(ip);
    final subnetParts = _parseIpv4(subnet!);
    if (ipParts == null || subnetParts == null) {
      return null;
    }

    final broadcastParts = List<int>.generate(
      4,
      (index) => ipParts[index] | (~subnetParts[index] & 0xFF),
    );

    return InternetAddress(broadcastParts.join('.'));
  }

  StreamSubscription<RawSocketEvent> listenResponses({
    required RawDatagramSocket socket,
    required Set<String> discovered,
    void Function(String ip)? onDeviceFound,
  }) {
    return socket.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final payload = utf8
              .decode(datagram!.data, allowMalformed: true)
              .trim();
          final sourceIp = datagram.address.address;

          debugPrint('[DISCOVERY] Response from $sourceIp payload="$payload"');

          if (!payload.startsWith(_config.responsePrefix)) {
            continue;
          }

          if (discovered.add(sourceIp)) {
            debugPrint('[DISCOVERY] Device accepted: $sourceIp');
            onDeviceFound?.call(sourceIp);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[DISCOVERY] Socket listen error: $error');
      },
      cancelOnError: false,
    );
  }

  Future<void> sendDiscovery(
    RawDatagramSocket socket, {
    required Iterable<InternetAddress> targets,
  }) async {
    final payload = utf8.encode(_config.message);

    for (final target in targets) {
      try {
        final sent = socket.send(payload, target, _config.port);
        debugPrint(
          '[DISCOVERY] Sent $sent bytes to ${target.address}:${_config.port}',
        );
      } on SocketException catch (error) {
        debugPrint('[DISCOVERY] Send failed to ${target.address}: $error');
      } catch (error) {
        debugPrint(
          '[DISCOVERY] Unexpected send error to ${target.address}: $error',
        );
      }
    }
  }

  Future<void> scanSubnet(
    RawDatagramSocket socket, {
    required String deviceIp,
    String? subnet,
  }) async {
    final hosts = _buildScanTargets(deviceIp, subnet);

    if (hosts.isEmpty) {
      debugPrint('[DISCOVERY] No subnet targets generated');
      return;
    }

    debugPrint(
      '[DISCOVERY] Scanning ${hosts.length} targets in batches of ${_config.batchSize}',
    );

    for (var start = 0; start < hosts.length; start += _config.batchSize) {
      final end = start + _config.batchSize > hosts.length
          ? hosts.length
          : start + _config.batchSize;
      final batch = hosts.sublist(start, end);

      await Future.wait(
        batch.map(
          (host) async =>
              sendDiscovery(socket, targets: [InternetAddress(host)]),
        ),
      );

      if (end < hosts.length) {
        await Future.delayed(_config.batchPause);
      }
    }
  }

  Future<List<String>> discoverDevices({
    void Function(String ip)? onDeviceFound,
  }) async {
    final info = await getNetworkInfo();
    if (info == null) {
      return const [];
    }

    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final discovered = <String>{};

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      debugPrint(
        '[DISCOVERY] UDP socket bound on ${socket.address.address}:${socket.port}',
      );

      subscription = listenResponses(
        socket: socket,
        discovered: discovered,
        onDeviceFound: onDeviceFound,
      );

      final broadcastTargets = <InternetAddress>{
        if (info.broadcast != null) info.broadcast!,
        InternetAddress('255.255.255.255'),
      };

      for (var attempt = 0; attempt < _config.broadcastRepeats; attempt++) {
        debugPrint(
          '[DISCOVERY] Broadcast attempt ${attempt + 1}/${_config.broadcastRepeats}',
        );
        await sendDiscovery(socket, targets: broadcastTargets);
      }

      await scanSubnet(socket, deviceIp: info.ip, subnet: info.subnet);

      await Future.delayed(_config.timeout);
      return discovered.toList()..sort();
    } on SocketException catch (error) {
      debugPrint('[DISCOVERY] Failed to bind UDP socket: $error');
      return const [];
    } catch (error) {
      debugPrint('[DISCOVERY] Discovery failed: $error');
      return const [];
    } finally {
      await subscription?.cancel();
      socket?.close();
      debugPrint('[DISCOVERY] Discovery finished, socket closed');
    }
  }

  List<String> _buildScanTargets(String ip, String? subnet) {
    final ipParts = _parseIpv4(ip);
    if (ipParts == null) {
      return const [];
    }

    final subnetParts = _parseIpv4(subnet);
    if (subnetParts == null) {
      final fallback = List<String>.generate(
        254,
        (index) => '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.${index + 1}',
      ).where((host) => host != ip).toList();

      debugPrint(
        '[DISCOVERY] Subnet unavailable, fallback scan on /24 segment',
      );
      return fallback;
    }

    final prefixLength = _prefixLength(subnetParts);
    if (prefixLength >= 24) {
      final networkParts = List<int>.generate(
        4,
        (index) => ipParts[index] & subnetParts[index],
      );
      final lastOctetBase =
          '${networkParts[0]}.${networkParts[1]}.${networkParts[2]}';

      return List<String>.generate(
        254,
        (index) => '$lastOctetBase.${index + 1}',
      ).where((host) => host != ip).toList();
    }

    debugPrint(
      '[DISCOVERY] Prefix /$prefixLength too wide, limiting scan to local /24 window',
    );
    return List<String>.generate(
      254,
      (index) => '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.${index + 1}',
    ).where((host) => host != ip).toList();
  }

  List<int>? _parseIpv4(String? value) {
    if (!_isValidIpv4(value)) {
      return null;
    }

    final parts = value!.split('.').map(int.parse).toList();
    if (parts.length != 4 || parts.any((part) => part < 0 || part > 255)) {
      return null;
    }
    return parts;
  }

  bool _isValidIpv4(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }

    final parts = value.split('.');
    if (parts.length != 4) {
      return false;
    }

    return parts.every((part) {
      final parsed = int.tryParse(part);
      return parsed != null && parsed >= 0 && parsed <= 255;
    });
  }

  int _prefixLength(List<int> subnetParts) {
    var bits = 0;
    for (final octet in subnetParts) {
      bits += octet
          .toRadixString(2)
          .split('')
          .where((bit) => bit == '1')
          .length;
    }
    return bits;
  }

  String? _sanitizeSsid(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value.replaceAll('"', '');
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final Esp32DiscoveryService _discoveryService = Esp32DiscoveryService();

  String ssid = 'Unknown';
  String ip = 'Unknown';
  String statusMessage = 'Siap melakukan scan';
  List<String> devices = [];
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    loadWifiInfo();
  }

  Future<void> loadWifiInfo() async {
    final details = await _discoveryService.getNetworkInfo();

    if (!mounted) {
      return;
    }

    if (details == null) {
      setState(() {
        ssid = 'Tidak terhubung';
        ip = 'Tidak ada WiFi';
        statusMessage = 'WiFi tidak tersedia atau permission ditolak';
      });
      return;
    }

    setState(() {
      ssid = details.ssid;
      ip = details.ip;
      statusMessage = details.broadcast == null
          ? 'WiFi terdeteksi, broadcast tidak tersedia'
          : 'WiFi siap untuk scan';
    });
  }

  Future<void> scanNetwork() async {
    if (isScanning) {
      return;
    }

    setState(() {
      isScanning = true;
      devices = [];
      statusMessage = 'Scanning ESP32...';
    });

    final foundDevices = await _discoveryService.discoverDevices(
      onDeviceFound: (foundIp) {
        if (!mounted) {
          return;
        }

        setState(() {
          if (!devices.contains(foundIp)) {
            devices = [...devices, foundIp]..sort();
            statusMessage = '${devices.length} device ditemukan';
          }
        });
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isScanning = false;
      devices = foundDevices;
      statusMessage = foundDevices.isEmpty
          ? 'Scan selesai, tidak ada device ditemukan'
          : 'Scan selesai, ${foundDevices.length} device ditemukan';
    });
  }

  Future<void> openHotspotSettings() async {
    try {
      final intent = AndroidIntent(action: 'android.settings.TETHER_SETTINGS');
      await intent.launch();
    } catch (error) {
      debugPrint('[APP] Failed to open tether settings: $error');
      final fallback = AndroidIntent(action: 'android.settings.SETTINGS');
      await fallback.launch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ESP32 Setup',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
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
                const Text(
                  'Instruksi Setup',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nyalakan hotspot dengan konfigurasi berikut:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.wifi_tethering,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hotspot Mobile',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'SSID : IOT\nPassword : 12345678',
                                style: TextStyle(fontSize: 14),
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
                    label: const Text('Buka Pengaturan Hotspot'),
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
                            color: Colors.lightBlueAccent.withValues(
                              alpha: 0.12,
                            ),
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
                                'WiFi Saat Ini',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'SSID : $ssid',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'IP : $ip',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                statusMessage,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
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
                              : const Text('Scan'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Perangkat Ditemukan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: devices.isEmpty
                      ? Center(
                          child: Text(
                            isScanning
                                ? 'Scanning device di jaringan...'
                                : 'Belum ada perangkat ditemukan',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (context, index) {
                            final deviceIP = devices[index];

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.15),
                                  child: Icon(
                                    Icons.memory,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  deviceIP,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  'ESP32 Device',
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key, required this.ip});

  final String ip;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  double distance = 0;
  double weight = 0;
  double temperature = 0;
  late final Timer timer;

  Future<void> openWeb() async {
    final url = Uri.parse('http://${widget.ip}/');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> fetchData() async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.ip}/data'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        debugPrint('[MONITOR] Failed to fetch data: ${response.statusCode}');
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }

      setState(() {
        distance = (data['distance'] as num?)?.toDouble() ?? 0;
        weight = (data['weight'] as num?)?.toDouble() ?? 0;
        temperature = (data['temperature'] as num?)?.toDouble() ?? 0;
      });
    } catch (error) {
      debugPrint('[MONITOR] Fetch error from ${widget.ip}: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    fetchData();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => fetchData());
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Widget sensorCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ESP32 Monitor',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      'Distance',
                      '${distance.toStringAsFixed(1)} cm',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      'Weight',
                      '${weight.toStringAsFixed(2)} kg',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: sensorCard(
                      'Temperature',
                      '${temperature.toStringAsFixed(1)} °C',
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
                  label: const Text('Lihat di Web'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

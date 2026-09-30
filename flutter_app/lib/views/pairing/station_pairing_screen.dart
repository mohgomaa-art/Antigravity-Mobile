import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/services/pairing_service.dart';
import '../../core/theme/antigravity_logo.dart';
import '../../providers/fleet_provider.dart';
import '../legal/disclaimer_screen.dart';
import '../widgets/developer_profile_card.dart';

class StationPairingScreen extends ConsumerStatefulWidget {
  const StationPairingScreen({super.key});

  @override
  ConsumerState<StationPairingScreen> createState() => _StationPairingScreenState();
}

class _StationPairingScreenState extends ConsumerState<StationPairingScreen> {
  bool _showManual = false;
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8765');
  final _tokenCtrl = TextEditingController();

  bool _isAutoScanning = false;

  @override
  void initState() {
    super.initState();
    final pairing = ref.read(pairingProvider);
    if (pairing.host.isNotEmpty && pairing.host != '127.0.0.1') {
      _hostCtrl.text = pairing.host;
    }
    if (pairing.port > 0) {
      _portCtrl.text = pairing.port.toString();
    }
    if (pairing.token.isNotEmpty && !pairing.token.contains('agy_sec_fleet')) {
      _tokenCtrl.text = pairing.token;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DisclaimerScreen.checkAndShowStartupNotice(context);
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _openCameraScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CameraScannerModal(
        onScanned: (data) async {
          Navigator.of(ctx).pop();
          final success = await ref.read(pairingProvider.notifier).pairFromQrData(data);
          if (success && mounted) {
            await ref.read(fleetProvider.notifier).loadFleet();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF10B981),
                  content: Text('Station Paired Successfully. 15 Accounts Synchronized.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _connectManual() async {
    var host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    final token = _tokenCtrl.text.trim();

    if (host.startsWith('http://') || host.startsWith('https://') ||
        host.contains('trycloudflare') || host.contains('ngrok') ||
        host.contains('loca.lt') || host.contains('pinggy')) {
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        host = 'https://$host';
      }
      host = host.replaceFirst(RegExp(r':\d+$'), '');
    }

    final success = await ref.read(pairingProvider.notifier).pairWithStation(
          host: host,
          port: port,
          token: token,
        );

    if (success && mounted) {
      await ref.read(fleetProvider.notifier).loadFleet();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Station Paired Successfully. 15 Accounts Synchronized.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
      }
    }
  }

  Future<bool> _sweepSubnets() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final candidateIps = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
              candidateIps.add('$prefix.1');
              candidateIps.add('$prefix.2');
              for (int i = 3; i < 255; i++) {
                candidateIps.add('$prefix.$i');
              }
            }
          }
        }
      }

      const chunkSize = 25;
      for (int i = 0; i < candidateIps.length; i += chunkSize) {
        if (!mounted) break;
        final chunk = candidateIps.sublist(
            i, (i + chunkSize > candidateIps.length) ? candidateIps.length : i + chunkSize);
        String? foundIp;
        String? foundToken;
        String? foundName;

        final targetPort = ref.read(agyClientProvider).port;
        await Future.wait(chunk.map((ip) async {
          if (foundIp != null) return;
          try {
            final client = http.Client();
            final res = await client.get(
              Uri.parse('http://$ip:$targetPort/api/pairing/info'),
            ).timeout(const Duration(milliseconds: 400));
            client.close();
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              foundIp = ip;
              foundToken = data['token'] as String?;
              foundName = data['name'] as String?;
            }
          } catch (_) {}
        }));

        if (foundIp != null) {
          final success = await ref.read(pairingProvider.notifier).pairWithStation(
            host: foundIp!,
            port: targetPort,
            token: foundToken ?? '',
            name: foundName ?? 'Auto-Discovered Station ($foundIp)',
          );
          if (success && mounted) {
            await ref.read(fleetProvider.notifier).loadFleet();
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _smartDirectConnect() async {
    setState(() => _isAutoScanning = true);
    final client = ref.read(agyClientProvider);
    final currentPort = client.port;

    // 1. First probe 127.0.0.1 (ADB Reverse)
    try {
      final httpClient = http.Client();
      final res = await httpClient.get(
        Uri.parse('http://127.0.0.1:$currentPort/api/pairing/info'),
      ).timeout(const Duration(milliseconds: 500));
      httpClient.close();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final dynamicToken = data['token'] as String? ?? '';
        final stationName = data['name'] as String? ?? 'Localhost / USB Bridge';

        final success = await ref.read(pairingProvider.notifier).pairWithStation(
              host: '127.0.0.1',
              port: currentPort,
              token: dynamicToken,
              name: stationName,
            );

        if (success && mounted) {
          setState(() => _isAutoScanning = false);
          await ref.read(fleetProvider.notifier).loadFleet();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF10B981),
                content: Text('Connected to USB Bridge (127.0.0.1:$currentPort)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            );
          }
          return;
        }
      }
    } catch (_) {}

    // 2. Dynamically discover candidate gateway IPs for any active local network adapters
    final candidateHosts = <String>[];
    try {
      final ifaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final parts = ip.split('.');
          if (parts.length == 4) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            for (final octet in ['1', '2']) {
              final cand = '$prefix.$octet';
              if (cand != ip && !candidateHosts.contains(cand)) {
                candidateHosts.add(cand);
              }
            }
          }
        }
      }
    } catch (_) {}

    String? foundTetherIp;
    String? foundTetherToken;
    String? foundTetherName;

    await Future.wait(candidateHosts.map((host) async {
      if (foundTetherIp != null) return;
      try {
        final httpClient = http.Client();
        final res = await httpClient.get(
          Uri.parse('http://$host:$currentPort/api/pairing/info'),
        ).timeout(const Duration(milliseconds: 600));
        httpClient.close();
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          foundTetherIp = host;
          foundTetherToken = data['token'] as String?;
          foundTetherName = data['name'] as String?;
        }
      } catch (_) {}
    }));

    if (foundTetherIp != null) {
      final success = await ref.read(pairingProvider.notifier).pairWithStation(
            host: foundTetherIp!,
            port: currentPort,
            token: foundTetherToken ?? '',
            name: foundTetherName ?? 'USB Tethering Station',
          );
      if (success && mounted) {
        setState(() => _isAutoScanning = false);
        await ref.read(fleetProvider.notifier).loadFleet();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('Connected via Network Adapter ($foundTetherIp:$currentPort)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          );
        }
        return;
      }
    }

    // 3. Subnet sweep for local Wi-Fi / LAN stations
    final swept = await _sweepSubnets();
    if (swept) {
      setState(() => _isAutoScanning = false);
      return;
    }

    setState(() => _isAutoScanning = false);

    // 4. Deterministic diagnosis and failure screen
    if (mounted) {
      _showDeterministicFailureModal();
    }
  }

  Future<void> _showDeterministicFailureModal() async {
    bool hasWifi = false;
    bool hasUsbTether = false;
    bool hasCellularOnly = true;
    final List<String> localIps = [];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          localIps.add('${iface.name}: ${addr.address}');
          if (name.contains('wlan') || name.contains('wifi') || name.contains('eth')) {
            hasWifi = true;
            hasCellularOnly = false;
          }
          if (name.contains('rndis') || name.contains('usb') || name.contains('tether') || name.contains('ncm') || name.contains('ecm')) {
            hasUsbTether = true;
            hasCellularOnly = false;
          }
        }
      }
    } catch (_) {}

    final port = ref.read(agyClientProvider).port;
    String conditionTitle;
    String conditionDetail;
    String singleFix;
    String actionBtnText;

    if (hasUsbTether) {
      conditionTitle = 'USB Tethering Active (Firewall Blocked)';
      conditionDetail = 'Your phone is connected via USB Tethering, but the PC Station at port $port did not respond.';
      singleFix = 'On your PC, open Antigravity Fleet Station and click "Diagnostics" > "Auto-Repair (UAC)" to allow port $port through Windows Firewall.';
      actionBtnText = 'Retry USB Direct Connect';
    } else if (hasWifi) {
      conditionTitle = 'Wi-Fi Connected (AP Isolation / Firewall)';
      conditionDetail = 'Your phone is on local Wi-Fi (${localIps.join(", ")}), but cannot reach port $port on your PC.';
      singleFix = 'Your Wi-Fi router has AP/Client Isolation enabled, or Windows Firewall is blocking inbound connections.\n\nSINGLE RECOMMENDED FIX:\nPlug in USB cable, turn on "USB Tethering" in Android Settings (Hotspot & Tethering), then tap the button below.';
      actionBtnText = 'Connect via USB Tethering';
    } else if (hasCellularOnly) {
      conditionTitle = 'Mobile / Cellular Data Only';
      conditionDetail = 'Your phone is not connected to any local network or USB cable.';
      singleFix = 'Connect your phone to the SAME Wi-Fi network as your PC.\n\nOR\n\nPlug in USB cable and enable "USB Tethering" in Android Settings.';
      actionBtnText = 'Retry Connection';
    } else {
      conditionTitle = 'No Offline Network Connection';
      conditionDetail = 'No local Wi-Fi or USB connection found.';
      singleFix = 'Plug USB cable into PC and turn on "USB Tethering" or connect to the local Wi-Fi network.';
      actionBtnText = 'Retry';
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E0E10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF27272A), width: 1.0),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conditionTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text('Deterministically Diagnosed Offline', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DETECTED CAUSE', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 5),
                  Text(conditionDetail, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.build_outlined, size: 13, color: Colors.white),
                      SizedBox(width: 6),
                      Text('RECOMMENDED FIX', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(singleFix, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showConnectionHelpDialog();
            },
            child: const Text('View USB Guide', style: TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.underline)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _smartDirectConnect();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(actionBtnText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showConnectionHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF27272A)),
        ),
        title: const Row(
          children: [
            Icon(Icons.usb_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              'How to Connect via USB',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick any of these 3 easy methods:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 14),

            // Option 1: USB Tethering
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Option A: USB Tethering (No setup required)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Plug phone into PC.\n2. Open Android Settings > Hotspot & Tethering.\n3. Turn on "USB Tethering".\n4. Tap "Retry Direct Connect" below!',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Option 2: USB Debugging
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Option B: USB Debugging (Developer Mode)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Enable Developer Options in phone settings.\n2. Turn on "USB Debugging".\n3. Unlock phone and tap "Allow" on the prompt.',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Option 3: Wi-Fi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Option C: Wi-Fi Pairing',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Connect phone and PC to the same Wi-Fi and tap "Scan Station QR Code".',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _smartDirectConnect();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('Retry Direct Connect', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Glowing Antigravity Badge
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121214),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF27272A), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.05),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: AntigravityLogo(size: 38),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'ANTIGRAVITY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'MOBILE FLEET COMMAND',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  'Connect to your Windows Station to manage your fleet',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),



                if (pairing.errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3F3F46)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            pairing.errorMessage!,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // Primary QR Scan Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: pairing.isLoading ? null : _openCameraScanner,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: pairing.isLoading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.qr_code_scanner, size: 20, color: Colors.black),
                    label: pairing.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : const Text(
                            'Scan Station QR Code',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Direct USB Connect Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: pairing.isLoading ? null : _smartDirectConnect,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3F3F46)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isAutoScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 1.5),
                          )
                        : const Icon(Icons.usb_rounded, size: 18, color: Colors.white70),
                    label: Text(
                      _isAutoScanning ? 'Connecting via USB...' : 'Connect via USB',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Manual Toggle
                TextButton(
                  onPressed: () => setState(() => _showManual = !_showManual),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showManual ? 'Hide Manual Config' : 'Manual Station IP Entry',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Icon(
                        _showManual ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey,
                        size: 18,
                      ),
                    ],
                  ),
                ),

                if (_showManual) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Station IP or Worldwide Remote URL',
                          style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _hostCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            fillColor: const Color(0xFF09090B),
                            filled: true,
                            hintText: 'e.g. 192.168.1.15 or https://*.trycloudflare.com',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF27272A)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Port',
                          style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            fillColor: const Color(0xFF09090B),
                            filled: true,
                            hintText: '8765',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF27272A)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Pairing Security Token (from PC QR / Station)',
                          style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _tokenCtrl,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            fillColor: const Color(0xFF09090B),
                            filled: true,
                            hintText: 'Paste token from PC Fleet Station',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF27272A)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: pairing.isLoading ? null : _connectManual,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Connect & Bind', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const DeveloperProfileCard(compact: true),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.gavel_outlined, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Legal Disclaimer & Unofficial Notice',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          decoration: TextDecoration.underline,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
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

class _CameraScannerModal extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _CameraScannerModal({required this.onScanned});

  @override
  State<_CameraScannerModal> createState() => _CameraScannerModalState();
}

class _CameraScannerModalState extends State<_CameraScannerModal> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          // Camera scanner
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_handled) return;
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final val = barcode.rawValue;
                  if (val != null && val.isNotEmpty) {
                    _handled = true;
                    widget.onScanned(val);
                    break;
                  }
                }
              },
            ),
          ),

          // High-tech viewfinder overlay
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      // Corner brackets
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(width: 20, height: 4, color: Colors.white),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(width: 4, height: 20, color: Colors.white),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(width: 20, height: 4, color: Colors.white),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(width: 4, height: 20, color: Colors.white),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(width: 20, height: 4, color: Colors.white),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(width: 4, height: 20, color: Colors.white),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(width: 20, height: 4, color: Colors.white),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(width: 4, height: 20, color: Colors.white),
                      ),
                      const Center(
                        child: Text(
                          'Point at Windows Station QR',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Header with close and torch buttons
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 26),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Text(
                  'SCAN STATION QR CODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white, size: 24),
                  onPressed: () => _controller.toggleTorch(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

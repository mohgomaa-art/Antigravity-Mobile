import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, NetworkInterface, InternetAddressType;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/fleet_provider.dart';
import '../api/agy_client.dart';

class PairingState {
  final bool isPaired;
  final bool isLoading;
  final String host;
  final int port;
  final String token;
  final String stationName;
  final String? errorMessage;

  const PairingState({
    this.isPaired = false,
    this.isLoading = true,
    this.host = '127.0.0.1',
    this.port = 8765,
    this.token = '',
    this.stationName = 'Antigravity Station',
    this.errorMessage,
  });

  PairingState copyWith({
    bool? isPaired,
    bool? isLoading,
    String? host,
    int? port,
    String? token,
    String? stationName,
    String? errorMessage,
  }) {
    return PairingState(
      isPaired: isPaired ?? this.isPaired,
      isLoading: isLoading ?? this.isLoading,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      stationName: stationName ?? this.stationName,
      errorMessage: errorMessage,
    );
  }
}

class PairingNotifier extends Notifier<PairingState> {
  static const String _keyIsPaired = 'agy_station_is_paired';
  static const String _keyHost = 'agy_station_host';
  static const String _keyPort = 'agy_station_port';
  static const String _keyToken = 'agy_station_token';
  static const String _keyStationName = 'agy_station_name';

  AgyClient get _client => ref.read(agyClientProvider);

  bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  PairingState build() {
    Future.microtask(() => init());
    return const PairingState();
  }

  Future<void> init() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    // On Desktop, station is local and pairs dynamically
    if (isDesktopPlatform) {
      _client.host = '127.0.0.1';
      _client.port = 8765;
      try {
        final info = await _client.getPairingInfo();
        _client.token = info['token'] as String? ?? '';
      } catch (_) {}

      state = state.copyWith(
        isPaired: true,
        isLoading: false,
        host: '127.0.0.1',
        port: 8765,
        token: _client.token,
        stationName: 'Local Command Station',
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final isPaired = prefs.getBool(_keyIsPaired) ?? false;
      final savedHost = prefs.getString(_keyHost) ?? '';
      final savedPort = prefs.getInt(_keyPort) ?? 8765;
      final savedToken = prefs.getString(_keyToken) ?? '';
      final savedName = prefs.getString(_keyStationName) ?? 'Antigravity Station';

      // Purge corrupt/internal Cloudflare endpoints
      if (savedHost.contains('api.trycloudflare.com')) {
        await prefs.remove(_keyHost);
        await prefs.setBool(_keyIsPaired, false);
      }

      if (isPaired && savedHost.isNotEmpty && !savedHost.contains('api.trycloudflare.com')) {
        _client.host = savedHost;
        _client.port = savedPort;
        _client.token = savedToken;

        state = state.copyWith(
          isPaired: true,
          isLoading: false,
          host: savedHost,
          port: savedPort,
          token: savedToken,
          stationName: savedName,
        );
      } else {
        state = state.copyWith(
          isPaired: false,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isPaired: false,
        isLoading: false,
        errorMessage: 'Failed to read pairing config: $e',
      );
    }
  }

  /// Pairs with the station given raw QR code payload or host/port/token
  Future<bool> pairWithStation({
    required String host,
    required int port,
    required String token,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    String cleanHost = host.trim();
    if (cleanHost.contains('api.trycloudflare.com')) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid tunnel URL: api.trycloudflare.com is Cloudflare\'s internal API, not your Station tunnel.\nPlease check that the tunnel is running on your PC and scan the updated QR code.',
      );
      return false;
    }
    if (cleanHost.contains('trycloudflare') || cleanHost.startsWith('https://')) {
      if (!cleanHost.startsWith('http://') && !cleanHost.startsWith('https://')) {
        cleanHost = 'https://$cleanHost';
      }
      cleanHost = cleanHost.replaceFirst(RegExp(r':\d+$'), '');
    }

    try {
      // Temporarily update client to test handshake
      _client.host = cleanHost;
      _client.port = port;
      _client.token = token;

      final isRemote = cleanHost.startsWith('http://') || cleanHost.startsWith('https://');
      final timeoutDuration = isRemote ? const Duration(seconds: 12) : const Duration(seconds: 5);

      // Verify connection to the station with timeout
      try {
        final healthRes = await http.get(Uri.parse('${_client.baseUrl}/api/fleet/health'))
            .timeout(timeoutDuration);
        if (healthRes.statusCode != 200) {
          throw Exception('Gateway returned status code ${healthRes.statusCode}');
        }
      } catch (_) {}

      // Verify authenticated connection to the station
      await _client.getFleetStatus().timeout(timeoutDuration);

      // Handshake succeeded! Persist permanently
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsPaired, true);
      await prefs.setString(_keyHost, cleanHost);
      await prefs.setInt(_keyPort, port);
      await prefs.setString(_keyToken, token);
      if (name != null) {
        await prefs.setString(_keyStationName, name);
      }

      state = state.copyWith(
        isPaired: true,
        isLoading: false,
        host: cleanHost,
        port: port,
        token: token,
        stationName: name ?? 'Antigravity Windows Station',
      );
      return true;
    } catch (e) {
      String friendlyError;
      final eStr = e.toString();
      final displayTarget = (cleanHost.startsWith('http://') || cleanHost.startsWith('https://'))
          ? _client.baseUrl
          : '$cleanHost:$port';

      if (cleanHost == '127.0.0.1') {
        friendlyError = 'USB Direct Connect Failed (Port 8765 Refused):\n'
            '1. Ensure "USB Debugging" is enabled in phone Developer Options.\n'
            '2. Unlock your phone and tap "Allow USB debugging" if prompted.\n'
            '3. Make sure Antigravity Windows Station is open on your PC.\n'
            'Alternatively, enable "USB Tethering" or connect to the same Wi-Fi and scan QR.';
      } else if (eStr.contains('113') || eStr.contains('No route to host')) {
        friendlyError = 'Could not reach Station at $displayTarget (No route to host):\n'
            '1. Check that the PC is awake and connected to the network.\n'
            '2. Ensure Antigravity Fleet Station is open and running on your PC.\n'
            '3. Check Windows Firewall: allow Port 8765 on Private/Public profiles.\n'
            '4. Or plug in USB cable and tap "Connect via USB" for direct connection.';
      } else if (eStr.contains('TimeoutException')) {
        if (cleanHost.contains('trycloudflare') || cleanHost.startsWith('https://')) {
          friendlyError = 'Worldwide Remote Connection Timed Out ($displayTarget):\n'
              '1. Ensure Antigravity Fleet Station is running on your PC.\n'
              '2. Check that Cloudflare Worldwide Tunnel is active on your PC.\n'
              '3. Verify your mobile data connection (4G/5G) and tap Retry.';
        } else {
          friendlyError = 'Connection timed out at $displayTarget:\n'
              '1. Ensure Antigravity Fleet Station is open and running on your PC.\n'
              '2. Check if your Wi-Fi router has "Client Isolation" or "AP Isolation" enabled.\n'
              '3. Or scan the Station QR Code to connect via Worldwide Remote Tunnel.';
        }
      } else {
        friendlyError = 'Connection failed to $displayTarget: $e\n'
            'Tip: Ensure Antigravity Fleet Station is active on your PC.';
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: friendlyError,
      );
      return false;
    }
  }

  /// Probes multiple candidate hosts concurrently and pairs with the first responsive station
  Future<bool> pairFromHosts({
    required List<String> hosts,
    required int port,
    required String token,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final candidates = <String>[];
    // Put remote tunnel URLs first so they are checked immediately
    for (final h in hosts) {
      final clean = h.trim();
      if (clean.contains('api.trycloudflare.com')) continue;
      if (clean.contains('trycloudflare') || clean.startsWith('https://') || clean.startsWith('http://')) {
        String normalized = clean;
        if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
          normalized = 'https://$normalized';
        }
        normalized = normalized.replaceFirst(RegExp(r':\d+$'), '');
        if (!candidates.contains(normalized)) {
          candidates.add(normalized);
        }
      }
    }
    // Then add LAN and loopback candidates
    for (final h in hosts) {
      final clean = h.trim();
      if (clean.contains('api.trycloudflare.com')) continue;
      if (clean.isNotEmpty && !candidates.contains(clean) && !clean.startsWith('http://') && !clean.startsWith('https://') && !clean.contains('trycloudflare')) {
        candidates.add(clean);
      }
    }
    if (!candidates.contains('127.0.0.1')) candidates.add('127.0.0.1');

    // Dynamically discover candidate gateway/peer IPs for any active local network adapters
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
              if (cand != ip && !candidates.contains(cand)) {
                candidates.add(cand);
              }
            }
          }
        }
      }
    } catch (_) {}

    String? winnerHost;

    // Concurrently probe candidate hosts (10s for remote tunnel, 3s for local LAN)
    await Future.wait(candidates.map((cand) async {
      if (winnerHost != null) return;
      try {
        final client = http.Client();
        final isUrl = cand.startsWith('http://') || cand.startsWith('https://');
        final probeTimeout = isUrl ? const Duration(seconds: 10) : const Duration(milliseconds: 3000);
        final base = isUrl ? (cand.endsWith('/') ? cand.substring(0, cand.length - 1) : cand) : 'http://$cand:$port';
        final res = await client.get(
          Uri.parse('$base/api/fleet/health'),
        ).timeout(probeTimeout);
        client.close();
        if (res.statusCode == 200 && winnerHost == null) {
          winnerHost = cand;
        }
      } catch (_) {
        // Fallback to authenticated endpoint
        try {
          final client = http.Client();
          final isUrl = cand.startsWith('http://') || cand.startsWith('https://');
          final probeTimeout = isUrl ? const Duration(seconds: 10) : const Duration(milliseconds: 3000);
          final base = isUrl ? (cand.endsWith('/') ? cand.substring(0, cand.length - 1) : cand) : 'http://$cand:$port';
          final res = await client.get(
            Uri.parse('$base/api/fleet/status'),
            headers: {'X-Bridge-Token': token},
          ).timeout(probeTimeout);
          client.close();
          if ((res.statusCode == 200 || res.statusCode == 401) && winnerHost == null) {
            winnerHost = cand;
          }
        } catch (_) {}
      }
    }));

    if (winnerHost != null) {
      return await pairWithStation(
        host: winnerHost!,
        port: port,
        token: token,
        name: name,
      );
    }

    // Try candidates sequentially before giving up (prioritizing remote URLs then LAN then USB)
    for (final cand in candidates) {
      final ok = await pairWithStation(
        host: cand,
        port: port,
        token: token,
        name: name,
      );
      if (ok) return true;
    }

    // Fallback to first host to capture full friendly diagnostic error
    return await pairWithStation(
      host: candidates.isNotEmpty ? candidates.first : '127.0.0.1',
      port: port,
      token: token,
      name: name,
    );
  }

  /// Parses QR code string (either JSON payload or custom URI) and pairs
  Future<bool> pairFromQrData(String rawData) async {
    try {
      final clean = rawData.trim();
      if (clean.startsWith('{') && clean.endsWith('}')) {
        final map = jsonDecode(clean) as Map<String, dynamic>;
        final List<String> hostsList = [];
        if (map['hosts'] is List) {
          for (final item in map['hosts']) {
            if (item != null) hostsList.add(item.toString());
          }
        }
        final pubUrl = (map['public_url'] as String? ?? '').trim();
        if (pubUrl.isNotEmpty && !hostsList.contains(pubUrl)) {
          hostsList.insert(0, pubUrl);
        }
        final host = map['host'] as String? ?? '127.0.0.1';
        if (!hostsList.contains(host)) hostsList.insert(0, host);
        final port = (map['port'] as num?)?.toInt() ?? 8765;
        final token = map['token'] as String? ?? '';
        final name = map['name'] as String? ?? 'Antigravity Station';
        return await pairFromHosts(hosts: hostsList, port: port, token: token, name: name);
      } else if (clean.startsWith('antigravity://pair') || clean.startsWith('http')) {
        final uri = Uri.parse(clean);
        final hostsParam = uri.queryParameters['hosts'];
        final List<String> hostsList = hostsParam != null ? hostsParam.split(',') : [];
        final host = uri.queryParameters['host'] ?? uri.host;
        if (host.isNotEmpty && !hostsList.contains(host)) hostsList.insert(0, host);
        final port = int.tryParse(uri.queryParameters['port'] ?? '') ?? (uri.port != 0 ? uri.port : 8765);
        final token = uri.queryParameters['token'] ?? '';
        final name = uri.queryParameters['name'] ?? 'Antigravity Station';
        return await pairFromHosts(hosts: hostsList, port: port, token: token, name: name);
      } else {
        throw FormatException('Invalid QR code format. Expected Antigravity JSON or pairing URI.');
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid QR Code: $e',
      );
      return false;
    }
  }

  /// Unbinds permanently and returns to pairing screen
  Future<void> unbind() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyIsPaired);
      await prefs.remove(_keyHost);
      await prefs.remove(_keyPort);
      await prefs.remove(_keyToken);
      await prefs.remove(_keyStationName);

      _client.host = '127.0.0.1';
      _client.port = 8765;
      _client.token = '';

      state = state.copyWith(
        isPaired: false,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Unbind error: $e');
    }
  }
}

final pairingProvider = NotifierProvider<PairingNotifier, PairingState>(PairingNotifier.new);

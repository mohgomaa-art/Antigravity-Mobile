import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/models/worker_account.dart';
import '../../core/theme/antigravity_logo.dart';
import '../../providers/fleet_provider.dart';
import '../legal/disclaimer_screen.dart';

class WindowsFleetStation extends ConsumerStatefulWidget {
  const WindowsFleetStation({super.key});

  @override
  ConsumerState<WindowsFleetStation> createState() => _WindowsFleetStationState();
}

class _WindowsFleetStationState extends ConsumerState<WindowsFleetStation> with WidgetsBindingObserver {
  Map<String, dynamic>? _pairingInfo;
  Timer? _adbTimer;
  Timer? _healthTimer;
  bool _isBridgeOnline = false;
  String _adbStatusText = 'Checking USB...';
  Color _adbStatusColor = Colors.grey;

  Future<void> _runAdbReverse() async {
    if (!Platform.isWindows) return;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundledAdb = '$exeDir\\bridge\\adb.exe';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final adbPaths = [
      bundledAdb,
      '$exeDir\\bridge\\_internal\\adb.exe',
      '${Directory.current.path}\\dist\\antigravity_bridge\\adb.exe',
      '${Directory.current.path}\\dist\\antigravity_bridge\\_internal\\adb.exe',
      'adb',
      '$userProfile\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe',
      'C:\\Android\\Sdk\\platform-tools\\adb.exe',
    ];

    String? workingAdb;
    for (final adb in adbPaths) {
      if (File(adb).existsSync() || adb == 'adb') {
        workingAdb = adb;
        break;
      }
    }
    _workingAdbPath = workingAdb;

    if (workingAdb == null) {
      if (mounted) {
        setState(() {
          _adbStatusText = 'ADB Engine Not Found';
          _adbStatusColor = const Color(0xFF71717A);
        });
      }
      return;
    }

    try {
      final devRes = await Process.run(workingAdb, ['devices']);
      final out = devRes.stdout.toString();
      if (out.contains('unauthorized')) {
        if (mounted) {
          setState(() {
            _adbStatusText = 'USB Phone Detected (Unlock phone & tap "Allow USB Debugging")';
            _adbStatusColor = const Color(0xFFA1A1AA);
          });
        }
      } else if (RegExp(r'(\w+)\s+device\b').hasMatch(out)) {
        final match = RegExp(r'(\w+)\s+device\b').firstMatch(out);
        final devId = match?.group(1) ?? 'Device';
        final port = ref.read(agyClientProvider).port;
        final revRes = await Process.run(workingAdb, ['reverse', 'tcp:$port', 'tcp:$port']);
        if (revRes.exitCode == 0) {
          if (mounted) {
            setState(() {
              _adbStatusText = 'USB Connected: $devId (Port $port Active)';
              _adbStatusColor = Colors.white;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _adbStatusText = 'USB Reverse Failed (${revRes.stderr.toString().trim()})';
              _adbStatusColor = const Color(0xFFA1A1AA);
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _adbStatusText = 'No USB Phone (Plug in cable & turn on USB Debugging or Tethering)';
            _adbStatusColor = Colors.grey;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _adbStatusText = 'USB Monitoring Active';
          _adbStatusColor = Colors.grey;
        });
      }
    }
  }

  bool get _isTesting => Platform.environment.containsKey('FLUTTER_TEST');

  void _loadLocalConfigSync() {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final cfgFile = File('$userProfile\\.antigravity-fleet\\config\\fleet_config.json');
      if (cfgFile.existsSync()) {
        final content = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
        final gw = content['gateway'] as Map<String, dynamic>?;
        final token = (gw?['pairing_token'] as String? ?? '').trim();
        final port = (gw?['port'] is int) ? gw!['port'] as int : 8765;
        if (token.isNotEmpty) {
          final client = ref.read(agyClientProvider);
          client.token = token;
          client.port = port;
          _pairingInfo = {
            'host': client.host,
            'lan_ip': client.host,
            'port': port,
            'token': token,
          };
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_isTesting) {
      _loadLocalConfigSync();
      _initApp();
      _runAdbReverse();
      _adbTimer = Timer.periodic(const Duration(seconds: 4), (_) => _runAdbReverse());
      _healthTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkBridgeHealth());
    }
  }

  String? _workingAdbPath;

  void _terminateChildProcesses() {
    if (!Platform.isWindows) return;
    try {
      if (_workingAdbPath != null) {
        Process.runSync(_workingAdbPath!, ['kill-server']);
      }
    } catch (_) {}
    try {
      Process.runSync('taskkill', ['/F', '/T', '/IM', 'antigravity_bridge.exe', '/IM', 'cloudflared.exe']);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adbTimer?.cancel();
    _healthTimer?.cancel();
    _terminateChildProcesses();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _terminateChildProcesses();
    }
  }

  bool _isStartingBridge = false;
  int _bridgeFailCount = 0;
  bool _firewallOk = false;
  String _firewallStatus = 'Checking...';
  List<String> _stationHosts = [];
  Map<String, bool> _hostPingResults = {};

  int get _stationPort => ref.read(agyClientProvider).port;

  Future<void> _checkBridgeHealth() async {
    if (!Platform.isWindows) return;
    if (_isStartingBridge) return; // Never interfere while bridge is launching

    bool healthy = false;
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:$_stationPort/api/fleet/health'))
          .timeout(const Duration(milliseconds: 2000));
      healthy = (res.statusCode == 200);
    } catch (_) {
      healthy = false;
    }

    if (healthy) {
      _bridgeFailCount = 0;
      if (mounted) {
        if (!_isBridgeOnline) {
          setState(() => _isBridgeOnline = true);
        }
        final tokenMissing = _pairingInfo == null || (_pairingInfo!['token'] as String? ?? '').isEmpty;
        if (tokenMissing) {
          _fetchPairingInfo();
          ref.read(fleetProvider.notifier).loadFleet();
        }
      }
    } else {
      _bridgeFailCount++;
      // Debounce: require 5 consecutive failed probes (15+ seconds) before showing offline
      if (_bridgeFailCount >= 5 && mounted && _isBridgeOnline) {
        setState(() => _isBridgeOnline = false);
      }
      // Never auto-kill bridge in the background watchdog - process remains intact
    }
  }

  Future<void> _runDiagnostics() async {
    if (!Platform.isWindows) return;
    try {
      final fwRes = await Process.run('netsh', [
        'advfirewall', 'firewall', 'show', 'rule',
        'name=Antigravity Fleet Station Port $_stationPort'
      ]);
      final fwOut = fwRes.stdout.toString();
      bool isEnabled = fwOut.contains('Enabled:') && (fwOut.contains('Yes') || fwOut.contains('yes'));

      // If rule is missing, attempt silent self-repair (succeeds immediately if elevated or installer launch)
      if (!isEnabled) {
        try {
          await Process.run('netsh', [
            'advfirewall', 'firewall', 'add', 'rule',
            'name=Antigravity Fleet Station Port $_stationPort',
            'dir=in', 'action=allow', 'protocol=TCP',
            'localport=$_stationPort', 'profile=any'
          ]);
          final retryRes = await Process.run('netsh', [
            'advfirewall', 'firewall', 'show', 'rule',
            'name=Antigravity Fleet Station Port $_stationPort'
          ]);
          final retryOut = retryRes.stdout.toString();
          isEnabled = retryOut.contains('Enabled:') && (retryOut.contains('Yes') || retryOut.contains('yes'));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _firewallOk = isEnabled;
          _firewallStatus = isEnabled ? 'Allowed (Port $_stationPort, All Profiles)' : 'Firewall Rule Missing or Blocked';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _firewallOk = false;
          _firewallStatus = 'Firewall Query Failed';
        });
      }
    }

    // Ping each discovered host on active gateway port
    final results = <String, bool>{};
    for (final host in _stationHosts) {
      try {
        final socket = await Socket.connect(host, _stationPort, timeout: const Duration(milliseconds: 600));
        socket.destroy();
        results[host] = true;
      } catch (_) {
        results[host] = false;
      }
    }
    if (mounted) {
      setState(() => _hostPingResults = results);
    }
  }

  Future<void> _repairFirewall() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final scriptCandidate = '$exeDir\\tools\\silent_firewall_setup.ps1';
      final projectScript = '${Directory.current.path}\\tools\\silent_firewall_setup.ps1';
      final targetScript = File(scriptCandidate).existsSync()
          ? scriptCandidate
          : (File(projectScript).existsSync() ? projectScript : null);

      if (targetScript != null) {
        await Process.run('powershell', [
          '-Command',
          'Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File \\"$targetScript\\" -GatewayPort $_stationPort" -Verb RunAs -Wait'
        ]);
      } else {
        await Process.run('powershell', [
          '-Command',
          'Start-Process netsh -ArgumentList "advfirewall firewall add rule name=\\"Antigravity Fleet Station Port $_stationPort\\" dir=in action=allow protocol=TCP localport=$_stationPort profile=any" -Verb RunAs -Wait'
        ]);
      }
      await _runDiagnostics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _firewallOk ? Colors.white : const Color(0xFFA1A1AA),
            content: Text(_firewallOk ? 'All firewall rules (Bridge, ADB, Cloudflare) configured!' : 'Firewall configuration completed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Firewall repair error: $e')),
        );
      }
    }
  }

  void _copyDiagnosticsReport() {
    final report = StringBuffer();
    report.writeln('### ANTIGRAVITY FLEET STATION DIAGNOSTIC REPORT');
    report.writeln('- Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('- Gateway Status: ${_isBridgeOnline ? "ONLINE (Port $_stationPort)" : "OFFLINE"}');
    report.writeln('- Gateway Bind: 0.0.0.0:$_stationPort (All Network Adapters)');
    report.writeln('- Discovered LAN IPs: ${_stationHosts.join(", ")}');
    for (final entry in _hostPingResults.entries) {
      report.writeln('  • ${entry.key}:$_stationPort -> ${entry.value ? "REACHABLE" : "UNREACHABLE"}');
    }
    report.writeln('- Firewall Status: ${_firewallOk ? "ALLOWED" : "BLOCKED / MISSING"} ($_firewallStatus)');
    report.writeln('- USB / ADB Status: $_adbStatusText');
    report.writeln('- Active Accounts: ${ref.read(fleetProvider).workers.where((w) => w.isActive).length}/15');
    report.writeln('- Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    report.writeln('- Executable: ${Platform.resolvedExecutable}');
    
    Clipboard.setData(ClipboardData(text: report.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF27272A),
        content: Text('Diagnostics report copied to clipboard!'),
      ),
    );
  }

  Future<void> _initApp() async {
    _loadLocalConfigSync();
    await _ensureBridgeRunning();
    await _fetchPairingInfo();
    await _checkBridgeHealth();
    await _runDiagnostics();
    ref.read(fleetProvider.notifier).loadFleet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DisclaimerScreen.checkAndShowStartupNotice(context);
    });
  }

  Future<void> _ensureBridgeRunning() async {
    if (!Platform.isWindows) return;
    if (_isStartingBridge) return;

    // Fast check: is bridge already responding?
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:$_stationPort/api/fleet/health'))
          .timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        if (mounted) setState(() => _isBridgeOnline = true);
        await _fetchPairingInfo();
        return;
      }
    } catch (_) {}

    _isStartingBridge = true;
    try {
      // Check if antigravity_bridge.exe is already in process list
      bool bridgeProcessRunning = false;
      try {
        final tasklistRes = await Process.run('tasklist', ['/FI', 'IMAGENAME eq antigravity_bridge.exe']);
        bridgeProcessRunning = tasklistRes.stdout.toString().contains('antigravity_bridge.exe');
      } catch (_) {}

      if (bridgeProcessRunning) {
        // It is already running; wait for it to become healthy instead of killing it
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            final res = await http.get(Uri.parse('http://127.0.0.1:$_stationPort/api/fleet/health'))
                .timeout(const Duration(milliseconds: 1000));
            if (res.statusCode == 200) {
              if (mounted) setState(() => _isBridgeOnline = true);
              await _fetchPairingInfo();
              return;
            }
          } catch (_) {}
        }
        // If it still hasn't responded after 7.5 seconds, then kill and restart
        try {
          await Process.run('taskkill', ['/F', '/T', '/IM', 'antigravity_bridge.exe']);
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      }

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final currDir = Directory.current.path;
      final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
      final progFiles = Platform.environment['PROGRAMFILES'] ?? 'C:\\Program Files';
      final progFilesX86 = Platform.environment['PROGRAMFILES(X86)'] ?? 'C:\\Program Files (x86)';

      final candidates = [
        '$exeDir\\bridge\\antigravity_bridge.exe',
        '$exeDir\\antigravity_bridge.exe',
        '$exeDir\\..\\bridge\\antigravity_bridge.exe',
        '$currDir\\dist\\antigravity_bridge\\antigravity_bridge.exe',
        '$currDir\\..\\dist\\antigravity_bridge\\antigravity_bridge.exe',
        '$progFiles\\Antigravity Fleet Station\\bridge\\antigravity_bridge.exe',
        '$progFilesX86\\Antigravity Fleet Station\\bridge\\antigravity_bridge.exe',
        if (localApp.isNotEmpty) '$localApp\\Programs\\Antigravity Fleet Station\\bridge\\antigravity_bridge.exe',
      ];

      final logDir = Directory(localApp.isNotEmpty ? '$localApp\\Antigravity\\logs' : '.\\logs');
      if (!logDir.existsSync()) {
        try { logDir.createSync(recursive: true); } catch (_) {}
      }
      final logFile = File('${logDir.path}\\bridge_startup.log');

      for (final c in candidates) {
        if (File(c).existsSync()) {
          final workDir = File(c).parent.path;

          final process = await Process.start(
            c,
            [],
            workingDirectory: workDir,
            environment: {
              'AGY_PORT': '$_stationPort',
              'AGY_HOST': '0.0.0.0',
              'AGY_PARENT_PID': '$pid',
            },
          );
          process.stdout.listen((data) => logFile.writeAsBytes(data, mode: FileMode.append).catchError((_) => logFile));
          process.stderr.listen((data) => logFile.writeAsBytes(data, mode: FileMode.append).catchError((_) => logFile));
          break;
        }
      }

      // Active poll loop: check every 500ms for up to 20s until FastAPI responds
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final res = await http.get(Uri.parse('http://127.0.0.1:$_stationPort/api/fleet/health'))
              .timeout(const Duration(seconds: 1));
          if (res.statusCode == 200) {
            if (mounted) {
              setState(() => _isBridgeOnline = true);
              await _fetchPairingInfo();
              ref.read(fleetProvider.notifier).loadFleet();
            }
            break;
          }
        } catch (_) {}
      }

      await _checkBridgeHealth();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isStartingBridge = false);
    }
  }

  Future<void> _fetchPairingInfo() async {
    final client = ref.read(agyClientProvider);
    Map<String, dynamic>? fetchedInfo;

    // Fast direct HTTP probe
    try {
      final info = await client.getPairingInfo().timeout(const Duration(milliseconds: 2000));
      final token = (info['token'] as String? ?? '').trim();
      if (token.isNotEmpty) {
        client.token = token;
        fetchedInfo = info;
      }
    } catch (_) {}

    if (fetchedInfo != null) {
      if (mounted) {
        setState(() {
          _isBridgeOnline = true;
          _bridgeFailCount = 0;
          _pairingInfo = fetchedInfo;
          final port = fetchedInfo?['port'];
          if (port is int && port > 0) {
            client.port = port;
          }
          final rawHosts = fetchedInfo?['hosts'] as List<dynamic>?;
          if (rawHosts != null && rawHosts.isNotEmpty) {
            _stationHosts = rawHosts.map((h) => h.toString()).toList();
          } else {
            _stationHosts = [fetchedInfo?['host']?.toString() ?? '127.0.0.1'];
          }
        });
      }
      return;
    }

    // Disk fallback if HTTP was not yet ready or failed
    String diskToken = '';
    int? diskPort;
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final cfgFile = File('$userProfile\\.antigravity-fleet\\config\\fleet_config.json');
      if (cfgFile.existsSync()) {
        final content = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
        final gw = content['gateway'] as Map<String, dynamic>?;
        diskToken = (gw?['pairing_token'] as String? ?? '').trim();
        final p = gw?['port'];
        if (p is int) diskPort = p;
      }
    } catch (_) {}
    if (diskPort != null && diskPort > 0) {
      client.port = diskPort;
    }

    // Enumerate active local network adapter IPs only if not already discovered
    List<String> discoveredIps = [];
    if (_stationHosts.isEmpty || _stationHosts.every((h) => h.startsWith('127.'))) {
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            if (!ip.startsWith('127.') && !ip.startsWith('169.254.') && !discoveredIps.contains(ip)) {
              discoveredIps.add(ip);
            }
          }
        }
      } catch (_) {}
    } else {
      discoveredIps = List.from(_stationHosts);
    }

    final effectiveToken = diskToken.isNotEmpty ? diskToken : (_pairingInfo?['token'] as String? ?? client.token);
    final primaryHost = discoveredIps.isNotEmpty ? discoveredIps.first : client.host;
    final allHosts = discoveredIps.isNotEmpty ? discoveredIps : [primaryHost];

    if (effectiveToken.isNotEmpty) {
      client.token = effectiveToken;
      if (mounted) {
        setState(() {
          _stationHosts = allHosts;
          _pairingInfo = {
            'host': primaryHost,
            'lan_ip': primaryHost,
            'hosts': allHosts,
            'port': client.port,
            'token': effectiveToken,
            'qr_payload': jsonEncode({
              'host': primaryHost,
              'hosts': allHosts,
              'port': client.port,
              'token': effectiveToken,
              'name': 'Antigravity Windows Station',
            }),
          };
        });
      }
    }
  }

  Future<String?> _getDefaultBrowserExe() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice',
        '/v', 'ProgId'
      ]);
      if (result.exitCode == 0) {
        final match = RegExp(r'ProgId\s+REG_SZ\s+(.+)').firstMatch(result.stdout.toString());
        if (match != null) {
          final progId = match.group(1)!.trim();
          final cmdResult = await Process.run('reg', [
            'query',
            'HKCR\\$progId\\shell\\open\\command'
          ]);
          if (cmdResult.exitCode == 0) {
            final cmdMatch = RegExp(r'REG_SZ\s+([^\n]+)').firstMatch(cmdResult.stdout.toString());
            if (cmdMatch != null) {
              String cmd = cmdMatch.group(1)!.trim();
              if (cmd.startsWith('"')) {
                cmd = cmd.substring(1, cmd.indexOf('"', 1));
              } else {
                cmd = cmd.split(' ')[0];
              }
              if (File(cmd).existsSync()) return cmd;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _launchForegroundWindow(int accountId, String targetUrl) async {
    if (!Platform.isWindows) return;
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final pdir = '$userProfile\\.antigravity-fleet\\browser_profile_${accountId.toString().padLeft(2, '0')}';
    
    String? browserExe = await _getDefaultBrowserExe();
    
    // Fallback candidates if registry check fails
    if (browserExe == null) {
      final progFiles = Platform.environment['PROGRAMFILES'] ?? 'C:\\Program Files';
      final progFilesX86 = Platform.environment['PROGRAMFILES(X86)'] ?? 'C:\\Program Files (x86)';
      final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
      final candidates = [
        '$progFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',
        '$progFiles\\Microsoft\\Edge\\Application\\msedge.exe',
        '$progFiles\\Google\\Chrome\\Application\\chrome.exe',
        if (localApp.isNotEmpty) '$localApp\\Google\\Chrome\\Application\\chrome.exe',
        if (userProfile.isNotEmpty) '$userProfile\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          browserExe = c;
          break;
        }
      }
    }

    try {
      if (browserExe != null) {
        await Process.start(browserExe, [
          '--user-data-dir=$pdir',
          '--new-window',
          targetUrl,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.run('cmd.exe', ['/c', 'start', '""', targetUrl]);
      }
    } catch (_) {
      try {
        await Process.run('cmd.exe', ['/c', 'start', '""', targetUrl]);
      } catch (_) {}
    }
  }

  Future<void> _launchAntigravityWindow(int accountId) async {
    if (!Platform.isWindows) return;
    final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
    final exePath = '$localApp\\Programs\\antigravity\\Antigravity.exe';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final pdir = '$userProfile\\.antigravity-fleet\\profile_${accountId.toString().padLeft(2, '0')}';
    if (File(exePath).existsSync()) {
      try {
        await Process.start(exePath, [
          '--user-data-dir=$pdir',
          '--new-window',
        ], mode: ProcessStartMode.detached);
      } catch (_) {}
    }
  }

  void _showPairingDialog() {
    // If token is missing, trigger async background fetch without stalling the UI
    final currentToken = (_pairingInfo?['token'] as String? ?? '').trim();
    if (currentToken.isEmpty) {
      _fetchPairingInfo();
    }

    showDialog(
      context: context,
      builder: (ctx) => _StationPairingDialog(
        stationPort: _stationPort,
        onRefresh: () async {
          await _fetchPairingInfo();
          if (mounted) setState(() {});
        },
        getPairingInfo: () => _pairingInfo,
        getStationHosts: () => _stationHosts,
        getClientToken: () => ref.read(agyClientProvider).token,
        getClientHost: () => ref.read(agyClientProvider).host,
      ),
    );
  }

  void _showAccountAuthDialog(WorkerAccount worker, {bool autoStart = false}) {
    final emailCtrl = TextEditingController(text: worker.email ?? '');
    final aliasCtrl = TextEditingController(text: worker.alias);
    bool isDetecting = false;
    bool isLaunching = false;
    bool isWaitingForAuth = false;
    String? authStatusText;
    String? currentOauthUrl;
    Timer? pollTimer;
    bool autoStarted = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isSlotAuth = (worker.email != null && worker.email!.isNotEmpty);

          void stopPolling() {
            pollTimer?.cancel();
            pollTimer = null;
            if (isWaitingForAuth) {
              ref.read(fleetProvider.notifier).cancelAuth(worker.accountId);
            }
          }

          void startPolling() {
            pollTimer?.cancel();
            pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
              final status = await ref.read(fleetProvider.notifier).checkAuthStatus(worker.accountId);
              final st = status['status'] as String?;
              final url = status['url'] as String?;

              if (url != null && url.isNotEmpty && url != currentOauthUrl) {
                final hadUrl = currentOauthUrl != null && currentOauthUrl!.isNotEmpty;
                setModalState(() {
                  currentOauthUrl = url;
                  authStatusText = 'Official Google Sign-In active. Choose your account.';
                });
                if (!hadUrl) {
                  await _launchForegroundWindow(worker.accountId, url);
                }
              }

              if (st == 'authenticated') {
                timer.cancel();
                pollTimer = null;
                final email = status['email'] as String? ?? '';
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Color(0xFF27272A),
                      content: Text('Account Slot #${worker.accountId} bound to $email'),
                    ),
                  );
                }
                ref.read(fleetProvider.notifier).loadFleet();
              } else if (st == 'timeout' || st == 'cancelled') {
                timer.cancel();
                pollTimer = null;
                if (context.mounted) {
                  setModalState(() {
                    isWaitingForAuth = false;
                    authStatusText = 'Sign-in session ended.';
                  });
                }
              }
            });
          }

          if (autoStart && !autoStarted && !isSlotAuth) {
            autoStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!context.mounted) return;
              setModalState(() {
                isLaunching = true;
                authStatusText = 'Starting worker and generating Google OAuth link...';
              });
              try {
                final res = await ref.read(fleetProvider.notifier).launchGoogleOAuth(worker.accountId);
                final ok = res['status'] == 'launched';
                final resolvedUrl = (res['url'] as String?);

                if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                  currentOauthUrl = resolvedUrl;
                  await _launchForegroundWindow(worker.accountId, resolvedUrl);
                } else {
                  await _launchAntigravityWindow(worker.accountId);
                }

                if (context.mounted) {
                  setModalState(() {
                    isLaunching = false;
                    if (ok) {
                      isWaitingForAuth = true;
                      authStatusText = resolvedUrl != null
                          ? 'Google Sign-In window launched. Choose or sign into your Google account.'
                          : 'Antigravity IDE window launched. Sign into your Google account to link Slot #${worker.accountId}.';
                      startPolling();
                    } else {
                      authStatusText = 'Failed: ${res['message'] ?? 'Could not launch Google Sign-In'}';
                    }
                  });
                }
              } catch (e) {
                if (context.mounted) {
                  setModalState(() {
                    isLaunching = false;
                    authStatusText = 'Error launching sign-in: $e';
                  });
                }
              }
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF0E0E10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF27272A)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${worker.accountId.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'AUTHENTICATE ACCOUNT SLOT #${worker.accountId.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dedicated Isolated Profile: ~/.antigravity-fleet/profile_${worker.accountId.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 18),

                    // Method A: Direct Official Google OAuth
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isWaitingForAuth ? const Color(0xFF52525B) : const Color(0xFF27272A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.login_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'Method A: Direct Google Account Sign-In',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Generates the official Google OAuth authorization link and opens an isolated browser window with zero saved cookies. Sign into your Google account to automatically bind Slot #${worker.accountId}.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5, height: 1.4),
                          ),
                          const SizedBox(height: 14),

                          if (isWaitingForAuth) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF18181B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF3F3F46)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'GOOGLE SIGN-IN ACTIVE',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              authStatusText ?? 'Complete Google Sign-In in the browser window...',
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          stopPolling();
                                          setModalState(() {
                                            isWaitingForAuth = false;
                                            authStatusText = 'Cancelled by user.';
                                          });
                                        },
                                        child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                  if (currentOauthUrl != null && currentOauthUrl!.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            currentOauthUrl!,
                                            style: const TextStyle(color: Colors.grey, fontSize: 9.5, fontFamily: 'monospace'),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: currentOauthUrl!));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Color(0xFF27272A),
                                                content: Text('Google Sign-In link copied to clipboard'),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Copy Link',
                                            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        InkWell(
                                          onTap: () => _launchForegroundWindow(
                                            worker.accountId,
                                            currentOauthUrl!,
                                          ),
                                          child: const Text(
                                            'Open Browser',
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          Row(
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isWaitingForAuth ? const Color(0xFF27272A) : Colors.white,
                                  foregroundColor: isWaitingForAuth ? Colors.white70 : Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: (isLaunching || isWaitingForAuth)
                                    ? null
                                    : () async {
                                        setModalState(() {
                                          isLaunching = true;
                                          authStatusText = 'Starting worker and generating Google OAuth link...';
                                        });
                                        final res = await ref.read(fleetProvider.notifier).launchGoogleOAuth(worker.accountId);
                                        final ok = res['status'] == 'launched';
                                        final resolvedUrl = (res['url'] as String?);

                                        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                                          currentOauthUrl = resolvedUrl;
                                          await _launchForegroundWindow(worker.accountId, resolvedUrl);
                                        } else {
                                          await _launchAntigravityWindow(worker.accountId);
                                        }

                                        setModalState(() {
                                          isLaunching = false;
                                          if (ok) {
                                            isWaitingForAuth = true;
                                            authStatusText = resolvedUrl != null
                                                ? 'Google Sign-In window launched. Choose or sign into your Google account.'
                                                : 'Antigravity IDE window launched. Sign into your Google account to link Slot #${worker.accountId}.';
                                            startPolling();
                                          } else {
                                            authStatusText = 'Failed to launch Google Sign-In.';
                                          }
                                        });
                                      },
                                icon: isLaunching
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 1.5))
                                    : Icon(
                                        isWaitingForAuth ? Icons.hourglass_top_rounded : Icons.login_rounded,
                                        size: 14,
                                        color: isWaitingForAuth ? Colors.white70 : Colors.black,
                                      ),
                                label: Text(
                                  isWaitingForAuth ? 'Awaiting Sign-In...' : 'Launch Google Sign-In Window',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF3F3F46)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: isDetecting
                                    ? null
                                    : () async {
                                        setModalState(() => isDetecting = true);
                                        final status = await ref.read(fleetProvider.notifier).checkAuthStatus(worker.accountId);
                                        final detected = status['email'] as String?;
                                        setModalState(() => isDetecting = false);
                                        if (detected != null && detected.isNotEmpty) {
                                          emailCtrl.text = detected;
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: Color(0xFF27272A),
                                                content: Text('Detected Google account: $detected'),
                                              ),
                                            );
                                          }
                                        } else {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Color(0xFF3F3F46),
                                                content: Text('No Google session found yet for this slot. Sign in first.'),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                icon: isDetecting
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                                    : const Icon(Icons.sync_rounded, size: 14),
                                label: const Text('Check Auth Now', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Method B: Direct Google Email & Alias Binding
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.alternate_email_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'Method B: Direct Account Binding',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Google Account Email', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: emailCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              hintText: 'e.g. your.other.account@gmail.com',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                              fillColor: const Color(0xFF09090B),
                              filled: true,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF27272A))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF27272A))),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('Custom Worker Alias', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: aliasCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'e.g. Worker-${worker.accountId.toString().padLeft(2, '0')}',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                              fillColor: const Color(0xFF09090B),
                              filled: true,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF27272A))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF27272A))),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () async {
                                final enteredEmail = emailCtrl.text.trim();
                                if (enteredEmail.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text('Please enter a valid Google Account email address.'),
                                    ),
                                  );
                                  return;
                                }
                                stopPolling();
                                Navigator.of(ctx).pop();
                                await ref.read(fleetProvider.notifier).saveAccount(
                                      worker.accountId,
                                      enteredEmail,
                                      alias: aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: Color(0xFF27272A),
                                      content: Text('Account Slot #${worker.accountId} linked to $enteredEmail'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.black),
                              label: const Text('Save & Authenticate Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (isSlotAuth) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF3F3F46)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () async {
                            stopPolling();
                            Navigator.of(ctx).pop();
                            await ref.read(fleetProvider.notifier).clearAuth(worker.accountId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF18181B),
                                  content: Text('Slot #${worker.accountId} unlinked.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 14),
                          label: const Text('Unlink Account / Reset Slot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  stopPolling();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Close', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDiagnosticsDialog() {
    _runDiagnostics();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF0C0C0E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF27272A), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM DIAGNOSTICS & CONNECTIVITY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Offline LAN, USB & Firewall Health Check',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Check 1: Gateway Status
                  _buildDiagRow(
                    title: 'Gateway Process (:$_stationPort)',
                    status: _isBridgeOnline ? 'ONLINE (Binding 0.0.0.0:$_stationPort)' : 'OFFLINE',
                    isOk: _isBridgeOnline,
                    actionText: _isBridgeOnline ? null : 'Restart Bridge',
                    onAction: () async {
                      await _ensureBridgeRunning();
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 8),

                  // Check 2: Windows Firewall
                  _buildDiagRow(
                    title: 'Windows Firewall (Port $_stationPort)',
                    status: _firewallStatus,
                    isOk: _firewallOk,
                    actionText: _firewallOk ? null : 'Auto-Repair (UAC)',
                    onAction: () async {
                      await _repairFirewall();
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 8),

                  // Check 3: Discovered LAN Adapters
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
                        const Row(
                          children: [
                            Icon(Icons.hub_rounded, size: 14, color: Colors.grey),
                            SizedBox(width: 8),
                            Text(
                              'Discovered Local IPs (Advertised in QR)',
                              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_stationHosts.isEmpty)
                          const Text('No active LAN IPs detected', style: TextStyle(color: Colors.grey, fontSize: 11))
                        else
                          ..._stationHosts.map((h) {
                            final pingOk = _hostPingResults[h] ?? false;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: pingOk ? Colors.white : const Color(0xFFA1A1AA),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$h:$_stationPort',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  const Spacer(),
                                  Text(
                                    pingOk ? 'Self-test PASS' : 'Self-test PENDING',
                                    style: TextStyle(
                                      color: pingOk ? Colors.white : const Color(0xFFA1A1AA),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Check 4: USB ADB Status
                  _buildDiagRow(
                    title: 'USB Direct Connect (ADB)',
                    status: _adbStatusText,
                    isOk: _adbStatusColor == Colors.white,
                    colorOverride: _adbStatusColor,
                    actionText: 'Rescan USB',
                    onAction: () async {
                      await _runAdbReverse();
                      setModalState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: _copyDiagnosticsReport,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF3F3F46)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('Copy Diagnostics Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagRow({
    required String title,
    required String status,
    required bool isOk,
    Color? colorOverride,
    String? actionText,
    VoidCallback? onAction,
  }) {
    final statusColor = colorOverride ?? (isOk ? Colors.white : const Color(0xFF71717A));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fleetState = ref.watch(fleetProvider);
    final fleetNotifier = ref.read(fleetProvider.notifier);

    final activeCount = fleetState.workers.where((w) => w.isActive).length;
    final authCount = fleetState.workers.where((w) => w.isRegistered && w.email != null && w.email!.isNotEmpty).length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Responsive Adaptive Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0E),
              border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 780;

                Widget buildActionButtons() {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mobile Pairing QR (Primary Action)
                      ElevatedButton.icon(
                        onPressed: _showPairingDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 16, color: Colors.black),
                        label: const Text('Pairing QR', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),

                      // Disclaimer (Secondary Action)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF3F3F46)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.gavel_outlined, size: 14, color: Colors.white70),
                        label: const Text('Disclaimer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 4),

                      // Discreet Refresh Button
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                        tooltip: 'Refresh Status',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        onPressed: () {
                          _ensureBridgeRunning();
                          fleetNotifier.loadFleet();
                          _fetchPairingInfo();
                        },
                      ),
                    ],
                  );
                }

                Widget buildTitleBlock() {
                  return Row(
                    children: [
                      const AntigravityLogo(size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ANTIGRAVITY // 15-ACCOUNT FLEET STATION',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            InkWell(
                              onTap: _showDiagnosticsDialog,
                              borderRadius: BorderRadius.circular(4),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Gateway Status (Clean Monochrome & Subtle LED)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: _isBridgeOnline ? Colors.white : const Color(0xFF52525B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isBridgeOnline ? 'Gateway Online (:$_stationPort)' : 'Gateway Connecting...',
                                      style: TextStyle(
                                        color: _isBridgeOnline ? Colors.white70 : Colors.white38,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (!_isBridgeOnline) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () async {
                                          await _fetchPairingInfo();
                                          await _checkBridgeHealth();
                                          if (!_isBridgeOnline) {
                                            await _ensureBridgeRunning();
                                          }
                                        },
                                        child: const Text(
                                          '[Retry]',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 12),

                                    // USB Connection Status (Subtle Zinc)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: _adbStatusColor == Colors.white ? Colors.white : const Color(0xFF52525B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _adbStatusText,
                                      style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(width: 12),

                                    // Accounts Summary
                                    Text(
                                      'Slots: $activeCount active / $authCount configured',
                                      style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: buildTitleBlock()),
                      const SizedBox(width: 12),
                      buildActionButtons(),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildTitleBlock(),
                      const SizedBox(height: 10),
                      buildActionButtons(),
                    ],
                  );
                }
              },
            ),
          ),

          // Worker Fleet Controls Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0E),
              border: Border(bottom: BorderSide(color: Color(0xFF1F1F23))),
            ),
            child: Row(
              children: [
                const Text(
                  'WORKER SLOTS (15 ACCOUNTS)',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => fleetNotifier.spawnAll(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3F3F46)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                  label: const Text('Spawn All (15)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => fleetNotifier.killAll(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Color(0xFF27272A)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 14, color: Colors.white60),
                  label: const Text('Kill All', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),

          // 15-Account Responsive Grid
          Expanded(
            child: fleetState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 360,
                      mainAxisExtent: 185,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: fleetState.workers.length,
                    itemBuilder: (context, index) {
                      final worker = fleetState.workers[index];
                      return _buildWorkerCard(worker, fleetNotifier);
                    },
                  ),
          ),

          // Legal Footer Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0E),
              border: Border(top: BorderSide(color: Color(0xFF1F1F23))),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unofficial Community Companion for Google Antigravity. Not affiliated with Google LLC.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11, letterSpacing: 0.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
                    );
                  },
                  child: Text(
                    'View Legal Disclaimer & ToS Notice',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(WorkerAccount worker, FleetNotifier notifier) {
    final isRunning = worker.isActive;
    final isAuth = (worker.email != null && worker.email!.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRunning
              ? Colors.white.withValues(alpha: 0.4)
              : isAuth
                  ? const Color(0xFF27272A)
                  : const Color(0xFF1E1E22),
          width: isRunning ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Badge + Title + Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isRunning ? Colors.white : const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '#${worker.accountId.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: isRunning ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  worker.alias,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isRunning
                      ? const Color(0xFF27272A)
                      : isAuth
                          ? const Color(0xFF18181B)
                          : const Color(0xFF121214),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isRunning
                        ? Colors.white
                        : isAuth
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFF27272A),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isRunning
                            ? Colors.white
                            : isAuth
                                ? const Color(0xFFA1A1AA)
                                : const Color(0xFF52525B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isRunning
                          ? 'RUNNING'
                          : isAuth
                              ? 'IDLE'
                              : 'UNLINKED',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isRunning
                            ? Colors.white
                            : isAuth
                                ? const Color(0xFFA1A1AA)
                                : const Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Email / Auth Status
          Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                size: 13,
                color: isAuth ? Colors.white70 : Colors.grey.shade600,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isAuth ? worker.email! : 'No Google Account Bound',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAuth ? Colors.white : Colors.grey.shade500,
                    fontSize: 11,
                    fontFamily: isAuth ? 'monospace' : null,
                    fontStyle: isAuth ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Port & Memory
          Row(
            children: [
              const Icon(Icons.settings_ethernet_rounded, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Text(
                'Port ${worker.port}',
                style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
              ),
              if (isRunning) ...[
                const SizedBox(width: 10),
                const Icon(Icons.memory_rounded, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  worker.pid != null ? 'PID ${worker.pid} • 85 MB' : '85 MB',
                  style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),

          const Spacer(),

          // Card Action Buttons
          Row(
            children: [
              if (!isAuth)
                // Prominent Google Sign-In Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAccountAuthDialog(worker, autoStart: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.login_rounded, size: 13, color: Colors.black),
                    label: const Text(
                      'Google Sign-In',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                )
              else ...[
                // Edit / Re-Auth Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAccountAuthDialog(worker),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3F3F46)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 12, color: Colors.white70),
                    label: const Text(
                      'Edit Auth',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Spawn / Kill Button
                if (!isRunning)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => notifier.spawnWorker(worker.accountId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 13, color: Colors.black),
                      label: const Text('Spawn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => notifier.killWorker(worker.accountId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 13),
                      label: const Text('Kill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StationPairingDialog extends StatefulWidget {
  final int stationPort;
  final Future<void> Function() onRefresh;
  final Map<String, dynamic>? Function() getPairingInfo;
  final List<String> Function() getStationHosts;
  final String Function() getClientToken;
  final String Function() getClientHost;

  const _StationPairingDialog({
    required this.stationPort,
    required this.onRefresh,
    required this.getPairingInfo,
    required this.getStationHosts,
    required this.getClientToken,
    required this.getClientHost,
  });

  @override
  State<_StationPairingDialog> createState() => _StationPairingDialogState();
}

class _StationPairingDialogState extends State<_StationPairingDialog> {
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _isRetryingTunnel = false;

  @override
  void initState() {
    super.initState();
    final pairingInfo = widget.getPairingInfo();
    final publicUrl = (pairingInfo?['public_url'] as String? ?? '').trim();
    if (publicUrl.isEmpty) {
      _startTimer();
    }
  }

  void _startTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      _pollCount++;
      await widget.onRefresh();
      if (mounted) {
        setState(() {});
      }
      final pairingInfo = widget.getPairingInfo();
      final hasTunnel = (pairingInfo?['public_url'] as String? ?? '').trim().isNotEmpty;
      if (hasTunnel || _pollCount >= 10) {
        timer.cancel();
      }
    });
  }

  Future<void> _retryTunnel() async {
    if (_isRetryingTunnel) return;
    setState(() {
      _isRetryingTunnel = true;
      _pollCount = 0;
    });
    try {
      final port = widget.stationPort;
      await http.post(
        Uri.parse('http://127.0.0.1:$port/api/tunnel/start'),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
    await widget.onRefresh();
    _startTimer();
    if (mounted) {
      setState(() {
        _isRetryingTunnel = false;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairingInfo = widget.getPairingInfo();
    final stationHosts = widget.getStationHosts();
    final clientToken = widget.getClientToken();
    final clientHost = widget.getClientHost();

    final rawToken = (pairingInfo?['token'] as String? ?? clientToken).trim();
    final hasValidToken = rawToken.isNotEmpty;
    final rawHost = pairingInfo?['lan_ip'] ?? pairingInfo?['host'] ?? clientHost;
    final cleanLanHost = rawHost.toString().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r':\d+$'), '');
    final port = pairingInfo?['port'] ?? widget.stationPort;
    final token = rawToken;
    final publicUrl = pairingInfo?['public_url']?.toString();

    final qrData = pairingInfo?['qr_payload'] ??
        jsonEncode({
          'host': cleanLanHost,
          'hosts': stationHosts.isNotEmpty ? stationHosts : [cleanLanHost],
          if (publicUrl != null && publicUrl.isNotEmpty) 'public_url': publicUrl,
          'port': port,
          'token': token,
          'name': 'Antigravity Windows Station',
        });

    return AlertDialog(
      backgroundColor: const Color(0xFF0C0C0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF27272A), width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MOBILE PAIRING QR CODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Scan from Antigravity Mobile for Permanent Binding',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (!hasValidToken) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'CONNECTING TO GATEWAY & GENERATING QR...',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Establishing local network listener and security credentials.\nYour pairing QR code will appear automatically in a few seconds.',
                        style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await widget.onRefresh();
                          if (mounted) setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.black),
                        label: const Text('Refresh Now', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text('LAN Wi-Fi', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const Spacer(),
                          SelectableText(
                            '$cleanLanHost:$port',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(color: Color(0xFF222226), height: 16),
                      Row(
                        children: [
                          const Icon(Icons.usb, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text('USB Tunnel', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const Spacer(),
                          SelectableText(
                            '127.0.0.1:${widget.stationPort}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(color: Color(0xFF222226), height: 16),
                      Row(
                        children: [
                          const Icon(Icons.key, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text('Pairing Token', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const Spacer(),
                          Text(
                            token.length > 18 ? '${token.substring(0, 16)}...' : token,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (publicUrl != null && publicUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3F3F46)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.public, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            const Text(
                              'Worldwide Remote (4G / Anywhere)',
                              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF27272A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF09090B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF27272A)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  publicUrl,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: publicUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Color(0xFF27272A),
                                      content: Text('Worldwide Remote URL copied to clipboard'),
                                    ),
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(2.0),
                                  child: Icon(Icons.copy, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_pollCount < 6 && !_isRetryingTunnel) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.public, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('Worldwide Remote', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const Spacer(),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                        ),
                        const SizedBox(width: 6),
                        Text('Negotiating (${(6 - _pollCount) * 2}s)...', style: const TextStyle(color: Colors.grey, fontSize: 10.5)),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
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
                        Row(
                          children: [
                            const Icon(Icons.public_off_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            const Text(
                              'Worldwide Remote',
                              style: TextStyle(color: Colors.grey, fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF27272A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'LOCAL LAN ONLY',
                                style: TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Local Wi-Fi & USB pairing are fully active and ready to use.',
                          style: TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: _isRetryingTunnel ? null : _retryTunnel,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F1F23),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF3F3F46)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isRetryingTunnel) ...[
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                    ),
                                    const SizedBox(width: 6),
                                  ] else ...[
                                    const Icon(Icons.refresh_rounded, size: 12, color: Colors.white),
                                    const SizedBox(width: 4),
                                  ],
                                  const Text(
                                    'Retry Tunnel',
                                    style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: qrData));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF27272A),
                              content: Text('Pairing payload copied to clipboard'),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF3F3F46)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy JSON', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        _pollCount = 0;
                        await widget.onRefresh();
                        _startTimer();
                        if (mounted) setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Refresh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


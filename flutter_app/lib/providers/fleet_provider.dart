import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/agy_client.dart';
import '../core/models/worker_account.dart';

final agyClientProvider = Provider<AgyClient>((ref) => AgyClient());

class FleetState {
  final List<WorkerAccount> workers;
  final int selectedAccountId;
  final String mode; // 'single_account', 'round_robin_pool', 'swarm_parallel'
  final bool isLoading;

  FleetState({
    required this.workers,
    this.selectedAccountId = 1,
    this.mode = 'single_account',
    this.isLoading = false,
  });

  FleetState copyWith({
    List<WorkerAccount>? workers,
    int? selectedAccountId,
    String? mode,
    bool? isLoading,
  }) {
    return FleetState(
      workers: workers ?? this.workers,
      selectedAccountId: selectedAccountId ?? this.selectedAccountId,
      mode: mode ?? this.mode,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FleetNotifier extends Notifier<FleetState> {
  Timer? _syncTimer;

  @override
  FleetState build() {
    ref.onDispose(() {
      _syncTimer?.cancel();
    });
    Future.microtask(() {
      loadFleet();
      _startSyncTimer();
    });
    return FleetState(workers: []);
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      loadFleet(silent: true);
    });
  }

  AgyClient get _client => ref.read(agyClientProvider);

  Future<void> _ensureToken() async {
    if (_client.token.isEmpty) {
      if (Platform.isWindows) {
        try {
          final userProfile = Platform.environment['USERPROFILE'] ?? '';
          final cfgFile = File('$userProfile\\.antigravity-fleet\\config\\fleet_config.json');
          if (cfgFile.existsSync()) {
            final content = jsonDecode(cfgFile.readAsStringSync());
            final t = content['gateway']?['pairing_token'] as String?;
            if (t != null && t.isNotEmpty) {
              _client.token = t;
              return;
            }
          }
        } catch (_) {}
      }
      try {
        final info = await _client.getPairingInfo();
        final token = info['token'] as String? ?? '';
        if (token.isNotEmpty) {
          _client.token = token;
        }
      } catch (_) {}
    }
  }

  Future<void> loadFleet({bool silent = false}) async {
    if (!silent && state.workers.isEmpty) {
      state = state.copyWith(isLoading: true);
    }
    try {
      await _ensureToken();
      final res = await _client.getFleetStatus();
      final rawWorkers = res['workers'] as List<dynamic>? ?? [];
      final mode = res['mode'] as String? ?? 'single_account';
      final workers = rawWorkers
          .map((w) => WorkerAccount.fromJson(w as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        workers: workers,
        mode: mode,
        isLoading: false,
      );
    } catch (_) {
      if (state.workers.isEmpty) {
        // Fallback generic 15 workers only if state is completely empty
        final fallbackWorkers = List.generate(
          15,
          (i) => WorkerAccount(
            accountId: i + 1,
            alias: 'Slot #${(i + 1).toString().padLeft(2, '0')}',
            email: null,
            port: 53001 + i,
            isActive: false,
            isRegistered: false,
            rateLimited: false,
          ),
        );
        state = state.copyWith(workers: fallbackWorkers, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void selectAccount(int accountId) {
    state = state.copyWith(selectedAccountId: accountId);
  }

  Future<void> setMode(String mode) async {
    state = state.copyWith(mode: mode);
    try {
      await _client.setFleetMode(mode);
    } catch (_) {}
  }

  Future<void> spawnWorker(int accountId) async {
    try {
      await _client.spawnWorker(accountId);
      await loadFleet();
    } catch (_) {}
  }

  Future<void> killWorker(int accountId) async {
    try {
      await _client.killWorker(accountId);
      await loadFleet();
    } catch (_) {}
  }

  Future<void> spawnAll() async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.spawnAll();
      await loadFleet();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> killAll() async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.killAll();
      await loadFleet();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> quickLogin(int accountId, {String? email, String? alias, String? token}) async {
    try {
      await _client.quickLogin(accountId, email: email, alias: alias, token: token);
      await loadFleet();
    } catch (_) {}
  }

  Future<void> batchLogin({String? baseEmail}) async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.batchLogin(baseEmail: baseEmail);
      await loadFleet();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> clearAuth(int accountId) async {
    try {
      await _client.clearAuth(accountId);
      await loadFleet();
    } catch (_) {}
  }

  Future<void> spawnMultiple(List<int> accountIds) async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.spawnMultiple(accountIds);
      await loadFleet();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> killMultiple(List<int> accountIds) async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.killMultiple(accountIds);
      await loadFleet();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<Map<String, dynamic>> launchGoogleOAuth(int accountId) async {
    try {
      await _ensureToken();
      final res = await _client.launchGoogleOAuth(accountId);
      return res;
    } catch (e) {
      debugPrint('[FleetNotifier] launchGoogleOAuth error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<String?> detectProfileAuth(int accountId) async {
    try {
      await _ensureToken();
      final email = await _client.detectProfileAuth(accountId);
      if (email != null) {
        await loadFleet();
      }
      return email;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> checkAuthStatus(int accountId) async {
    try {
      await _ensureToken();
      final res = await _client.checkAuthStatus(accountId);
      if (res['status'] == 'authenticated') {
        await loadFleet();
      }
      return res;
    } catch (e) {
      debugPrint('[FleetNotifier] checkAuthStatus error: $e');
      return {'status': 'unknown', 'message': e.toString()};
    }
  }

  Future<void> cancelAuth(int accountId) async {
    try {
      await _client.cancelAuth(accountId);
    } catch (_) {}
  }

  Future<void> saveAccount(int accountId, String email, {String? alias, String? token}) async {
    try {
      await _client.saveAccount(
        accountId: accountId,
        email: email,
        alias: alias,
        token: token,
      );
      await loadFleet();
    } catch (_) {}
  }
}

final fleetProvider = NotifierProvider<FleetNotifier, FleetState>(FleetNotifier.new);

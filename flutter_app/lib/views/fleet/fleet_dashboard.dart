import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/worker_account.dart';
import '../../core/theme/agy_theme.dart';
import '../../providers/fleet_provider.dart';

class FleetDashboard extends ConsumerWidget {
  const FleetDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleetState = ref.watch(fleetProvider);
    final notifier = ref.read(fleetProvider.notifier);
    final isDark = AgyTheme.isDark(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF4F4F5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
        elevation: 0,
        title: Text(
          '15-Account Fleet Orchestrator',
          style: TextStyle(
            color: AgyTheme.getTextPrimary(context),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            tooltip: 'Spawn All Workers',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Spawning all authenticated workers...'),
                  duration: Duration(seconds: 2),
                ),
              );
              notifier.spawnAll();
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            tooltip: 'Stop All Workers',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Stopping all running workers...'),
                  duration: Duration(seconds: 2),
                ),
              );
              notifier.killAll();
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AgyTheme.getTextPrimary(context)),
            tooltip: 'Refresh Status',
            onPressed: () => notifier.loadFleet(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workers List
          Expanded(
            child: fleetState.isLoading && fleetState.workers.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: fleetState.workers.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final worker = fleetState.workers[index];
                      final isSelected = worker.accountId == fleetState.selectedAccountId;
                      return _buildWorkerCard(context, ref, worker, isSelected, () {
                        notifier.selectAccount(worker.accountId);
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(
    BuildContext context,
    WidgetRef ref,
    WorkerAccount worker,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final notifier = ref.read(fleetProvider.notifier);
    final isDark = AgyTheme.isDark(context);
    final isRunning = worker.isActive;
    final isAuth = worker.isRegistered && (worker.email != null && worker.email!.isNotEmpty);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0C0C0E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : isRunning
                    ? (isDark ? const Color(0xFF34D399).withValues(alpha: 0.6) : const Color(0xFF10B981))
                    : (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7)),
            width: isSelected ? 1.6 : (isRunning ? 1.2 : 1.0),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Slot Badge + Alias + Status Pill + Select Indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '#${worker.accountId.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: isRunning
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.white : Colors.black),
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
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Status Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5))
                        : (isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isRunning
                          ? const Color(0xFF10B981)
                          : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8)),
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
                              ? const Color(0xFF34D399)
                              : (isAuth ? Colors.grey : Colors.grey.shade600),
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
                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                              : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Active Prompt Indicator
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8)),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Middle Row: Email & Port Info
            Row(
              children: [
                Icon(
                  Icons.alternate_email_rounded,
                  size: 12,
                  color: isAuth
                      ? (isDark ? Colors.white70 : Colors.black87)
                      : (isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA)),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isAuth ? worker.email! : 'No Google Account Bound',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isAuth
                          ? (isDark ? Colors.white70 : Colors.black87)
                          : (isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA)),
                      fontSize: 11,
                      fontFamily: isAuth ? 'monospace' : null,
                      fontStyle: isAuth ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.settings_ethernet_rounded,
                  size: 12,
                  color: isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                ),
                const SizedBox(width: 4),
                Text(
                  ':${worker.port}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (isRunning && worker.pid != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'PID ${worker.pid}',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // Bottom Action Buttons: Prominent Touch Targets
            Row(
              children: [
                if (!isAuth)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showAccountAuthDialog(context, ref, worker),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 14),
                      label: const Text(
                        'Google Sign-In',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                else ...[
                  // Edit / Re-Auth Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () => _showAccountAuthDialog(context, ref, worker),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AgyTheme.getTextPrimary(context),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 13),
                      label: const Text(
                        'Edit Auth',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Spawn / Kill Button
                  if (!isRunning)
                    Expanded(
                      flex: 1,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF27272A),
                              duration: const Duration(seconds: 2),
                              content: Text('Spawning Antigravity GUI for Slot #${worker.accountId}...'),
                            ),
                          );
                          notifier.spawnWorker(worker.accountId);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text(
                          'Spawn',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF7F1D1D),
                              duration: const Duration(seconds: 2),
                              content: Text('Terminating Slot #${worker.accountId}...'),
                            ),
                          );
                          notifier.killWorker(worker.accountId);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 16, color: Color(0xFFEF4444)),
                        label: const Text(
                          'Kill',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountAuthDialog(BuildContext context, WidgetRef ref, WorkerAccount worker) {
    final emailCtrl = TextEditingController(text: worker.email ?? '');
    final aliasCtrl = TextEditingController(text: worker.alias);
    bool isDetecting = false;
    bool isLaunching = false;
    bool isWaitingForAuth = false;
    String? authStatusText;
    Timer? pollTimer;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isSlotAuth = worker.isRegistered && (worker.email != null && worker.email!.isNotEmpty);

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
                      backgroundColor: const Color(0xFF10B981),
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
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSlotAuth ? 'Configure Slot #${worker.accountId}' : 'Authenticate Slot #${worker.accountId}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Worker Alias', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: aliasCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF18181B),
                      hintText: 'e.g. Worker-${worker.accountId.toString().padLeft(2, '0')}',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF27272A))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Email Address', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: emailCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF18181B),
                      hintText: 'user@example.com',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF27272A))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF27272A))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Google OAuth Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (isLaunching || isWaitingForAuth)
                          ? null
                          : () async {
                              setModalState(() {
                                isLaunching = true;
                                authStatusText = 'Starting Google Sign-In...';
                              });
                              try {
                                final res = await ref.read(fleetProvider.notifier).launchGoogleOAuth(worker.accountId);
                                setModalState(() {
                                  isLaunching = false;
                                  if (res['status'] == 'browser_launched' || res['status'] == 'waiting_for_callback') {
                                    isWaitingForAuth = true;
                                    authStatusText = 'Google Sign-In opened on Windows. Complete sign-in in browser.';
                                    startPolling();
                                  } else {
                                    authStatusText = res['message'] ?? 'Could not launch Google Sign-In';
                                  }
                                });
                              } catch (e) {
                                setModalState(() {
                                  isLaunching = false;
                                  authStatusText = 'Error launching OAuth: $e';
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: isLaunching
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.login_rounded, size: 16, color: Colors.black),
                      label: Text(
                        isWaitingForAuth ? 'Waiting for Sign-In...' : 'Launch Google Sign-In on Windows',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),

                  if (authStatusText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: Row(
                        children: [
                          if (isWaitingForAuth) ...[
                            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              authStatusText!,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  // Auto-detect local credentials button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isDetecting
                          ? null
                          : () async {
                              setModalState(() => isDetecting = true);
                              final detected = await ref.read(fleetProvider.notifier).detectProfileAuth(worker.accountId);
                              setModalState(() {
                                isDetecting = false;
                                if (detected != null) {
                                  emailCtrl.text = detected;
                                  authStatusText = 'Detected: $detected';
                                } else {
                                  authStatusText = 'No active profile found for Slot #${worker.accountId}';
                                }
                              });
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.sync_rounded, size: 14),
                      label: const Text('Auto-Detect Local State', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (isSlotAuth)
                TextButton(
                  onPressed: () async {
                    stopPolling();
                    Navigator.of(ctx).pop();
                    await ref.read(fleetProvider.notifier).clearAuth(worker.accountId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cleared credentials for Slot #${worker.accountId}')),
                      );
                    }
                  },
                  child: const Text('Clear Auth', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                ),
              TextButton(
                onPressed: () {
                  stopPolling();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () async {
                  stopPolling();
                  final email = emailCtrl.text.trim();
                  final alias = aliasCtrl.text.trim();
                  if (email.isNotEmpty) {
                    await ref.read(fleetProvider.notifier).quickLogin(
                          worker.accountId,
                          email: email,
                          alias: alias.isNotEmpty ? alias : null,
                        );
                  }
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

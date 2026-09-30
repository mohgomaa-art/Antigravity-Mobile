class WorkerAccount {
  final int accountId;
  final String alias;
  final String? email;
  final int port;
  final bool isActive;
  final bool isRegistered;
  final bool rateLimited;
  final int? pid;
  final double memoryMb;
  final String authType;

  WorkerAccount({
    required this.accountId,
    required this.alias,
    this.email,
    required this.port,
    required this.isActive,
    required this.isRegistered,
    required this.rateLimited,
    this.pid,
    this.memoryMb = 0.0,
    this.authType = 'google_oauth',
  });

  factory WorkerAccount.fromJson(Map<String, dynamic> json) {
    return WorkerAccount(
      accountId: json['account_id'] as int? ?? 1,
      alias: json['alias'] as String? ?? 'Antigravity',
      email: json['email'] as String?,
      port: json['port'] as int? ?? 53001,
      isActive: json['is_active'] as bool? ?? false,
      isRegistered: json['is_registered'] as bool? ?? false,
      rateLimited: json['rate_limited'] as bool? ?? false,
      pid: json['pid'] as int?,
      memoryMb: (json['memory_mb'] as num?)?.toDouble() ?? 0.0,
      authType: json['auth_type'] as String? ?? 'google_oauth',
    );
  }
}

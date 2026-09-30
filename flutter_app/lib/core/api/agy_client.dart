import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/skill.dart';
import '../models/workspace_node.dart';

class AgyClient {
  String host;
  int port;
  String token;

  AgyClient({
    this.host = '127.0.0.1',
    this.port = 8765,
    this.token = '',
  });

  String get baseUrl {
    String trimmed = host.trim();
    if (trimmed.isEmpty) return 'http://127.0.0.1:$port';

    // If it's a trycloudflare tunnel or remote https domain, ensure https:// and strip any port like :8765
    if (trimmed.contains('trycloudflare.com') ||
        trimmed.contains('ngrok') ||
        trimmed.contains('loca.lt') ||
        trimmed.contains('pinggy') ||
        trimmed.startsWith('https://')) {
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        trimmed = 'https://$trimmed';
      }
      // Remove any trailing port like :8765 because Cloudflare tunnels terminate on port 443
      trimmed = trimmed.replaceFirst(RegExp(r':\d+$'), '');
      return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    }

    if (trimmed.startsWith('http://')) {
      return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    }

    return 'http://$trimmed:$port';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Bridge-Token': token,
      };

  Future<Map<String, dynamic>> getFleetStatus() async {
    final res = await http.get(Uri.parse('$baseUrl/api/fleet/status'), headers: _headers);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get fleet status: ${res.statusCode}');
  }

  Future<void> setFleetMode(String mode) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/mode'),
      headers: _headers,
      body: jsonEncode({'mode': mode}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to set fleet mode: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> spawnWorker(int accountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/spawn/$accountId'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to spawn worker $accountId: ${res.statusCode}');
  }

  Future<void> killWorker(int accountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/kill/$accountId'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to kill worker $accountId: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> spawnAll() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/spawn_all'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to spawn all workers: ${res.statusCode}');
  }

  Future<void> killAll() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/kill_all'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to kill all workers: ${res.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getAuthStatus() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/fleet/auth_status'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['slots'] as List);
    }
    return [];
  }

  Future<void> updateAuthToken({
    required int accountId,
    required String email,
    required String token,
    String? authType,
    String? alias,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth_token'),
      headers: _headers,
      body: jsonEncode({
        'account_id': accountId,
        'email': email,
        'token': token,
        'auth_type': authType ?? 'google_oauth',
        'alias': alias,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update auth token: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> quickLogin(int accountId, {String? email, String? alias, String? token}) async {
    final payload = <String, dynamic>{'account_id': accountId};
    if (email != null) payload['email'] = email;
    if (alias != null) payload['alias'] = alias;
    if (token != null) payload['token'] = token;

    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth/login/$accountId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed quick login for account $accountId: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> batchLogin({String? baseEmail}) async {
    final payload = <String, dynamic>{};
    if (baseEmail != null) payload['base_email'] = baseEmail;

    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth/batch_login'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed batch login: ${res.statusCode}');
  }

  Future<void> clearAuth(int accountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth/clear/$accountId'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to clear auth for account $accountId: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> launchGoogleOAuth(int accountId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/fleet/auth/launch_oauth/$accountId'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'status': 'error'};
  }

  Future<String?> detectProfileAuth(int accountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth/detect/$accountId'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['email'] as String?;
    }
    return null;
  }

  Future<Map<String, dynamic>> checkAuthStatus(int accountId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/fleet/auth/status/$accountId'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'status': 'unknown'};
  }

  Future<void> cancelAuth(int accountId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/fleet/auth/cancel/$accountId'),
        headers: _headers,
      );
    } catch (_) {}
  }

  Future<void> saveAccount({
    required int accountId,
    required String email,
    String? alias,
    String? token,
  }) async {
    final payload = <String, dynamic>{
      'account_id': accountId,
      'email': email,
    };
    if (alias != null) payload['alias'] = alias;
    if (token != null) payload['token'] = token;

    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/auth/save_account'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to save account $accountId: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> spawnMultiple(List<int> accountIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/spawn_multiple'),
      headers: _headers,
      body: jsonEncode({'account_ids': accountIds}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to spawn multiple workers: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> killMultiple(List<int> accountIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/fleet/kill_multiple'),
      headers: _headers,
      body: jsonEncode({'account_ids': accountIds}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to kill multiple workers: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> getPairingInfo() async {
    final res = await http.get(Uri.parse('$baseUrl/api/pairing/info'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get pairing info: ${res.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getModels() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/models'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['models'] is List) {
          return List<Map<String, dynamic>>.from(data['models'] as List);
        }
      }
    } catch (e) {
      if (kDebugMode) print('getModels error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> getQuotaSummary() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/fleet/quota'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) print('getQuotaSummary error: $e');
    }
    return null;
  }


  Future<Map<String, dynamic>> switchModel(
    String model, {
    int? accountId,
    String? conversationId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/chat/model'),
        headers: _headers,
        body: jsonEncode({
          'model': model,
          'account_id': accountId,
          'conversation_id': conversationId,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'status': 'error'};
  }

  Future<Map<String, dynamic>> sendPrompt(
    String prompt, {
    int? accountId,
    String? conversationId,
    String? model,
    String? workspacePath,
    String? projectName,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final payload = {
      'prompt': prompt,
      'account_id': accountId,
      'conversation_id': conversationId,
      'model': model,
      'workspace_path': ?workspacePath,
      'project_name': ?projectName,
      if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
    };
    final res = await http.post(
      Uri.parse('$baseUrl/api/chat/send'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to send prompt: ${res.statusCode}');
  }

  Future<void> stopExecution() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/chat/stop'),
        headers: _headers,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> sendSteer(
    String prompt, {
    required String conversationId,
    int? accountId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chat/steer'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt,
        'conversation_id': conversationId,
        'account_id': accountId,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to send steer message: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> queueMessage(
    String prompt, {
    required String conversationId,
    int? accountId,
    String? model,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chat/queue'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt,
        'conversation_id': conversationId,
        'account_id': accountId,
        'model': model,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to queue message: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> getQueue(String conversationId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/chat/queue/${Uri.encodeComponent(conversationId)}'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'count': 0, 'queue': []};
  }

  Future<void> resolveApproval(String callId, bool approved) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/approvals/resolve'),
      headers: _headers,
      body: jsonEncode({
        'call_id': callId,
        'approved': approved,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to resolve approval: ${res.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> listWorkspaces() async {
    final res = await http.get(Uri.parse('$baseUrl/api/workspaces'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['roots'] as List);
    }
    return [];
  }

  Future<void> setWorkspace(String path) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/workspaces/active?path=${Uri.encodeComponent(path)}'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to set workspace: ${res.statusCode}');
    }
  }

  Future<List<WorkspaceNode>> getFileTree({int depth = 3}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/workspaces/tree?depth=$depth'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final rawList = data['tree'] as List<dynamic>;
      return rawList.map((e) => WorkspaceNode.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/workspaces/file?path=${Uri.encodeComponent(path)}'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to read file: ${res.statusCode}');
  }

  Future<void> writeFile(String path, String content) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/workspaces/file'),
      headers: _headers,
      body: jsonEncode({'path': path, 'content': content}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to write file: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> executeCommand(String command) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/workspaces/command'),
      headers: _headers,
      body: jsonEncode({'command': command}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to execute command: ${res.statusCode}');
  }

  Future<List<SkillModel>> listSkills() async {
    final res = await http.get(Uri.parse('$baseUrl/api/skills'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final raw = data['skills'] as List<dynamic>;
      return raw.map((e) => SkillModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<void> toggleSkill(String name, bool enabled) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/skills/toggle?name=${Uri.encodeComponent(name)}&enabled=$enabled'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to toggle skill: ${res.statusCode}');
    }
  }

  String getMediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl/api/media/file?path=${Uri.encodeComponent(path)}';
  }

  Future<Map<String, dynamic>> uploadMedia(
    List<int> bytes,
    String filename, {
    String? conversationId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/media/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers);
    if (conversationId != null && conversationId.isNotEmpty) {
      req.fields['conversation_id'] = conversationId;
    }
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    final streamedRes = await req.send();
    final res = await http.Response.fromStream(streamedRes);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to upload media: ${res.statusCode} - ${res.body}');
  }

  Future<List<Map<String, dynamic>>> searchWorkspaceFiles(String query, {int limit = 50}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/workspaces/files?query=${Uri.encodeComponent(query)}&limit=$limit'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final raw = data['files'] as List<dynamic>? ?? [];
      return List<Map<String, dynamic>>.from(raw);
    }
    return [];
  }

  Future<Map<String, dynamic>> getSkillDetail(String skillId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/skills/${Uri.encodeComponent(skillId)}'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get skill: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> createSkill({
    required String name,
    required String description,
    required String instructions,
    String source = 'global',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/skills'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'description': description,
        'instructions': instructions,
        'source': source,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to create skill: ${res.statusCode} - ${res.body}');
  }

  Future<Map<String, dynamic>> updateSkill(
    String skillId, {
    required String description,
    required String instructions,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/skills/${Uri.encodeComponent(skillId)}'),
      headers: _headers,
      body: jsonEncode({
        'description': description,
        'instructions': instructions,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to update skill: ${res.statusCode} - ${res.body}');
  }

  Future<void> deleteSkill(String skillId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/skills/${Uri.encodeComponent(skillId)}'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete skill: ${res.statusCode} - ${res.body}');
    }
  }

  Future<List<Map<String, dynamic>>> listHistory() async {
    final res = await http.get(Uri.parse('$baseUrl/api/history'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['conversations'] as List);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getTranscript(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/history/$conversationId/transcript'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['transcript'] as List);
    }
    return [];
  }

  Future<Map<String, dynamic>> createNewConversation({
    String? workspacePath,
    String? projectName,
    String? model,
    int? accountId,
  }) async {
    final payload = <String, dynamic>{};
    if (workspacePath != null) payload['workspace_path'] = workspacePath;
    if (projectName != null) payload['project_name'] = projectName;
    if (model != null) payload['model'] = model;
    if (accountId != null) payload['account_id'] = accountId;

    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/new'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Failed to create new conversation: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> getProjectsGrouped({String? convoId, String? project}) async {
    try {
      final queryParams = <String, String>{};
      if (convoId != null) queryParams['convo_id'] = convoId;
      if (project != null) queryParams['project'] = project;

      final uri = Uri.parse('$baseUrl/api/projects/grouped')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[AgyClient] getProjectsGrouped error: $e');
    }
    return {'active_project': project ?? 'Antigravity', 'projects': []};
  }

  Future<Map<String, dynamic>> addProject(String name, String path) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/projects/add'),
      headers: _headers,
      body: jsonEncode({'name': name, 'path': path}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to add project: ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> removeProject(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/projects/remove'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to remove project: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getConversationSteps(String conversationId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/conversations/$conversationId/steps'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return data;
      }
    } catch (e, stack) {
      debugPrint('[AgyClient] getConversationSteps error: $e\n$stack');
    }
    return {};
  }

  Future<Map<String, dynamic>> getRunningTasks([String conversationId = '']) async {
    try {
      final uri = conversationId.isNotEmpty
          ? Uri.parse('$baseUrl/api/tasks/running?conversation_id=${Uri.encodeComponent(conversationId)}')
          : Uri.parse('$baseUrl/api/tasks/running');
      final res = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[AgyClient] getRunningTasks error: $e');
    }
    return {'count': 0, 'tasks': []};
  }

  Future<String> getTaskLog({String taskId = '', String logUri = ''}) async {
    try {
      final q = taskId.isNotEmpty
          ? 'task_id=${Uri.encodeComponent(taskId)}'
          : 'log_uri=${Uri.encodeComponent(logUri)}';
      final res = await http.get(Uri.parse('$baseUrl/api/tasks/log?$q'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return data['log'] as String? ?? '';
      }
    } catch (e) {
      debugPrint('[AgyClient] getTaskLog error: $e');
    }
    return '';
  }

  Future<List<Map<String, dynamic>>> getCommands() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/commands'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(data['commands'] as List? ?? []);
      }
    } catch (e) {
      debugPrint('[AgyClient] getCommands error: $e');
    }
    return [];
  }
}

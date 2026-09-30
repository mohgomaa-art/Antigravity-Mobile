import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/agy_client.dart';
import '../core/api/ws_channel.dart';
import '../core/models/chat_message.dart';
import '../core/services/pairing_service.dart';
import 'fleet_provider.dart';
import 'projects_provider.dart';

final wsServiceProvider = Provider<WebSocketService>((ref) {
  final pairing = ref.watch(pairingProvider);
  final ws = WebSocketService(
    host: pairing.host,
    port: pairing.port,
    token: pairing.token,
  );
  ws.connect();
  ref.onDispose(() => ws.disconnect());
  return ws;
});

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final Map<String, dynamic>? pendingApproval; // {call_id, tool_name, args}
  final Map<String, dynamic>? pendingQuestion; // {call_id, questions, tool_summary}
  final int queuedCount;
  final List<String> queuedPrompts;

  ChatState({
    required this.messages,
    this.isStreaming = false,
    this.pendingApproval,
    this.pendingQuestion,
    this.queuedCount = 0,
    this.queuedPrompts = const [],
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    Map<String, dynamic>? pendingApproval,
    bool clearApproval = false,
    Map<String, dynamic>? pendingQuestion,
    bool clearQuestion = false,
    int? queuedCount,
    List<String>? queuedPrompts,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      pendingApproval: clearApproval ? null : (pendingApproval ?? this.pendingApproval),
      pendingQuestion: clearQuestion ? null : (pendingQuestion ?? this.pendingQuestion),
      queuedCount: queuedCount ?? this.queuedCount,
      queuedPrompts: queuedPrompts ?? this.queuedPrompts,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  StreamSubscription? _sub;
  String? _lastDispatchedPrompt;
  DateTime? _lastDispatchTime;

  AgyClient get _client => ref.read(agyClientProvider);
  WebSocketService get _ws => ref.read(wsServiceProvider);

  @override
  ChatState build() {
    ref.listen<WebSocketService>(wsServiceProvider, (previous, next) {
      debugPrint('[ChatNotifier] wsServiceProvider changed (${next.host}:${next.port}). Re-subscribing live stream.');
      _subscribeToWs(next);
    });

    _subscribeToWs(ref.read(wsServiceProvider));

    ref.onDispose(() {
      _sub?.cancel();
    });
    return ChatState(
      messages: const [],
    );
  }

  void _subscribeToWs(WebSocketService ws) {
    _sub?.cancel();
    _sub = ws.stream.listen((event) {
      _handleWsEvent(event);
    });
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final accountId = event['account_id'] as int? ?? 1;

    if (type == 'token') {
      final token = event['data'] as String? ?? '';
      _appendToken(accountId, token);
    } else if (type == 'thought') {
      final thought = event['data'] as String? ?? '';
      _appendThought(accountId, thought);
    } else if (type == 'conversation_created') {
      final newId = event['conversation_id'] as String?;
      if (newId != null) {
        ref.read(projectsProvider.notifier).updateConversationId(newId);
      }
    } else if (type == 'message_queued') {
      final qCount = event['queue_count'] as int? ?? (state.queuedCount + 1);
      final prompt = event['prompt'] as String? ?? '';
      final newPrompts = List<String>.from(state.queuedPrompts);
      if (prompt.isNotEmpty && !newPrompts.contains(prompt)) {
        newPrompts.add(prompt);
      }
      state = state.copyWith(queuedCount: qCount, queuedPrompts: newPrompts);
    } else if (type == 'steer_sent') {
      final prompt = event['prompt'] as String? ?? '';
      if (prompt.isNotEmpty) {
        _appendThought(accountId, '\n[Steer] $prompt\n');
      }
    } else if (type == 'done' || type == 'cancelled' || type == 'error') {
      _finishStream(accountId);
      final currentConvoId = ref.read(projectsProvider).activeConversationId;
      ref.read(projectsProvider.notifier).loadSteps(currentConvoId);
      if (state.queuedCount > 0) {
        final newCount = state.queuedCount - 1;
        final newPrompts = state.queuedPrompts.length > 1
            ? state.queuedPrompts.sublist(1)
            : <String>[];
        state = state.copyWith(
          queuedCount: newCount,
          queuedPrompts: newPrompts,
          isStreaming: newCount > 0,
        );
      }
    } else if (type == 'steps_updated') {
      final currentConvoId = ref.read(projectsProvider).activeConversationId;
      ref.read(projectsProvider.notifier).loadSteps(currentConvoId);
      ref.read(projectsProvider.notifier).loadProjects();
    } else if (type == 'tool_approval_request') {
      state = state.copyWith(pendingApproval: event);
    } else if (type == 'ask_question') {
      state = state.copyWith(pendingQuestion: event, isStreaming: false);
    }
  }

  void setStreaming(bool value) {
    if (state.isStreaming != value) {
      state = state.copyWith(isStreaming: value);
    }
  }

  void resolveQuestion(String answer) {
    state = state.copyWith(clearQuestion: true);
    final accountId = ref.read(fleetProvider).selectedAccountId;
    final convoId = ref.read(projectsProvider).activeConversationId;
    sendUserPrompt(answer, accountId, conversationId: convoId);
  }

  void clearInFlight() {
    if (state.messages.isNotEmpty || state.isStreaming) {
      state = state.copyWith(messages: const [], isStreaming: false);
    }
  }

  void _finishStream(int accountId) {
    state = state.copyWith(isStreaming: false);
  }

  void resetConversation() {
    state = state.copyWith(
      messages: const [],
      isStreaming: false,
      queuedCount: 0,
      queuedPrompts: const [],
    );
  }

  void _appendToken(int accountId, String token) {
    final index = state.messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );
    if (index != -1) {
      final old = state.messages[index];
      final updated = old.copyWith(text: old.text + token, isStreaming: true);
      final newMessages = List<ChatMessage>.from(state.messages);
      newMessages[index] = updated;
      state = state.copyWith(messages: newMessages, isStreaming: true);
    } else {
      final newMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        accountId: accountId,
        text: token,
        isStreaming: true,
      );
      state = state.copyWith(
        messages: [...state.messages, newMsg],
        isStreaming: true,
      );
    }
  }

  void _appendThought(int accountId, String thought) {
    final index = state.messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );
    if (index != -1) {
      final old = state.messages[index];
      final updated = old.copyWith(thinking: old.thinking + thought, isStreaming: true);
      final newMessages = List<ChatMessage>.from(state.messages);
      newMessages[index] = updated;
      state = state.copyWith(messages: newMessages, isStreaming: true);
    } else {
      final newMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        accountId: accountId,
        text: '',
        thinking: thought,
        isStreaming: true,
      );
      state = state.copyWith(
        messages: [...state.messages, newMsg],
        isStreaming: true,
      );
    }
  }

  Future<void> sendUserPrompt(
    String text,
    int targetAccountId, {
    String? conversationId,
    String? model,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty && (attachments == null || attachments.isEmpty)) return;
    final now = DateTime.now();
    if (clean.isNotEmpty && _lastDispatchedPrompt == clean && _lastDispatchTime != null && now.difference(_lastDispatchTime!).inMilliseconds < 1500) {
      debugPrint('[ChatNotifier] Ignored duplicate sendUserPrompt within 1500ms: $clean');
      return;
    }
    _lastDispatchedPrompt = clean;
    _lastDispatchTime = now;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      accountId: targetAccountId,
      text: text,
      attachments: attachments,
    );

    final assistantMsg = ChatMessage(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      role: MessageRole.assistant,
      accountId: targetAccountId,
      text: '',
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [userMsg, assistantMsg],
      isStreaming: true,
    );

    String? wsPath;
    String? projectName;
    try {
      final pState = ref.read(projectsProvider);
      projectName = pState.activeProject;
      for (final p in pState.projects) {
        if (p.name == pState.activeProject && p.path.isNotEmpty) {
          wsPath = p.path;
          break;
        }
      }
    } catch (_) {}

    try {
      final res = await _client.sendPrompt(
        text,
        accountId: targetAccountId,
        conversationId: conversationId,
        model: model,
        workspacePath: wsPath,
        projectName: projectName,
        attachments: attachments,
      );
      final returnedConvoId = res['conversation_id'] as String?;
      if (returnedConvoId != null && returnedConvoId != conversationId) {
        ref.read(projectsProvider.notifier).updateConversationId(returnedConvoId);
      }
      final targetConvoId = returnedConvoId ?? conversationId ?? ref.read(projectsProvider).activeConversationId;
      ref.read(projectsProvider.notifier).loadSteps(targetConvoId);
      Future.delayed(const Duration(milliseconds: 1000), () {
        ref.read(projectsProvider.notifier).loadSteps(targetConvoId);
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        ref.read(projectsProvider.notifier).loadSteps(targetConvoId);
      });
      Future.delayed(const Duration(milliseconds: 4000), () {
        ref.read(projectsProvider.notifier).loadProjects();
      });
    } catch (e) {
      assistantMsg.text = 'Error sending prompt: $e';
      assistantMsg.isStreaming = false;
      state = state.copyWith(
        messages: List.from(state.messages),
        isStreaming: false,
      );
    }
  }

  void finishAllStreaming() {
    state = state.copyWith(isStreaming: false);
  }

  void stopStreaming() {
    state = state.copyWith(messages: const [], isStreaming: false);
  }

  Future<void> sendSteer(
    String text, {
    required String conversationId,
    int? accountId,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    if (_lastDispatchedPrompt == clean && _lastDispatchTime != null && now.difference(_lastDispatchTime!).inMilliseconds < 1500) {
      debugPrint('[ChatNotifier] Ignored duplicate sendSteer within 1500ms: $clean');
      return;
    }
    _lastDispatchedPrompt = clean;
    _lastDispatchTime = now;

    final steerMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      accountId: accountId ?? 1,
      text: '[Steer] $text',
    );
    final assistantMsg = ChatMessage(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      role: MessageRole.assistant,
      accountId: accountId ?? 1,
      text: '',
      isStreaming: true,
    );
    final purgedQueue = state.queuedPrompts.where((p) => p.trim() != clean).toList();
    state = state.copyWith(
      messages: [steerMsg, assistantMsg],
      isStreaming: true,
      queuedPrompts: purgedQueue,
      queuedCount: purgedQueue.length,
    );

    try {
      await _client.sendSteer(
        text,
        conversationId: conversationId,
        accountId: accountId,
      );
    } catch (e) {
      debugPrint('[ChatNotifier] Steer error: $e');
    }
  }

  Future<void> queuePrompt(
    String text, {
    required String conversationId,
    int? accountId,
    String? model,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    if (_lastDispatchedPrompt == clean && _lastDispatchTime != null && now.difference(_lastDispatchTime!).inMilliseconds < 1500) {
      debugPrint('[ChatNotifier] Ignored duplicate queuePrompt within 1500ms: $clean');
      return;
    }
    _lastDispatchedPrompt = clean;
    _lastDispatchTime = now;

    try {
      final res = await _client.queueMessage(
        text,
        conversationId: conversationId,
        accountId: accountId,
        model: model,
      );
      if (res['status'] == 'ignored_steered') {
        debugPrint('[ChatNotifier] Ignored queuePrompt: prompt was recently steered');
        return;
      }
      final qCount = res['queue_count'] as int? ?? (state.queuedCount + 1);
      final newPrompts = List<String>.from(state.queuedPrompts);
      if (!newPrompts.contains(clean)) {
        newPrompts.add(clean);
      }
      state = state.copyWith(queuedCount: qCount, queuedPrompts: newPrompts);
    } catch (e) {
      debugPrint('[ChatNotifier] Queue error: $e');
    }
  }

  Future<void> switchModel(String model, {int? accountId, String? conversationId}) async {
    final activeConvoId = conversationId ?? ref.read(projectsProvider).activeConversationId;
    final targetAccountId = accountId ?? ref.read(fleetProvider).selectedAccountId;
    try {
      await _client.switchModel(
        model,
        accountId: targetAccountId,
        conversationId: activeConvoId,
      );
    } catch (_) {}
  }

  Future<void> resolveApproval(String callId, bool approved) async {
    _ws.sendApproval(callId, approved);
    try {
      await _client.resolveApproval(callId, approved);
    } catch (_) {}
    state = state.copyWith(clearApproval: true);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

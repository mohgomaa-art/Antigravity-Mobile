import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/agy_client.dart';
import '../../core/models/chat_message.dart';
import '../../core/theme/agy_theme.dart';
import '../../core/theme/language_icons.dart';
import '../../providers/chat_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/projects_provider.dart';
import 'interactive_question_card.dart';
import 'prompt_composer.dart';
import 'tool_approval_sheet.dart';
import '../workspaces/file_viewer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _expandedTurnIds = {};
  final Set<int> _collapsedTurnIds = {};
  final Set<int> _expandedThoughtTurnIds = {};
  final Set<int> _collapsedThoughtTurnIds = {};
  final Set<int> _collapsedReviewTurnIds = {};
  final Set<String> _expandedExploreKeys = {};
  String? _expandedCommandKey;
  bool _isTasksExpanded = true;
  bool _showScrollToBottom = false;
  int _unreadCount = 0;
  String? _lastConvoId;
  int _lastTurnsCount = 0;
  int _lastStepLogsCount = 0;

  bool _hasQuestionContent(Map<String, dynamic>? data) {
    if (data == null) return false;
    final questions = data['questions'];
    if (questions is List && questions.isNotEmpty) return true;
    if (questions is String && questions.trim().isNotEmpty && questions.trim() != '[]') return true;
    if (data['question'] != null && data['question'].toString().trim().isNotEmpty) return true;
    if (data['question_data'] is Map) return _hasQuestionContent(Map<String, dynamic>.from(data['question_data'] as Map));
    if (data['arguments'] is Map) return _hasQuestionContent(Map<String, dynamic>.from(data['arguments'] as Map));
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final isFar = (maxScroll - currentScroll) > 90;
    if (isFar != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = isFar;
        if (!isFar) _unreadCount = 0;
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = MediaQuery.maybeViewInsetsOf(context)?.bottom ??
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    if (bottomInset > 0) {
      // Keyboard popped up - auto-scroll to bottom so chat messages are pushed up and visible
      _scrollToBottom(smooth: false);
      Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom(smooth: true));
      Future.delayed(const Duration(milliseconds: 350), () => _scrollToBottom(smooth: true));
    }
  }

  void _scrollToBottomIterative({int maxAttempts = 6}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(target);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final newTarget = _scrollController.position.maxScrollExtent;
      if (newTarget > target && maxAttempts > 0) {
        _scrollToBottomIterative(maxAttempts: maxAttempts - 1);
      } else {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        if (_showScrollToBottom) {
          setState(() {
            _showScrollToBottom = false;
            _unreadCount = 0;
          });
        }
      }
    });
  }

  void _scrollToBottom({bool smooth = true}) {
    if (_scrollController.hasClients) {
      if (smooth) {
        final current = _scrollController.offset;
        final maxExt = _scrollController.position.maxScrollExtent;
        if ((maxExt - current) > 1200) {
          _scrollController.jumpTo(maxExt - 300);
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollToBottomIterative();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final selectedAccountId = ref.watch(fleetProvider.select((f) => f.selectedAccountId));
    final projectsState = ref.watch(projectsProvider);
    final client = ref.read(agyClientProvider);

    final steps = projectsState.activeSteps ?? {};
    final rawTurns = (steps['turns'] as List<dynamic>?) ?? [];
    final runningTasks = projectsState.runningTasks;
    debugPrint('[ChatScreen] convoId: ${projectsState.activeConversationId}, activeSteps: ${projectsState.activeSteps != null}, rawTurns: ${rawTurns.length}');

    final currentConvoId = projectsState.activeConversationId;
    final convoChanged = _lastConvoId != currentConvoId;
    final turnsChanged = rawTurns.length != _lastTurnsCount;
    final currentStepLogsCount = rawTurns.isNotEmpty ? ((rawTurns.last as Map<String, dynamic>?)?['step_logs'] as List<dynamic>?)?.length ?? 0 : 0;
    final stepLogsChanged = currentStepLogsCount != _lastStepLogsCount;

    if (convoChanged || (turnsChanged && rawTurns.length > _lastTurnsCount)) {
      _lastConvoId = currentConvoId;
      _lastTurnsCount = rawTurns.length;
      _lastStepLogsCount = currentStepLogsCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollToBottom(smooth: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollToBottom(smooth: false);
          }
        });
      });
    } else if (stepLogsChanged && !_showScrollToBottom) {
      _lastStepLogsCount = currentStepLogsCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollToBottom(smooth: true);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      final isFar = (maxScroll - currentScroll) > 90;
      if (isFar != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = isFar;
          if (!isFar) _unreadCount = 0;
        });
      }
    });

    final fallbackPrompt = (steps['user_prompt'] as String? ?? '').trim();
    final fallbackContent = (steps['final_content'] as String? ?? '').trim();

    final turns = rawTurns.isNotEmpty
        ? rawTurns
        : (fallbackPrompt.isNotEmpty || fallbackContent.isNotEmpty
            ? [
                {
                  'turn_id': 1,
                  'user_prompt': fallbackPrompt,
                  'edited_files': steps['edited_files'] ?? [],
                  'explored_files_count': steps['explored_files_count'] ?? 0,
                  'tasks_count': steps['tasks_count'] ?? 0,
                  'commands_count': steps['commands_count'] ?? 0,
                  'step_logs': steps['step_logs'] ?? [],
                  'thinking': steps['thinking'] ?? '',
                  'response': fallbackContent,
                  'is_working': steps['is_working'] ?? false,
                }
              ]
            : <dynamic>[]);

    final hasPendingQuestion = chatState.pendingQuestion != null ||
        (turns.isNotEmpty &&
            _hasQuestionContent((turns.last as Map<String, dynamic>)['question_data'] as Map<String, dynamic>?) &&
            (turns.last as Map<String, dynamic>)['question_data']?['answered'] != true);

    final lastTurn = turns.isNotEmpty ? (turns.last as Map<String, dynamic>) : null;
    final lastTurnExplicitWorking = lastTurn?['is_working'] == true;

    // Detect if the active in-flight prompt in chatState has already been committed to turns
    final inFlightUserMsg = chatState.messages.where((m) => m.role == MessageRole.user).lastOrNull;
    final inFlightPrompt = inFlightUserMsg != null
        ? inFlightUserMsg.text.replaceFirst('[Steer] ', '').trim().toLowerCase()
        : '';

    final bool inFlightAlreadyCommitted;
    if (hasPendingQuestion) {
      inFlightAlreadyCommitted = true;
    } else if (inFlightUserMsg == null || inFlightPrompt.isEmpty) {
      inFlightAlreadyCommitted = true;
    } else if (turns.isEmpty) {
      inFlightAlreadyCommitted = false;
    } else {
      final lastTurn = turns.last as Map<String, dynamic>;
      final lastPrompt = (lastTurn['user_prompt'] as String? ?? '').trim().toLowerCase();
      final promptMatches = lastPrompt.isNotEmpty && (lastPrompt == inFlightPrompt || lastPrompt.contains(inFlightPrompt) || inFlightPrompt.contains(lastPrompt));
      inFlightAlreadyCommitted = promptMatches;
    }

    // Only render live uncommitted messages when NOT yet recorded in turns
    final uncommittedMessages = inFlightAlreadyCommitted
        ? <ChatMessage>[]
        : chatState.messages.where((msg) => msg.id != 'welcome').toList();

    final bool isWorking;
    if (hasPendingQuestion) {
      isWorking = false;
    } else if (!inFlightAlreadyCommitted) {
      isWorking = true;
    } else if (lastTurnExplicitWorking || steps['is_working'] == true || chatState.isStreaming) {
      isWorking = true;
    } else {
      isWorking = false;
    }

    if (inFlightAlreadyCommitted && chatState.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(chatProvider.notifier).clearInFlight();
        }
      });
    }

    return Column(
      children: [
        if (chatState.pendingApproval != null)
          ToolApprovalCard(
            approvalData: chatState.pendingApproval!,
            onDecision: (callId, approved) {
              ref.read(chatProvider.notifier).resolveApproval(callId, approved);
            },
          ),

        // Main Antigravity IDE Execution Canvas (Full Chronological Multi-Turn History)
        Expanded(
          child: Stack(
            children: [
              ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                children: [
                  ...turns.map((turnData) {
                    final turn = turnData as Map<String, dynamic>;
                    final turnId = turn['turn_id'] as int? ?? 1;
                    final prompt = turn['user_prompt'] as String? ?? '';
                    final promptTime = turn['prompt_time'] as String? ?? '';
                    final workedDuration = turn['worked_duration'] as String? ?? 'Worked for 1m';
                    final thoughtDuration = turn['thought_duration'] as String? ?? 'Thought for a few seconds';
                    final editedFiles = (turn['edited_files'] as List<dynamic>?) ?? [];
                    final exploredCount = turn['explored_files_count'] as int? ?? 0;
                    final tasksCount = turn['tasks_count'] as int? ?? 0;
                    final commandsCount = turn['commands_count'] as int? ?? 0;
                    final stepLogs = (turn['step_logs'] as List<dynamic>?) ?? [];
                    final thinking = turn['thinking'] as String? ?? '';
                    final response = turn['response'] as String? ?? '';
                    final questionData = turn['question_data'] as Map<String, dynamic>?;
                    final isLastTurn = turns.isNotEmpty && identical(turn, turns.last);
                    final isTurnWorking = isLastTurn && isWorking;
                    final bool isWorkExpanded;
                    if (_expandedTurnIds.contains(turnId)) {
                      isWorkExpanded = true;
                    } else if (_collapsedTurnIds.contains(turnId)) {
                      isWorkExpanded = false;
                    } else {
                      isWorkExpanded = isTurnWorking || isLastTurn;
                    }

                    final bool isThoughtExpanded;
                    if (_expandedThoughtTurnIds.contains(turnId)) {
                      isThoughtExpanded = true;
                    } else if (_collapsedThoughtTurnIds.contains(turnId)) {
                      isThoughtExpanded = false;
                    } else {
                      isThoughtExpanded = isTurnWorking && thinking.trim().isNotEmpty && response.isEmpty;
                    }

                    return _buildTurnBlock(
                      context,
                      turnId: turnId,
                      prompt: prompt,
                      promptTime: promptTime,
                      workedDuration: workedDuration,
                      thoughtDuration: thoughtDuration,
                      editedFiles: editedFiles,
                      exploredCount: exploredCount,
                      tasksCount: tasksCount,
                      commandsCount: commandsCount,
                      stepLogs: stepLogs,
                      thinking: thinking,
                      response: response,
                      isWorking: isTurnWorking,
                      isWorkExpanded: isWorkExpanded,
                      isThoughtExpanded: isThoughtExpanded,
                      questionData: questionData,
                    );
                  }),


                  // Live incoming interactive question from stream
                  if (chatState.pendingQuestion != null &&
                      (turns.isEmpty ||
                          (turns.last as Map<String, dynamic>)['question_data'] == null ||
                          (turns.last as Map<String, dynamic>)['question_data']?['call_id'] !=
                              chatState.pendingQuestion!['call_id']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: InteractiveQuestionCard(
                        questionData: chatState.pendingQuestion!,
                        isPending: true,
                        onAnswer: (answer) {
                          ref.read(chatProvider.notifier).resolveQuestion(answer);
                        },
                      ),
                    ),

                  // Live uncommitted messages (shows immediately on Send with 0ms delay)
                  if (uncommittedMessages.isNotEmpty)
                    ...uncommittedMessages.map((msg) => _buildLiveMessageItem(context, msg)),
                ],
              ),

              // Go Down to Last Message Floating Button
              if (_showScrollToBottom)
                Positioned(
                  bottom: 12,
                  right: 16,
                  child: _buildScrollToBottomButton(context),
                ),
            ],
          ),
        ),

        // Running Tasks Banner (Matching Desktop PC Image 1)
        if (runningTasks.isNotEmpty)
          _buildRunningTasksBanner(context, runningTasks),

        // Floating Antigravity Prompt Composer with Dynamic Stop/Send/Steer/Queue State
        PromptComposer(
          activeAccountId: selectedAccountId,
          client: client,
          isStreaming: isWorking,
          queuedCount: chatState.queuedCount,
          onFocus: () {
            Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom(smooth: true));
            Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom(smooth: true));
          },
          onClear: () {
            ref.read(projectsProvider.notifier).newConversation();
          },
          onModelChanged: (model) {
            ref.read(chatProvider.notifier).switchModel(model);
          },
          onSend: (text, model, {attachments}) {
            ref.read(chatProvider.notifier).sendUserPrompt(
              text,
              selectedAccountId,
              conversationId: projectsState.activeConversationId,
              model: model,
              attachments: attachments,
            );
            Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
          },
          onSteer: (text) {
            ref.read(chatProvider.notifier).sendSteer(
              text,
              conversationId: projectsState.activeConversationId,
              accountId: selectedAccountId,
            );
            Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
          },
          onQueue: (text, model) {
            ref.read(chatProvider.notifier).queuePrompt(
              text,
              conversationId: projectsState.activeConversationId,
              accountId: selectedAccountId,
              model: model,
            );
          },
          onStop: () {
            ref.read(chatProvider.notifier).stopStreaming();
            ref.read(projectsProvider.notifier).stopExecution();
          },
        ),
      ],
    );
  }

  // --- Turn Block UI ---

  Widget _buildTurnBlock(
    BuildContext context, {
    required int turnId,
    required String prompt,
    required String promptTime,
    required String workedDuration,
    required String thoughtDuration,
    required List<dynamic> editedFiles,
    required int exploredCount,
    required int tasksCount,
    required int commandsCount,
    required List<dynamic> stepLogs,
    required String thinking,
    required String response,
    required bool isWorking,
    required bool isWorkExpanded,
    required bool isThoughtExpanded,
    Map<String, dynamic>? questionData,
  }) {
    final hasThinking = thinking.trim().isNotEmpty || (isWorking && stepLogs.isEmpty && response.isEmpty);
    final hasTools = stepLogs.isNotEmpty || exploredCount > 0 || commandsCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. User Prompt Bubble (Rounded card with border, timestamp & copy/retry at bottom right)
          if (prompt.trim().isNotEmpty) ...[
            _buildUserPromptPill(context, prompt, promptTime),
            const SizedBox(height: 6),
          ],

          // 2. Thought Section: 'Thought for 12s >' (NO BOX!)
          if (hasThinking) ...[
            _buildThoughtSection(
              context,
              turnId: turnId,
              durationText: isWorking && response.isEmpty ? 'Thinking...' : thoughtDuration,
              isExpanded: isThoughtExpanded,
              isWorking: isWorking && response.isEmpty,
              thinking: thinking,
            ),
            const SizedBox(height: 6),
          ],

          // 3. Work Steps Section: 'Worked for 3m >' (NO BOX!)
          if (hasTools || (isWorking && stepLogs.isNotEmpty)) ...[
            _buildWorkHeaderAndSteps(
              context,
              turnId: turnId,
              durationText: isWorking ? 'Working...' : workedDuration,
              isExpanded: isWorkExpanded,
              isWorking: isWorking,
              stepLogs: stepLogs,
            ),
            const SizedBox(height: 6),
          ],


          // 4b. Interactive Choice / Question Card (ask_question)
          if (_hasQuestionContent(questionData)) ...[
            const SizedBox(height: 8),
            InteractiveQuestionCard(
              questionData: questionData!,
              isPending: questionData['answered'] != true,
              onAnswer: (answer) {
                ref.read(chatProvider.notifier).sendUserPrompt(
                  answer,
                  ref.read(fleetProvider).selectedAccountId,
                  conversationId: ref.read(projectsProvider).activeConversationId,
                );
              },
            ),
          ],

          // 5. Assistant Response (if any)
          if (response.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildAssistantTurnResponse(context, response),
          ],

          // 7. Changed Files Review Card (Screenshot 1)
          if (editedFiles.isNotEmpty) ...[
            _buildFileReviewCard(context, turnId, editedFiles),
          ],
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton(BuildContext context) {
    final isDark = AgyTheme.isDark(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _scrollToBottomIterative(),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF22242B) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white30 : Colors.black26,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 15,
                color: AgyTheme.getTextPrimary(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Latest message',
                style: TextStyle(
                  color: AgyTheme.getTextPrimary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              if (_unreadCount > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getCommandLabel(String cmd) {
    switch (cmd.toLowerCase()) {
      case '/plan':
        return 'Architectural Planning Mode';
      case '/btw':
        return 'Side Question';
      case '/browser':
        return 'Web & Browser Automation';
      case '/goal':
        return 'Autonomous Goal Runner';
      case '/schedule':
        return 'Automation Schedule';
      case '/grill-me':
        return 'Design Review Interview';
      case '/boost':
        return 'Cognitive Boost Analysis';
      case '/learn':
        return 'Project Learning Guideline';
      case '/clear':
      case '/reset':
        return 'Chat Reset';
      case '/help':
        return 'Antigravity Help';
      default:
        return 'Specialized Directive';
    }
  }

  Widget _buildUserPromptPill(BuildContext context, String prompt, String? promptTime, {List<Map<String, dynamic>>? attachments}) {
    final trimmed = prompt.trim();
    final isSteer = trimmed.startsWith('[Steer]');
    final isCommand = !isSteer && trimmed.startsWith('/');
    String? cmdName;
    String cleanText = trimmed;

    if (isSteer) {
      cleanText = trimmed.replaceFirst('[Steer]', '').trim();
    } else if (isCommand) {
      final spaceIdx = trimmed.indexOf(' ');
      if (spaceIdx != -1) {
        cmdName = trimmed.substring(0, spaceIdx);
        cleanText = trimmed.substring(spaceIdx + 1).trim();
      } else {
        cmdName = trimmed;
        cleanText = '';
      }
    }

    final isDark = AgyTheme.isDark(context);
    final bgColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
    final textPrimary = AgyTheme.getTextPrimary(context);
    final textMuted = AgyTheme.getTextMuted(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSteer) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.near_me_rounded,
                        size: 11,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'STEER',
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Mid-Execution Guidance',
                  style: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (cmdName != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 11,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        cmdName.toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getCommandLabel(cmdName),
                  style: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (attachments != null && attachments.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: attachments.map((att) {
                  final name = att['filename'] as String? ?? att['original_name'] as String? ?? 'attachment';
                  final mime = att['mime_type'] as String? ?? '';
                  final path = att['absolute_path'] as String? ?? att['url'] as String? ?? '';
                  final isImg = mime.startsWith('image/') ||
                      name.toLowerCase().endsWith('.png') ||
                      name.toLowerCase().endsWith('.jpg') ||
                      name.toLowerCase().endsWith('.jpeg');

                  if (isImg) {
                    final mediaUrl = AgyClient().getMediaUrl(path);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: AgyTheme.getSurfaceLight(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const Center(
                            child: Icon(Icons.image, size: 24, color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AgyTheme.getSurfaceLight(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file, size: 13, color: textMuted),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            name,
                            style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (cleanText.isNotEmpty)
            SelectableText(
              cleanText,
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 8),
          // Bottom action row: Timestamp, Copy, Retry
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (promptTime != null && promptTime.isNotEmpty) ...[
                Text(
                  promptTime,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // Copy icon
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: prompt));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Prompt copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.copy_outlined,
                    size: 13.5,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Retry / Edit icon
              InkWell(
                onTap: () {
                  ref.read(chatProvider.notifier).sendUserPrompt(
                    prompt,
                    ref.read(fleetProvider).selectedAccountId,
                    conversationId: ref.read(projectsProvider).activeConversationId,
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.replay,
                    size: 14,
                    color: textMuted,
                  ),
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  // --- Antigravity PC Unboxed Thought Stream ---

  Widget _buildThoughtSection(
    BuildContext context, {
    required int turnId,
    required String durationText,
    required bool isExpanded,
    required bool isWorking,
    required String thinking,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedThoughtTurnIds.remove(turnId);
                _collapsedThoughtTurnIds.add(turnId);
              } else {
                _collapsedThoughtTurnIds.remove(turnId);
                _expandedThoughtTurnIds.add(turnId);
              }
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    durationText,
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 16,
                  color: AgyTheme.getTextMuted(context),
                ),
                if (isWorking) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
            child: thinking.trim().isNotEmpty
                ? MarkdownBody(
                    data: thinking,
                    sizedImageBuilder: (config) => _buildMarkdownImage(context, config.uri, config.title, config.alt),
                    onTapLink: (text, href, title) {
                      if (href != null && href.isNotEmpty) {
                        _handleMarkdownLinkTap(context, href, text);
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: AgyTheme.getTextSecondary(context),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                      code: TextStyle(
                        backgroundColor: AgyTheme.getInlineCodeBg(context),
                        color: AgyTheme.getInlineCodeText(context),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : (isWorking
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(
                          'Thinking and analyzing instructions...',
                          style: TextStyle(
                            color: AgyTheme.getTextMuted(context),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
          ),
      ],
    );
  }

  // --- Antigravity PC Unboxed Work Stream & Steps ---

  Widget _buildWorkHeaderAndSteps(
    BuildContext context, {
    required int turnId,
    required String durationText,
    required bool isExpanded,
    required bool isWorking,
    required List<dynamic> stepLogs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Master unboxed header: 'Worked for 14m v' (or 'Working...')
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedTurnIds.remove(turnId);
                _collapsedTurnIds.add(turnId);
              } else {
                _collapsedTurnIds.remove(turnId);
                _expandedTurnIds.add(turnId);
              }
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    durationText,
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 16,
                  color: AgyTheme.getTextMuted(context),
                ),
                if (isWorking) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Under header (when expanded) - NO BOX! Just clean unboxed lines:
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Steps stream in chronological order
                ...stepLogs.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value as Map<String, dynamic>;
                  final type = item['type'] as String? ?? '';

                  if (type == 'file_edit') {
                    return _buildStepFileEditRow(context, item);
                  } else if (type == 'explore_summary' || type == 'explore_file' || type == 'file_view') {
                    return _buildStepExploreRow(context, turnId, idx, item);
                  } else if (type == 'command') {
                    return _buildStepCommandRow(context, turnId, idx, item);
                  } else {
                    return _buildGenericStepRow(context, item);
                  }
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStepFileEditRow(BuildContext context, Map<String, dynamic> step) {
    final fname = step['file'] as String? ?? step['name'] as String? ?? 'file';
    final fpath = step['path'] as String? ?? fname;
    final adds = step['additions'] as int? ?? 0;
    final dels = step['deletions'] as int? ?? 0;

    return InkWell(
      onTap: () => _openFileViewer(context, fname, fpath),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edited ',
              style: TextStyle(
                color: AgyTheme.getTextSecondary(context),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
            ),
            LanguageFileIcon(filename: fname, size: 14.5),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                fname,
                style: TextStyle(
                  color: AgyTheme.getTextPrimary(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (adds > 0 || dels > 0) ...[
              if (adds > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+$adds',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (dels > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '-$dels',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepExploreRow(BuildContext context, int turnId, int stepIdx, Map<String, dynamic> step) {
    final title = step['title'] as String? ?? 'Explored files';
    final key = 't${turnId}_e$stepIdx';
    final isExpanded = _expandedExploreKeys.contains(key);
    final rawFiles = step['files'] as List<dynamic>?;
    final List<Map<String, String>> files = [];

    if (rawFiles != null && rawFiles.isNotEmpty) {
      for (final f in rawFiles) {
        if (f is Map) {
          final n = (f['name'] ?? f['file'] ?? '').toString();
          final p = (f['path'] ?? n).toString();
          if (n.isNotEmpty) files.add({'name': n, 'path': p});
        } else if (f is String && f.isNotEmpty) {
          files.add({'name': f, 'path': f});
        }
      }
    } else if (step['file'] != null) {
      final n = step['file'].toString();
      final p = (step['path'] ?? n).toString();
      files.add({'name': n, 'path': p});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedExploreKeys.remove(key);
              } else {
                _expandedExploreKeys.add(key);
              }
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 15,
                  color: AgyTheme.getTextMuted(context),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded && files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: files.map((f) {
                final fname = f['name']!;
                final fpath = f['path']!;
                return InkWell(
                  onTap: () => _openFileViewer(context, fname, fpath),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LanguageFileIcon(filename: fname, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            fname,
                            style: TextStyle(
                              color: AgyTheme.getTextPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildStepCommandRow(BuildContext context, int turnId, int stepIdx, Map<String, dynamic> step) {
    final isDark = AgyTheme.isDark(context);
    final rawCmd = step['command'] as String? ?? step['title'] as String? ?? 'Command';
    final title = step['title'] as String? ?? 'Ran $rawCmd';
    final cmdKey = 't${turnId}_s$stepIdx';
    final isExpanded = _expandedCommandKey == cmdKey;
    final output = step['output'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expandedCommandKey = isExpanded ? null : cmdKey;
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 15,
                  color: AgyTheme.getTextMuted(context),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1014) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AgyTheme.getBorder(context),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Terminal header: .../dir > command and copy icon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AgyTheme.getBorder(context), width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rawCmd,
                          style: TextStyle(
                            color: AgyTheme.getTextPrimary(context),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: output.isNotEmpty ? output : rawCmd));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Command output copied'), duration: Duration(seconds: 1)),
                          );
                        },
                        child: Icon(Icons.copy_outlined, size: 13, color: AgyTheme.getTextMuted(context)),
                      ),
                    ],
                  ),
                ),
                // Terminal scrollable output
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: _buildOutputWithDiffHighlighting(
                      context,
                      output.isNotEmpty ? output : 'Command completed successfully.',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGenericStepRow(BuildContext context, Map<String, dynamic> step) {
    final title = step['title'] as String? ?? 'Action executed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: AgyTheme.getTextSecondary(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 14,
            color: AgyTheme.getTextMuted(context),
          ),
        ],
      ),
    );
  }

  // --- Changed Files Review Card (Screenshot 1) ---

  Widget _buildFileReviewCard(BuildContext context, int turnId, List<dynamic> editedFiles) {
    final isExpanded = !_collapsedReviewTurnIds.contains(turnId);
    final isDark = AgyTheme.isDark(context);
    final bgColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);

    int totalAdds = 0;
    int totalDels = 0;
    for (final f in editedFiles) {
      final map = f as Map<String, dynamic>;
      totalAdds += map['additions'] as int? ?? 0;
      totalDels += map['deletions'] as int? ?? 0;
    }

    final count = editedFiles.length;
    final countText = '$count ${count == 1 ? 'file' : 'files'} changed';

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar: "2 files changed +7 -21 v" and "[Review]" button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _collapsedReviewTurnIds.add(turnId);
                        } else {
                          _collapsedReviewTurnIds.remove(turnId);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            countText,
                            style: TextStyle(
                              color: AgyTheme.getTextPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (totalAdds > 0)
                          Text(
                            '+$totalAdds',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (totalAdds > 0 && totalDels > 0)
                          const SizedBox(width: 4),
                        if (totalDels > 0)
                          Text(
                            '-$totalDels',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(width: 6),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                          size: 16,
                          color: AgyTheme.getTextMuted(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Review button
                InkWell(
                  onTap: () {
                    if (editedFiles.isNotEmpty) {
                      final first = editedFiles.first as Map<String, dynamic>;
                      final fname = first['name'] as String? ?? 'file';
                      final fpath = first['path'] as String? ?? fname;
                      _openFileViewer(context, fname, fpath);
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 14,
                          color: AgyTheme.getTextPrimary(context),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Review',
                          style: TextStyle(
                            color: AgyTheme.getTextPrimary(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded list of changed files
          if (isExpanded) ...[
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: editedFiles.map((f) {
                  final map = f as Map<String, dynamic>;
                  final fname = map['name'] as String? ?? 'file';
                  final fpath = map['path'] as String? ?? fname;
                  String dirPath = '';
                  if (fpath.contains('/') || fpath.contains('\\')) {
                    final normalized = fpath.replaceAll('\\', '/');
                    final lastSlash = normalized.lastIndexOf('/');
                    if (lastSlash != -1) {
                      dirPath = normalized.substring(0, lastSlash);
                    }
                  }

                  return InkWell(
                    onTap: () => _openFileViewer(context, fname, fpath),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          LanguageFileIcon(filename: fname, size: 14.5),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fname,
                              style: TextStyle(
                                color: AgyTheme.getTextPrimary(context),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (dirPath.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dirPath,
                                style: TextStyle(
                                  color: AgyTheme.getTextMuted(context),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }


  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    final isDark = AgyTheme.isDark(context);
    final textPrimary = AgyTheme.getTextPrimary(context);
    final textSecondary = AgyTheme.getTextSecondary(context);

    return MarkdownStyleSheet(
      p: TextStyle(
        color: textPrimary,
        fontSize: 14.5,
        height: 1.5,
      ),
      h1: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h2: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h3: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h4: TextStyle(
        color: textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      strong: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.bold,
      ),
      em: TextStyle(
        color: textPrimary,
        fontStyle: FontStyle.italic,
      ),
      code: TextStyle(
        backgroundColor: AgyTheme.getInlineCodeBg(context),
        color: AgyTheme.getInlineCodeText(context),
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: AgyTheme.getCodeBg(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgyTheme.getCodeBorder(context), width: 0.8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF141519) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: TextStyle(
        color: textSecondary,
        fontSize: 14.5,
      ),
      tableHead: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 13.5,
      ),
      tableBody: TextStyle(
        color: textPrimary,
        fontSize: 13.5,
      ),
      tableBorder: TableBorder.all(
        color: AgyTheme.getBorder(context),
        width: 0.8,
      ),
      tableHeadAlign: TextAlign.left,
      tablePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  Widget _buildMarkdownImage(BuildContext context, Uri uri, String? title, String? alt) {
    final uriStr = uri.toString();
    final client = AgyClient();
    final finalUrl = client.getMediaUrl(uriStr);
    final displayTitle = alt ?? title ?? 'Image';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _openImageViewer(context, uriStr, displayTitle),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            finalUrl,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AgyTheme.getSurfaceLight(ctx),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgyTheme.getBorder(ctx)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 16, color: AgyTheme.getTextSecondary(ctx)),
                  const SizedBox(width: 6),
                  Text(displayTitle, style: TextStyle(color: AgyTheme.getTextSecondary(ctx), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantTurnResponse(BuildContext context, String response) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MarkdownBody(
        data: response,
        sizedImageBuilder: (config) => _buildMarkdownImage(context, config.uri, config.title, config.alt),
        onTapLink: (text, href, title) {
          if (href != null && href.isNotEmpty) {
            _handleMarkdownLinkTap(context, href, text);
          }
        },
        styleSheet: _buildMarkdownStyleSheet(context),
      ),
    );
  }

  void _showTaskLogSheet(BuildContext context, Map<String, dynamic> task) {
    final isDark = AgyTheme.isDark(context);
    final taskId = task['id'] as String? ?? '';
    final logUri = task['log_uri'] as String? ?? '';
    final cmd = task['command'] as String? ?? 'Task';
    final client = ref.read(agyClientProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141518) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: AgyTheme.getBorder(context)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AgyTheme.getBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      size: 18,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cmd,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: AgyTheme.getTextPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AgyTheme.getTextMuted(context),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AgyTheme.getBorder(context)),
              Expanded(
                child: FutureBuilder<String>(
                  future: client.getTaskLog(taskId: taskId, logUri: logUri),
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final logText = snapshot.data ?? '';
                    if (logText.isEmpty) {
                      return Center(
                        child: Text(
                          'No output recorded yet.',
                          style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 13),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      reverse: true,
                      child: SelectableText(
                        logText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.45,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Running Tasks Banner (Strictly Matching Desktop PC Image 1) ---

  Widget _buildRunningTasksBanner(BuildContext context, List<Map<String, dynamic>> tasks) {
    final isDark = AgyTheme.isDark(context);
    final count = tasks.length;
    final title = count == 1 ? '1 task running' : '$count tasks running';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2024) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isTasksExpanded = !_isTasksExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isTasksExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 16,
                    color: AgyTheme.getTextMuted(context),
                  ),
                ],
              ),
            ),
          ),
          if (_isTasksExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tasks.map((t) {
                  final cmd = t['command'] as String? ?? 'Task';
                  return InkWell(
                    onTap: () => _showTaskLogSheet(context, t),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cmd,
                              style: TextStyle(
                                color: AgyTheme.getTextPrimary(context),
                                fontSize: 12.5,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.terminal_rounded,
                            size: 15,
                            color: AgyTheme.getTextMuted(context),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveMessageItem(BuildContext context, ChatMessage msg) {
    final isUser = msg.role == MessageRole.user;

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildUserPromptPill(context, msg.text, null, attachments: msg.attachments),
      );
    }

    final thinkingText = msg.thinking.trim();
    final hasThinking = thinkingText.isNotEmpty;
    final hasText = msg.text.trim().isNotEmpty;
    final isStreamingWithoutContent = msg.isStreaming && !hasThinking && !hasText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasThinking) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.isStreaming && !hasText ? 'Thinking...' : 'Thoughts',
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (msg.isStreaming && !hasText) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AgyTheme.getTextPrimary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: MarkdownBody(
                data: thinkingText,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 13,
                    height: 1.45,
                  ),
                  code: TextStyle(
                    backgroundColor: AgyTheme.getInlineCodeBg(context),
                    color: AgyTheme.getInlineCodeText(context),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ] else if (isStreamingWithoutContent) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasText)
            MarkdownBody(
              data: msg.text,
              sizedImageBuilder: (config) => _buildMarkdownImage(context, config.uri, config.title, config.alt),
              onTapLink: (text, href, title) {
                if (href != null && href.isNotEmpty) {
                  _handleMarkdownLinkTap(context, href, text);
                }
              },
              styleSheet: _buildMarkdownStyleSheet(context),
            ),
        ],
      ),
    );
  }


  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  void _openImageViewer(BuildContext context, String imageUrlOrPath, String title) {
    final client = AgyClient();
    final finalUrl = (imageUrlOrPath.startsWith('http://') || imageUrlOrPath.startsWith('https://'))
        ? imageUrlOrPath
        : client.getMediaUrl(imageUrlOrPath);

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (modalCtx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.85),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(modalCtx).pop(),
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Image.network(
                finalUrl,
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  );
                },
                errorBuilder: (ctx, err, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
                      const SizedBox(height: 12),
                      const Text('Failed to load image', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(imageUrlOrPath, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFileViewer(BuildContext context, String filename, String? filePath) {
    final targetPath = filePath ?? filename;
    if (_isImageFile(targetPath) || _isImageFile(filename)) {
      _openImageViewer(context, targetPath, filename);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileViewerScreen(
          filePath: targetPath,
          fileName: filename,
        ),
      ),
    );
  }

  void _handleMarkdownLinkTap(BuildContext context, String href, String text) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      if (_isImageFile(href)) {
        _openImageViewer(context, href, text.isNotEmpty ? text : 'Image');
        return;
      }
      return;
    }
    String cleanPath = href;
    if (cleanPath.startsWith('file:///')) {
      cleanPath = cleanPath.substring(8);
    } else if (cleanPath.startsWith('file://')) {
      cleanPath = cleanPath.substring(7);
    }
    final name = cleanPath.split(RegExp(r'[/\\]')).last;
    if (_isImageFile(cleanPath) || _isImageFile(name)) {
      _openImageViewer(context, cleanPath, name.isNotEmpty ? name : text);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileViewerScreen(
          filePath: cleanPath,
          fileName: name.isNotEmpty ? name : text,
        ),
      ),
    );
  }

  Widget _buildOutputWithDiffHighlighting(BuildContext context, String text) {
    final lines = text.split('\n');
    final isDiff = lines.any((l) => l.startsWith('@@') || (l.startsWith('+') && !l.startsWith('+++')) || (l.startsWith('-') && !l.startsWith('---')));

    if (!isDiff) {
      return Text(
        text,
        style: TextStyle(
          color: AgyTheme.getTextSecondary(context),
          fontSize: 10.5,
          fontFamily: 'monospace',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        Color textColor = AgyTheme.getTextSecondary(context);
        Color? bgColor;

        if (line.startsWith('+') && !line.startsWith('+++')) {
          textColor = const Color(0xFF22C55E); // Green for additions
          bgColor = const Color(0x1F22C55E);
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          textColor = const Color(0xFFEF4444); // Red for deletions
          bgColor = const Color(0x1FEF4444);
        } else if (line.startsWith('@@')) {
          textColor = const Color(0xFF60A5FA); // Cyan for hunk header
          bgColor = const Color(0x1460A5FA);
        }

        return Container(
          width: double.infinity,
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
          child: Text(
            line,
            style: TextStyle(
              color: textColor,
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
        );
      }).toList(),
    );
  }
}

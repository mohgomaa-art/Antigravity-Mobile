import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/agy_client.dart';
import '../core/models/project_models.dart';
import '../core/models/chat_message.dart';
import '../core/services/pairing_service.dart';
import 'chat_provider.dart';
import 'fleet_provider.dart';

class ProjectsState {
  final bool isLoading;
  final String activeProject;
  final String activeConversationId;
  final String activeConversationTitle;
  final List<ProjectGroup> projects;
  final List<Map<String, dynamic>> recentConversations;
  final Map<String, dynamic>? activeSteps;
  final List<Map<String, dynamic>> runningTasks;

  ProjectsState({
    this.isLoading = false,
    this.activeProject = '',
    this.activeConversationId = '',
    this.activeConversationTitle = 'New Chat',
    this.projects = const [],
    this.recentConversations = const [],
    this.activeSteps,
    this.runningTasks = const [],
  });

  ProjectsState copyWith({
    bool? isLoading,
    String? activeProject,
    String? activeConversationId,
    String? activeConversationTitle,
    List<ProjectGroup>? projects,
    List<Map<String, dynamic>>? recentConversations,
    Map<String, dynamic>? activeSteps,
    bool clearActiveSteps = false,
    List<Map<String, dynamic>>? runningTasks,
  }) {
    return ProjectsState(
      isLoading: isLoading ?? this.isLoading,
      activeProject: activeProject ?? this.activeProject,
      activeConversationId: activeConversationId ?? this.activeConversationId,
      activeConversationTitle: activeConversationTitle ?? this.activeConversationTitle,
      projects: projects ?? this.projects,
      recentConversations: recentConversations ?? this.recentConversations,
      activeSteps: clearActiveSteps ? null : (activeSteps ?? this.activeSteps),
      runningTasks: runningTasks ?? this.runningTasks,
    );
  }
}

class ProjectsNotifier extends Notifier<ProjectsState> {
  AgyClient get _client => ref.read(agyClientProvider);
  Timer? _livePollingTimer;
  int _consecutiveIdleTicks = 0;
  int _convoEpoch = 0;
  int _requestEpoch = 0;

  @override
  ProjectsState build() {
    ref.listen<PairingState>(pairingProvider, (previous, next) {
      if (next.isPaired && (previous == null || previous.host != next.host || previous.port != next.port || previous.token != next.token)) {
        debugPrint('[ProjectsNotifier] pairing changed to ${next.host}:${next.port}. Reloading projects and active steps.');
        _requestEpoch++;
        _convoEpoch++;
        state = state.copyWith(clearActiveSteps: true, activeConversationId: '');
        loadProjects(setBusy: true);
        try {
          ref.read(fleetProvider.notifier).loadFleet();
        } catch (_) {}
      }
    });

    ref.onDispose(() {
      _livePollingTimer?.cancel();
    });
    Future.microtask(() {
      loadProjects();
      loadSteps(state.activeConversationId);
      _ensureLivePolling();
    });
    return ProjectsState();
  }

  Future<void> loadProjects({String? forceProject, bool setBusy = false}) async {
    final myEpoch = ++_requestEpoch;
    if (setBusy) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final targetProject = forceProject ?? state.activeProject;
      final results = await Future.wait([
        _client.getProjectsGrouped(
          convoId: state.activeConversationId,
          project: targetProject,
        ),
        _client.listHistory().catchError((e) {
          debugPrint('[ProjectsNotifier] listHistory error: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      if (myEpoch != _requestEpoch) {
        debugPrint('[ProjectsNotifier] loadProjects discarded due to newer user action');
        return;
      }

      final res = results[0] as Map<String, dynamic>;
      final history = results[1] as List<Map<String, dynamic>>;

      final rawList = res['projects'] as List<dynamic>? ?? [];
      final projects = rawList.map((e) => ProjectGroup.fromJson(e as Map<String, dynamic>)).toList();
      final activeProject = res['active_project'] as String? ?? targetProject;
      final serverActiveId = res['active_conversation_id'] as String?;
      final prevActiveId = state.activeConversationId;
      final activeId = prevActiveId.isNotEmpty
          ? prevActiveId
          : (serverActiveId ?? '');

      String activeTitle = state.activeConversationTitle;
      for (final p in projects) {
        for (final c in p.conversations) {
          if (c.id == activeId) {
            activeTitle = c.title;
            break;
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        activeProject: activeProject,
        activeConversationId: activeId,
        activeConversationTitle: activeTitle,
        projects: projects,
        recentConversations: history,
      );

      // Only load steps if activeId is present and (steps have not been loaded yet or conversation switched)
      if (activeId.isNotEmpty && (state.activeSteps == null || prevActiveId != activeId)) {
        loadSteps(activeId);
      }
    } catch (e, stack) {
      debugPrint('[ProjectsNotifier] loadProjects error: $e\n$stack');
      if (myEpoch == _requestEpoch) {
        state = state.copyWith(isLoading: false);
        loadSteps(state.activeConversationId);
      }
    }
  }

  Future<void> loadSteps(String convoId) async {
    final myConvoEpoch = _convoEpoch;
    debugPrint('[ProjectsNotifier] loadSteps starting for: $convoId');
    try {
      final results = await Future.wait([
        _client.getConversationSteps(convoId),
        _client.getRunningTasks(convoId).catchError((e) {
          debugPrint('[ProjectsNotifier] getRunningTasks error: $e');
          return <String, dynamic>{'tasks': []};
        }),
      ]);

      if (myConvoEpoch != _convoEpoch) {
        debugPrint('[ProjectsNotifier] loadSteps discarded because conversation switched');
        return;
      }

      if (convoId.isNotEmpty && convoId != state.activeConversationId && !state.activeConversationId.startsWith('convo-')) {
        debugPrint('[ProjectsNotifier] loadSteps discarded: $convoId is not active (${state.activeConversationId})');
        return;
      }

      final steps = results[0];
      final tasksRes = results[1];
      final tasksResList = List<Map<String, dynamic>>.from(tasksRes['tasks'] as List? ?? []);
      final stepsTasksList = List<Map<String, dynamic>>.from(steps['running_tasks'] as List? ?? []);
      final tasks = tasksResList.isNotEmpty ? tasksResList : stepsTasksList;
      debugPrint('[ProjectsNotifier] loadSteps got: ${steps.keys}, turns count: ${(steps['turns'] as List?)?.length}, runningTasks: ${tasks.length}');

      // If server resolved a temp/alias convoId to the genuine cascade UUID, adopt it immediately
      final resolvedId = steps['resolved_conversation_id'] as String?;
      if (resolvedId != null && resolvedId.isNotEmpty && resolvedId != state.activeConversationId && state.activeConversationId.startsWith('convo-')) {
        debugPrint('[ProjectsNotifier] Updating activeConversationId from temp ${state.activeConversationId} to real $resolvedId');
        state = state.copyWith(activeConversationId: resolvedId);
      }

      final isServerWorking = steps['is_working'] == true;
      final turnsList = (steps['turns'] as List<dynamic>?) ?? [];
      final lastTurn = turnsList.isNotEmpty ? (turnsList.last as Map<String, dynamic>) : null;
      final isLastTurnWorking = lastTurn?['is_working'] == true;

      try {
        if (isServerWorking || isLastTurnWorking) {
          ref.read(chatProvider.notifier).setStreaming(true);
        } else {
          ref.read(chatProvider.notifier).setStreaming(false);
          final chatMsgs = ref.read(chatProvider).messages;
          final userMsg = chatMsgs.where((m) => m.role == MessageRole.user).lastOrNull;
          if (userMsg != null && turnsList.isNotEmpty) {
            final cleanPrompt = userMsg.text.replaceFirst('[Steer] ', '').trim().toLowerCase();
            final lastTurnPrompt = (lastTurn?['user_prompt'] as String? ?? '').trim().toLowerCase();
            final promptMatches = cleanPrompt.isNotEmpty && (cleanPrompt == lastTurnPrompt || lastTurnPrompt.contains(cleanPrompt) || cleanPrompt.contains(lastTurnPrompt));
            if (promptMatches) {
              ref.read(chatProvider.notifier).clearInFlight();
            }
          }
        }
      } catch (_) {}

      state = state.copyWith(
        activeSteps: steps,
        runningTasks: tasks,
      );

      _ensureLivePolling();
    } catch (e, stack) {
      debugPrint('[ProjectsNotifier] loadSteps error: $e\n$stack');
    }
  }

  void _ensureLivePolling() {
    if (_livePollingTimer != null && _livePollingTimer!.isActive) return;
    _livePollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      final convoId = state.activeConversationId;
      if (convoId.isEmpty) return;
      final currentlyWorking = state.activeSteps?['is_working'] == true;
      final stillInFlight = ref.read(chatProvider).messages.isNotEmpty;
      final hasTasks = state.runningTasks.isNotEmpty;
      final isWorking = currentlyWorking || stillInFlight || hasTasks;
      if (isWorking) {
        _consecutiveIdleTicks = 0;
        loadSteps(convoId);
      } else {
        _consecutiveIdleTicks++;
        // Poll every 3 seconds when idle to guarantee real-time detection of external PC actions
        if (_consecutiveIdleTicks % 2 == 0) {
          loadSteps(convoId);
        }
      }
    });
  }

  void toggleProjectExpand(String projectName) {
    final updated = state.projects.map((p) {
      if (p.name == projectName) {
        p.isExpanded = !p.isExpanded;
      }
      return p;
    }).toList();
    state = state.copyWith(projects: updated);
  }

  void selectConversation(String convoId, String title, String projectName) {
    _convoEpoch++;
    _requestEpoch++;
    _consecutiveIdleTicks = 0;
    try {
      ref.read(chatProvider.notifier).resetConversation();
    } catch (_) {}

    final updatedRecent = List<Map<String, dynamic>>.from(state.recentConversations);
    final idx = updatedRecent.indexWhere((c) => c['id'] == convoId);
    if (idx != -1) {
      final item = Map<String, dynamic>.from(updatedRecent.removeAt(idx));
      item['last_modified'] = DateTime.now().toIso8601String();
      if (title.isNotEmpty) item['title'] = title;
      if (projectName.isNotEmpty) item['project'] = projectName;
      updatedRecent.insert(0, item);
    } else {
      updatedRecent.insert(0, {
        'id': convoId,
        'title': title.isNotEmpty ? title : 'Conversation',
        'project': projectName.isNotEmpty ? projectName : 'Workspace',
        'last_modified': DateTime.now().toIso8601String(),
        'status': 'done',
      });
    }

    state = state.copyWith(
      activeConversationId: convoId,
      activeConversationTitle: title,
      activeProject: projectName,
      recentConversations: updatedRecent,
      clearActiveSteps: true,
      runningTasks: [],
    );
    loadSteps(convoId);
    _ensureLivePolling();
  }

  Future<void> selectProject(String projectName) async {
    _requestEpoch++;
    _consecutiveIdleTicks = 0;
    state = state.copyWith(
      activeProject: projectName,
      clearActiveSteps: true,
    );
    ProjectGroup? group;
    for (final p in state.projects) {
      if (p.name == projectName) {
        group = p;
        break;
      }
    }
    if (group != null && group.conversations.isNotEmpty) {
      final latest = group.conversations.first;
      selectConversation(latest.id, latest.title, projectName);
    } else {
      final wsPath = (group != null && group.path.isNotEmpty) ? group.path : null;
      await newConversation(workspacePath: wsPath, projectName: projectName);
    }
    await loadProjects(forceProject: projectName);
  }

  void updateConversationId(String realConvoId) {
    if (state.activeConversationId != realConvoId) {
      state = state.copyWith(activeConversationId: realConvoId);
      loadSteps(realConvoId);
      loadProjects(forceProject: state.activeProject);
    }
  }

  Future<void> addProject(String name, String path) async {
    _requestEpoch++;
    try {
      await _client.addProject(name, path);
      state = state.copyWith(
        activeProject: name,
        activeConversationId: '',
        activeConversationTitle: 'New Chat',
        clearActiveSteps: true,
      );
      await loadProjects(forceProject: name);
    } catch (e) {
      debugPrint('[ProjectsNotifier] addProject error: $e');
    }
  }

  Future<void> removeProject(String name) async {
    try {
      await _client.removeProject(name);
      await loadProjects();
    } catch (_) {}
  }

  void stopExecution() {
    _client.stopExecution();
    if (state.activeSteps != null) {
      final updated = Map<String, dynamic>.from(state.activeSteps!);
      updated['is_working'] = false;
      final rawTurns = updated['turns'] as List<dynamic>? ?? [];
      if (rawTurns.isNotEmpty) {
        final turns = List<dynamic>.from(rawTurns);
        final lastTurn = Map<String, dynamic>.from(turns.last as Map);
        lastTurn['is_working'] = false;
        turns[turns.length - 1] = lastTurn;
        updated['turns'] = turns;
      }
      state = state.copyWith(activeSteps: updated, runningTasks: []);
    } else {
      state = state.copyWith(runningTasks: []);
    }
  }

  Future<void> newConversation({String? workspacePath, String? projectName}) async {
    _convoEpoch++;
    _requestEpoch++;
    _livePollingTimer?.cancel();
    _livePollingTimer = null;
    try {
      ref.read(chatProvider.notifier).resetConversation();
    } catch (_) {}

    final targetProject = projectName ?? state.activeProject;
    String? ws = workspacePath;
    if (ws == null) {
      for (final p in state.projects) {
        if (p.name == targetProject && p.path.isNotEmpty) {
          ws = p.path;
          break;
        }
      }
    }

    try {
      final res = await _client.createNewConversation(workspacePath: ws, projectName: targetProject);
      final realId = res['conversation_id'] as String?;
      if (realId != null && realId.isNotEmpty) {
        state = state.copyWith(
          activeProject: targetProject,
          activeConversationId: realId,
          activeConversationTitle: 'New Conversation',
          clearActiveSteps: true,
          runningTasks: [],
        );
        await loadProjects(forceProject: targetProject);
        loadSteps(realId);
        _ensureLivePolling();
        return;
      }
    } catch (e) {
      debugPrint('[ProjectsNotifier] Failed to create cascade on station: $e');
    }

    final fallbackId = 'convo-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    state = state.copyWith(
      activeProject: targetProject,
      activeConversationId: fallbackId,
      activeConversationTitle: 'New Conversation',
      clearActiveSteps: true,
      runningTasks: [],
    );
    await loadProjects(forceProject: targetProject);
    loadSteps(fallbackId);
    _ensureLivePolling();
  }
}

final projectsProvider = NotifierProvider<ProjectsNotifier, ProjectsState>(ProjectsNotifier.new);

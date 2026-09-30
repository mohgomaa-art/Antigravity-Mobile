import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/agy_client.dart';
import '../core/models/workspace_node.dart';
import 'fleet_provider.dart';

class WorkspaceState {
  final List<Map<String, dynamic>> workspaces;
  final String activeRoot;
  final List<WorkspaceNode> fileTree;
  final String? openFileName;
  final String? openFileContent;
  final bool isLoading;

  WorkspaceState({
    required this.workspaces,
    this.activeRoot = '',
    required this.fileTree,
    this.openFileName,
    this.openFileContent,
    this.isLoading = false,
  });

  WorkspaceState copyWith({
    List<Map<String, dynamic>>? workspaces,
    String? activeRoot,
    List<WorkspaceNode>? fileTree,
    String? openFileName,
    String? openFileContent,
    bool? isLoading,
  }) {
    return WorkspaceState(
      workspaces: workspaces ?? this.workspaces,
      activeRoot: activeRoot ?? this.activeRoot,
      fileTree: fileTree ?? this.fileTree,
      openFileName: openFileName ?? this.openFileName,
      openFileContent: openFileContent ?? this.openFileContent,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  AgyClient get _client => ref.read(agyClientProvider);

  @override
  WorkspaceState build() {
    Future.microtask(() => loadWorkspaces());
    return WorkspaceState(workspaces: [], fileTree: []);
  }

  Future<void> loadWorkspaces() async {
    state = state.copyWith(isLoading: true);
    try {
      final wsList = await _client.listWorkspaces();
      final tree = await _client.getFileTree(depth: 3);
      final active = wsList.firstWhere(
        (w) => w['is_active'] == true,
        orElse: () => wsList.isNotEmpty ? wsList.first : {'path': ''},
      );
      state = state.copyWith(
        workspaces: wsList,
        activeRoot: (active['path'] as String?)?.isNotEmpty == true
            ? active['path'] as String
            : state.activeRoot,
        fileTree: tree,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> selectWorkspace(String path) async {
    state = state.copyWith(activeRoot: path, isLoading: true);
    try {
      await _client.setWorkspace(path);
      final tree = await _client.getFileTree(depth: 3);
      state = state.copyWith(fileTree: tree, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> openFile(String path, String name) async {
    state = state.copyWith(isLoading: true);
    try {
      final fileData = await _client.readFile(path);
      state = state.copyWith(
        openFileName: name,
        openFileContent: fileData['content'] as String? ?? '',
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(WorkspaceNotifier.new);

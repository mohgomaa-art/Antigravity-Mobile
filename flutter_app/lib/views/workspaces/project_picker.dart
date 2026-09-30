import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/workspace_node.dart';
import '../../core/theme/agy_theme.dart';
import '../../core/theme/antigravity_logo.dart';
import '../../core/theme/language_icons.dart';
import '../../providers/projects_provider.dart';
import '../../providers/workspace_provider.dart';
import 'file_viewer.dart';

void showAddProjectDialog(
  BuildContext context,
  ProjectsNotifier notifier, {
  VoidCallback? onSuccess,
}) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AgyTheme.getSurface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const AntigravityLogo(size: 20),
          const SizedBox(width: 8),
          Text(
            'New Project / Workspace',
            style: TextStyle(
              color: AgyTheme.getTextPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter a project name or folder path on your Windows host:',
            style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. MyMobileApp or D:/work/project',
              hintStyle: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 13),
              filled: true,
              fillColor: AgyTheme.getSurfaceLight(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AgyTheme.getBorder(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AgyTheme.getTextPrimary(context)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
        ),
        ElevatedButton(
          onPressed: () {
            final val = controller.text.trim();
            if (val.isNotEmpty) {
              notifier.addProject(val, val);
              Navigator.of(ctx).pop();
              onSuccess?.call();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AgyTheme.isDark(context) ? Colors.white : Colors.black,
            foregroundColor: AgyTheme.isDark(context) ? Colors.black : Colors.white,
          ),
          child: const Text('Create Project'),
        ),
      ],
    ),
  );
}

class ProjectPickerView extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToChat;

  const ProjectPickerView({super.key, this.onNavigateToChat});

  @override
  ConsumerState<ProjectPickerView> createState() => _ProjectPickerViewState();
}

class _ProjectPickerViewState extends ConsumerState<ProjectPickerView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(workspaceProvider);
    final wsNotifier = ref.read(workspaceProvider.notifier);
    final projectsState = ref.watch(projectsProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);

    return Scaffold(
      backgroundColor: AgyTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AgyTheme.getSurface(context),
        elevation: 0,
        title: Text(
          'Projects & Workspaces',
          style: TextStyle(
            color: AgyTheme.getTextPrimary(context),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AgyTheme.getTextPrimary(context),
          labelColor: AgyTheme.getTextPrimary(context),
          unselectedLabelColor: AgyTheme.getTextMuted(context),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Projects'),
            Tab(text: 'File Explorer'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AgyTheme.getTextPrimary(context)),
            tooltip: 'New Project',
            onPressed: () => showAddProjectDialog(
              context,
              projectsNotifier,
              onSuccess: widget.onNavigateToChat,
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AgyTheme.getTextPrimary(context)),
            tooltip: 'Refresh',
            onPressed: () {
              projectsNotifier.loadProjects();
              wsNotifier.loadWorkspaces();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProjectsTab(context, projectsState, projectsNotifier),
          _buildExplorerTab(context, wsState, wsNotifier),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: AgyTheme.isDark(context) ? Colors.white : Colors.black,
              foregroundColor: AgyTheme.isDark(context) ? Colors.black : Colors.white,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => showAddProjectDialog(
                context,
                projectsNotifier,
                onSuccess: widget.onNavigateToChat,
              ),
            )
          : null,
    );
  }

  Widget _buildProjectsTab(
    BuildContext context,
    ProjectsState state,
    ProjectsNotifier notifier,
  ) {
    if (state.isLoading && state.projects.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AgyTheme.getTextPrimary(context),
        ),
      );
    }

    if (state.projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 48, color: AgyTheme.getTextMuted(context)),
            const SizedBox(height: 12),
            Text(
              'No projects registered',
              style: TextStyle(
                color: AgyTheme.getTextPrimary(context),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a project on your host to organize conversations',
              style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create First Project'),
              onPressed: () => showAddProjectDialog(
                context,
                notifier,
                onSuccess: widget.onNavigateToChat,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgyTheme.isDark(context) ? Colors.white : Colors.black,
                foregroundColor: AgyTheme.isDark(context) ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: state.projects.length,
      itemBuilder: (context, index) {
        final project = state.projects[index];
        final isActive = project.name == state.activeProject;
        final isDark = AgyTheme.isDark(context);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? const Color(0xFF1E1E24) : const Color(0xFFF1F1F5))
                : AgyTheme.getSurface(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? (isDark ? Colors.white38 : Colors.black38)
                  : AgyTheme.getBorder(context),
              width: isActive ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project Card Header
              InkWell(
                onTap: () {
                  notifier.selectProject(project.name);
                  widget.onNavigateToChat?.call();
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 22,
                        color: isActive
                            ? AgyTheme.getTextPrimary(context)
                            : AgyTheme.getTextSecondary(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    project.name,
                                    style: TextStyle(
                                      color: AgyTheme.getTextPrimary(context),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white : Colors.black,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        color: isDark ? Colors.black : Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (project.path.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                project.path,
                                style: TextStyle(
                                  color: AgyTheme.getTextMuted(context),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_comment_outlined, size: 18),
                        tooltip: 'New Chat in ${project.name}',
                        onPressed: () {
                          notifier.newConversation(
                            workspacePath: project.path.isNotEmpty ? project.path : null,
                            projectName: project.name,
                          );
                          widget.onNavigateToChat?.call();
                        },
                      ),
                      if (project.name != 'Antigravity')
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Remove Project',
                          color: Colors.redAccent,
                          onPressed: () => _confirmRemoveProject(context, project.name, notifier),
                        ),
                    ],
                  ),
                ),
              ),

              Divider(height: 1, color: AgyTheme.getBorder(context)),

              // Sub-conversations or start prompt
              if (project.conversations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Text(
                        'No conversations yet.',
                        style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Start Chat', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          notifier.newConversation(
                            workspacePath: project.path.isNotEmpty ? project.path : null,
                            projectName: project.name,
                          );
                          widget.onNavigateToChat?.call();
                        },
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    children: project.conversations.take(3).map((convo) {
                      final isCurrentConvo = convo.id == state.activeConversationId;
                      return InkWell(
                        onTap: () {
                          notifier.selectConversation(convo.id, convo.title, project.name);
                          widget.onNavigateToChat?.call();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrentConvo
                                ? AgyTheme.getSurfaceLight(context)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 13,
                                color: isCurrentConvo
                                    ? AgyTheme.getTextPrimary(context)
                                    : AgyTheme.getTextMuted(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  convo.title,
                                  style: TextStyle(
                                    color: isCurrentConvo
                                        ? AgyTheme.getTextPrimary(context)
                                        : AgyTheme.getTextSecondary(context),
                                    fontSize: 12,
                                    fontWeight: isCurrentConvo ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (convo.stepCount > 0)
                                Text(
                                  '${convo.stepCount} steps',
                                  style: TextStyle(
                                    color: AgyTheme.getTextMuted(context),
                                    fontSize: 10,
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
          ),
        );
      },
    );
  }

  Widget _buildExplorerTab(
    BuildContext context,
    WorkspaceState wsState,
    WorkspaceNotifier wsNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project switcher dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AgyTheme.getSurface(context),
          child: Row(
            children: [
              Icon(Icons.folder_special, color: AgyTheme.getTextPrimary(context), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: wsState.activeRoot,
                    isExpanded: true,
                    dropdownColor: AgyTheme.getSurfaceLight(context),
                    style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                    items: wsState.workspaces.map((w) {
                      final path = w['path'] as String;
                      final name = w['name'] as String;
                      return DropdownMenuItem<String>(
                        value: path,
                        child: Text('$name ($path)', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (newPath) {
                      if (newPath != null) {
                        wsNotifier.selectWorkspace(newPath);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AgyTheme.getBorder(context)),
        // File Explorer Tree
        Expanded(
          child: wsState.isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AgyTheme.getTextPrimary(context),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: wsState.fileTree
                      .map((node) => _buildTreeNode(context, node))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildTreeNode(BuildContext context, WorkspaceNode node) {
    if (node.isDirectory) {
      return ExpansionTile(
        leading: Icon(Icons.folder, color: AgyTheme.getTextSecondary(context), size: 18),
        title: Text(
          node.name,
          style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
        ),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: node.children.map((child) => _buildTreeNode(context, child)).toList(),
      );
    } else {
      return ListTile(
        dense: true,
        leading: LanguageFileIcon(filename: node.name, size: 16),
        title: Text(
          node.name,
          style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
        ),
        trailing: node.size != null
            ? Text(
                '${(node.size! / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 10),
              )
            : null,
        onTap: () async {
          await ref.read(workspaceProvider.notifier).openFile(node.path, node.name);
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FileViewerScreen(filePath: node.path, fileName: node.name),
              ),
            );
          }
        },
      );
    }
  }

  void _confirmRemoveProject(
    BuildContext context,
    String name,
    ProjectsNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgyTheme.getSurface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Remove Project', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 16)),
        content: Text(
          'Are you sure you want to remove project "$name" from your project list?\n\nFiles on your host system will not be deleted.',
          style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () {
              notifier.removeProject(name);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/project_models.dart';
import '../../core/services/pairing_service.dart';
import '../../core/theme/agy_theme.dart';
import '../../core/theme/antigravity_logo.dart';
import '../../providers/projects_provider.dart';
import '../legal/disclaimer_screen.dart';
import '../widgets/developer_profile_card.dart';

class AntigravityDrawer extends ConsumerStatefulWidget {
  const AntigravityDrawer({super.key});

  @override
  ConsumerState<AntigravityDrawer> createState() => _AntigravityDrawerState();
}

class _AntigravityDrawerState extends ConsumerState<AntigravityDrawer> {
  bool _recentChatsExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(projectsProvider.notifier).loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectsState = ref.watch(projectsProvider);
    final notifier = ref.read(projectsProvider.notifier);
    final currentThemeMode = ref.watch(themeModeProvider);

    return Drawer(
      backgroundColor: AgyTheme.getSidebarBg(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: Official Antigravity Branding & Theme Switcher (Fixed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  const AntigravityLogo(size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'ANTIGRAVITY',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      currentThemeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 19,
                      color: AgyTheme.getTextSecondary(context),
                    ),
                    tooltip: currentThemeMode == ThemeMode.dark ? 'Switch to White Theme' : 'Switch to Black Theme',
                    onPressed: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                  ),
                ],
              ),
            ),

            Divider(color: AgyTheme.getBorderSubtle(context), height: 1),

            // UNIFIED SCROLLABLE AREA: Scrolls smoothly across the entire drawer!
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  // + New Conversation Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          notifier.newConversation();
                          Navigator.of(context).pop();
                        },
                        icon: Icon(Icons.add, size: 16, color: AgyTheme.getTextPrimary(context)),
                        label: Text(
                          'New Conversation',
                          style: TextStyle(
                            color: AgyTheme.getTextPrimary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AgyTheme.getBorder(context), width: 1),
                          backgroundColor: AgyTheme.getSurface(context),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ),

                  // Navigation links
                  _buildNavTile(
                    context,
                    Icons.history,
                    'Conversation History',
                    () => _showConversationHistorySheet(
                      context,
                      projectsState.recentConversations,
                      projectsState.activeConversationId,
                      notifier,
                    ),
                  ),
                  _buildNavTile(context, Icons.schedule, 'Scheduled Tasks', () {}),
                  _buildNavTile(
                    context,
                    Icons.gavel_outlined,
                    'Legal & Disclaimer',
                    () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 4),
                  Divider(color: AgyTheme.getBorderSubtle(context), height: 1),

                  // Recent Conversations Section (Collapsible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _recentChatsExpanded = !_recentChatsExpanded;
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _recentChatsExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                size: 16,
                                color: AgyTheme.getTextSecondary(context),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Recent Chats',
                                style: TextStyle(
                                  color: AgyTheme.getTextSecondary(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => notifier.loadProjects(),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Icon(
                              Icons.refresh,
                              size: 13,
                              color: AgyTheme.getTextMuted(context),
                            ),
                          ),
                        ),
                        if (projectsState.recentConversations.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showConversationHistorySheet(
                              context,
                              projectsState.recentConversations,
                              projectsState.activeConversationId,
                              notifier,
                            ),
                            child: Text(
                              'View All',
                              style: TextStyle(
                                color: AgyTheme.getTextMuted(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_recentChatsExpanded) ...[
                    if (projectsState.recentConversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          'No recent conversations yet',
                          style: TextStyle(
                            color: AgyTheme.getTextMuted(context),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ...projectsState.recentConversations.take(6).map((convo) {
                        final id = convo['id'] as String? ?? '';
                        final title = convo['title'] as String? ?? 'Untitled';
                        final project = convo['project'] as String? ?? 'Workspace';
                        final isCurrent = id == projectsState.activeConversationId;
                        final isServerWorking = projectsState.activeSteps?['is_working'] == true;
                        final isWorking = (convo['status'] == 'working' || convo['status'] == 'running' || convo['status'] == 'busy') ||
                            (isCurrent && isServerWorking);

                        return InkWell(
                          onTap: () {
                            notifier.selectConversation(id, title, project);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AgyTheme.getSurfaceLight(context)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: isCurrent
                                  ? Border.all(color: AgyTheme.getBorder(context), width: 0.8)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 14,
                                  color: isCurrent
                                      ? AgyTheme.getTextPrimary(context)
                                      : AgyTheme.getTextSecondary(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: AgyTheme.getTextPrimary(context),
                                      fontSize: 12.5,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AgyTheme.getSurfaceLight(context),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    project,
                                    style: TextStyle(
                                      color: AgyTheme.getTextMuted(context),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],

                  const SizedBox(height: 8),
                  Divider(color: AgyTheme.getBorderSubtle(context), height: 1),

                  // Projects Header with Count Badge, Add and Remove buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          'Projects',
                          style: TextStyle(
                            color: AgyTheme.getTextSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AgyTheme.getSurfaceLight(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${projectsState.projects.length}',
                            style: TextStyle(
                              color: AgyTheme.getTextSecondary(context),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Add Project (+)
                        Tooltip(
                          message: 'Add Workspace / Project',
                          child: InkWell(
                            onTap: () => _showAddProjectDialog(context, notifier),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.create_new_folder_outlined, size: 16, color: AgyTheme.getTextSecondary(context)),
                                  const SizedBox(width: 2),
                                  Icon(Icons.add, size: 11, color: AgyTheme.getTextSecondary(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Remove Project (-)
                        InkWell(
                          onTap: () => _showRemoveProjectDialog(context, projectsState.projects, notifier),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Icon(Icons.remove_circle_outline, size: 18, color: AgyTheme.getTextSecondary(context)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Projects Tree List (Full scrollable height, completely unconstrained!)
                  if (projectsState.isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AgyTheme.getTextPrimary(context),
                        ),
                      ),
                    )
                  else if (projectsState.projects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Text(
                        'No projects configured. Tap + to add a project workspace.',
                        style: TextStyle(
                          color: AgyTheme.getTextMuted(context),
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    for (final project in projectsState.projects)
                      _buildProjectGroup(context, project, projectsState, notifier),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Settings & Station Status
            Divider(color: AgyTheme.getBorder(context), height: 1),
            Consumer(
              builder: (ctx, r, _) {
                final pairing = r.watch(pairingProvider);
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: AgyTheme.getTextSecondary(context),
                  ),
                  title: Row(
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: AgyTheme.getTextPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AgyTheme.getSurfaceLight(context),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AgyTheme.getBorder(context),
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
                                color: pairing.isPaired
                                    ? AgyTheme.getTextPrimary(context)
                                    : AgyTheme.getTextMuted(context),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              pairing.isPaired ? 'Station Bound' : 'Not Bound',
                              style: TextStyle(
                                color: pairing.isPaired
                                    ? AgyTheme.getTextPrimary(context)
                                    : AgyTheme.getTextMuted(context),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    pairing.isPaired ? '${pairing.host}:${pairing.port}' : 'Tap to pair station',
                    style: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  onTap: () => _showStationSettingsDialog(context, r),
                );
              },
            ),
            const DeveloperProfileCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      leading: Icon(icon, size: 16, color: AgyTheme.getTextSecondary(context)),
      title: Text(
        title,
        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
      ),
      onTap: onTap,
    );
  }

  Widget _buildProjectGroup(
    BuildContext context,
    ProjectGroup project,
    ProjectsState projectsState,
    ProjectsNotifier notifier,
  ) {
    final activeConvoId = projectsState.activeConversationId;
    final isServerWorking = projectsState.activeSteps?['is_working'] == true;
    final hasRunningSession = project.conversations.any((c) =>
        (c.status == 'working' || c.status == 'running' || c.status == 'busy') ||
        (c.id == activeConvoId && isServerWorking));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  notifier.selectProject(project.name);
                  Navigator.of(context).pop();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      project.isExpanded ? Icons.folder_open : Icons.folder,
                      size: 16,
                      color: AgyTheme.getTextSecondary(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    notifier.selectProject(project.name);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            project.name,
                            style: TextStyle(
                              color: AgyTheme.getTextPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasRunningSession) ...[
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
              ),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined, size: 15),
                color: AgyTheme.getTextSecondary(context),
                tooltip: 'New chat in ${project.name}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  notifier.newConversation(
                    workspacePath: project.path.isNotEmpty ? project.path : null,
                    projectName: project.name,
                  );
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => notifier.toggleProjectExpand(project.name),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    project.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 16,
                    color: AgyTheme.getTextSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sub-conversations if expanded
        if (project.isExpanded) ...[
          if (project.conversations.isEmpty)
            InkWell(
              onTap: () {
                notifier.newConversation(
                  workspacePath: project.path.isNotEmpty ? project.path : null,
                  projectName: project.name,
                );
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: AgyTheme.getBorder(context), width: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 13, color: AgyTheme.getTextMuted(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '+ Start first chat in ${project.name}',
                        style: TextStyle(
                          color: AgyTheme.getTextMuted(context),
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ...project.conversations.map((convo) {
            final isCurrentActive = convo.id == activeConvoId;
            final isConvoWorking = (convo.status == 'working' || convo.status == 'running' || convo.status == 'busy') ||
                (isCurrentActive && isServerWorking);

            return InkWell(
              onTap: () {
                notifier.selectConversation(convo.id, convo.title, project.name);
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isCurrentActive
                      ? AgyTheme.getSurfaceLight(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        convo.title,
                        style: TextStyle(
                          color: isCurrentActive ? AgyTheme.getTextPrimary(context) : AgyTheme.getTextSecondary(context),
                          fontSize: 12,
                          fontWeight: isCurrentActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isConvoWorking) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AgyTheme.getTextPrimary(context),
                        ),
                      ),
                    ] else if (isCurrentActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AgyTheme.getTextPrimary(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AgyTheme.getTextMuted(context).withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  void _showAddProjectDialog(BuildContext context, ProjectsNotifier notifier) {
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
              'Add Workspace / Project',
              style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter project folder name or path:',
              style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. mobile_client or D:/Projects/App',
                hintStyle: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 13),
                filled: true,
                fillColor: AgyTheme.getSurfaceLight(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AgyTheme.getBorder(context)),
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
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AgyTheme.isDark(context) ? Colors.white : Colors.black,
              foregroundColor: AgyTheme.isDark(context) ? Colors.black : Colors.white,
            ),
            child: const Text('Add Project'),
          ),
        ],
      ),
    );
  }

  void _showRemoveProjectDialog(BuildContext context, List<ProjectGroup> projects, ProjectsNotifier notifier) {
    if (projects.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Remove Project from Workspace',
                style: TextStyle(
                  color: AgyTheme.getTextPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...projects.map(
              (p) => ListTile(
                leading: Icon(Icons.folder_outlined, color: AgyTheme.getTextSecondary(context), size: 18),
                title: Text(
                  p.name,
                  style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: AgyTheme.getTextSecondary(context), size: 18),
                  onPressed: () {
                    notifier.removeProject(p.name);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationHistorySheet(
    BuildContext context,
    List<Map<String, dynamic>> conversations,
    String activeConversationId,
    ProjectsNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = conversations.where((c) {
              final title = (c['title'] as String? ?? '').toLowerCase();
              final project = (c['project'] as String? ?? '').toLowerCase();
              final q = query.toLowerCase();
              return title.contains(q) || project.contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AgyTheme.getBorder(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header
                      Row(
                        children: [
                          Icon(Icons.history, size: 20, color: AgyTheme.getTextPrimary(context)),
                          const SizedBox(width: 8),
                          Text(
                            'Conversation History',
                            style: TextStyle(
                              color: AgyTheme.getTextPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${conversations.length} total',
                            style: TextStyle(
                              color: AgyTheme.getTextMuted(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Search bar
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AgyTheme.isDark(context) ? const Color(0xFF161618) : const Color(0xFFF2F2F4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                        ),
                        child: TextField(
                          onChanged: (val) {
                            setModalState(() {
                              query = val;
                            });
                          },
                          style: TextStyle(
                            color: AgyTheme.getTextPrimary(context),
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search chats or projects...',
                            hintStyle: TextStyle(
                              color: AgyTheme.getTextMuted(context),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(Icons.search, size: 18, color: AgyTheme.getTextMuted(context)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // List
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No conversations found',
                                  style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 13),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: AgyTheme.getBorder(context).withValues(alpha: 0.5),
                                ),
                                itemBuilder: (cContext, index) {
                                  final item = filtered[index];
                                  final id = item['id'] as String? ?? '';
                                  final title = item['title'] as String? ?? 'Untitled';
                                  final project = item['project'] as String? ?? 'Workspace';
                                  final isActive = id == activeConversationId;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    leading: Icon(
                                      Icons.chat_bubble_outline,
                                      size: 18,
                                      color: isActive ? (AgyTheme.isDark(context) ? Colors.white : Colors.black) : AgyTheme.getTextMuted(context),
                                    ),
                                    title: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isActive ? (AgyTheme.isDark(context) ? Colors.white : Colors.black) : AgyTheme.getTextPrimary(context),
                                        fontSize: 13,
                                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AgyTheme.isDark(context) ? const Color(0xFF222224) : const Color(0xFFE8E8EC),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            project,
                                            style: TextStyle(
                                              color: AgyTheme.getTextSecondary(context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (isActive) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            'Active',
                                            style: TextStyle(
                                              color: AgyTheme.getTextPrimary(context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: isActive
                                        ? Icon(Icons.check, size: 18, color: AgyTheme.isDark(context) ? Colors.white : Colors.black)
                                        : null,
                                    onTap: () {
                                      Navigator.of(ctx).pop(); // Close sheet
                                      Navigator.of(context).pop(); // Close drawer
                                      notifier.selectConversation(id, title, project);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showStationSettingsDialog(BuildContext context, WidgetRef ref) {
    final pairing = ref.read(pairingProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgyTheme.getSurface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AgyTheme.getBorder(context), width: 0.8),
        ),
        title: Row(
          children: [
            Icon(Icons.desktop_windows_outlined, size: 20, color: AgyTheme.getTextPrimary(context)),
            const SizedBox(width: 10),
            Text(
              'Windows Station Pairing',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AgyTheme.getSurfaceLight(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: pairing.isPaired
                          ? AgyTheme.getTextPrimary(context)
                          : AgyTheme.getTextMuted(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pairing.isPaired ? 'Station Permanently Bound' : 'Station Disconnected',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AgyTheme.getSurfaceLight(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Station Host: ',
                        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      ),
                      Text(
                        pairing.host,
                        style: TextStyle(
                          color: AgyTheme.getTextPrimary(context),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        'Port: ',
                        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      ),
                      Text(
                        '${pairing.port}',
                        style: TextStyle(
                          color: AgyTheme.getTextPrimary(context),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        'Token: ',
                        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      ),
                      Text(
                        pairing.token.length > 14
                            ? '${pairing.token.substring(0, 14)}...'
                            : (pairing.token.isEmpty ? 'none' : pairing.token),
                        style: TextStyle(
                          color: AgyTheme.getTextSecondary(context),
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your mobile device stays bound across sessions without needing to re-scan. To link to another PC or restart pairing, tap Unbind below.',
              style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
          ),
          if (pairing.isPaired)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AgyTheme.getTextPrimary(context),
                backgroundColor: AgyTheme.getSurfaceLight(context),
                side: BorderSide(color: AgyTheme.getBorder(context), width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(Icons.link_off, size: 15, color: AgyTheme.getTextPrimary(context)),
              label: Text(
                'Unbind Station',
                style: TextStyle(
                  color: AgyTheme.getTextPrimary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // close drawer
                await ref.read(pairingProvider.notifier).unbind();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AgyTheme.getSurface(context),
                      content: Text(
                        'Station Unbound. Ready to scan new Station QR.',
                        style: TextStyle(color: AgyTheme.getTextPrimary(context)),
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}


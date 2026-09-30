import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/agy_theme.dart';
import '../core/theme/antigravity_logo.dart';
import '../providers/projects_provider.dart';
import 'chat/chat_screen.dart';
import 'fleet/fleet_dashboard.dart';
import 'workspaces/project_picker.dart';
import 'legal/disclaimer_screen.dart';
import 'skills/skills_catalog.dart';
import 'sidebar/antigravity_drawer.dart';

class HomeScaffold extends ConsumerStatefulWidget {
  const HomeScaffold({super.key});

  @override
  ConsumerState<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends ConsumerState<HomeScaffold> {
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DisclaimerScreen.checkAndShowStartupNotice(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectsState = ref.watch(projectsProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);
    final currentThemeMode = ref.watch(themeModeProvider);

    final pages = [
      const ChatScreen(),
      const FleetDashboard(),
      ProjectPickerView(onNavigateToChat: () => setState(() => _currentTabIndex = 0)),
      const SkillsCatalogView(),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: const AntigravityDrawer(),
      appBar: AppBar(
        backgroundColor: AgyTheme.getSurface(context),
        elevation: 0,
        leading: Builder(
          builder: (scaffoldCtx) => IconButton(
            icon: Icon(Icons.menu, color: AgyTheme.getTextPrimary(context), size: 20),
            tooltip: 'Open Antigravity Projects',
            onPressed: () => Scaffold.of(scaffoldCtx).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: () => _showProjectSwitcher(context, projectsState, projectsNotifier),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AntigravityLogo(size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    projectsState.activeProject.isNotEmpty ? projectsState.activeProject : 'Workspace',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 18, color: AgyTheme.getTextSecondary(context)),
              ],
            ),
          ),
        ),
        actions: [
          // Theme Switcher (White / Black Monochrome)
          IconButton(
            icon: Icon(
              currentThemeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: AgyTheme.getTextPrimary(context),
              size: 19,
            ),
            tooltip: currentThemeMode == ThemeMode.dark ? 'Switch to White Theme' : 'Switch to Black Theme',
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle();
            },
          ),

          IconButton(
            icon: Icon(Icons.add, color: AgyTheme.getTextPrimary(context), size: 20),
            tooltip: 'New Conversation',
            onPressed: () {
              projectsNotifier.newConversation(projectName: projectsState.activeProject);
              if (_currentTabIndex != 0) {
                setState(() => _currentTabIndex = 0);
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AgyTheme.getSurface(context),
        selectedItemColor: AgyTheme.getTextPrimary(context),
        unselectedItemColor: AgyTheme.getTextMuted(context),
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub_outlined),
            activeIcon: Icon(Icons.hub),
            label: '15-Fleet',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open),
            activeIcon: Icon(Icons.folder),
            label: 'Projects',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.extension_outlined),
            activeIcon: Icon(Icons.extension),
            label: 'Skills',
          ),
        ],
      ),
    );
  }



  void _showProjectSwitcher(
    BuildContext context,
    ProjectsState projectsState,
    ProjectsNotifier projectsNotifier,
  ) {
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const AntigravityLogo(size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Switch Active Project',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Project', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      showAddProjectDialog(
                        context,
                        projectsNotifier,
                        onSuccess: () => setState(() => _currentTabIndex = 0),
                      );
                    },
                  ),
                ],
              ),
            ),
            Divider(color: AgyTheme.getBorder(context), height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: projectsState.projects.length,
                itemBuilder: (context, index) {
                  final p = projectsState.projects[index];
                  final isCurrent = p.name == projectsState.activeProject;
                  final isDark = AgyTheme.isDark(context);

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.folder,
                      size: 20,
                      color: isCurrent
                          ? AgyTheme.getTextPrimary(context)
                          : AgyTheme.getTextMuted(context),
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(
                        color: AgyTheme.getTextPrimary(context),
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    subtitle: p.path.isNotEmpty
                        ? Text(
                            p.path,
                            style: TextStyle(
                              color: AgyTheme.getTextMuted(context),
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isCurrent
                        ? Container(
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
                          )
                        : Text(
                            '${p.totalConversations} chats',
                            style: TextStyle(
                              color: AgyTheme.getTextMuted(context),
                              fontSize: 11,
                            ),
                          ),
                    onTap: () {
                      projectsNotifier.selectProject(p.name);
                      Navigator.pop(ctx);
                      setState(() => _currentTabIndex = 0);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

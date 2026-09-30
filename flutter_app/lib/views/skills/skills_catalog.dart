import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/skill.dart';
import '../../core/theme/agy_theme.dart';
import '../../providers/skills_provider.dart';

class SkillsCatalogView extends ConsumerStatefulWidget {
  const SkillsCatalogView({super.key});

  @override
  ConsumerState<SkillsCatalogView> createState() => _SkillsCatalogViewState();
}

class _SkillsCatalogViewState extends ConsumerState<SkillsCatalogView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skillsState = ref.watch(skillsProvider);
    final notifier = ref.read(skillsProvider.notifier);
    final filteredSkills = skillsState.filteredSkills;

    return Scaffold(
      backgroundColor: AgyTheme.getBg(context),
      appBar: AppBar(
        title: Text(
          'Skills & Customizations',
          style: TextStyle(
            color: AgyTheme.getTextPrimary(context),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Custom Skill',
            icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
            onPressed: () => _showCreateSkillDialog(context),
          ),
          IconButton(
            tooltip: 'Refresh Skills',
            icon: Icon(Icons.refresh, color: AgyTheme.getTextPrimary(context)),
            onPressed: () => notifier.loadSkills(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filters
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: AgyTheme.getSurface(context),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => notifier.setSearchQuery(val),
                  style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search skills by name, tag, or description...',
                    hintStyle: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 13),
                    prefixIcon: Icon(Icons.search, size: 18, color: AgyTheme.getTextSecondary(context)),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              notifier.setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: AgyTheme.getSurfaceLight(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AgyTheme.getBorder(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AgyTheme.getBorder(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(context, 'All', 'all', skillsState.skills.length, skillsState.selectedCategory),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        context,
                        'Builtin',
                        'builtin',
                        skillsState.skills.where((s) => s.source == 'builtin').length,
                        skillsState.selectedCategory,
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        context,
                        'Global',
                        'global',
                        skillsState.skills.where((s) => s.source == 'global').length,
                        skillsState.selectedCategory,
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        context,
                        'Workspace',
                        'workspace',
                        skillsState.skills.where((s) => s.source == 'workspace').length,
                        skillsState.selectedCategory,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AgyTheme.getBorder(context)),

          // Body List
          Expanded(
            child: skillsState.isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  )
                : filteredSkills.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.extension_off_outlined, size: 48, color: AgyTheme.getTextMuted(context)),
                            const SizedBox(height: 10),
                            Text(
                              'No skills matching criteria',
                              style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredSkills.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final skill = filteredSkills[index];
                          return _buildSkillCard(context, skill, notifier);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String key, int count, String currentKey) {
    final isSelected = currentKey.toLowerCase() == key.toLowerCase();
    final notifier = ref.read(skillsProvider.notifier);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => notifier.setSelectedCategory(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (AgyTheme.isDark(context) ? Colors.white : Colors.black)
              : AgyTheme.getSurfaceLight(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : AgyTheme.getBorder(context),
            width: 0.8,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            color: isSelected
                ? (AgyTheme.isDark(context) ? Colors.black : Colors.white)
                : AgyTheme.getTextSecondary(context),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSkillCard(BuildContext context, SkillModel skill, SkillsNotifier notifier) {
    Color badgeColor;
    Color badgeTextColor;
    switch (skill.source.toLowerCase()) {
      case 'builtin':
        badgeColor = Colors.purple.withValues(alpha: 0.15);
        badgeTextColor = Colors.purpleAccent;
        break;
      case 'workspace':
        badgeColor = Colors.amber.withValues(alpha: 0.15);
        badgeTextColor = Colors.amber;
        break;
      default:
        badgeColor = Colors.blue.withValues(alpha: 0.15);
        badgeTextColor = Colors.blueAccent;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showSkillDetailSheet(context, skill),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AgyTheme.getSurface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AgyTheme.getBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeTextColor.withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: Text(
                    skill.source.toUpperCase(),
                    style: TextStyle(
                      color: badgeTextColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 14,
                    ),
                  ),
                ),
                Switch(
                  value: skill.isEnabled,
                  activeThumbColor: AgyTheme.isDark(context) ? Colors.white : Colors.black,
                  activeTrackColor: AgyTheme.isDark(context) ? Colors.white38 : Colors.black38,
                  inactiveThumbColor: AgyTheme.getTextSecondary(context),
                  inactiveTrackColor: AgyTheme.getSurfaceLight(context),
                  onChanged: (val) {
                    notifier.toggleSkill(skill.name, val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              skill.description,
              style: TextStyle(
                color: AgyTheme.getTextSecondary(context),
                fontSize: 12,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 12, color: AgyTheme.getTextMuted(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    skill.path,
                    style: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right, size: 14, color: AgyTheme.getTextMuted(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSkillDetailSheet(BuildContext context, SkillModel initialSkill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<SkillModel?>(
          future: ref.read(skillsProvider.notifier).getSkillDetail(initialSkill.id),
          builder: (context, snapshot) {
            final skill = snapshot.data ?? initialSkill;
            final isEditable = skill.isEditable;

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AgyTheme.getBorder(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              skill.name,
                              style: TextStyle(
                                color: AgyTheme.getTextPrimary(context),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              skill.path,
                              style: TextStyle(
                                color: AgyTheme.getTextMuted(context),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (isEditable) ...[
                        IconButton(
                          tooltip: 'Edit Skill',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditSkillDialog(context, skill);
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete Skill',
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmDeleteSkill(context, skill);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: AgyTheme.getBorder(context)),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AgyTheme.getSurfaceLight(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AgyTheme.getBorder(context)),
                              ),
                              child: Text(
                                skill.description,
                                style: TextStyle(
                                  color: AgyTheme.getTextSecondary(context),
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'INSTRUCTIONS (SKILL.MD)',
                              style: TextStyle(
                                color: AgyTheme.getTextSecondary(context),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            MarkdownBody(
                              data: skill.fullInstructions ?? skill.instructionPreview,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, height: 1.4),
                                code: TextStyle(
                                  backgroundColor: AgyTheme.getSurfaceLight(context),
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: AgyTheme.getSurfaceLight(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AgyTheme.getBorder(context)),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCreateSkillDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final instCtrl = TextEditingController();
    String source = 'global';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AgyTheme.getSurface(context),
          title: Text(
            'Create Custom Skill',
            style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Skill Identifier (e.g. fast-api-expert)',
                      labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    dropdownColor: AgyTheme.getSurface(context),
                    decoration: InputDecoration(
                      labelText: 'Scope / Location',
                      labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'global', child: Text('Global (~/.gemini/config/skills)')),
                      DropdownMenuItem(value: 'workspace', child: Text('Workspace (./skills)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => source = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Brief Description',
                      labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instCtrl,
                    maxLines: 7,
                    style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Instructions (Markdown)',
                      labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                      hintText: 'Define guidelines, rules, tool preferences, and triggers...',
                      hintStyle: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final desc = descCtrl.text.trim();
                final inst = instCtrl.text.trim();
                if (name.isEmpty) return;

                final success = await ref.read(skillsProvider.notifier).createSkill(
                      name: name,
                      description: desc.isNotEmpty ? desc : 'Custom skill $name',
                      instructions: inst.isNotEmpty ? inst : 'Execute tasks according to $name instructions.',
                      source: source,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create skill. Check name and permissions.')),
                  );
                }
              },
              child: const Text('Create Skill'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSkillDialog(BuildContext context, SkillModel skill) {
    final descCtrl = TextEditingController(text: skill.description);
    final instCtrl = TextEditingController(text: skill.fullInstructions ?? skill.instructionPreview);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgyTheme.getSurface(context),
        title: Text(
          'Edit Skill: ${skill.name}',
          style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: descCtrl,
                  style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: instCtrl,
                  maxLines: 8,
                  style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'Instructions (Markdown)',
                    labelStyle: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await ref.read(skillsProvider.notifier).updateSkill(
                    skill.id,
                    description: descCtrl.text.trim(),
                    instructions: instCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted && !success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to update skill.')),
                );
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSkill(BuildContext context, SkillModel skill) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgyTheme.getSurface(context),
        title: Text('Delete Skill', style: TextStyle(color: AgyTheme.getTextPrimary(context))),
        content: Text(
          'Are you sure you want to permanently delete custom skill "${skill.name}"?',
          style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AgyTheme.getTextSecondary(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(skillsProvider.notifier).deleteSkill(skill.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

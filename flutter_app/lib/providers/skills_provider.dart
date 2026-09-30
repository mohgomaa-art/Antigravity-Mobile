import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/agy_client.dart';
import '../core/models/skill.dart';
import 'fleet_provider.dart';

class SkillsState {
  final List<SkillModel> skills;
  final bool isLoading;
  final String searchQuery;
  final String selectedCategory; // 'all', 'builtin', 'global', 'workspace'

  SkillsState({
    required this.skills,
    this.isLoading = false,
    this.searchQuery = '',
    this.selectedCategory = 'all',
  });

  List<SkillModel> get filteredSkills {
    return skills.where((s) {
      final matchesCategory = selectedCategory == 'all' || s.source.toLowerCase() == selectedCategory.toLowerCase();
      if (!matchesCategory) return false;

      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q);
    }).toList();
  }

  SkillsState copyWith({
    List<SkillModel>? skills,
    bool? isLoading,
    String? searchQuery,
    String? selectedCategory,
  }) {
    return SkillsState(
      skills: skills ?? this.skills,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
    );
  }
}

class SkillsNotifier extends Notifier<SkillsState> {
  AgyClient get _client => ref.read(agyClientProvider);

  @override
  SkillsState build() {
    Future.microtask(() => loadSkills());
    return SkillsState(skills: []);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  Future<void> loadSkills() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _client.listSkills();
      state = state.copyWith(skills: list, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> toggleSkill(String name, bool enabled) async {
    try {
      await _client.toggleSkill(name, enabled);
      final updated = state.skills.map((s) {
        if (s.name == name || s.id == name) {
          return SkillModel(
            id: s.id,
            name: s.name,
            description: s.description,
            source: s.source,
            path: s.path,
            isEnabled: enabled,
            isEditable: s.isEditable,
            instructionPreview: s.instructionPreview,
            fullInstructions: s.fullInstructions,
          );
        }
        return s;
      }).toList();
      state = state.copyWith(skills: updated);
    } catch (_) {}
  }

  Future<SkillModel?> getSkillDetail(String skillId) async {
    try {
      final data = await _client.getSkillDetail(skillId);
      return SkillModel.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> createSkill({
    required String name,
    required String description,
    required String instructions,
    String source = 'global',
  }) async {
    try {
      final res = await _client.createSkill(
        name: name,
        description: description,
        instructions: instructions,
        source: source,
      );
      if (res['skill'] != null) {
        final newSkill = SkillModel.fromJson(res['skill'] as Map<String, dynamic>);
        state = state.copyWith(skills: [newSkill, ...state.skills]);
        return true;
      }
      await loadSkills();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateSkill(
    String skillId, {
    required String description,
    required String instructions,
  }) async {
    try {
      final res = await _client.updateSkill(
        skillId,
        description: description,
        instructions: instructions,
      );
      if (res['skill'] != null) {
        final updated = SkillModel.fromJson(res['skill'] as Map<String, dynamic>);
        final list = state.skills.map((s) => s.id == skillId ? updated : s).toList();
        state = state.copyWith(skills: list);
        return true;
      }
      await loadSkills();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSkill(String skillId) async {
    try {
      await _client.deleteSkill(skillId);
      final list = state.skills.where((s) => s.id != skillId).toList();
      state = state.copyWith(skills: list);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final skillsProvider = NotifierProvider<SkillsNotifier, SkillsState>(SkillsNotifier.new);

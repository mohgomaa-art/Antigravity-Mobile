import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/agy_theme.dart';

class InteractiveQuestionCard extends StatefulWidget {
  final Map<String, dynamic> questionData;
  final ValueChanged<String> onAnswer;
  final bool isPending;

  const InteractiveQuestionCard({
    super.key,
    required this.questionData,
    required this.onAnswer,
    this.isPending = true,
  });

  @override
  State<InteractiveQuestionCard> createState() => _InteractiveQuestionCardState();
}

class _InteractiveQuestionCardState extends State<InteractiveQuestionCard> {
  int _currentQIndex = 0;
  final Map<int, Set<String>> _selectedOptions = {};
  final Map<int, String> _customAnswers = {};
  final TextEditingController _customInputController = TextEditingController();
  bool _submitted = false;
  Timer? _countdownTimer;
  int _secondsRemaining = 15;
  bool _isAutoProceedPaused = false;

  List<dynamic> get _questions {
    dynamic raw = widget.questionData['questions'];
    if (raw == null && widget.questionData['question_data'] is Map) {
      raw = (widget.questionData['question_data'] as Map)['questions'];
    }
    if (raw == null && widget.questionData['arguments'] is Map) {
      raw = (widget.questionData['arguments'] as Map)['questions'] ??
          (widget.questionData['arguments'] as Map)['question'];
    }
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }
    if (raw is List) {
      return raw.map((item) {
        if (item is String) {
          try {
            final decoded = jsonDecode(item);
            if (decoded is Map) return decoded;
          } catch (_) {}
          return {'question': item, 'options': <dynamic>[]};
        }
        return item;
      }).toList();
    }
    if (raw is Map) {
      return [raw];
    }
    final singleQ = widget.questionData['question'] ??
        (widget.questionData['question_data'] is Map
            ? (widget.questionData['question_data'] as Map)['question']
            : null);
    if (singleQ != null) {
      return [
        {
          'question': singleQ.toString(),
          'options': widget.questionData['options'] ??
              (widget.questionData['question_data'] is Map
                  ? (widget.questionData['question_data'] as Map)['options']
                  : null) ??
              [],
          'is_multi_select': widget.questionData['is_multi_select'] == true,
        }
      ];
    }
    return [];
  }

  List<String> _extractOptions(dynamic rawQ) {
    if (rawQ == null) return [];
    final currentQ = rawQ is Map ? Map<String, dynamic>.from(rawQ) : <String, dynamic>{};
    dynamic rawOptions = currentQ['options'] ?? currentQ['choices'] ?? currentQ['items'];
    if (rawOptions is String) {
      try {
        rawOptions = jsonDecode(rawOptions);
      } catch (_) {
        rawOptions = rawOptions.split(RegExp(r',\s*'));
      }
    }
    final List<String> options = [];
    if (rawOptions is List) {
      for (final opt in rawOptions) {
        if (opt is Map) {
          final label = opt['text'] ?? opt['label'] ?? opt['title'] ?? opt['value'] ?? opt.toString();
          options.add(label.toString());
        } else if (opt != null) {
          options.add(opt.toString());
        }
      }
    }
    return options;
  }

  String _findRecommended(List<String> options) {
    if (options.isEmpty) return 'Proceed with recommended plan';
    for (final opt in options) {
      if (opt.toLowerCase().contains('(recommended)')) {
        return opt;
      }
    }
    return options.first;
  }

  @override
  void initState() {
    super.initState();
    _submitted = (widget.questionData['answered'] == true) && !widget.isPending;
    if (!_submitted && widget.isPending) {
      _startAutoProceedTimer();
    }
  }

  void _startAutoProceedTimer() {
    _countdownTimer?.cancel();
    _secondsRemaining = 15;
    _isAutoProceedPaused = false;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_submitted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _submitRecommendedAnswers();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _pauseAutoProceed() {
    if (!_isAutoProceedPaused) {
      setState(() {
        _isAutoProceedPaused = true;
      });
      _countdownTimer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPending != oldWidget.isPending ||
        widget.questionData['answered'] != oldWidget.questionData['answered']) {
      final isSub = (widget.questionData['answered'] == true) && !widget.isPending;
      setState(() {
        _submitted = isSub;
      });
      if (isSub) {
        _countdownTimer?.cancel();
      } else if (!isSub && widget.isPending && _countdownTimer == null && !_isAutoProceedPaused) {
        _startAutoProceedTimer();
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _customInputController.dispose();
    super.dispose();
  }

  void _submitRecommendedAnswers() {
    _countdownTimer?.cancel();
    final questions = _questions;
    if (questions.isEmpty) {
      setState(() => _submitted = true);
      widget.onAnswer('Proceed with recommended plan');
      return;
    }

    final List<String> answerLines = [];
    for (int i = 0; i < questions.length; i++) {
      final rawQ = questions[i];
      final opts = _extractOptions(rawQ);
      final recommended = _findRecommended(opts);
      final label = 'A${i + 1}';
      answerLines.add('$label: $recommended');
    }

    final fullAnswer = answerLines.join('\n');
    setState(() {
      _submitted = true;
    });
    widget.onAnswer(fullAnswer);
  }

  void _submitAnswers() {
    _countdownTimer?.cancel();
    final questions = _questions;
    if (questions.isEmpty) return;

    final List<String> answerLines = [];
    for (int i = 0; i < questions.length; i++) {
      final selected = _selectedOptions[i] ?? {};
      final custom = _customAnswers[i]?.trim() ?? '';

      final List<String> choices = [];
      for (final s in selected) {
        if (s == '__other__') {
          if (custom.isNotEmpty) choices.add(custom);
        } else {
          choices.add(s);
        }
      }

      if (choices.isEmpty && custom.isNotEmpty) {
        choices.add(custom);
      }

      final label = 'A${i + 1}';
      if (choices.isNotEmpty) {
        answerLines.add('$label: ${choices.join(", ")}');
      } else {
        answerLines.add('$label: (Skipped)');
      }
    }

    final fullAnswer = answerLines.join('\n');
    setState(() {
      _submitted = true;
    });
    widget.onAnswer(fullAnswer);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AgyTheme.isDark(context);
    final questions = _questions;

    if (questions.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalQ = questions.length;
    final rawQ = questions[_currentQIndex.clamp(0, totalQ - 1)];
    final currentQ = rawQ is Map ? Map<String, dynamic>.from(rawQ) : <String, dynamic>{};
    final qText = (currentQ['question'] ?? currentQ['prompt'] ?? currentQ['title'] ?? currentQ['text']) as String? ??
        'Please provide your selection:';
    dynamic rawOptions = currentQ['options'] ?? currentQ['choices'] ?? currentQ['items'];
    if (rawOptions is String) {
      try {
        rawOptions = jsonDecode(rawOptions);
      } catch (_) {
        rawOptions = rawOptions.split(RegExp(r',\s*'));
      }
    }
    final List<String> options = [];
    if (rawOptions is List) {
      for (final opt in rawOptions) {
        if (opt is Map) {
          final label = opt['text'] ?? opt['label'] ?? opt['title'] ?? opt['value'] ?? opt.toString();
          options.add(label.toString());
        } else if (opt != null) {
          options.add(opt.toString());
        }
      }
    }
    final isMulti = currentQ['is_multi_select'] == true;
    final selectedSet = _selectedOptions.putIfAbsent(_currentQIndex, () => <String>{});
    final answeredStr = widget.questionData['answer'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _submitted
              ? (isDark ? Colors.white24 : Colors.black12)
              : (isDark ? Colors.white38 : Colors.black26),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Question badge + Title + Pagination
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              color: isDark ? const Color(0xFF22242A) : const Color(0xFFF7F7F8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 15,
                      color: AgyTheme.getTextPrimary(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      qText,
                      style: TextStyle(
                        color: AgyTheme.getTextPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (totalQ > 1) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: _currentQIndex > 0
                              ? () => setState(() => _currentQIndex--)
                              : null,
                          child: Icon(
                            Icons.chevron_left,
                            size: 18,
                            color: _currentQIndex > 0
                                ? AgyTheme.getTextPrimary(context)
                                : AgyTheme.getTextMuted(context),
                          ),
                        ),
                        Text(
                          '${_currentQIndex + 1} of $totalQ',
                          style: TextStyle(
                            color: AgyTheme.getTextSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        InkWell(
                          onTap: _currentQIndex < totalQ - 1
                              ? () => setState(() => _currentQIndex++)
                              : null,
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: _currentQIndex < totalQ - 1
                                ? AgyTheme.getTextPrimary(context)
                                : AgyTheme.getTextMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.8),

            // Auto-Proceed Status Banner
            if (!_submitted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF22242B) : const Color(0xFFF1F3F5),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 15,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isAutoProceedPaused
                            ? 'Auto-proceed paused. Select an option or proceed.'
                            : 'Auto-proceeding with recommended option in ${_secondsRemaining}s...',
                        style: TextStyle(
                          color: AgyTheme.getTextSecondary(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_isAutoProceedPaused)
                      InkWell(
                        onTap: _pauseAutoProceed,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          child: Text(
                            'Pause',
                            style: TextStyle(
                              color: AgyTheme.getTextMuted(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _submitRecommendedAnswers,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text(
                        'Proceed Now',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // If already submitted in past turn, display answered banner
            if (_submitted && answeredStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: AgyTheme.getTextPrimary(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Selection: $answeredStr',
                        style: TextStyle(
                          color: AgyTheme.getTextSecondary(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Options List
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                children: [
                  ...List.generate(options.length, (idx) {
                    final opt = options[idx];
                    final isRecommended = opt.toLowerCase().contains('(recommended)');
                    final isSelected = selectedSet.contains(opt);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: _submitted
                            ? null
                            : () {
                                _pauseAutoProceed();
                                setState(() {
                                  if (isMulti) {
                                    if (isSelected) {
                                      selectedSet.remove(opt);
                                    } else {
                                      selectedSet.add(opt);
                                    }
                                  } else {
                                    selectedSet.clear();
                                    selectedSet.add(opt);
                                  }
                                });
                              },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
                                : (isDark ? const Color(0xFF22242B) : const Color(0xFFF9F9FB)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? (isDark ? Colors.white70 : Colors.black87)
                                  : (isDark ? Colors.white10 : Colors.black12),
                              width: isSelected ? 1.2 : 0.8,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Number Badge
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? (isDark ? Colors.black : Colors.white)
                                        : AgyTheme.getTextPrimary(context),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        opt,
                                        style: TextStyle(
                                          color: AgyTheme.getTextPrimary(context),
                                          fontSize: 12.5,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    if (isRecommended) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AgyTheme.getBorder(context), width: 0.6),
                                        ),
                                        child: Text(
                                          'RECOMMENDED',
                                          style: TextStyle(
                                            color: AgyTheme.getTextSecondary(context),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  isMulti ? Icons.check_box_rounded : Icons.radio_button_checked,
                                  size: 16,
                                  color: AgyTheme.getTextPrimary(context),
                                )
                              else
                                Icon(
                                  isMulti ? Icons.check_box_outline_blank : Icons.radio_button_off,
                                  size: 16,
                                  color: AgyTheme.getTextMuted(context),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // "Other (write your answer)" option
                  InkWell(
                    onTap: _submitted
                        ? null
                        : () {
                            _pauseAutoProceed();
                            setState(() {
                              if (isMulti) {
                                if (selectedSet.contains('__other__')) {
                                  selectedSet.remove('__other__');
                                } else {
                                  selectedSet.add('__other__');
                                }
                              } else {
                                selectedSet.clear();
                                selectedSet.add('__other__');
                              }
                            });
                          },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedSet.contains('__other__')
                            ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
                            : (isDark ? const Color(0xFF22242B) : const Color(0xFFF9F9FB)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selectedSet.contains('__other__')
                              ? (isDark ? Colors.white70 : Colors.black87)
                              : (isDark ? Colors.white10 : Colors.black12),
                          width: selectedSet.contains('__other__') ? 1.2 : 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedSet.contains('__other__')
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${options.length + 1}',
                                  style: TextStyle(
                                    color: selectedSet.contains('__other__')
                                        ? (isDark ? Colors.black : Colors.white)
                                        : AgyTheme.getTextPrimary(context),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Other (write your answer)',
                                  style: TextStyle(
                                    color: AgyTheme.getTextPrimary(context),
                                    fontSize: 12.5,
                                    fontWeight: selectedSet.contains('__other__') ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Icon(
                                selectedSet.contains('__other__')
                                    ? (isMulti ? Icons.check_box_rounded : Icons.radio_button_checked)
                                    : (isMulti ? Icons.check_box_outline_blank : Icons.radio_button_off),
                                size: 16,
                                color: selectedSet.contains('__other__')
                                    ? AgyTheme.getTextPrimary(context)
                                    : AgyTheme.getTextMuted(context),
                              ),
                            ],
                          ),
                          if (selectedSet.contains('__other__') && !_submitted) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _customInputController,
                              style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Type your custom answer here...',
                                hintStyle: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF16181D) : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: AgyTheme.getBorder(context)),
                                ),
                              ),
                              onChanged: (val) {
                                _pauseAutoProceed();
                                _customAnswers[_currentQIndex] = val;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Actions (Cancel / Skip / Auto-Proceed / Continue)
            if (!_submitted)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _submitted = true);
                        widget.onAnswer('Skip');
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: AgyTheme.getTextSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submitRecommendedAnswers,
                      icon: const Icon(Icons.bolt, size: 14),
                      label: const Text(
                        'Auto-Proceed (Recommended)',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const Spacer(),
                    if (_currentQIndex < totalQ - 1)
                      OutlinedButton(
                        onPressed: () => setState(() => _currentQIndex++),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(color: AgyTheme.getBorder(context)),
                        ),
                        child: Text(
                          'Next Question',
                          style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 12),
                        ),
                      )
                    else
                      ElevatedButton(
                        onPressed: _submitAnswers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Continue',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

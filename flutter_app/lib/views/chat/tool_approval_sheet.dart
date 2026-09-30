import 'package:flutter/material.dart';
import '../../core/theme/agy_theme.dart';

class ToolApprovalCard extends StatelessWidget {
  final Map<String, dynamic> approvalData;
  final Function(String callId, bool approved) onDecision;

  const ToolApprovalCard({
    super.key,
    required this.approvalData,
    required this.onDecision,
  });

  @override
  Widget build(BuildContext context) {
    final callId = approvalData['call_id'] as String? ?? '';
    final toolName = approvalData['tool_name'] as String? ?? 'command';
    final args = approvalData['args'] as Map<String, dynamic>? ?? {};
    final isDark = AgyTheme.isDark(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AgyTheme.getSurface(context),
        border: Border.all(color: AgyTheme.getTextPrimary(context), width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: AgyTheme.getTextPrimary(context), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tool Execution Approval Required: $toolName',
                  style: TextStyle(
                    color: AgyTheme.getTextPrimary(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AgyTheme.getSurfaceLight(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AgyTheme.getBorder(context)),
            ),
            child: Text(
              args.toString(),
              style: TextStyle(
                color: AgyTheme.getTextSecondary(context),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => onDecision(callId, false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AgyTheme.getBorder(context)),
                ),
                child: Text('Deny', style: TextStyle(color: AgyTheme.getTextPrimary(context))),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => onDecision(callId, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                ),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

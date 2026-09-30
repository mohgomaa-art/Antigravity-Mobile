import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/agy_theme.dart';

class DeveloperProfileCard extends StatelessWidget {
  final bool compact;

  const DeveloperProfileCard({super.key, this.compact = false});

  static const String githubUrl = 'https://github.com/mohgomaa-art/';
  static const String linkedinUrl = 'https://www.linkedin.com/in/moh-gomaa-art/';

  static Future<void> launchTargetUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AgyTheme.getSurface(context),
            content: Text(
              'Could not open link: $url',
              style: TextStyle(color: AgyTheme.getTextPrimary(context)),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AgyTheme.getSurface(context),
            content: Text(
              'Error opening link: $e',
              style: TextStyle(color: AgyTheme.getTextPrimary(context)),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AgyTheme.isDark(context);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AgyTheme.getSurface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Moh Gomaa',
              style: TextStyle(
                color: AgyTheme.getTextPrimary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 12),
            _buildMonochromePill(
              context: context,
              icon: Icons.code_rounded,
              label: 'GitHub',
              url: githubUrl,
            ),
            const SizedBox(width: 8),
            _buildMonochromePill(
              context: context,
              icon: Icons.business_center_outlined,
              label: 'LinkedIn',
              url: linkedinUrl,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgyTheme.getSurface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AgyTheme.getBorder(context),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
                  border: Border.all(
                    color: AgyTheme.getBorder(context),
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Text(
                    'MG',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moh Gomaa',
                      style: TextStyle(
                        color: AgyTheme.getTextPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      'Lead Developer & Creator',
                      style: TextStyle(
                        color: AgyTheme.getTextMuted(context),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  context: context,
                  label: 'GitHub',
                  icon: Icons.terminal_rounded,
                  url: githubUrl,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  context: context,
                  label: 'LinkedIn',
                  icon: Icons.link_rounded,
                  url: linkedinUrl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String url,
  }) {
    return InkWell(
      onTap: () => launchTargetUrl(context, url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AgyTheme.getSurfaceLight(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AgyTheme.getBorder(context),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AgyTheme.getTextPrimary(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AgyTheme.getTextPrimary(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonochromePill({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      onTap: () => launchTargetUrl(context, url),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AgyTheme.getSurfaceLight(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AgyTheme.getBorder(context),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AgyTheme.getTextPrimary(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: AgyTheme.getTextPrimary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

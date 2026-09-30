import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/antigravity_logo.dart';
import '../widgets/developer_profile_card.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  static const String kDisclaimerPrefKey = 'disclaimer_acknowledged_v1';

  static Future<bool> isAcknowledged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kDisclaimerPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markAcknowledged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kDisclaimerPrefKey, true);
    } catch (_) {}
  }

  static Future<void> checkAndShowStartupNotice(BuildContext context) async {
    final acknowledged = await isAcknowledged();
    if (!acknowledged && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const StartupDisclaimerDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0E),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFFFFFFF)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Legal & Disclaimer',
          style: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18, color: Color(0xFFA1A1AA)),
            tooltip: 'Copy Disclaimer Text',
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _kFullDisclaimerText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF27272A),
                  content: Text(
                    'Disclaimer text copied to clipboard',
                    style: TextStyle(color: Color(0xFFFFFFFF)),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            const DeveloperProfileCard(),
            const SizedBox(height: 16),
            // Warning Callout Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3F3F46), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27272A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF52525B), width: 0.8),
                        ),
                        child: const Text(
                          'IMPORTANT NOTICE',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'UNOFFICIAL PROJECT',
                        style: TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This software is an independent, community-driven, personal research companion and developer utility. It is NOT an official Google product and is NOT affiliated with, sponsored by, or endorsed by Google LLC or Alphabet Inc.',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildSection(
              title: '1. Unofficial Personal Research Project',
              body:
                  'This software is an open-source development tool designed to give engineers remote mobile and desktop multi-profile orchestration over their local Google Antigravity developer sessions. It is provided strictly for personal developer workflows, education, and interoperability experimentation.',
            ),

            _buildSection(
              title: '2. Trademark & Brand Attribution',
              body:
                  '• "Google", "Google Antigravity", "Antigravity", "Gemini", and "Android" are trademarks or registered trademarks of Google LLC.\n'
                  '• "Windows" and "PowerShell" are trademarks of Microsoft Corporation.\n'
                  '• "Claude" is a trademark of Anthropic, PBC.\n'
                  '• "OpenAI" and "ChatGPT" are trademarks of OpenAI, Inc.\n\n'
                  'All product names, logos, and brands cited herein belong to their respective owners. Use of these marks is conducted strictly under Nominative Fair Use solely for descriptive identification and technical compatibility. It does not imply endorsement, sponsorship, or licensing.',
            ),

            _buildSection(
              title: '3. Local Interoperability & Privacy',
              body:
                  '• 100% Peer-to-Peer: Communication between mobile devices and host machines operates exclusively across your private local area network (LAN / Wi-Fi / Loopback) with zero intermediate cloud servers and zero external data telemetry.\n'
                  '• Zero Bundled Binaries: This project does NOT distribute or redistribute any proprietary Google binaries, internal source code, or application packages. It interfaces exclusively with the user\'s locally installed, legally licensed copy of Antigravity on their own machine.\n'
                  '• No DRM Circumvention: This tool does not bypass authentication, encryption, or digital rights management mechanisms in violation of 17 U.S.C. Section 1201 or applicable copyright law.',
            ),

            _buildSection(
              title: '4. Terms of Service & User Responsibility',
              body:
                  'Users are solely responsible for ensuring that their use of this software complies with all third-party agreements, including the Google Terms of Service and the Google Generative AI Prohibited Use Policy. The developers assume no liability for account suspensions, rate limitations, quota adjustments, or third-party service modifications.',
            ),

            _buildSection(
              title: '5. Disclaimer of Warranties & Limitation of Liability',
              body:
                  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.\n\n'
                  'UNDER NO CIRCUMSTANCES SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, LOSS OF DATA, WORK STOPPAGE, COMPUTER FAILURE, OR OTHER LIABILITY ARISING FROM OR IN CONNECTION WITH THE SOFTWARE.',
            ),

            _buildSection(
              title: '6. License',
              body:
                  'Licensed under the Apache License, Version 2.0. Section 6 explicitly excludes the grant of any trademark permissions.',
            ),

            const SizedBox(height: 20),

            // Acknowledge Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: const Color(0xFF000000),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await markAcknowledged();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  'Acknowledge & Close',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFA1A1AA),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class StartupDisclaimerDialog extends StatelessWidget {
  const StartupDisclaimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C0C0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF27272A), width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          const AntigravityLogo(size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'LEGAL DISCLAIMER',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3F3F46), width: 0.8),
            ),
            child: const Text(
              'UNOFFICIAL COMMUNITY COMPANION',
              style: TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This application is an independent, open-source personal research companion and developer workflow utility.\n\n'
            'It is NOT an official Google product and is NOT affiliated with, sponsored by, or endorsed by Google LLC or Alphabet Inc.\n\n'
            'All communication runs strictly peer-to-peer over your private local network. Users are solely responsible for ensuring compliance with third-party Terms of Service.',
            style: TextStyle(
              color: Color(0xFFD4D4D8),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFA1A1AA),
                  side: const BorderSide(color: Color(0xFF27272A), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
                  );
                },
                child: const Text(
                  'Full Details',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: const Color(0xFF000000),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  await DisclaimerScreen.markAcknowledged();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  'I Acknowledge',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const String _kFullDisclaimerText = '''
LEGAL DISCLAIMER & TERMS OF USE

1. Unofficial Personal Research Project
This project is an independent, community-driven, open-source personal research companion and developer utility. It is developed solely for educational, workflow automation, and interoperability research purposes.
This software is NOT an official Google product and is NOT developed, maintained, supported, endorsed, or affiliated with Google LLC, Alphabet Inc., or any of their subsidiaries.

2. Trademark & Brand Attribution
- "Google", "Google Antigravity", "Antigravity", "Gemini", "Android", "Chrome", "Google Cloud", and associated logos are trademarks or registered trademarks of Google LLC.
- "Windows", "PowerShell", and "Edge" are trademarks or registered trademarks of Microsoft Corporation.
- "Claude" is a trademark of Anthropic, PBC.
- "OpenAI" and "ChatGPT" are trademarks of OpenAI, Inc.
All product names, logos, brands, and registered trademarks cited in this repository are property of their respective owners. Use of these names, marks, and visual symbols is conducted strictly under Nominative Fair Use for descriptive identification, technical interoperability, and documentation purposes only.

3. Architecture & Non-Distribution of Proprietary Software
- Zero Bundled Binaries: This repository does NOT contain, redistribute, or pirate any proprietary Google binaries, compiled libraries, application packages, or internal schemas.
- Local Self-Hosted Interoperability: This tool operates as an external companion bridge communicating exclusively with the developer's own legally obtained, locally installed Antigravity application running on their personal machine via standard inter-process communication (IPC), local WebSockets, and loopback HTTP APIs.
- No DRM Circumvention: This software does not bypass, crack, disable, or circumvent technological protection measures, encryption, or digital rights management (DRM) in violation of the Digital Millennium Copyright Act (DMCA) 17 U.S.C. Section 1201 or international equivalents.

4. User Responsibility & Terms of Service Compliance
Users are solely responsible for ensuring their usage of this software complies with all applicable third-party terms, including the Google Terms of Service and the Google Generative AI Prohibited Use Policy.

5. Disclaimer of Warranties and Limitation of Liability
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS, MAINTAINERS, OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, LOSS OF DATA, ACCOUNT SUSPENSION, SERVICE RESTRICTION, RATE-LIMITING, HARDWARE DAMAGE, OR OTHER LIABILITY.

6. License
Licensed under the Apache License, Version 2.0. Section 6 explicitly excludes the grant of any trademark permissions.
''';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// ストア上の最新バージョンを確認し、必要なら更新ダイアログを出す。
class UpdateChecker {
  UpdateChecker._();

  static const String _dismissedVersionKey = 'update_prompt_dismissed_version';

  /// チュートリアル表示後など、画面が安定してから呼ぶ。
  static Future<void> maybePrompt(BuildContext context) async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final status = await _check();
      if (status == null || !status.isUpdateAvailable) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_dismissedVersionKey) == status.storeVersion) {
        return;
      }

      if (!context.mounted) return;
      await _showDialog(context, status);
    } catch (e) {
      debugPrint('アップデート確認に失敗しました: $e');
    }
  }

  static Future<_UpdateStatus?> _check() async {
    final info = await PackageInfo.fromPlatform();
    final localVersion = info.version;
    final packageName = info.packageName;

    if (Platform.isIOS) {
      return _checkIos(localVersion: localVersion, bundleId: packageName);
    }
    return _checkAndroid(localVersion: localVersion, packageName: packageName);
  }

  static Future<_UpdateStatus?> _checkIos({
    required String localVersion,
    required String bundleId,
  }) async {
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'bundleId': bundleId,
      'country': 'jp',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final body = response.body;
    final versionMatch = RegExp(
      r'"version"\s*:\s*"([^"]+)"',
    ).firstMatch(body);
    final trackMatch = RegExp(r'"trackId"\s*:\s*(\d+)').firstMatch(body);
    final urlMatch = RegExp(
      r'"trackViewUrl"\s*:\s*"([^"]+)"',
    ).firstMatch(body);

    final storeVersion = versionMatch?.group(1);
    if (storeVersion == null) return null;

    final storeUrl =
        urlMatch?.group(1)?.replaceAll(r'\u0026', '&') ??
        (trackMatch != null
            ? 'https://apps.apple.com/app/id${trackMatch.group(1)}'
            : null);
    if (storeUrl == null) return null;

    return _UpdateStatus(
      localVersion: localVersion,
      storeVersion: storeVersion,
      storeUrl: storeUrl,
    );
  }

  static Future<_UpdateStatus?> _checkAndroid({
    required String localVersion,
    required String packageName,
  }) async {
    final uri = Uri.https('play.google.com', '/store/apps/details', {
      'id': packageName,
      'hl': 'en',
      'gl': 'US',
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final storeVersion = _parsePlayStoreVersion(response.body);
    if (storeVersion == null) return null;

    return _UpdateStatus(
      localVersion: localVersion,
      storeVersion: storeVersion,
      storeUrl: 'https://play.google.com/store/apps/details?id=$packageName',
    );
  }

  static String? _parsePlayStoreVersion(String html) {
    final patterns = <RegExp>[
      RegExp(r'\[\[\["([\d.]+?)"\]\]'),
      RegExp(r'"softwareVersion"\s*:\s*"([\d.]+)"'),
      RegExp(r'Current Version.+?>([\d.]+)<'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final version = match?.group(1);
      if (version != null && version.contains('.')) {
        return version;
      }
    }
    return null;
  }

  static Future<void> _showDialog(
    BuildContext context,
    _UpdateStatus status,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('アップデートのお知らせ'),
          content: Text(
            '新しいバージョン（${status.storeVersion}）が公開されています。\n'
            '現在のバージョンは ${status.localVersion} です。\n\n'
            'ストアで更新してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('あとで'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ストアを開く'),
            ),
          ],
        );
      },
    );

    final prefs = await SharedPreferences.getInstance();
    // 「あとで」でも同じストア版では再表示しない
    await prefs.setString(_dismissedVersionKey, status.storeVersion);

    if (result == true) {
      final uri = Uri.parse(status.storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _UpdateStatus {
  final String localVersion;
  final String storeVersion;
  final String storeUrl;

  const _UpdateStatus({
    required this.localVersion,
    required this.storeVersion,
    required this.storeUrl,
  });

  bool get isUpdateAvailable =>
      _compareVersions(storeVersion, localVersion) > 0;
}

/// 1.10.0 > 1.9.9 のように数値比較する。
int _compareVersions(String a, String b) {
  final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

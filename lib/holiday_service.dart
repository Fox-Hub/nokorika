import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'holidays_fallback.dart';

/// 日本の祝日データを管理するサービス。
///
/// 取得の優先順位:
/// 1. キャッシュ（前回API取得時に保存したデータ。期限内ならこれを使う）
/// 2. API（内閣府祝日API: holidays-jp）から最新データを取得し、キャッシュを更新
/// 3. どちらも失敗した場合は holidays_fallback.dart の静的データを使用
class HolidayService {
  static const String _apiUrl =
      'https://holidays-jp.github.io/api/v1/date.json';
  static const String _cacheKey = 'holiday_api_cache_v1';
  static const String _cacheDateKey = 'holiday_api_cache_date_v1';
  static const Duration _cacheValidDuration = Duration(days: 7);

  /// 日付文字列（yyyy-MM-dd）→祝日名 のMapを返す
  static Future<Map<String, String>> fetchHolidays() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. キャッシュが新しければそのまま使う
    final cachedDateStr = prefs.getString(_cacheDateKey);
    final cachedJson = prefs.getString(_cacheKey);
    if (cachedDateStr != null && cachedJson != null) {
      final cachedDate = DateTime.tryParse(cachedDateStr);
      if (cachedDate != null &&
          DateTime.now().difference(cachedDate) < _cacheValidDuration) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(cachedJson);
          return decoded.map((k, v) => MapEntry(k, v.toString()));
        } catch (_) {
          // キャッシュが壊れていたら無視してAPI取得に進む
        }
      }
    }

    // 2. APIから取得を試みる
    try {
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        final Map<String, String> holidays = decoded.map(
          (k, v) => MapEntry(k, v.toString()),
        );
        // キャッシュへ保存
        await prefs.setString(_cacheKey, jsonEncode(holidays));
        await prefs.setString(_cacheDateKey, DateTime.now().toIso8601String());
        return holidays;
      }
    } catch (_) {
      // ネットワークエラーなどは無視してフォールバックへ
    }

    // 3. キャッシュが古くても残っていればそれを使う（オフライン時の救済）
    if (cachedJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cachedJson);
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    // 4. 最終フォールバック：同梱の静的データ
    return Map<String, String>.from(japaneseHolidaysFallback);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Android ホームウィジェットへ今月の残り営業日データを同期する。
///
/// 日付またぎでもアプリ未起動で数字が追従するよう、
/// 「日付 → その日時点の残り営業日」マップを渡す。
class WidgetSync {
  static const String androidWidgetName = 'NokorikaWidgetProvider';

  static const String keyRemainingByDate = 'remaining_by_date';
  static const String keyLastBusinessDay = 'last_business_day';
  static const String keyMonthLabel = 'month_label';
  static const String keyMonthKey = 'month_key';

  /// [businessDays] は対象月の営業日一覧（昇順想定）。
  /// [month] はその月の任意日（通常は今日）。
  static Future<void> syncRemainingBusinessDays({
    required List<DateTime> businessDays,
    required DateTime month,
  }) async {
    // Windows / Web 等ではウィジェット対象外
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final year = month.year;
      final monthNum = month.month;
      final lastDayOfMonth = DateTime(year, monthNum + 1, 0).day;

      final Map<String, int> remainingByDate = {};
      for (int day = 1; day <= lastDayOfMonth; day++) {
        final date = DateTime(year, monthNum, day);
        final remaining =
            businessDays.where((bd) => bd.isAfter(date)).length;
        remainingByDate[_dateKey(date)] = remaining;
      }

      final DateTime lastBd = businessDays.isNotEmpty
          ? businessDays.last
          : DateTime(year, monthNum, lastDayOfMonth);

      await HomeWidget.saveWidgetData<String>(
        keyRemainingByDate,
        jsonEncode(remainingByDate),
      );
      await HomeWidget.saveWidgetData<String>(
        keyLastBusinessDay,
        '${lastBd.month}/${lastBd.day}',
      );
      await HomeWidget.saveWidgetData<String>(
        keyMonthLabel,
        '$year年$monthNum月',
      );
      await HomeWidget.saveWidgetData<String>(
        keyMonthKey,
        '${year.toString().padLeft(4, '0')}-${monthNum.toString().padLeft(2, '0')}',
      );

      await HomeWidget.updateWidget(name: androidWidgetName);
    } catch (e) {
      debugPrint('ウィジェット同期に失敗しました: $e');
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

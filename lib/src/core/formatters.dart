import 'package:intl/intl.dart';

class AppFormatters {
  static final DateFormat _listTimeFormat = DateFormat('MM-dd HH:mm');
  static final DateFormat _detailTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _daySectionFormat = DateFormat('M月d日');
  static final DateFormat _fullDaySectionFormat = DateFormat('yyyy年M月d日');
  static final DateFormat _dayKeyFormat = DateFormat('yyyy-MM-dd');

  static String listDate(DateTime value) =>
      _listTimeFormat.format(value.toLocal());

  static String detailDate(DateTime value) =>
      _detailTimeFormat.format(value.toLocal());

  static String daySection(DateTime value, {DateTime? now}) {
    final localValue = value.toLocal();
    final localNow = (now ?? DateTime.now()).toLocal();
    if (_isSameLocalDay(localValue, localNow)) {
      return '今天';
    }
    if (_isSameLocalDay(
      localValue,
      localNow.subtract(const Duration(days: 1)),
    )) {
      return '昨天';
    }
    if (localValue.year == localNow.year) {
      return _daySectionFormat.format(localValue);
    }
    return _fullDaySectionFormat.format(localValue);
  }

  static String dayKey(DateTime value) => _dayKeyFormat.format(value.toLocal());

  static String host(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }

  static bool _isSameLocalDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

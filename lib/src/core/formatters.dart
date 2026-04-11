import 'package:intl/intl.dart';

class AppFormatters {
  static final DateFormat _listTimeFormat = DateFormat('MM-dd HH:mm');
  static final DateFormat _detailTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  static String listDate(DateTime value) =>
      _listTimeFormat.format(value.toLocal());

  static String detailDate(DateTime value) =>
      _detailTimeFormat.format(value.toLocal());

  static String host(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }
}

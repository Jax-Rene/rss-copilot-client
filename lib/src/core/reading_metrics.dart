import '../models/entry_record.dart';

class ReadingMetrics {
  static const int _latinWordsPerMinute = 220;
  static const int _cjkCharsPerMinute = 500;

  static int estimateReadingMinutes(EntryRecord entry) {
    final text = _readingText(entry);
    if (text.isEmpty) {
      return 1;
    }

    final cjkChars = RegExp(r'[\u3400-\u9fff]').allMatches(text).length;
    final latinWords = RegExp(
      r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*",
    ).allMatches(text).length;
    final seconds =
        (latinWords / _latinWordsPerMinute * 60) +
        (cjkChars / _cjkCharsPerMinute * 60);
    return seconds <= 0 ? 1 : (seconds / 60).ceil().clamp(1, 240);
  }

  static String readingTimeLabel(EntryRecord entry) {
    return '${estimateReadingMinutes(entry)} 分钟';
  }

  static int estimateRemainingReadingMinutes(EntryRecord entry) {
    if (entry.isRead || entry.readingProgress >= 0.98) {
      return 0;
    }

    final totalMinutes = estimateReadingMinutes(entry);
    if (entry.readingProgress <= 0.02) {
      return totalMinutes;
    }

    final remainingMinutes = (totalMinutes * (1 - entry.readingProgress))
        .ceil()
        .clamp(1, totalMinutes);
    return remainingMinutes;
  }

  static String remainingReadingTimeLabel(EntryRecord entry) {
    return '剩余 ${durationLabel(estimateRemainingReadingMinutes(entry))}';
  }

  static int estimateTotalMinutes(Iterable<EntryRecord> entries) {
    var total = 0;
    for (final entry in entries) {
      total += estimateReadingMinutes(entry);
    }
    return total;
  }

  static int estimateRemainingTotalMinutes(Iterable<EntryRecord> entries) {
    var total = 0;
    for (final entry in entries) {
      total += estimateRemainingReadingMinutes(entry);
    }
    return total;
  }

  static String durationLabel(int minutes) {
    if (minutes <= 0) {
      return '0 分钟';
    }
    if (minutes < 60) {
      return '$minutes 分钟';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours 小时';
    }
    return '$hours 小时 $remainingMinutes 分钟';
  }

  static String _readingText(EntryRecord entry) {
    final body = _plainText(entry.contentHtml);
    if (body.isNotEmpty) {
      return body;
    }

    final translatedSource = entry.translationSegments
        .map((segment) => segment.source)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
    if (translatedSource.trim().isNotEmpty) {
      return translatedSource;
    }

    return [entry.title, entry.summary]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  static String _plainText(String? html) {
    final raw = html?.trim();
    if (raw == null || raw.isEmpty) {
      return '';
    }

    return raw
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'&[#a-zA-Z0-9]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

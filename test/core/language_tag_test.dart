import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/core/language_tag.dart';

void main() {
  test('validateLanguageTag rejects blank and malformed values', () {
    expect(validateLanguageTag(' ', '默认语言'), '默认语言 不能为空');
    expect(
      validateLanguageTag('not a language', '默认语言'),
      '默认语言 必须是 BCP 47 标签，例如 zh-CN',
    );
  });

  test('normalizeLanguageTag normalizes common tags', () {
    expect(normalizeLanguageTag('ZH-cn'), 'zh-CN');
    expect(normalizeLanguageTag(' en-us '), 'en-US');
    expect(normalizedLanguageTagOrNull('ja-jp'), 'ja-JP');
    expect(normalizedLanguageTagOrNull('not a language'), isNull);
  });
}

import 'package:rss_copilot_client/src/core/diagnostic_redaction.dart';
import 'package:test/test.dart';

void main() {
  group('diagnostic redaction', () {
    test('redacts sensitive free text without removing useful context', () {
      final redacted = redactDiagnosticText(
        'probe failed https://user:pass@reader.example/api '
        'Authorization: Bearer sk-secret123456 Cookie: sid=raw-session '
        'Set-Cookie: refresh=raw-refresh token=raw-token password=raw-pass',
      );

      expect(
        redacted,
        contains('probe failed https://redacted@reader.example/api'),
      );
      expect(redacted, contains('Authorization: Bearer [redacted]'));
      expect(redacted, contains('Cookie: [redacted]'));
      expect(redacted, contains('Set-Cookie: [redacted]'));
      expect(redacted, contains('[redacted]'));
      expect(redacted, isNot(contains('user:pass')));
      expect(redacted, isNot(contains('sk-secret123456')));
      expect(redacted, isNot(contains('raw-session')));
      expect(redacted, isNot(contains('raw-refresh')));
      expect(redacted, isNot(contains('raw-token')));
      expect(redacted, isNot(contains('raw-pass')));
    });

    test('redacts URL userinfo and sensitive query parameters', () {
      final redacted = redactDiagnosticUrl(
        'https://user:pass@reader.example/app?api_key=raw-key&topic=ai&token=raw-token',
      );

      expect(
        redacted,
        'https://redacted@reader.example/app?redacted=%5Bredacted%5D&topic=ai',
      );
      expect(redacted, isNot(contains('user:pass')));
      expect(redacted, isNot(contains('raw-key')));
      expect(redacted, isNot(contains('raw-token')));
    });

    test('uses configurable empty placeholders', () {
      expect(redactDiagnosticText(null), '-');
      expect(redactDiagnosticText('  ', emptyPlaceholder: ''), '');
      expect(redactDiagnosticUrl('  '), '-');
    });
  });
}

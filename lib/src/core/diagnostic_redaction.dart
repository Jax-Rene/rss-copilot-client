String redactDiagnosticText(String? value, {String emptyPlaceholder = '-'}) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return emptyPlaceholder;
  }
  return text
      .replaceAllMapped(
        RegExp(
          r'\b([a-z][a-z0-9+.-]*://)[^\s/@]+(?::[^\s/@]*)?@',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}redacted@',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9][A-Za-z0-9_-]{6,}\b'), '[redacted]')
      .replaceAllMapped(
        RegExp(
          r'\b(Authorization)\s*:\s*(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}: ${match.group(2)} [redacted]',
      )
      .replaceAllMapped(
        RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        (match) => 'Bearer [redacted]',
      )
      .replaceAllMapped(
        RegExp(r'\bBasic\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        (match) => 'Basic [redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'\b(Authorization)\s*:\s*(?!Bearer\s+\[redacted\]|Basic\s+\[redacted\])[^\r\n\s]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}: [redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'\b(Set-Cookie|Cookie)\s*:\s*(?:(?!\bSet-Cookie\s*:|\bCookie\s*:)[^\r\n])+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}: [redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'\b(x[_-]?api[_-]?key|api[_-]?key|access[_-]?token|auth[_-]?token|refresh[_-]?token|token|secret|password|signature|sig)\s*[=:]\s*([^&\s]+)',
          caseSensitive: false,
        ),
        (match) => '[redacted]',
      );
}

String redactDiagnosticUrl(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasQuery) {
    return redactDiagnosticText(_redactDiagnosticUriUserInfo(uri, text));
  }
  final redactedParameters = <String, dynamic>{};
  for (final entry in uri.queryParametersAll.entries) {
    if (_isSensitiveDiagnosticParam(entry.key)) {
      redactedParameters['redacted'] = '[redacted]';
    } else {
      redactedParameters[entry.key] = entry.value;
    }
  }
  return redactDiagnosticText(
    uri
        .replace(
          userInfo: uri.userInfo.isEmpty ? null : 'redacted',
          queryParameters: redactedParameters,
        )
        .toString(),
  );
}

String _redactDiagnosticUriUserInfo(Uri? uri, String fallbackText) {
  if (uri == null || uri.userInfo.isEmpty) {
    return fallbackText;
  }
  return uri.replace(userInfo: 'redacted').toString();
}

bool _isSensitiveDiagnosticParam(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized == 'xapikey' ||
      normalized == 'apikey' ||
      normalized == 'accesstoken' ||
      normalized == 'authtoken' ||
      normalized == 'refreshtoken' ||
      normalized == 'token' ||
      normalized == 'secret' ||
      normalized == 'password' ||
      normalized == 'signature' ||
      normalized == 'sig';
}

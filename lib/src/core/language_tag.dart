final _languageTagPattern = RegExp(
  r'^[a-z]{2,3}(-[a-z0-9]{2,8})*$',
  caseSensitive: false,
);

String? validateLanguageTag(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    return '$label 不能为空';
  }
  if (!_languageTagPattern.hasMatch(value.trim())) {
    return '$label 必须是 BCP 47 标签，例如 zh-CN';
  }
  return null;
}

String normalizeLanguageTag(String value) {
  final parts = value.trim().split('-');
  final normalized = <String>[parts.first.toLowerCase()];
  for (final part in parts.skip(1)) {
    normalized.add(part.length == 2 ? part.toUpperCase() : part);
  }
  return normalized.join('-');
}

String? normalizedLanguageTagOrNull(String value) {
  return validateLanguageTag(value, '语言') == null
      ? normalizeLanguageTag(value)
      : null;
}

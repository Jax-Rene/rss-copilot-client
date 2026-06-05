const maxSearchTokenCount = 8;

List<String> searchQueryTokens(String query) {
  final tokens = <String>{};
  for (final token in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
    if (token.isEmpty) {
      continue;
    }
    tokens.add(token);
    if (tokens.length >= maxSearchTokenCount) {
      break;
    }
  }
  return tokens.toList(growable: false);
}

String normalizeSearchQuery(String query) => searchQueryTokens(query).join(' ');

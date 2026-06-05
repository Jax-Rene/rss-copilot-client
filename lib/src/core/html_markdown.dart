import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

String htmlToMarkdown(String html) {
  final document = html_parser.parseFragment(html);
  return _normalizeMarkdown(
    document.nodes.map(_nodeToMarkdown).where(_hasText).join('\n\n'),
  );
}

String _nodeToMarkdown(dom.Node node) {
  if (node is dom.Text) {
    return node.text.replaceAll(RegExp(r'\s+'), ' ');
  }
  if (node is! dom.Element) {
    return '';
  }

  final tag = node.localName?.toLowerCase() ?? '';
  return switch (tag) {
    'h1' => '# ${_childrenText(node)}',
    'h2' => '## ${_childrenText(node)}',
    'h3' => '### ${_childrenText(node)}',
    'h4' => '#### ${_childrenText(node)}',
    'h5' => '##### ${_childrenText(node)}',
    'h6' => '###### ${_childrenText(node)}',
    'p' => _childrenText(node),
    'br' => '\n',
    'strong' || 'b' => '**${_childrenText(node)}**',
    'em' || 'i' => '*${_childrenText(node)}*',
    'del' || 's' || 'strike' => '~~${_childrenText(node)}~~',
    'kbd' => _htmlInlineMarkdown(node, 'kbd'),
    'sup' => _htmlInlineMarkdown(node, 'sup'),
    'sub' => _htmlInlineMarkdown(node, 'sub'),
    'code' => _inlineCodeMarkdown(node),
    'pre' => _preformattedMarkdown(node),
    'blockquote' => _blockquoteMarkdown(node),
    'a' => _linkMarkdown(node),
    'img' => _imageMarkdown(node),
    'hr' => '---',
    'table' => _tableMarkdown(node),
    'dl' => _definitionListMarkdown(node),
    'ul' => _listMarkdown(node, ordered: false),
    'ol' => _listMarkdown(node, ordered: true),
    'li' => _childrenText(node),
    'script' || 'style' || 'noscript' || 'svg' => '',
    'figure' ||
    'figcaption' ||
    'article' ||
    'main' ||
    'section' ||
    'div' => _childrenBlockMarkdown(node),
    _ => _childrenText(node),
  };
}

String _childrenText(dom.Element element) {
  return _normalizeInline(element.nodes.map(_nodeToMarkdown).join(''));
}

String _childrenBlockMarkdown(dom.Element element) {
  return element.nodes.map(_nodeToMarkdown).where(_hasText).join('\n\n');
}

String _linkMarkdown(dom.Element element) {
  final text = _childrenText(element);
  final href = element.attributes['href']?.trim();
  if (!_hasText(href)) {
    return text;
  }
  final label = text.isEmpty ? href! : text;
  return '[${_escapeMarkdownLabel(label)}](${_markdownDestination(href!)})';
}

String _imageMarkdown(dom.Element element) {
  final src = element.attributes['src']?.trim();
  if (!_hasText(src)) {
    return '';
  }
  final alt = element.attributes['alt']?.trim() ?? '';
  return '![${_escapeMarkdownLabel(alt)}](${_markdownDestination(src!)})';
}

String _escapeMarkdownLabel(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
}

String _markdownDestination(String value) {
  final destination = value.replaceAll('<', '%3C').replaceAll('>', '%3E');
  if (RegExp(r'[\s()]').hasMatch(destination)) {
    return '<$destination>';
  }
  return destination;
}

String _listMarkdown(
  dom.Element element, {
  required bool ordered,
  int depth = 0,
}) {
  var index = 1;
  return element.children
      .where((child) => child.localName?.toLowerCase() == 'li')
      .map((child) {
        final taskMarker = _taskListMarker(child);
        final line = _listItemMarkdown(
          child,
          marker: taskMarker ?? (ordered ? '${index++}.' : '-'),
          depth: depth,
        );
        return line;
      })
      .where(_hasText)
      .join('\n');
}

String _listItemMarkdown(
  dom.Element element, {
  required String marker,
  required int depth,
}) {
  final nestedLists = <String>[];
  final contentNodes = <dom.Node>[];

  for (final node in element.nodes) {
    if (node is dom.Element && _isListElement(node)) {
      final tag = node.localName?.toLowerCase();
      nestedLists.add(
        _listMarkdown(node, ordered: tag == 'ol', depth: depth + 1),
      );
    } else if (node is dom.Element && _isTaskCheckbox(node)) {
      continue;
    } else {
      contentNodes.add(node);
    }
  }

  final indent = '  ' * depth;
  final content = _normalizeInline(contentNodes.map(_nodeToMarkdown).join(''));
  return [
    if (_hasText(content)) '$indent$marker $content',
    for (final nestedList in nestedLists)
      if (_hasText(nestedList)) nestedList,
  ].join('\n');
}

bool _isListElement(dom.Element element) {
  final tag = element.localName?.toLowerCase();
  return tag == 'ul' || tag == 'ol';
}

String? _taskListMarker(dom.Element element) {
  final checkbox = element.children.cast<dom.Element?>().firstWhere(
    (child) => child != null && _isTaskCheckbox(child),
    orElse: () => null,
  );
  if (checkbox == null) {
    return null;
  }
  return checkbox.attributes.containsKey('checked') ? '- [x]' : '- [ ]';
}

bool _isTaskCheckbox(dom.Element element) {
  return element.localName?.toLowerCase() == 'input' &&
      element.attributes['type']?.toLowerCase() == 'checkbox';
}

String _definitionListMarkdown(dom.Element element) {
  final lines = <String>[];
  String? currentTerm;

  for (final child in element.children) {
    final tag = child.localName?.toLowerCase();
    if (tag == 'dt') {
      currentTerm = _childrenText(child);
      continue;
    }
    if (tag != 'dd') {
      continue;
    }

    final description = _childrenText(child);
    if (!_hasText(description)) {
      continue;
    }
    if (_hasText(currentTerm)) {
      lines.add('- **$currentTerm**: $description');
      currentTerm = null;
    } else {
      lines.add('- $description');
    }
  }

  if (_hasText(currentTerm)) {
    lines.add('- **$currentTerm**');
  }
  return lines.join('\n');
}

String _tableMarkdown(dom.Element element) {
  final rows = element
      .querySelectorAll('tr')
      .map(_tableRowCells)
      .where((cells) => cells.isNotEmpty)
      .toList(growable: false);
  if (rows.isEmpty) {
    return '';
  }

  final headerIndex = rows.indexWhere(
    (cells) => cells.any((cell) => cell.isHeader),
  );
  final headerCells = rows[headerIndex < 0 ? 0 : headerIndex];
  final bodyRows = [
    for (var index = 0; index < rows.length; index += 1)
      if (index != (headerIndex < 0 ? 0 : headerIndex)) rows[index],
  ];
  final columnCount = rows.fold<int>(
    headerCells.length,
    (max, cells) => cells.length > max ? cells.length : max,
  );

  return [
    _markdownTableLine(headerCells, columnCount),
    _markdownTableSeparator(columnCount),
    for (final row in bodyRows) _markdownTableLine(row, columnCount),
  ].join('\n');
}

List<({String text, bool isHeader})> _tableRowCells(dom.Element row) {
  return row.children
      .where((cell) {
        final tag = cell.localName?.toLowerCase();
        return tag == 'th' || tag == 'td';
      })
      .map(
        (cell) => (
          text: _escapeTableCell(_childrenText(cell)),
          isHeader: cell.localName?.toLowerCase() == 'th',
        ),
      )
      .toList(growable: false);
}

String _markdownTableLine(
  List<({String text, bool isHeader})> cells,
  int columnCount,
) {
  final paddedCells = [
    for (var index = 0; index < columnCount; index += 1)
      index < cells.length && cells[index].text.isNotEmpty
          ? cells[index].text
          : ' ',
  ];
  return '| ${paddedCells.join(' | ')} |';
}

String _markdownTableSeparator(int columnCount) {
  return '| ${List.filled(columnCount, '---').join(' | ')} |';
}

String _escapeTableCell(String text) {
  return text.replaceAll('\n', '<br>').replaceAll('|', r'\|');
}

String _blockquoteMarkdown(dom.Element element) {
  return _childrenBlockMarkdown(element)
      .split('\n')
      .map((line) => line.trim().isEmpty ? '>' : '> ${line.trim()}')
      .join('\n');
}

String _htmlInlineMarkdown(dom.Element element, String tag) {
  final text = _childrenText(element);
  if (text.isEmpty) {
    return '';
  }
  return '<$tag>${_escapeHtml(text)}</$tag>';
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _inlineCodeMarkdown(dom.Element element) {
  final text = _childrenText(element);
  if (text.isEmpty) {
    return '';
  }
  final fence = _inlineCodeFenceFor(text);
  final padding = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
  return '$fence$padding$text$padding$fence';
}

String _inlineCodeFenceFor(String text) {
  final matches = RegExp(r'`+').allMatches(text);
  final longestRun = matches.fold<int>(
    0,
    (max, match) => match.group(0)!.length > max ? match.group(0)!.length : max,
  );
  return '`' * (longestRun + 1);
}

String _preformattedMarkdown(dom.Element element) {
  final text = element.text.trimRight();
  if (text.isEmpty) {
    return '';
  }
  final fence = _codeFenceFor(text);
  final language = _codeLanguage(element);
  return '$fence$language\n$text\n$fence';
}

String _codeFenceFor(String text) {
  final matches = RegExp(r'`+').allMatches(text);
  final longestRun = matches.fold<int>(
    0,
    (max, match) => match.group(0)!.length > max ? match.group(0)!.length : max,
  );
  return '`' * (longestRun >= 3 ? longestRun + 1 : 3);
}

String _codeLanguage(dom.Element element) {
  final candidates = [
    element.attributes['data-language'],
    element.attributes['data-lang'],
    _languageFromClass(element.classes),
    for (final code in element.children.where(
      (child) => child.localName?.toLowerCase() == 'code',
    )) ...[
      code.attributes['data-language'],
      code.attributes['data-lang'],
      _languageFromClass(code.classes),
    ],
  ];
  for (final candidate in candidates) {
    final language = _sanitizeCodeLanguage(candidate);
    if (language != null) {
      return language;
    }
  }
  return '';
}

String? _languageFromClass(Iterable<String> classes) {
  for (final className in classes) {
    final normalized = className.trim();
    if (normalized.startsWith('language-')) {
      return normalized.substring('language-'.length);
    }
    if (normalized.startsWith('lang-')) {
      return normalized.substring('lang-'.length);
    }
  }
  return null;
}

String? _sanitizeCodeLanguage(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return RegExp(r'^[A-Za-z0-9_+#.-]+$').hasMatch(normalized)
      ? normalized
      : null;
}

String _normalizeInline(String text) {
  return text
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
}

String _normalizeMarkdown(String markdown) {
  return markdown
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}

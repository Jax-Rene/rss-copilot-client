enum ReaderWidth { narrow, comfortable, wide }

enum EntrySortOrder { newestFirst, oldestFirst, shortestFirst, longestFirst }

enum EntryQueueFilter { all, unread, inProgress }

enum EntryListDensity { comfortable, compact }

enum SourceListSortOrder { original, unread, health, name }

const Object _unchanged = Object();

class ReaderPreferences {
  const ReaderPreferences({
    required this.fontSize,
    required this.lineHeight,
    required this.width,
    this.entrySortOrder = EntrySortOrder.newestFirst,
    this.entryQueueFilter = EntryQueueFilter.all,
    this.entryListDensity = EntryListDensity.comfortable,
    this.sourceListSortOrder = SourceListSortOrder.original,
    this.collapsedEntryDateSections = const <String>[],
    this.collapsedSourceFolders = const <String>[],
    this.showTranslations = true,
    this.lastSection,
    this.lastSelectedSourceId,
    this.lastSelectedEntryId,
    this.lastEntrySourceFilterId,
    this.lastEntryFolderFilter,
  });

  static const defaultPreferences = ReaderPreferences(
    fontSize: 17,
    lineHeight: 1.7,
    width: ReaderWidth.comfortable,
    entrySortOrder: EntrySortOrder.newestFirst,
    entryQueueFilter: EntryQueueFilter.all,
    entryListDensity: EntryListDensity.comfortable,
    sourceListSortOrder: SourceListSortOrder.original,
    showTranslations: true,
  );

  final double fontSize;
  final double lineHeight;
  final ReaderWidth width;
  final EntrySortOrder entrySortOrder;
  final EntryQueueFilter entryQueueFilter;
  final EntryListDensity entryListDensity;
  final SourceListSortOrder sourceListSortOrder;
  final List<String> collapsedEntryDateSections;
  final List<String> collapsedSourceFolders;
  final bool showTranslations;
  final String? lastSection;
  final int? lastSelectedSourceId;
  final int? lastSelectedEntryId;
  final int? lastEntrySourceFilterId;
  final String? lastEntryFolderFilter;

  double get maxContentWidth => switch (width) {
    ReaderWidth.narrow => 720,
    ReaderWidth.comfortable => 860,
    ReaderWidth.wide => 1040,
  };

  ReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderWidth? width,
    EntrySortOrder? entrySortOrder,
    EntryQueueFilter? entryQueueFilter,
    EntryListDensity? entryListDensity,
    SourceListSortOrder? sourceListSortOrder,
    List<String>? collapsedEntryDateSections,
    List<String>? collapsedSourceFolders,
    bool? showTranslations,
    Object? lastSection = _unchanged,
    Object? lastSelectedSourceId = _unchanged,
    Object? lastSelectedEntryId = _unchanged,
    Object? lastEntrySourceFilterId = _unchanged,
    Object? lastEntryFolderFilter = _unchanged,
  }) {
    return ReaderPreferences(
      fontSize: _clampFontSize(fontSize ?? this.fontSize),
      lineHeight: _clampLineHeight(lineHeight ?? this.lineHeight),
      width: width ?? this.width,
      entrySortOrder: entrySortOrder ?? this.entrySortOrder,
      entryQueueFilter: entryQueueFilter ?? this.entryQueueFilter,
      entryListDensity: entryListDensity ?? this.entryListDensity,
      sourceListSortOrder: sourceListSortOrder ?? this.sourceListSortOrder,
      collapsedEntryDateSections: collapsedEntryDateSections == null
          ? this.collapsedEntryDateSections
          : _normalizeStringList(collapsedEntryDateSections),
      collapsedSourceFolders: collapsedSourceFolders == null
          ? this.collapsedSourceFolders
          : _normalizeStringList(collapsedSourceFolders),
      showTranslations: showTranslations ?? this.showTranslations,
      lastSection: lastSection == _unchanged
          ? this.lastSection
          : lastSection as String?,
      lastSelectedSourceId: lastSelectedSourceId == _unchanged
          ? this.lastSelectedSourceId
          : lastSelectedSourceId as int?,
      lastSelectedEntryId: lastSelectedEntryId == _unchanged
          ? this.lastSelectedEntryId
          : lastSelectedEntryId as int?,
      lastEntrySourceFilterId: lastEntrySourceFilterId == _unchanged
          ? this.lastEntrySourceFilterId
          : lastEntrySourceFilterId as int?,
      lastEntryFolderFilter: lastEntryFolderFilter == _unchanged
          ? this.lastEntryFolderFilter
          : lastEntryFolderFilter as String?,
    );
  }

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    return ReaderPreferences.defaultPreferences.copyWith(
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      lineHeight: (json['lineHeight'] as num?)?.toDouble(),
      width: _parseWidth(json['width'] as String?),
      entrySortOrder: _parseEntrySortOrder(json['entrySortOrder'] as String?),
      entryQueueFilter: _parseEntryQueueFilter(
        json['entryQueueFilter'] as String?,
      ),
      entryListDensity: _parseEntryListDensity(
        json['entryListDensity'] as String?,
      ),
      sourceListSortOrder: _parseSourceListSortOrder(
        json['sourceListSortOrder'] as String?,
      ),
      collapsedEntryDateSections: _parseStringList(
        json['collapsedEntryDateSections'],
      ),
      collapsedSourceFolders: _parseStringList(json['collapsedSourceFolders']),
      showTranslations: json['showTranslations'] as bool?,
      lastSection: _parseNullableString(json['lastSection']),
      lastSelectedSourceId: _parseNullableInt(json['lastSelectedSourceId']),
      lastSelectedEntryId: _parseNullableInt(json['lastSelectedEntryId']),
      lastEntrySourceFilterId: _parseNullableInt(
        json['lastEntrySourceFilterId'],
      ),
      lastEntryFolderFilter: _parseNullableString(
        json['lastEntryFolderFilter'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'width': width.name,
      'entrySortOrder': entrySortOrder.name,
      'entryQueueFilter': entryQueueFilter.name,
      'entryListDensity': entryListDensity.name,
      'sourceListSortOrder': sourceListSortOrder.name,
      if (collapsedEntryDateSections.isNotEmpty)
        'collapsedEntryDateSections': collapsedEntryDateSections,
      if (collapsedSourceFolders.isNotEmpty)
        'collapsedSourceFolders': collapsedSourceFolders,
      'showTranslations': showTranslations,
      if (lastSection != null) 'lastSection': lastSection,
      if (lastSelectedSourceId != null)
        'lastSelectedSourceId': lastSelectedSourceId,
      if (lastSelectedEntryId != null)
        'lastSelectedEntryId': lastSelectedEntryId,
      if (lastEntrySourceFilterId != null)
        'lastEntrySourceFilterId': lastEntrySourceFilterId,
      if (lastEntryFolderFilter != null)
        'lastEntryFolderFilter': lastEntryFolderFilter,
    };
  }
}

double _clampFontSize(double value) => value.clamp(14, 24).toDouble();

double _clampLineHeight(double value) => value.clamp(1.35, 2.1).toDouble();

ReaderWidth? _parseWidth(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final width in ReaderWidth.values) {
    if (width.name == value) {
      return width;
    }
  }
  return null;
}

EntrySortOrder? _parseEntrySortOrder(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final sortOrder in EntrySortOrder.values) {
    if (sortOrder.name == value) {
      return sortOrder;
    }
  }
  return null;
}

EntryQueueFilter? _parseEntryQueueFilter(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final filter in EntryQueueFilter.values) {
    if (filter.name == value) {
      return filter;
    }
  }
  return null;
}

EntryListDensity? _parseEntryListDensity(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final density in EntryListDensity.values) {
    if (density.name == value) {
      return density;
    }
  }
  return null;
}

SourceListSortOrder? _parseSourceListSortOrder(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final sortOrder in SourceListSortOrder.values) {
    if (sortOrder.name == value) {
      return sortOrder;
    }
  }
  return null;
}

List<String> _parseStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return _normalizeStringList(value.whereType<String>());
}

List<String> _normalizeStringList(Iterable<String> value) {
  final normalized = <String>{};
  for (final item in value) {
    final text = item.trim();
    if (text.isNotEmpty) {
      normalized.add(text);
    }
  }
  final sorted = normalized.toList(growable: false);
  sorted.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return sorted;
}

String? _parseNullableString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _parseNullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

enum PendingEntryActionType {
  readState('readState'),
  savedState('savedState'),
  noiseState('noiseState'),
  readingProgress('readingProgress');

  const PendingEntryActionType(this.wireValue);

  final String wireValue;

  static PendingEntryActionType fromWireValue(String? value) {
    return PendingEntryActionType.values.firstWhere(
      (type) => type.wireValue == value,
      orElse: () => PendingEntryActionType.readState,
    );
  }
}

class PendingEntryAction {
  const PendingEntryAction({
    required this.type,
    required this.entryId,
    required this.updatedAtMicros,
    this.boolValue,
    this.doubleValue,
  });

  final PendingEntryActionType type;
  final int entryId;
  final int updatedAtMicros;
  final bool? boolValue;
  final double? doubleValue;

  String get key => keyFor(type, entryId);

  static String keyFor(PendingEntryActionType type, int entryId) {
    return '${type.wireValue}:$entryId';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.wireValue,
      'entryId': entryId,
      'updatedAtMicros': updatedAtMicros,
      'boolValue': boolValue,
      'doubleValue': doubleValue,
    };
  }

  factory PendingEntryAction.fromJson(Map<String, dynamic> json) {
    return PendingEntryAction(
      type: PendingEntryActionType.fromWireValue(json['type'] as String?),
      entryId: json['entryId'] as int? ?? 0,
      updatedAtMicros: json['updatedAtMicros'] as int? ?? 0,
      boolValue: json['boolValue'] as bool?,
      doubleValue: (json['doubleValue'] as num?)?.toDouble(),
    );
  }
}

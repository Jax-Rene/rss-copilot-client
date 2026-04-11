import 'auth_user.dart';
import 'settings_bundle.dart';

class SessionData {
  const SessionData({
    required this.baseUrl,
    required this.token,
    required this.user,
    required this.lastServerTime,
    required this.themeOverride,
  });

  final String baseUrl;
  final String token;
  final AuthUser user;
  final DateTime? lastServerTime;
  final AppThemeMode? themeOverride;

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      baseUrl: json['baseUrl'] as String? ?? '',
      token: json['token'] as String? ?? '',
      user: AuthUser.fromJson(
        (json['user'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      lastServerTime: _parseDateTime(json['lastServerTime'] as String?),
      themeOverride: _parseThemeMode(json['themeOverride'] as String?),
    );
  }

  SessionData copyWith({
    String? baseUrl,
    String? token,
    AuthUser? user,
    DateTime? lastServerTime,
    bool clearLastServerTime = false,
    AppThemeMode? themeOverride,
    bool clearThemeOverride = false,
  }) {
    return SessionData(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
      user: user ?? this.user,
      lastServerTime: clearLastServerTime
          ? null
          : lastServerTime ?? this.lastServerTime,
      themeOverride: clearThemeOverride
          ? null
          : themeOverride ?? this.themeOverride,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'baseUrl': baseUrl,
      'token': token,
      'user': user.toJson(),
      'lastServerTime': lastServerTime?.toUtc().toIso8601String(),
      'themeOverride': themeOverride?.wireValue,
    };
  }
}

DateTime? _parseDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toUtc();
}

AppThemeMode? _parseThemeMode(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return AppThemeMode.fromWire(value);
}

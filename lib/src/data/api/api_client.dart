import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/search_query.dart';
import '../../models/auth_user.dart';
import '../../models/entry_detail.dart';
import '../../models/entry_list_item.dart';
import '../../models/entry_page_cursor.dart';
import '../../models/feed_source.dart';
import '../../models/settings_bundle.dart';
import 'api_exception.dart';

enum EntryView {
  feed('feed'),
  noise('noise'),
  saved('saved'),
  all('all');

  const EntryView(this.wireValue);

  final String wireValue;
}

class LoginResponse {
  const LoginResponse({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

class ServerHealth {
  const ServerHealth({
    required this.service,
    required this.apiVersion,
    required this.status,
    required this.serverTime,
  });

  static const String expectedService = 'rss-copilot-server';
  static const int minimumApiVersion = 1;

  final String service;
  final int apiVersion;
  final String status;
  final DateTime? serverTime;

  bool get isUp => status.toUpperCase() == 'UP';
  bool get isExpectedService => service == expectedService;
  bool get isSupportedApi => apiVersion >= minimumApiVersion;

  factory ServerHealth.fromJson(Map<String, dynamic> json) {
    final serverTimeText = json['serverTime'] as String?;
    return ServerHealth(
      service: json['service'] as String? ?? '',
      apiVersion: json['apiVersion'] as int? ?? 0,
      status: (json['status'] as String? ?? 'UNKNOWN').toUpperCase(),
      serverTime: serverTimeText == null
          ? null
          : DateTime.tryParse(serverTimeText)?.toUtc(),
    );
  }
}

class SyncPayload {
  const SyncPayload({
    required this.serverTime,
    required this.sources,
    required this.entries,
    required this.deletedSourceIds,
    required this.settings,
  });

  final DateTime serverTime;
  final List<FeedSource> sources;
  final List<EntryDetail> entries;
  final List<int> deletedSourceIds;
  final SettingsBundle settings;
}

class OpmlImportResult {
  const OpmlImportResult({
    required this.importedCount,
    required this.skippedCount,
    this.refreshAcceptedCount = 0,
    required this.sources,
  });

  final int importedCount;
  final int skippedCount;
  final int refreshAcceptedCount;
  final List<FeedSource> sources;

  factory OpmlImportResult.fromJson(Map<String, dynamic> json) {
    return OpmlImportResult(
      importedCount: json['importedCount'] as int? ?? 0,
      skippedCount: json['skippedCount'] as int? ?? 0,
      refreshAcceptedCount: json['refreshAcceptedCount'] as int? ?? 0,
      sources: ((json['sources'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => FeedSource.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class RefreshAcceptedResult {
  const RefreshAcceptedResult({
    required this.accepted,
    required this.acceptedCount,
    required this.requestedCount,
    required this.skippedCount,
  });

  final bool accepted;
  final int acceptedCount;
  final int requestedCount;
  final int skippedCount;

  factory RefreshAcceptedResult.fromJson(
    Map<String, dynamic> json, {
    required int fallbackRequestedCount,
    required int fallbackAcceptedCount,
  }) {
    final acceptedCount = _nonNegativeInt(
      json['acceptedCount'],
      fallbackAcceptedCount,
    );
    final requestedCount = _nonNegativeInt(
      json['requestedCount'],
      fallbackRequestedCount,
    );
    final fallbackSkippedCount = requestedCount > acceptedCount
        ? requestedCount - acceptedCount
        : 0;
    return RefreshAcceptedResult(
      accepted: json['accepted'] as bool? ?? true,
      acceptedCount: acceptedCount,
      requestedCount: requestedCount,
      skippedCount: _nonNegativeInt(json['skippedCount'], fallbackSkippedCount),
    );
  }
}

class EntryPage {
  const EntryPage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<EntryListItem> items;
  final bool hasMore;
  final EntryPageCursor? nextCursor;

  factory EntryPage.fromJson(Map<String, dynamic> json) {
    return EntryPage(
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => EntryListItem.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      hasMore: json['hasMore'] as bool? ?? false,
      nextCursor: json['nextCursor'] is Map<String, dynamic>
          ? EntryPageCursor.fromJson(json['nextCursor'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RssApiClient {
  RssApiClient({required String baseUrl, this.token, http.Client? httpClient})
    : baseUrl = _normalizeApiClientBaseUrl(baseUrl),
      _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _httpClient;

  Future<ServerHealth> health() async {
    final response = await _send(
      method: 'GET',
      path: '/health',
      authenticated: false,
    );

    return ServerHealth.fromJson(response);
  }

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/auth/login',
      authenticated: false,
      body: <String, dynamic>{'email': email, 'password': password},
    );

    return LoginResponse(
      token: response['token'] as String,
      user: AuthUser.fromJson(response['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthUser> me() async {
    final response = await _send(method: 'GET', path: '/auth/me');

    return AuthUser.fromJson(response);
  }

  Future<void> logout() async {
    await _send(method: 'POST', path: '/auth/logout', allowNoContent: true);
  }

  Future<List<FeedSource>> fetchSources() async {
    final payload = await _sendList(method: 'GET', path: '/feed-sources');

    return payload.map(FeedSource.fromJson).toList(growable: false);
  }

  Future<FeedSource> createSource(String rssUrl, {String? folder}) async {
    final response = await _send(
      method: 'POST',
      path: '/feed-sources',
      body: <String, dynamic>{
        'rssUrl': rssUrl,
        'folder': folder ?? defaultSourceFolder,
      },
    );

    return FeedSource.fromJson(response);
  }

  Future<FeedSource> updateSource(FeedSource source) async {
    final response = await _send(
      method: 'PUT',
      path: '/feed-sources/${source.id}',
      body: <String, dynamic>{
        'name': source.name,
        'rssUrl': source.rssUrl,
        'iconUrl': source.iconUrl,
        'folder': source.folder,
        'enabled': source.enabled,
      },
    );

    return FeedSource.fromJson(response);
  }

  Future<void> deleteSource(int sourceId) async {
    await _send(
      method: 'DELETE',
      path: '/feed-sources/$sourceId',
      allowNoContent: true,
    );
  }

  Future<RefreshAcceptedResult> refreshAllSources() async {
    final response = await _send(method: 'POST', path: '/feed-sources/refresh');
    return RefreshAcceptedResult.fromJson(
      response,
      fallbackRequestedCount: 0,
      fallbackAcceptedCount: 0,
    );
  }

  Future<RefreshAcceptedResult> refreshSource(int sourceId) async {
    final response = await _send(
      method: 'POST',
      path: '/feed-sources/$sourceId/refresh',
    );
    return RefreshAcceptedResult.fromJson(
      response,
      fallbackRequestedCount: 1,
      fallbackAcceptedCount: 1,
    );
  }

  Future<RefreshAcceptedResult> refreshSources(List<int> sourceIds) async {
    if (sourceIds.isEmpty) {
      return const RefreshAcceptedResult(
        accepted: true,
        acceptedCount: 0,
        requestedCount: 0,
        skippedCount: 0,
      );
    }

    final response = await _send(
      method: 'POST',
      path: '/feed-sources/refresh',
      body: <String, dynamic>{'sourceIds': sourceIds},
    );
    return RefreshAcceptedResult.fromJson(
      response,
      fallbackRequestedCount: sourceIds.length,
      fallbackAcceptedCount: sourceIds.length,
    );
  }

  Future<String> exportOpml() {
    return _sendText(
      method: 'GET',
      path: '/feed-sources/opml',
      accept: 'application/xml',
    );
  }

  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/feed-sources/opml/import',
      body: <String, dynamic>{
        'opml': opml,
        'refreshAfterImport': refreshAfterImport,
      },
    );

    return OpmlImportResult.fromJson(response);
  }

  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    final folderName = folder?.trim();
    final normalizedSearchQuery = _normalizeApiSearchQuery(searchQuery);
    final response = await _send(
      method: 'GET',
      path: '/entries',
      queryParameters: <String, String>{
        'view': view.wireValue,
        'unreadOnly': unreadOnly.toString(),
        'limit': limit.toString(),
        if (folderName != null && folderName.isNotEmpty) 'folder': folderName,
        if (sourceId != null && sourceId > 0) 'sourceId': sourceId.toString(),
        'q': normalizedSearchQuery,
        if (before != null) ...{
          'beforePublishedAt': before.publishedAt.toUtc().toIso8601String(),
          'beforeId': before.id.toString(),
        },
      },
    );

    return EntryPage.fromJson(response);
  }

  Future<EntryPage> fetchSourceEntries(
    int sourceId, {
    int limit = 60,
    EntryPageCursor? before,
    String? searchQuery,
  }) async {
    final normalizedSearchQuery = _normalizeApiSearchQuery(searchQuery);
    final response = await _send(
      method: 'GET',
      path: '/feed-sources/$sourceId/entries',
      queryParameters: <String, String>{
        'limit': limit.toString(),
        'q': normalizedSearchQuery,
        if (before != null) ...{
          'beforePublishedAt': before.publishedAt.toUtc().toIso8601String(),
          'beforeId': before.id.toString(),
        },
      },
    );

    return EntryPage.fromJson(response);
  }

  Future<EntryDetail> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    final response = await _send(
      method: 'GET',
      path: '/entries/$entryId',
      queryParameters: <String, String>{'markRead': markRead.toString()},
    );

    return EntryDetail.fromJson(response);
  }

  Future<void> markRead(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/read',
      allowNoContent: true,
    );
  }

  Future<int> markEntriesRead(List<int> entryIds) async {
    if (entryIds.isEmpty) {
      return 0;
    }

    final response = await _send(
      method: 'POST',
      path: '/entries/read',
      body: <String, dynamic>{'entryIds': entryIds},
    );

    return response['updatedCount'] as int? ?? 0;
  }

  Future<void> markUnread(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/unread',
      allowNoContent: true,
    );
  }

  Future<void> markSaved(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/saved',
      allowNoContent: true,
    );
  }

  Future<void> markUnsaved(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/unsaved',
      allowNoContent: true,
    );
  }

  Future<void> updateReadingProgress(int entryId, double progress) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/progress',
      allowNoContent: true,
      body: <String, dynamic>{'progress': progress.clamp(0, 1)},
    );
  }

  Future<void> markNoise(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/noise',
      allowNoContent: true,
    );
  }

  Future<void> markFeed(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/feed',
      allowNoContent: true,
    );
  }

  Future<void> reprocessEntryAi(int entryId) async {
    await _send(method: 'POST', path: '/entries/$entryId/ai/reprocess');
  }

  Future<int> markAllRead(
    EntryView view, {
    int? sourceId,
    String? folder,
  }) async {
    final folderName = folder?.trim();
    final response = await _send(
      method: 'POST',
      path: '/entries/read-all',
      queryParameters: <String, String>{
        'view': view.wireValue,
        if (sourceId != null) 'sourceId': sourceId.toString(),
        if (folderName != null && folderName.isNotEmpty) 'folder': folderName,
      },
    );

    return response['updatedCount'] as int? ?? 0;
  }

  Future<SettingsBundle> fetchSettings() async {
    final response = await _send(method: 'GET', path: '/settings');

    return SettingsBundle.fromJson(response);
  }

  Future<AiSettings> updateAiSettings({
    required String provider,
    required String filterPrompt,
    required String summaryPrompt,
    required String translationPrompt,
    required bool autoSummaryEnabled,
    required bool autoTranslationEnabled,
    required String outputLanguage,
    String? apiKey,
    bool clearApiKey = false,
  }) async {
    final normalizedApiKey = apiKey?.trim();
    final response = await _send(
      method: 'PUT',
      path: '/settings/ai',
      body: <String, dynamic>{
        'provider': provider,
        if (normalizedApiKey != null && normalizedApiKey.isNotEmpty)
          'apiKey': normalizedApiKey,
        if (clearApiKey) 'clearApiKey': true,
        'filterPrompt': filterPrompt,
        'summaryPrompt': summaryPrompt,
        'translationPrompt': translationPrompt,
        'autoSummaryEnabled': autoSummaryEnabled,
        'autoTranslationEnabled': autoTranslationEnabled,
        'outputLanguage': outputLanguage,
      },
    );

    return AiSettings.fromJson(response);
  }

  Future<AppearanceSettings> updateAppearanceSettings({
    required AppThemeMode themeMode,
  }) async {
    final response = await _send(
      method: 'PUT',
      path: '/settings/appearance',
      body: <String, dynamic>{'themeMode': themeMode.wireValue},
    );

    return AppearanceSettings.fromJson(response);
  }

  Future<FeedSettings> updateFeedSettings({
    required String defaultLanguage,
  }) async {
    final response = await _send(
      method: 'PUT',
      path: '/settings/feeds',
      body: <String, dynamic>{'defaultLanguage': defaultLanguage.trim()},
    );

    return FeedSettings.fromJson(response);
  }

  Future<SyncPayload> syncBootstrap() => _sync('/sync/bootstrap');

  Future<SyncPayload> syncChanges(DateTime since) {
    return _sync(
      '/sync/changes',
      queryParameters: <String, String>{
        'since': since.toUtc().toIso8601String(),
      },
    );
  }

  Future<SyncPayload> _sync(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await _send(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
    );

    return SyncPayload(
      serverTime: DateTime.parse(response['serverTime'] as String).toUtc(),
      sources: ((response['sources'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => FeedSource.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      entries: ((response['entries'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => EntryDetail.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      deletedSourceIds:
          ((response['deletedSourceIds'] as List<dynamic>?) ??
                  const <dynamic>[])
              .map((item) => item as int)
              .toList(growable: false),
      settings: SettingsBundle.fromJson(
        (response['settings'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
    );
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    bool authenticated = true,
    bool allowNoContent = false,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final request = http.Request(method, _buildUri(path, queryParameters));
    request.headers.addAll(_headers(authenticated: authenticated));
    if (body != null) {
      request.body = jsonEncode(body);
    }

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      if (allowNoContent && response.statusCode == 204) {
        return const <String, dynamic>{};
      }

      final text = utf8.decode(response.bodyBytes);

      if (response.statusCode >= 400) {
        throw _apiExceptionFromResponse(response.statusCode, text);
      }

      return _decodeJsonObject(text);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    } on Exception catch (error) {
      throw NetworkException(error.toString());
    }
  }

  Future<List<Map<String, dynamic>>> _sendList({
    required String method,
    required String path,
  }) async {
    final request = http.Request(method, _buildUri(path, null));
    request.headers.addAll(_headers(authenticated: true));

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      final text = utf8.decode(response.bodyBytes);

      if (response.statusCode >= 400) {
        throw _apiExceptionFromResponse(response.statusCode, text);
      }

      final payload = text.isEmpty ? const <dynamic>[] : jsonDecode(text);
      final items = payload is List<dynamic> ? payload : const <dynamic>[];
      return items
          .map((item) => item as Map<String, dynamic>)
          .toList(growable: false);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    } on Exception catch (error) {
      throw NetworkException(error.toString());
    }
  }

  Future<String> _sendText({
    required String method,
    required String path,
    String accept = 'text/plain',
  }) async {
    final request = http.Request(method, _buildUri(path, null));
    request.headers.addAll(_headers(authenticated: true));
    request.headers['accept'] = accept;

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      final text = utf8.decode(response.bodyBytes);

      if (response.statusCode >= 400) {
        var error = const <String, dynamic>{};
        try {
          final decoded = text.isEmpty ? null : jsonDecode(text);
          if (decoded is Map<String, dynamic>) {
            error = decoded;
          }
        } on FormatException {
          error = const <String, dynamic>{};
        }
        throw ApiException(
          statusCode: response.statusCode,
          code: error['code'] as String? ?? 'UNKNOWN',
          message: error['message'] as String? ?? 'Request failed',
        );
      }

      return text;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    } on Exception catch (error) {
      throw NetworkException(error.toString());
    }
  }

  Map<String, String> _headers({required bool authenticated}) {
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
    };
    if (authenticated && token != null && token!.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    return headers;
  }

  ApiException _apiExceptionFromResponse(int statusCode, String responseText) {
    final error = _decodeErrorObject(responseText);
    return ApiException(
      statusCode: statusCode,
      code: error['code'] as String? ?? 'UNKNOWN',
      message: error['message'] as String? ?? 'Request failed',
    );
  }

  Map<String, dynamic> _decodeJsonObject(String responseText) {
    if (responseText.isEmpty) {
      return const <String, dynamic>{};
    }
    return jsonDecode(responseText) as Map<String, dynamic>;
  }

  Map<String, dynamic> _decodeErrorObject(String responseText) {
    try {
      final decoded = responseText.isEmpty ? null : jsonDecode(responseText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  Uri _buildUri(String path, Map<String, String>? queryParameters) {
    final root = Uri.parse(baseUrl.trim());
    final baseSegments = root.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final normalizedSegments = <String>[
      ...baseSegments,
      if (baseSegments.isEmpty || baseSegments.last != 'api') 'api',
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ];

    return root.replace(
      pathSegments: normalizedSegments,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value),
      ),
    );
  }
}

String _normalizeApiClientBaseUrl(String value) {
  final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority) {
    return trimmed;
  }
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final apiIndex = segments.lastIndexWhere(
    (segment) => segment.toLowerCase() == 'api',
  );
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: apiIndex < 0
        ? segments
        : segments.take(apiIndex).toList(growable: false),
  ).toString().replaceFirst(RegExp(r'/+$'), '');
}

int _nonNegativeInt(dynamic value, int fallback) {
  if (value is int && value >= 0) {
    return value;
  }
  if (value is num && value >= 0) {
    return value.toInt();
  }
  return fallback;
}

String _normalizeApiSearchQuery(String? searchQuery) {
  if (searchQuery == null) {
    return '';
  }
  return normalizeSearchQuery(searchQuery);
}

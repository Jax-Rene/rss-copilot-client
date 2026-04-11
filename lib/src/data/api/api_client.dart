import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/auth_user.dart';
import '../../models/entry_detail.dart';
import '../../models/entry_list_item.dart';
import '../../models/feed_source.dart';
import '../../models/settings_bundle.dart';
import 'api_exception.dart';

enum EntryView {
  feed('feed'),
  noise('noise'),
  all('all');

  const EntryView(this.wireValue);

  final String wireValue;
}

class LoginResponse {
  const LoginResponse({required this.token, required this.user});

  final String token;
  final AuthUser user;
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

class RssApiClient {
  RssApiClient({required this.baseUrl, this.token, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _httpClient;

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

  Future<FeedSource> createSource(String rssUrl) async {
    final response = await _send(
      method: 'POST',
      path: '/feed-sources',
      body: <String, dynamic>{'rssUrl': rssUrl},
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

  Future<void> refreshAllSources() async {
    await _send(method: 'POST', path: '/feed-sources/refresh');
  }

  Future<List<EntryListItem>> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
  }) async {
    final response = await _send(
      method: 'GET',
      path: '/entries',
      queryParameters: <String, String>{
        'view': view.wireValue,
        'unreadOnly': unreadOnly.toString(),
      },
    );

    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => EntryListItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    return items;
  }

  Future<List<EntryListItem>> fetchSourceEntries(int sourceId) async {
    final response = await _send(
      method: 'GET',
      path: '/feed-sources/$sourceId/entries',
    );

    return (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => EntryListItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
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

  Future<void> markUnread(int entryId) async {
    await _send(
      method: 'POST',
      path: '/entries/$entryId/unread',
      allowNoContent: true,
    );
  }

  Future<int> markAllRead(EntryView view) async {
    final response = await _send(
      method: 'POST',
      path: '/entries/read-all',
      queryParameters: <String, String>{'view': view.wireValue},
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
  }) async {
    final response = await _send(
      method: 'PUT',
      path: '/settings/ai',
      body: <String, dynamic>{
        'provider': provider,
        'apiKey': apiKey,
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

      final payload = response.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw ApiException(
          statusCode: response.statusCode,
          code: payload['code'] as String? ?? 'UNKNOWN',
          message: payload['message'] as String? ?? 'Request failed',
        );
      }

      return payload;
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
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
      final payload = response.body.isEmpty
          ? const <dynamic>[]
          : jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode >= 400) {
        final error = payload is Map<String, dynamic>
            ? payload
            : const <String, dynamic>{};
        throw ApiException(
          statusCode: response.statusCode,
          code: error['code'] as String? ?? 'UNKNOWN',
          message: error['message'] as String? ?? 'Request failed',
        );
      }

      final items = payload is List<dynamic> ? payload : const <dynamic>[];
      return items
          .map((item) => item as Map<String, dynamic>)
          .toList(growable: false);
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    }
  }

  Map<String, String> _headers({required bool authenticated}) {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    if (authenticated && token != null && token!.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    return headers;
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

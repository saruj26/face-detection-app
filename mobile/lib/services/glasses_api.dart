import 'package:dio/dio.dart';

import '../models/glasses.dart';

/// A user-presentable API error.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// HTTP client for the FastAPI backend. The app never talks to PostgreSQL
/// directly; everything goes through these endpoints.
class GlassesApi {
  GlassesApi(this._dio);

  final Dio _dio;

  static Dio createDio(String baseUrl) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.json,
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  String get baseUrl => _dio.options.baseUrl;

  /// GET /health — true when the API and its database are reachable.
  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/health');
      return res.data?['status'] == 'ok';
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /glasses
  Future<List<Glasses>> fetchGlasses({String? category}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/glasses',
        queryParameters: {'category': ?category},
      );
      final items = (res.data?['items'] as List?) ?? const [];
      return items
          .map((e) => Glasses.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _mapError(e);
    } on TypeError {
      throw const ApiException('The server returned an unexpected response.');
    }
  }

  /// GET /glasses/{id}
  Future<Glasses> fetchGlassesById(int id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/glasses/$id');
      return Glasses.fromJson(res.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    } on TypeError {
      throw const ApiException('The server returned an unexpected response.');
    }
  }

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.sendTimeout:
        return ApiException(
          "Can't reach the server at $baseUrl. Make sure the backend is running "
          'and the API URL in Settings matches your computer\'s address.',
        );
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException('The server took too long to respond. Please try again.');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return const ApiException('Frame not found.', statusCode: 404);
        if (code == 503) {
          return const ApiException(
            'The server is up but its database is unavailable.',
            statusCode: 503,
          );
        }
        return ApiException('Server error ($code). Please try again.', statusCode: code);
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.');
      case DioExceptionType.badCertificate:
        return const ApiException('The server certificate is not trusted.');
      case DioExceptionType.unknown:
        return const ApiException('Network error. Check your connection and try again.');
    }
  }
}

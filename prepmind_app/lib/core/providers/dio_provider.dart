import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
import '../services/log_service.dart';

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  // Attach JWT token on every request
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      // Bypass ngrok browser-warning interstitial for API clients
      options.headers['ngrok-skip-browser-warning'] = 'true';
      handler.next(options);
    },
    onError: (DioException error, handler) {
      // Convert low-level network errors into a readable exception so every
      // caller (provider / screen) sees the same clean message instead of the
      // raw Dio stack trace.
      final isNetworkError = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;

      if (isNetworkError) {
        handler.reject(
          DioException(
            requestOptions: error.requestOptions,
            type: error.type,
            error: error.error,
            message:
                'No internet connection. Please check your network and try again.',
          ),
        );
        return;
      }
      handler.next(error);
    },
  ));

  dio.interceptors.add(
    TalkerDioLogger(
      talker: LogService.talker,
      settings: const TalkerDioLoggerSettings(
        printRequestHeaders: true,
        printResponseHeaders: false,
      ),
    ),
  );

  return dio;
});

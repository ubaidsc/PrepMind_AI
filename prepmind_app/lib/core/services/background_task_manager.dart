import 'package:workmanager/workmanager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'poll_document_status') {
      final documentId = inputData?['documentId'] as String?;
      final subjectId = inputData?['subjectId'] as String?;
      final documentName = inputData?['documentName'] as String?;
      final apiUrl = inputData?['apiUrl'] as String?;

      if (documentId == null || subjectId == null || apiUrl == null) return false;

      try {
        final dio = Dio(BaseOptions(baseUrl: apiUrl));
        // Poll up to 15 times inside background runner
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(seconds: 5));
          final response = await dio.get('/documents/$subjectId');
          final List data = response.data['data'] as List;
          final doc = data.firstWhere((d) => d['id'] == documentId, orElse: () => null);
          
          if (doc != null) {
            final status = doc['status'] as String?;
            if (status == 'ready') {
              await NotificationService.showNotification(
                'Document Ready!',
                '"$documentName" has been processed successfully.',
              );
              return true;
            } else if (status == 'failed') {
              await NotificationService.showNotification(
                'Processing Failed',
                'Failed to process "$documentName".',
              );
              return true;
            }
          }
        }
      } catch (e) {
        return false;
      }
    }
    return true;
  });
}

class BackgroundTaskManager {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static void registerDocumentPolling(String subjectId, String documentId, String documentName) {
    final String baseApiUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
    
    Workmanager().registerOneOffTask(
      documentId,
      'poll_document_status',
      inputData: {
        'documentId': documentId,
        'subjectId': subjectId,
        'documentName': documentName,
        'apiUrl': baseApiUrl,
      },
    );
  }
}

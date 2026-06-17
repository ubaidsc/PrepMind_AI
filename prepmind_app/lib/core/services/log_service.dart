import 'package:talker_flutter/talker_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class LogService {
  static final Talker talker = Talker();

  static void info(String message) => talker.info(message);
  
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    talker.handle(error ?? message, stackTrace, message);
    if (error != null) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: message);
    }
  }
}

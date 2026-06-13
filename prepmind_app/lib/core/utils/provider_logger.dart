import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;

class ProviderLogger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? oldValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    developer.log(
      'Provider: ${provider.name ?? provider.runtimeType} | State Updated',
      name: 'RiverpodProfiler',
    );
  }
}

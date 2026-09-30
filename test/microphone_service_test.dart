import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/audio/microphone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.resohertz/microphone';
  late MethodChannel channel;
  late MicrophoneService service;
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    channel = const MethodChannel(channelName);
    service = MicrophoneService(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MicrophoneService - checkPermission', () {
    test('returns true when permission is granted', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'checkPermission') {
              return true;
            }
            return null;
          });

      final result = await service.checkPermission();
      expect(result, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'checkPermission');
    });

    test('returns false when permission is denied', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'checkPermission') {
              return false;
            }
            return null;
          });

      final result = await service.checkPermission();
      expect(result, isFalse);
    });

    test('returns false on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            throw PlatformException(code: 'ERROR', message: 'Failed');
          });

      final result = await service.checkPermission();
      expect(result, isFalse);
    });
  });

  group('MicrophoneService - requestPermission', () {
    test('returns true when user grants permission', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'requestPermission') {
              return true;
            }
            return null;
          });

      final result = await service.requestPermission();
      expect(result, isTrue);
      expect(log.first.method, 'requestPermission');
    });

    test('returns false when user denies permission', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'requestPermission') {
              return false;
            }
            return null;
          });

      final result = await service.requestPermission();
      expect(result, isFalse);
    });
  });

  group('MicrophoneService - initializeMicrophone', () {
    test('returns valid result when hardware is supported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final result = await service.initializeMicrophone(sampleRate: 44100);
      expect(result.isAvailable, isTrue);
      expect(result.sampleRate, 44100);
      expect(result.minBufferSize, 3584);
      expect(result.error, isNull);
      expect(log.first.arguments, {'sampleRate': 44100});
    });

    test(
      'returns failure result when hardware config is unsupported',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              if (methodCall.method == 'initializeMicrophone') {
                return <dynamic, dynamic>{
                  'isAvailable': false,
                  'sampleRate': 44100,
                  'minBufferSize': -2,
                  'error': 'UNSUPPORTED_CONFIGURATION',
                };
              }
              return null;
            });

        final result = await service.initializeMicrophone(sampleRate: 44100);
        expect(result.isAvailable, isFalse);
        expect(result.error, 'UNSUPPORTED_CONFIGURATION');
      },
    );

    test('handles PlatformException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            throw PlatformException(code: 'INIT_FAIL', message: 'Init failed');
          });

      final result = await service.initializeMicrophone();
      expect(result.isAvailable, isFalse);
      expect(result.error, 'Init failed');
    });
  });

  group('MicrophoneInitResult', () {
    test('equality and hash code check', () {
      const res1 = MicrophoneInitResult(
        isAvailable: true,
        sampleRate: 44100,
        minBufferSize: 2048,
      );
      const res2 = MicrophoneInitResult(
        isAvailable: true,
        sampleRate: 44100,
        minBufferSize: 2048,
      );
      const res3 = MicrophoneInitResult(
        isAvailable: false,
        sampleRate: 44100,
        minBufferSize: 0,
      );

      expect(res1, equals(res2));
      expect(res1.hashCode, equals(res2.hashCode));
      expect(res1, isNot(equals(res3)));
    });
  });
}

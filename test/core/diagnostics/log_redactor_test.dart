import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_redactor.dart';

void main() {
  group('LogRedactor secrets', () {
    final redactor = LogRedactor();

    test('replaces values of secret query parameters and keeps the key', () {
      expect(
        redactor.redact(
          'GET http://192.168.1.5:8080/stream?token=abc123&track=7',
        ),
        'GET http://192.168.1.5:8080/stream?token=<redacted>&track=7',
      );
      expect(
        redactor.redact('access_token=xyz refresh-token: qqq'),
        'access_token=<redacted> refresh-token: <redacted>',
      );
    });

    test('replaces header values including the KTV query token', () {
      expect(
        redactor.redact('KTV-QUERY-TOKEN: 9f8e7d6c'),
        'KTV-QUERY-TOKEN: <redacted>',
      );
      expect(
        redactor.redact('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.x.y'),
        'Authorization: Bearer <redacted>',
      );
      expect(
        redactor.redact('sent Bearer abcdefghijklmnop to hub'),
        'sent Bearer <redacted> to hub',
      );
    });

    test('replaces quoted JSON secret values', () {
      expect(
        redactor.redact('{"password": "hunter2", "name": "ok"}'),
        '{"password": "<redacted>", "name": "ok"}',
      );
      expect(redactor.redact("{'api_key':'k-1'}"), "{'api_key':'<redacted>'}");
    });

    test('replaces URL user info', () {
      expect(
        redactor.redact('proxy http://alice:s3cret@proxy.local:3128 failed'),
        'proxy http://<redacted>@proxy.local:3128 failed',
      );
    });

    test('does not touch words that merely end in a secret key', () {
      const text = 'fingerprint=abc tokenizer=bpe spinning: yes';
      expect(redactor.redact(text), text);
    });

    test('is idempotent', () {
      const text = 'token=abc Authorization: Bearer abcdefghij me@x.org';
      final once = redactor.redact(text);
      expect(redactor.redact(once), once);
    });
  });

  group('LogRedactor personal data', () {
    test('replaces e-mail addresses', () {
      expect(
        LogRedactor().redact('contact alice.w@example.com now'),
        'contact <email> now',
      );
    });

    test('replaces the known home directory, longest first', () {
      final redactor = LogRedactor(
        homeDirectories: ['/Users/alice', '/Users/alice/Library/Containers/x/'],
      );
      expect(
        redactor.redact('/Users/alice/Library/Containers/x/Data/app.log'),
        '~/Data/app.log',
      );
      expect(redactor.redact('/Users/alice/Music/a.mp3'), '~/Music/a.mp3');
    });

    test('matches Windows homes case-insensitively with either separator', () {
      final redactor = LogRedactor(homeDirectories: [r'C:\Users\Bob']);
      expect(redactor.redact(r'c:\users\bob\Music\a.flac'), r'~\Music\a.flac');
      expect(redactor.redact('C:/Users/Bob/Music/a.flac'), '~/Music/a.flac');
    });

    test('replaces other users\' homes generically', () {
      final redactor = LogRedactor();
      expect(redactor.redact('/home/carol/x.wav'), '~/x.wav');
      expect(redactor.redact(r'D:\Users\dave\x.wav'), r'~\x.wav');
      expect(redactor.redact('/Users/Shared/x.wav'), '/Users/Shared/x.wav');
    });

    test('leaves URL paths that contain /home/ alone', () {
      const text = 'https://example.org/home/page';
      expect(LogRedactor().redact(text), text);
    });

    test('ignores unusable home directories', () {
      final redactor = LogRedactor(homeDirectories: ['/', 'C:\\', '  ']);
      expect(redactor.homeDirectories, isEmpty);
      expect(redactor.redact('/usr/bin/ffmpeg'), '/usr/bin/ffmpeg');
    });
  });

  group('redactValue', () {
    test('redacts nested strings and secret-keyed values', () {
      final redactor = LogRedactor(homeDirectories: ['/home/eve']);
      final value = redactor.redactValue({
        'path': '/home/eve/models/ggml.bin',
        'token': 'abc',
        'pairing_code': null,
        'nested': [
          {'password': 1234, 'count': 3},
          'mail eve@example.com',
        ],
      });
      expect(value, {
        'path': '~/models/ggml.bin',
        'token': '<redacted>',
        'pairing_code': null,
        'nested': [
          {'password': '<redacted>', 'count': 3},
          'mail <email>',
        ],
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  test('config rejects credentials and secret-bearing URLs', () {
    final base = {
      'schema_version': 1,
      'api_base_url': 'https://api.example.org',
      'update_manifest_url': 'https://updates.example.org/latest.json',
    };
    expect(RuntimeConfig.fromJson(base).configured, isTrue);
    for (final bad in [
      {...base, 'token': 'private'},
      {...base, 'api_base_url': 'http://api.example.org'},
      {...base, 'api_base_url': 'https://user:password@api.example.org'},
      {...base, 'authorization_url': 'https://api.example.org/?token=private'},
    ]) {
      expect(() => RuntimeConfig.fromJson(bad), throwsFormatException);
    }
  });
}

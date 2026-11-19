import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/check_no_secrets.sh against a throw-away git repository.
void main() {
  final script = File('tool/check_no_secrets.sh').absolute.path;
  bool has(String tool, List<String> args) {
    try {
      return Process.runSync(tool, args).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Skipped (not failed) where bash, git or python3 are missing.
  final canRun =
      !Platform.isWindows &&
      File(script).existsSync() &&
      has('bash', ['--version']) &&
      has('git', ['--version']) &&
      has('python3', ['-V']);

  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('secrets_check_');
    Process.runSync('git', ['init', '-q'], workingDirectory: repo.path);
  });
  tearDown(() => repo.deleteSync(recursive: true));

  ProcessResult run() =>
      Process.runSync('bash', [script], workingDirectory: repo.path);

  void write(String name, String text) =>
      File('${repo.path}/$name').writeAsStringSync(text);

  // Built from pieces so this file itself never contains a key-shaped string.
  final publishable = 'sb_${'publishable'}_${'A1b2C3d4E5f6G7h8I9j0'}';
  final jwt = 'ey${'J'}${'hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'}.payload';

  test('a clean repository passes', () {
    write('a.txt', 'hello');
    write('notes.md', 'keys start with sb_${'publishable'}_ (a prefix only)');
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: !canRun);

  test('a Supabase key is found, by file name only', () {
    write('config.txt', 'key = $publishable');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stdout, contains('config.txt'));
    expect(r.stdout, isNot(contains(publishable)));
  }, skip: !canRun);

  test('a JWT-looking string is found', () {
    write('token.txt', 'Bearer $jwt');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stdout, isNot(contains('hbGciOi')));
  }, skip: !canRun);

  test('the project URL from env.json is found, and never printed', () {
    const url = 'https://projectref123456.example.test';
    write('env.json', '{"SUPABASE_URL": "$url", "SUPABASE_KEY": "x"}');
    write('page.html', '<a href="$url/x">link</a>');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stdout, contains('page.html'));
    expect(r.stdout, isNot(contains('projectref123456')));
  }, skip: !canRun);

  test('env.json itself is not reported (it is git-ignored in the repo)', () {
    const url = 'https://projectref123456.example.test';
    write('env.json', '{"SUPABASE_URL": "$url"}');
    write('.gitignore', 'env.json\n');
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: !canRun);
}

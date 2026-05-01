@Tags(['integration'])
library;

import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  const runner = RealProcessRunner();

  group('RealProcessRunner.run (no mocks)', () {
    test('captures stdout and exit code 0 from echo', () async {
      final r = await runner.run('echo', ['hello, beagle']);
      expect(r.exitCode, 0);
      expect(r.stdout.trim(), 'hello, beagle');
      expect(r.stderr, isEmpty);
      expect(r.ok, isTrue);
      expect(r.timedOut, isFalse);
    });

    test('captures stderr and non-zero exit', () async {
      // /bin/sh -c 'echo err >&2; exit 7'
      final r = await runner.run('sh', ['-c', 'echo bad >&2; exit 7']);
      expect(r.exitCode, 7);
      expect(r.stderr.trim(), 'bad');
      expect(r.ok, isFalse);
    });

    test('passes stdin through', () async {
      final r = await runner.run('cat', const [], stdinInput: 'piped\n');
      expect(r.exitCode, 0);
      expect(r.stdout.trim(), 'piped');
    });

    test('arguments are not interpreted by a shell', () async {
      // If the runner went through a shell, the `;` would terminate echo.
      final r = await runner.run('echo', ['; rm -rf /']);
      expect(r.exitCode, 0);
      expect(r.stdout.trim(), '; rm -rf /');
    });

    test('timeout fires and reports timedOut=true', () async {
      final started = DateTime.now();
      final r = await runner.run(
        'sleep',
        ['5'],
        timeout: const Duration(milliseconds: 200),
      );
      final elapsed = DateTime.now().difference(started);
      expect(r.timedOut, isTrue);
      expect(r.exitCode, isNot(0));
      expect(elapsed.inMilliseconds, lessThan(2000));
    });

    test('commandLine quotes args with spaces and special chars', () async {
      final r = await runner.run('echo', const ['needs quoting', "ok'word"]);
      expect(r.exitCode, 0);
      expect(r.commandLine, contains("'needs quoting'"));
      expect(r.commandLine, contains(r"'ok'\''word'"));
    });
  });

  group('RealProcessRunner.stream (no mocks)', () {
    test('streams lines and yields exit code', () async {
      final sp = await runner.stream(
        'sh',
        ['-c', 'for i in 1 2 3; do echo line\$i; done'],
      );
      final lines = await sp.stdoutLines.toList();
      expect(lines, ['line1', 'line2', 'line3']);
      expect(await sp.exitCode, 0);
    });

    test('kill terminates the process', () async {
      final sp = await runner.stream('sleep', ['30']);
      sp.kill();
      final code = await sp.exitCode.timeout(const Duration(seconds: 2));
      expect(code, isNot(0));
    });
  });
}

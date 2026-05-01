import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';

/// Result of a one-shot process invocation.
class ProcessResult {
  ProcessResult({
    required this.executable,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.timedOut = false,
  });

  final String executable;
  final List<String> arguments;
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool timedOut;

  String get commandLine => ([executable, ...arguments]).map(_shellQuote).join(' ');
  bool get ok => exitCode == 0 && !timedOut;
}

/// Streamed (long-running) process handle, e.g. inotifywait/fswatch/rclone.
class StreamedProcess {
  StreamedProcess({
    required this.process,
    required this.executable,
    required this.arguments,
    required this.stdoutLines,
    required this.stderrLines,
  });

  final Process process;
  final String executable;
  final List<String> arguments;
  final Stream<String> stdoutLines;
  final Stream<String> stderrLines;

  String get commandLine => ([executable, ...arguments]).map(_shellQuote).join(' ');

  Future<int> get exitCode => process.exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      process.kill(signal);
}

/// Abstraction over `Process.start`/`Process.run` with timeout, escaping, and
/// fakable behavior for tests. NEVER pass user-supplied paths through a shell —
/// always use the argument list form to avoid command injection.
abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinInput,
  });

  /// Start a long-running process and stream its stdout/stderr line-by-line.
  /// Caller is responsible for cancelling.
  Future<StreamedProcess> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinInput,
  }) async {
    final started = DateTime.now();
    final proc = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    if (stdinInput != null) {
      proc.stdin.add(utf8.encode(stdinInput));
    }
    unawaited(proc.stdin.close());

    final outFut = proc.stdout.transform(utf8.decoder).join();
    final errFut = proc.stderr.transform(utf8.decoder).join();
    var timedOut = false;
    final exit = await proc.exitCode.timeout(timeout, onTimeout: () {
      timedOut = true;
      proc.kill(ProcessSignal.sigterm);
      return -1;
    });
    final out = await outFut;
    final err = await errFut;
    return ProcessResult(
      executable: executable,
      arguments: arguments,
      exitCode: exit,
      stdout: out,
      stderr: err,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      timedOut: timedOut,
    );
  }

  @override
  Future<StreamedProcess> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final proc = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false,
      );
      final out = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final err = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      return StreamedProcess(
        process: proc,
        executable: executable,
        arguments: arguments,
        stdoutLines: out,
        stderrLines: err,
      );
    } on ProcessException catch (e) {
      throw BeagleError(
        BeagleErrorCode.internalError,
        'Failed to start $executable: ${e.message}',
        cause: e,
      );
    }
  }
}

String _shellQuote(String s) {
  if (s.isEmpty) return "''";
  if (RegExp(r'^[A-Za-z0-9_./@%+\-:=]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", "'\\''")}'";
}

/// In-memory fake for tests. Programs invocations to deterministic results.
class FakeProcessRunner implements ProcessRunner {
  final List<ProcessInvocation> invocations = [];
  final List<ProcessResult Function(String, List<String>)> _runResponders = [];
  final List<StreamedProcess Function(String, List<String>)> _streamResponders =
      [];

  void onRun(ProcessResult Function(String exe, List<String> args) responder) =>
      _runResponders.add(responder);

  void onStream(
          StreamedProcess Function(String exe, List<String> args) responder) =>
      _streamResponders.add(responder);

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinInput,
  }) async {
    invocations.add(ProcessInvocation(executable, arguments));
    if (_runResponders.isEmpty) {
      return ProcessResult(
        executable: executable,
        arguments: arguments,
        exitCode: 0,
        stdout: '',
        stderr: '',
        durationMs: 0,
      );
    }
    final r = _runResponders.removeAt(0);
    return r(executable, arguments);
  }

  @override
  Future<StreamedProcess> stream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    invocations.add(ProcessInvocation(executable, arguments));
    if (_streamResponders.isEmpty) {
      throw StateError(
        'FakeProcessRunner.stream called without a programmed responder.',
      );
    }
    return _streamResponders.removeAt(0)(executable, arguments);
  }
}

class ProcessInvocation {
  ProcessInvocation(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
}

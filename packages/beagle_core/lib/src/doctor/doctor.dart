import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config_dir.dart';
import '../errors.dart';
import '../models.dart';
import '../process/process_runner.dart';
import '../watcher/watcher_supervisor.dart';

class DoctorCheck {
  DoctorCheck({
    required this.id,
    required this.label,
    required this.passed,
    this.detail,
    this.severity = DoctorSeverity.info,
    this.remedy,
  });

  final String id;
  final String label;
  final bool passed;
  final String? detail;
  final DoctorSeverity severity;
  final String? remedy;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'passed': passed,
        if (detail != null) 'detail': detail,
        'severity': severity.name,
        if (remedy != null) 'remedy': remedy,
      };
}

enum DoctorSeverity { info, warn, error }

class DoctorReport {
  DoctorReport(this.checks);
  final List<DoctorCheck> checks;
  bool get allPassed => checks.every((c) => c.passed || c.severity != DoctorSeverity.error);
  Map<String, Object?> toJson() => {
        'all_passed': allPassed,
        'checks': checks.map((c) => c.toJson()).toList(),
      };
}

class Doctor {
  Doctor({
    required this.runner,
    required this.dir,
    this.rcloneExecutable = 'rclone',
  });

  final ProcessRunner runner;
  final ConfigDir dir;
  final String rcloneExecutable;

  Future<DoctorReport> run({List<SyncPair> pairs = const []}) async {
    final checks = <DoctorCheck>[];

    checks.add(await _checkRclone());
    checks.add(await _checkRcloneBisync());
    checks.add(await _checkPlatformWatcher());
    if (Platform.isLinux) checks.add(await _checkInotifyLimit());
    checks.add(await _checkConfigDirWritable());

    for (final pair in pairs) {
      checks.add(await _checkLocalPath(pair));
      checks.add(await _checkRemoteReachable(pair));
    }

    return DoctorReport(checks);
  }

  Future<DoctorCheck> _checkRclone() async {
    try {
      final r = await runner.run(rcloneExecutable, const ['version'],
          timeout: const Duration(seconds: 5));
      if (!r.ok) {
        return DoctorCheck(
          id: 'rclone_present',
          label: 'rclone is installed',
          passed: false,
          severity: DoctorSeverity.error,
          detail: 'rclone returned exit ${r.exitCode}',
          remedy: 'Install rclone: https://rclone.org/install/',
        );
      }
      final firstLine = r.stdout.split('\n').firstWhere((_) => true,
          orElse: () => '');
      return DoctorCheck(
        id: 'rclone_present',
        label: 'rclone is installed',
        passed: true,
        detail: firstLine.trim(),
      );
    } on ProcessException {
      return DoctorCheck(
        id: 'rclone_present',
        label: 'rclone is installed',
        passed: false,
        severity: DoctorSeverity.error,
        remedy: 'Install rclone: https://rclone.org/install/ '
            '(`pacman -S rclone` on Arch, `brew install rclone` on macOS).',
      );
    }
  }

  Future<DoctorCheck> _checkRcloneBisync() async {
    final r = await runner.run(rcloneExecutable, const ['help', 'bisync'],
        timeout: const Duration(seconds: 5));
    if (r.exitCode != 0) {
      return DoctorCheck(
        id: 'rclone_bisync_supported',
        label: 'rclone supports bisync',
        passed: false,
        severity: DoctorSeverity.error,
        remedy: 'Upgrade rclone to v1.64+ which ships bisync as stable.',
      );
    }
    return DoctorCheck(
      id: 'rclone_bisync_supported',
      label: 'rclone supports bisync',
      passed: true,
    );
  }

  Future<DoctorCheck> _checkPlatformWatcher() async {
    final exe = Platform.isMacOS ? 'fswatch' : 'inotifywait';
    final args = const ['--help'];
    try {
      final r = await runner.run(exe, args, timeout: const Duration(seconds: 5));
      // Both tools exit non-zero on --help on some distros; presence of stdout
      // is the real signal.
      if (r.stdout.isNotEmpty || r.stderr.isNotEmpty) {
        return DoctorCheck(
          id: 'watcher_present',
          label: '$exe is installed',
          passed: true,
        );
      }
      return DoctorCheck(
        id: 'watcher_present',
        label: '$exe is installed',
        passed: false,
        severity: DoctorSeverity.error,
        remedy: Platform.isMacOS
            ? 'brew install fswatch'
            : 'pacman -S inotify-tools',
      );
    } on ProcessException {
      return DoctorCheck(
        id: 'watcher_present',
        label: '$exe is installed',
        passed: false,
        severity: DoctorSeverity.error,
        remedy: Platform.isMacOS
            ? 'brew install fswatch'
            : 'pacman -S inotify-tools',
      );
    }
  }

  Future<DoctorCheck> _checkInotifyLimit() async {
    final n = await readInotifyMaxUserWatches();
    if (n == null) {
      return DoctorCheck(
        id: 'inotify_watch_limit',
        label: 'inotify watch limit readable',
        passed: false,
        severity: DoctorSeverity.warn,
      );
    }
    final ok = n >= 65536;
    return DoctorCheck(
      id: 'inotify_watch_limit',
      label: 'inotify watch limit',
      passed: ok,
      severity: ok ? DoctorSeverity.info : DoctorSeverity.warn,
      detail: 'max_user_watches=$n',
      remedy: ok
          ? null
          : 'Bump it: echo "fs.inotify.max_user_watches=524288" | '
              'sudo tee /etc/sysctl.d/99-drive-beagle.conf && sudo sysctl --system',
    );
  }

  Future<DoctorCheck> _checkConfigDirWritable() async {
    try {
      await dir.ensure();
      final probe = File(p.join(dir.root.path, '.write-probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return DoctorCheck(
        id: 'config_dir_writable',
        label: 'config dir is writable',
        passed: true,
        detail: dir.root.path,
      );
    } on Object catch (e) {
      return DoctorCheck(
        id: 'config_dir_writable',
        label: 'config dir is writable',
        passed: false,
        severity: DoctorSeverity.error,
        detail: '${dir.root.path}: $e',
        remedy: 'Adjust permissions on ${dir.root.path}',
      );
    }
  }

  Future<DoctorCheck> _checkLocalPath(SyncPair pair) async {
    final d = Directory(pair.localPath);
    if (await d.exists()) {
      return DoctorCheck(
        id: 'pair_local_path:${pair.id}',
        label: 'local path exists for "${pair.name}"',
        passed: true,
        detail: pair.localPath,
      );
    }
    return DoctorCheck(
      id: 'pair_local_path:${pair.id}',
      label: 'local path exists for "${pair.name}"',
      passed: false,
      severity: DoctorSeverity.warn,
      detail: pair.localPath,
      remedy: 'Create it: mkdir -p "${pair.localPath}"',
    );
  }

  Future<DoctorCheck> _checkRemoteReachable(SyncPair pair) async {
    final r = await runner.run(rcloneExecutable,
        ['lsd', pair.rcloneRemoteSpec, '--max-depth', '1'],
        timeout: const Duration(seconds: 15));
    final ok = r.exitCode == 0;
    return DoctorCheck(
      id: 'pair_remote_reachable:${pair.id}',
      label: 'remote reachable for "${pair.name}"',
      passed: ok,
      severity: ok ? DoctorSeverity.info : DoctorSeverity.error,
      detail: ok ? null : (r.stderr.split('\n').firstWhere((_) => true, orElse: () => '')),
      remedy: ok
          ? null
          : 'Check `rclone config` for remote "${pair.remoteName}".',
    );
  }
}

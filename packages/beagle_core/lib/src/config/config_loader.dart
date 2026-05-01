import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../errors.dart';
import '../models.dart';
import 'config_dir.dart';

class ConfigLoader {
  ConfigLoader(this.dir);

  final ConfigDir dir;

  Future<AppConfig> load() async {
    final f = File(dir.configFilePath);
    if (!await f.exists()) return const AppConfig();
    final raw = await f.readAsString();
    return _parse(raw);
  }

  /// Parse from raw YAML or JSON text. Visible for testing.
  static AppConfig parse(String raw) => _parse(raw);

  Future<void> save(AppConfig config) async {
    await dir.ensure();
    final tmp = File('${dir.configFilePath}.tmp');
    await tmp.writeAsString(_renderYaml(config), flush: true);
    await tmp.rename(dir.configFilePath);
  }
}

AppConfig _parse(String raw) {
  final trimmed = raw.trimLeft();
  Object? decoded;
  try {
    if (trimmed.startsWith('{')) {
      decoded = jsonDecode(raw);
    } else {
      decoded = loadYaml(raw);
    }
  } catch (e) {
    throw BeagleError(
      BeagleErrorCode.invalidConfig,
      'Failed to parse config: $e',
      remedy: 'Check YAML/JSON syntax in config.yaml',
    );
  }
  if (decoded is! Map) {
    throw BeagleError(
      BeagleErrorCode.invalidConfig,
      'Config must be a mapping at the top level.',
    );
  }
  return AppConfig.fromJson(_normalize(decoded));
}

Map<String, Object?> _normalize(Map<dynamic, dynamic> m) =>
    m.map((k, v) => MapEntry(k.toString(), _normalizeValue(v)));

Object? _normalizeValue(Object? v) {
  if (v is YamlMap) return _normalize(v);
  if (v is Map) return _normalize(v);
  if (v is YamlList) return v.map(_normalizeValue).toList();
  if (v is List) return v.map(_normalizeValue).toList();
  return v;
}

/// Minimal hand-rolled YAML emitter — yaml_writer's API churns and we don't
/// need anchors/tags. Output is deterministic and round-trips through parse().
String _renderYaml(AppConfig c) {
  final b = StringBuffer();
  b.writeln('# drive-beagle config');
  b.writeln('config_version: ${c.configVersion}');
  b.writeln('global_concurrency: ${c.globalConcurrency}');
  b.writeln('log_level: ${_yScalar(c.logLevel)}');
  if (c.ipcSocketPath != null) {
    b.writeln('ipc_socket_path: ${_yScalar(c.ipcSocketPath!)}');
  }
  b.writeln('pairs:');
  for (final p in c.pairs) {
    b.writeln('  - id: ${_yScalar(p.id)}');
    b.writeln('    name: ${_yScalar(p.name)}');
    b.writeln('    local_path: ${_yScalar(p.localPath)}');
    b.writeln('    remote_name: ${_yScalar(p.remoteName)}');
    b.writeln('    remote_path: ${_yScalar(p.remotePath)}');
    b.writeln('    mode: ${p.mode.wire}');
    b.writeln('    conflict_policy: ${p.conflictPolicy.wire}');
    b.writeln('    debounce_ms: ${p.debounceMs}');
    b.writeln('    reconcile_every_seconds: ${p.reconcileEverySeconds}');
    b.writeln('    enabled: ${p.enabled}');
    b.writeln('    bootstrapped: ${p.bootstrapped}');
    b.writeln('    filters:');
    b.writeln(
        '      include_extensions: ${_yList(p.filters.includeExtensions)}');
    b.writeln('      exclude_globs: ${_yList(p.filters.excludeGlobs)}');
    b.writeln('      ignore_hidden: ${p.filters.ignoreHidden}');
    b.writeln('      ignore_vcs: ${p.filters.ignoreVcs}');
    b.writeln('      ignore_node_modules: ${p.filters.ignoreNodeModules}');
    b.writeln(
        '      ignore_common_build_dirs: ${p.filters.ignoreCommonBuildDirs}');
    b.writeln('      custom_rules: ${_yList(p.filters.customRules)}');
    b.writeln('    size_policy:');
    b.writeln(
        '      max_bytes: ${p.sizePolicy.maxBytes ?? 'null'}');
  }
  return b.toString();
}

String _yScalar(String s) {
  if (s.isEmpty) return '""';
  if (RegExp(r'^[A-Za-z0-9_./\-:]+$').hasMatch(s)) return s;
  return jsonEncode(s);
}

String _yList(List<String> xs) =>
    '[${xs.map(_yScalar).join(', ')}]';

/// Stable error codes surfaced by drive-beagle.
///
/// These strings appear in CLI JSON output and UI dialogs. Treat them as a
/// public contract — never rename without bumping schema version.
enum BeagleErrorCode {
  rcloneMissing('RCLONE_MISSING'),
  rcloneVersionTooOld('RCLONE_VERSION_TOO_OLD'),
  watcherMissing('WATCHER_MISSING'),
  watchLimitLow('WATCH_LIMIT_LOW'),
  remoteUnreachable('REMOTE_UNREACHABLE'),
  authError('AUTH_ERROR'),
  conflict('CONFLICT'),
  bisyncNeedsResync('BISYNC_NEEDS_RESYNC'),
  journalCorrupt('JOURNAL_CORRUPT'),
  cursorMismatch('CURSOR_MISMATCH'),
  offline('OFFLINE'),
  timeout('TIMEOUT'),
  permissionDenied('PERMISSION_DENIED'),
  invalidConfig('INVALID_CONFIG'),
  notRunning('NOT_RUNNING'),
  pairNotFound('PAIR_NOT_FOUND'),
  rcloneFailed('RCLONE_FAILED'),
  internalError('INTERNAL_ERROR');

  const BeagleErrorCode(this.wire);
  final String wire;
}

class BeagleError implements Exception {
  BeagleError(this.code, this.message, {this.remedy, this.cause});

  final BeagleErrorCode code;
  final String message;
  final String? remedy;
  final Object? cause;

  Map<String, Object?> toJson() => {
        'code': code.wire,
        'message': message,
        if (remedy != null) 'remedy': remedy,
      };

  @override
  String toString() => '${code.wire}: $message';
}

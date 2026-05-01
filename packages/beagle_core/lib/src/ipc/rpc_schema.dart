/// JSON-RPC method names spoken by the drive-beagle control socket.
///
/// All requests are JSON objects with shape:
///   { "id": <int|str>, "method": "<name>", "params": {...} }
/// Replies:
///   { "id": <same>, "result": <any> } | { "id": <same>, "error": {"code","message"} }
/// Server may also push notifications (no `id` field) for streamed methods
/// such as `watch_events.update` and `journal.update`.
abstract class RpcMethods {
  static const ping = 'ping';
  static const status = 'status';
  static const listPairs = 'list_pairs';
  static const getPair = 'get_pair';
  static const addPair = 'add_pair';
  static const removePair = 'remove_pair';
  static const pause = 'pause';
  static const resume = 'resume';
  static const syncNow = 'sync_now';
  static const dryRun = 'dry_run';
  static const tailLogs = 'tail_logs';
  static const subscribeWatchEvents = 'subscribe_watch_events';
  static const subscribeJournal = 'subscribe_journal';
  static const lastSync = 'last_sync';
  static const snapshotNow = 'snapshot_now';
  static const changes = 'changes';
  static const ack = 'ack';
}

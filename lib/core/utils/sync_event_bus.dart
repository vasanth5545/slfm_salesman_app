import 'dart:async';

class SyncEventBus {
  static final StreamController<void> _syncCompletedController =
      StreamController<void>.broadcast();

  static Stream<void> get onSyncCompleted => _syncCompletedController.stream;

  static void broadcastSyncCompleted() {
    _syncCompletedController.add(null);
  }
}

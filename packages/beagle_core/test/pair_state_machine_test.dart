import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  group('PairStateMachine', () {
    test('happy path: idle → watching → pending → syncing → idle', () {
      final fsm = PairStateMachine();
      expect(fsm.state, PairLifecycleState.idle);
      expect(fsm.transition(PairLifecycleEvent.start), isTrue);
      expect(fsm.state, PairLifecycleState.watching);
      expect(fsm.transition(PairLifecycleEvent.changeDetected), isTrue);
      expect(fsm.state, PairLifecycleState.pending);
      expect(fsm.transition(PairLifecycleEvent.dispatch), isTrue);
      expect(fsm.state, PairLifecycleState.syncing);
      expect(fsm.transition(PairLifecycleEvent.runSucceeded), isTrue);
      expect(fsm.state, PairLifecycleState.idle);
    });

    test('failure paths land in warning or error', () {
      final fsm = PairStateMachine(PairLifecycleState.syncing);
      expect(fsm.transition(PairLifecycleEvent.runFailedRecoverable), isTrue);
      expect(fsm.state, PairLifecycleState.warning);

      final fsm2 = PairStateMachine(PairLifecycleState.syncing);
      expect(fsm2.transition(PairLifecycleEvent.runFailedFatal), isTrue);
      expect(fsm2.state, PairLifecycleState.error);
    });

    test('pause and resume', () {
      final fsm = PairStateMachine(PairLifecycleState.watching);
      expect(fsm.transition(PairLifecycleEvent.pause), isTrue);
      expect(fsm.state, PairLifecycleState.paused);
      expect(fsm.transition(PairLifecycleEvent.pause), isFalse,
          reason: 'pausing while paused is a no-op');
      expect(fsm.transition(PairLifecycleEvent.resume), isTrue);
      expect(fsm.state, PairLifecycleState.idle);
    });

    test('changeDetected while syncing is absorbed (stays syncing)', () {
      final fsm = PairStateMachine(PairLifecycleState.syncing);
      expect(fsm.transition(PairLifecycleEvent.changeDetected), isTrue);
      expect(fsm.state, PairLifecycleState.syncing);
    });

    test('illegal transition rejected', () {
      final fsm = PairStateMachine(PairLifecycleState.idle);
      expect(fsm.transition(PairLifecycleEvent.runSucceeded), isFalse);
      expect(fsm.state, PairLifecycleState.idle);
    });

    test('error → recover', () {
      final fsm = PairStateMachine(PairLifecycleState.error);
      expect(fsm.transition(PairLifecycleEvent.recover), isTrue);
      expect(fsm.state, PairLifecycleState.idle);
    });
  });
}

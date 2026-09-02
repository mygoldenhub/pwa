import 'package:flutter_test/flutter_test.dart';
import 'package:pwa/utils/scan_voter.dart';

void main() {
  late DateTime now;
  late ScanVoter voter;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    voter = ScanVoter(clock: () => now);
  });

  test('does not accept before 3 frames of the same value', () {
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.hasAccepted, isFalse);
  });

  test('accepts after 3 consecutive frames of the same value', () {
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), '9780201379624');
    expect(voter.hasAccepted, isTrue);
  });

  test('does not fire again after acceptance', () {
    voter.vote('9780201379624');
    voter.vote('9780201379624');
    expect(voter.vote('9780201379624'), '9780201379624');
    expect(voter.vote('9780201379624'), isNull);
  });

  test('resets when a different value is seen', () {
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('0036000291452'), isNull);
    expect(voter.vote('0036000291452'), isNull);
    expect(voter.hasAccepted, isFalse);
    expect(voter.vote('0036000291452'), '0036000291452');
  });

  test('resets after 1.5s with no detections', () {
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), isNull);
    now = now.add(const Duration(milliseconds: 1500));
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), isNull);
    expect(voter.vote('9780201379624'), '9780201379624');
  });

  test('reset() allows a new value to be accepted', () {
    voter.vote('9780201379624');
    voter.vote('9780201379624');
    voter.vote('9780201379624');
    voter.reset();
    expect(voter.hasAccepted, isFalse);
    expect(voter.vote('0036000291452'), isNull);
    expect(voter.vote('0036000291452'), isNull);
    expect(voter.vote('0036000291452'), '0036000291452');
  });
}

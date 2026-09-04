/// Requires the same barcode to be seen across multiple detections before it
/// is accepted, so a single misread does not fire the success callback.
///
/// Acceptance: [requiredHits] detections of the same value (default 3). Votes
/// are the last [windowSize] detections (default 5), so 3 consecutive frames
/// or 3 of the last 5 both qualify when the value does not change.
///
/// Votes reset when a different value is seen, or when [staleAfter] elapses
/// with no detections. After a value is accepted, further votes are ignored
/// until [reset] is called.
class ScanVoter {
  ScanVoter({
    /// Two agreeing check-digit-valid reads is enough; three slows hard scans.
    this.requiredHits = 2,
    this.windowSize = 4,
    this.staleAfter = const Duration(milliseconds: 1800),
    DateTime Function()? clock,
  })  : assert(requiredHits > 0),
        assert(windowSize >= requiredHits),
        _clock = clock ?? DateTime.now;

  final int requiredHits;
  final int windowSize;
  final Duration staleAfter;
  final DateTime Function() _clock;

  final List<_Vote> _votes = <_Vote>[];
  bool _accepted = false;

  bool get hasAccepted => _accepted;

  /// How many detections of the current value are held (0 after a stale reset).
  int get voteCount => _votes.length;

  String? get pendingValue => _votes.isEmpty ? null : _votes.last.value;

  /// Record a detection. Returns the value once it has enough votes; otherwise
  /// `null`. Returns `null` after a value has already been accepted.
  String? vote(String value) {
    if (_accepted) return null;

    final now = _clock();
    _dropStale(now);

    if (_votes.isNotEmpty && _votes.last.value != value) {
      _votes.clear();
    }

    _votes.add(_Vote(value, now));
    if (_votes.length > windowSize) {
      _votes.removeRange(0, _votes.length - windowSize);
    }

    final hits = _votes.where((v) => v.value == value).length;
    if (hits < requiredHits) return null;

    _accepted = true;
    return value;
  }

  void reset() {
    _votes.clear();
    _accepted = false;
  }

  void _dropStale(DateTime now) {
    if (_votes.isEmpty) return;
    if (now.difference(_votes.last.at) >= staleAfter) {
      _votes.clear();
    }
  }
}

class _Vote {
  const _Vote(this.value, this.at);

  final String value;
  final DateTime at;
}

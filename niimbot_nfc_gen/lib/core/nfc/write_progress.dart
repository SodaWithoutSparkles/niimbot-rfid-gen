// Progress reporting for a write.
//
// A write is roughly 70 NFC round trips, and the revive after a NAK polls for
// the tag for up to ten seconds. Without progress the user watches an
// indeterminate spinner through the whole thing and cannot tell whether it is
// working, waiting on them, or stuck.

enum WritePhase {
  /// Waiting for the user to present a tag.
  connecting,

  /// Writing the first page with no password, to see if it is protected.
  probing,

  /// Trying passwords because the probe was refused.
  authenticating,

  /// Writing pages one at a time.
  writing,

  /// Re-establishing the session after the tag went IDLE.
  reviving,

  /// Reading pages back to confirm them.
  verifying,

  done,
}

/// How far along a write is.
///
/// [done] and [total] count NFC round trips across the whole run, not within a
/// phase. Phases interleave (a revive interrupts the writing loop), so a flat
/// step count is the only way to keep [fraction] monotonic without modelling
/// every ordering.
class WriteProgress {
  final WritePhase phase;

  /// Round trips completed, and the expected total.
  final int done;
  final int total;

  /// Phase-specific detail, already formatted. The runner supplies it because
  /// only it knows what the counters mean in the current phase.
  final String message;

  const WriteProgress(this.phase, this.done, this.total, this.message);

  /// 0..1 for a progress bar.
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  /// True when the user may have to do something, so the UI can highlight it.
  bool get needsAttention => phase == WritePhase.reviving;
}

/// Called as a write advances. A listener that throws must not break the write,
/// so the runner wraps this before handing it over.
typedef ProgressCallback = void Function(WriteProgress progress);
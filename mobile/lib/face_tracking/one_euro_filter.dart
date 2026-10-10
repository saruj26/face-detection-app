import 'dart:math' as math;

/// 1€ filter (Casiez, Roussel & Vogel, CHI 2012): an adaptive low-pass filter.
///
/// When the signal moves slowly the cut-off is low (strong smoothing, little
/// jitter); when it moves fast the cut-off rises (low lag). Well suited to
/// smoothing landmark positions from a per-frame detector.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.0, this.derivativeCutoff = 1.0});

  /// Minimum cut-off frequency (Hz). Lower = smoother when still.
  final double minCutoff;

  /// Speed coefficient. Higher = less lag during fast movement.
  final double beta;

  final double derivativeCutoff;

  double? _x;
  double _dx = 0;
  double? _lastTime;

  bool get isInitialized => _x != null;

  void reset() {
    _x = null;
    _dx = 0;
    _lastTime = null;
  }

  /// Filters [value] observed at [timeSeconds] (monotonic).
  double filter(double value, double timeSeconds) {
    final prev = _x;
    final last = _lastTime;
    if (prev == null || last == null) {
      _x = value;
      _lastTime = timeSeconds;
      return value;
    }
    var dt = timeSeconds - last;
    if (dt <= 0) dt = 1 / 30; // duplicate timestamps: assume 30 fps
    _lastTime = timeSeconds;

    final rawDerivative = (value - prev) / dt;
    _dx = _lerp(_dx, rawDerivative, _alpha(dt, derivativeCutoff));
    final cutoff = minCutoff + beta * _dx.abs();
    final result = _lerp(prev, value, _alpha(dt, cutoff));
    _x = result;
    return result;
  }

  static double _alpha(double dt, double cutoff) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  static double _lerp(double from, double to, double alpha) => from + alpha * (to - from);
}

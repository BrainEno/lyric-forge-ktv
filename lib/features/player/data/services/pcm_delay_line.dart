class PcmDelayLine {
  final int sampleRate;
  double _gain;
  Duration _delay;
  List<double> _buffer;
  int _cursor = 0;

  PcmDelayLine({
    this.sampleRate = 48000,
    double gain = 1.0,
    Duration delay = Duration.zero,
  })  : _gain = gain,
        _delay = delay,
        _buffer = List<double>.filled(
          _delaySamples(sampleRate, delay),
          0,
          growable: false,
        );

  double get gain => _gain;
  Duration get delay => _delay;

  void setGain(double value) {
    _gain = value.clamp(0.0, 2.0).toDouble();
  }

  void setDelay(Duration value) {
    final normalized = value.isNegative ? Duration.zero : value;
    if (normalized == _delay) return;
    _delay = normalized;
    _buffer = List<double>.filled(
      _delaySamples(sampleRate, normalized),
      0,
      growable: false,
    );
    _cursor = 0;
  }

  List<double> process(List<double> input) {
    if (input.isEmpty) return const <double>[];

    if (_buffer.isEmpty) {
      return input
          .map((sample) => _scaledSample(sample))
          .toList(growable: false);
    }

    final output = List<double>.filled(input.length, 0, growable: false);
    for (var index = 0; index < input.length; index++) {
      output[index] = _buffer[_cursor];
      _buffer[_cursor] = _scaledSample(input[index]);
      _cursor++;
      if (_cursor == _buffer.length) _cursor = 0;
    }
    return output;
  }

  double _scaledSample(double sample) =>
      (sample * _gain).clamp(-1.0, 1.0).toDouble();

  static int _delaySamples(int sampleRate, Duration delay) {
    if (delay <= Duration.zero) return 0;
    return (sampleRate * delay.inMicroseconds / Duration.microsecondsPerSecond)
        .round();
  }
}

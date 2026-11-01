import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/asr_quality_report.dart' as quality;

quality.QualityLine line(String text, [int? startMs, int? endMs]) =>
    quality.QualityLine(text: text, startMs: startMs, endMs: endMs);

Map<String, Object?> evaluate({
  required List<quality.QualityLine> reference,
  required List<quality.QualityLine> hypothesis,
  String engine = 'fused',
  String songId = 'song-01',
  double threshold = quality.kDefaultMatchThreshold,
}) => quality.evaluateLyricQualityPair(
  songId: songId,
  engine: engine,
  reference: reference,
  hypothesis: hypothesis,
  matchThreshold: threshold,
);

void main() {
  group('line metrics', () {
    test('a clean transcript scores perfectly', () {
      final reference = <quality.QualityLine>[
        line('我们跳舞', 0, 3000),
        line('唱一首歌', 4000, 8000),
        line('直到天亮', 9000, 12000),
      ];
      final score = evaluate(reference: reference, hypothesis: reference);

      expect(score['lineRecall'], 1.0);
      expect(score['linePrecision'], 1.0);
      expect(score['lineF1'], 1.0);
      expect(score['normalizedCharacterErrorRate'], 0.0);
      expect(score['duplicateLineCount'], 0);
      expect(score['duplicateLineRate'], 0.0);
      expect(score['lineCountRatio'], 1.0);
      expect(score['startTimeMaeMs'], 0.0);
      expect(score['within500msRate'], 1.0);
      expect(score['matchedLineCount'], 3);
    });

    test('a missing line lowers recall but not precision', () {
      final reference = <quality.QualityLine>[
        line('我们跳舞', 0, 3000),
        line('唱一首歌', 4000, 8000),
        line('直到天亮', 9000, 12000),
      ];
      final score = evaluate(
        reference: reference,
        hypothesis: <quality.QualityLine>[reference[0], reference[2]],
      );

      expect(score['matchedLineCount'], 2);
      expect(score['lineRecall'], closeTo(2 / 3, 1e-9));
      expect(score['linePrecision'], 1.0);
      expect(score['missingLineCount'], 1);
      expect(score['missingReferenceLines'], hasLength(1));
    });

    test('a whole extra line lowers precision and line count ratio', () {
      final reference = <quality.QualityLine>[
        line('我们跳舞', 0, 3000),
        line('唱一首歌', 4000, 8000),
      ];
      final score = evaluate(
        reference: reference,
        hypothesis: <quality.QualityLine>[
          reference[0],
          line('啦啦啦啦啦', 9000, 11000),
          reference[1],
        ],
      );

      expect(score['lineRecall'], 1.0);
      expect(score['linePrecision'], closeTo(2 / 3, 1e-9));
      expect(score['lineCountRatio'], 1.5);
      expect(score['extraLineCount'], 1);
    });

    test('character error rate ignores case, punctuation and spacing', () {
      final score = evaluate(
        reference: <quality.QualityLine>[line('Hello, world!', 0)],
        hypothesis: <quality.QualityLine>[line('hello word', 0)],
      );
      // "helloworld" -> "helloword" is one deletion over ten characters.
      expect(score['normalizedCharacterErrorRate'], closeTo(0.1, 1e-9));
    });
  });

  group('duplicate detection', () {
    test('catches a word of a line emitted as its own row', () {
      // This is the dual-engine fusion signature: a shorter fragment placed
      // inside the time span of the line it came from.
      final reference = <quality.QualityLine>[
        line('we are dancing through the night', 10000, 14000),
        line('sing a little song', 15000, 18000),
      ];
      final hypothesis = <quality.QualityLine>[
        line('we are dancing through the night', 10000, 14000),
        line('dancing', 10500, 11500),
        line('sing a little song', 15000, 18000),
        line('little song', 15300, 16000),
      ];
      final groups = quality.findDuplicateLyricLines(hypothesis);
      expect(groups, hasLength(2));
      expect(groups.first.kind, 'contained');
      expect(groups.first.lineIndexes, <int>[0, 1]);
      expect(groups.first.text, 'we are dancing through the night');
      expect(groups.last.lineIndexes, <int>[2, 3]);

      final score = evaluate(reference: reference, hypothesis: hypothesis);
      expect(score['matchedLineCount'], 2);
      expect(score['lineRecall'], 1.0);
      expect(score['duplicateLineCount'], 2);
      expect(score['duplicateLineRate'], 0.5);
      expect(score['lineCountRatio'], 2.0);
    });

    test('a chorus that repeats a minute later is not a duplicate', () {
      final lines = <quality.QualityLine>[
        line('我们跳舞', 10000, 13000),
        line('唱一首歌', 15000, 18000),
        line('我们跳舞', 60000, 63000),
      ];
      expect(quality.findDuplicateLyricLines(lines), isEmpty);
    });

    test('near-identical variants in the same window count once', () {
      final lines = <quality.QualityLine>[
        line('我们跳舞直到天亮', 10000),
        line('我们跳舞　直到天亮', 10200),
      ];
      final groups = quality.findDuplicateLyricLines(lines);
      expect(groups, hasLength(1));
      expect(groups.single.lineIndexes, <int>[0, 1]);
    });

    test('identical lines at different times are distinct lyrics', () {
      final lines = <quality.QualityLine>[
        line('我们跳舞', 1000),
        line('我们跳舞', 30000),
      ];
      expect(quality.findDuplicateLyricLines(lines), isEmpty);
    });

    test('without timestamps only adjacent lines are compared', () {
      final adjacent = <quality.QualityLine>[line('我们跳舞直到天亮'), line('跳舞')];
      expect(quality.findDuplicateLyricLines(adjacent), hasLength(1));

      final farApart = <quality.QualityLine>[
        line('我们跳舞直到天亮'),
        line('唱一首好听的歌'),
        line('跳舞'),
      ];
      expect(quality.findDuplicateLyricLines(farApart), isEmpty);
    });

    test('very short fragments are ignored', () {
      final lines = <quality.QualityLine>[line('我们跳舞', 1000), line('啊', 1100)];
      expect(quality.findDuplicateLyricLines(lines), isEmpty);
    });
  });

  group('timestamps', () {
    test('reports mean, median and p95 start error over matched pairs', () {
      final score = evaluate(
        reference: <quality.QualityLine>[
          line('第一句歌词', 1000),
          line('第二句歌词', 5000),
          line('第三句歌词', 9000),
          line('第四句歌词', 13000),
        ],
        hypothesis: <quality.QualityLine>[
          line('第一句歌词', 1200),
          line('第二句歌词', 5400),
          line('第三句歌词', 10100),
          line('第四句歌词', 14000),
        ],
      );
      // Errors are 200, 400, 1100 and 1000 ms.
      expect(score['timedMatchCount'], 4);
      expect(score['startTimeMaeMs'], closeTo(675, 1e-9));
      expect(score['startTimeMedianMs'], closeTo(700, 1e-9));
      expect(score['startTimeP95Ms'], closeTo(1100, 1e-9));
      expect(score['within500msRate'], 0.5);
    });

    test('end-time error is reported when both sides carry end times', () {
      final score = evaluate(
        reference: <quality.QualityLine>[line('第一句歌词', 1000, 3000)],
        hypothesis: <quality.QualityLine>[line('第一句歌词', 1000, 3200)],
      );
      expect(score['endTimeMaeMs'], 200.0);
    });

    test('timing metrics stay null when either side has no timestamps', () {
      final score = evaluate(
        reference: <quality.QualityLine>[line('第一句歌词')],
        hypothesis: <quality.QualityLine>[line('第一句歌词', 1000)],
      );
      expect(score['timedMatchCount'], 0);
      expect(score['startTimeMaeMs'], isNull);
      expect(score['within500msRate'], isNull);
      expect(score['lineRecall'], 1.0);
    });
  });

  group('parsing', () {
    test('LRC timestamps, metadata and repeated stamps are expanded', () {
      final lines = quality.parseLrcLyrics(
        '[ti:测试]\n'
        '[ar:歌手]\n'
        '[00:01.50]第一句\n'
        '[00:05.00][00:45.25]副歌\n'
        '[00:09]结尾\n',
      );
      expect(lines.map((line) => line.text).toList(), <String>[
        '第一句',
        '副歌',
        '副歌',
        '结尾',
      ]);
      expect(lines.map((line) => line.startMs).toList(), <int>[
        1500,
        5000,
        45250,
        9000,
      ]);
    });

    test('LRC fractions are read as centiseconds and milliseconds', () {
      final lines = quality.parseLrcLyrics(
        '[00:00.5]a\n[00:01.25]b\n[00:02.123]c\n',
      );
      expect(lines.map((line) => line.startMs).toList(), <int>[
        500,
        1250,
        2123,
      ]);
    });

    test('LyricDocument JSON with millisecond fields is accepted', () {
      final lines = quality.parseLyricSource(
        jsonEncode(<String, Object?>{
          'language': 'zh',
          'lines': <Object?>[
            <String, Object?>{
              'text': '第一句',
              'startTime': 1000,
              'endTime': 2000,
            },
          ],
        }),
        'doc',
      );
      expect(lines, hasLength(1));
      expect(lines.single.startMs, 1000);
      expect(lines.single.endMs, 2000);
    });

    test('a projects.json export is unwrapped to its lyric document', () {
      final lines = quality.parseLyricSource(
        jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'project-1',
            'lyricDocument': <String, Object?>{
              'language': 'zh',
              'lines': <Object?>[
                <String, Object?>{'text': '第一句', 'startMs': 1000},
              ],
            },
          },
        ]),
        'projects',
      );
      expect(lines.single.text, '第一句');
      expect(lines.single.startMs, 1000);
    });

    test('two lyric documents in one export are rejected', () {
      expect(
        () => quality.parseLyricSource(
          jsonEncode(<Object?>[
            <String, Object?>{
              'lyricDocument': <String, Object?>{
                'lines': <Object?>[
                  <String, Object?>{'text': 'a'},
                ],
              },
            },
            <String, Object?>{
              'lyricDocument': <String, Object?>{
                'lines': <Object?>[
                  <String, Object?>{'text': 'b'},
                ],
              },
            },
          ]),
          'projects',
        ),
        throwsFormatException,
      );
    });

    test('plain text becomes untimed lines', () {
      final lines = quality.parseLyricSource('第一句\n\n第二句\n', 'txt');
      expect(lines.map((line) => line.text).toList(), <String>['第一句', '第二句']);
      expect(lines.every((line) => line.startMs == null), isTrue);
    });

    test('empty input is rejected', () {
      expect(
        () => quality.parseLyricSource('   \n', 'empty'),
        throwsFormatException,
      );
    });
  });

  group('corpus scoring', () {
    String corpus() => jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'songs': <Object?>[
        <String, Object?>{
          'id': 'zh-01',
          'language': 'zh',
          'reference': <String, Object?>{
            'reviewed': true,
            'lines': <Object?>[
              <String, Object?>{'text': '我们跳舞', 'startMs': 10000},
              <String, Object?>{'text': '唱一首歌', 'startMs': 20000},
            ],
          },
          'candidates': <Object?>[
            <String, Object?>{
              'engine': 'whisper',
              'lines': <Object?>[
                <String, Object?>{'text': '我们跳舞', 'startMs': 10000},
                <String, Object?>{'text': '唱一首歌', 'startMs': 20000},
              ],
            },
            <String, Object?>{
              'engine': 'fused',
              'lines': <Object?>[
                <String, Object?>{'text': '我们跳舞', 'startMs': 10000},
                <String, Object?>{'text': '跳舞', 'startMs': 10500},
                <String, Object?>{'text': '唱一首歌', 'startMs': 20000},
              ],
            },
          ],
        },
      ],
    });

    test('scores every engine of every song', () {
      final report = quality.evaluateQualityCorpus(corpus());
      expect(report['songCount'], 1);
      expect(report['candidateCount'], 2);

      final engines = report['overallByEngine']! as Map<String, dynamic>;
      expect(engines.keys.toList(), <String>['fused', 'whisper']);

      final whisper = engines['whisper']! as Map<String, dynamic>;
      expect(whisper['lineRecall'], 1.0);
      expect(whisper['duplicateLineRate'], 0.0);
      expect(whisper['normalizedCharacterErrorRate'], 0.0);

      final fused = engines['fused']! as Map<String, dynamic>;
      expect(fused['lineRecall'], 1.0);
      expect(fused['duplicateLineCount'], 1);
      expect(fused['duplicateLineRate'], closeTo(1 / 3, 1e-9));
      expect(fused['lineCountRatio'], 1.5);
    });

    test('aggregates rates from totals, not averaged averages', () {
      final report = quality.evaluateQualityCorpus(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'songs': <Object?>[
            <String, Object?>{
              'id': 'short',
              'reference': <String, Object?>{
                'lines': <Object?>[
                  <String, Object?>{'text': '我们跳舞', 'startMs': 0},
                ],
              },
              'candidates': <Object?>[
                <String, Object?>{
                  'engine': 'fused',
                  'lines': <Object?>[
                    <String, Object?>{'text': '我们跳舞', 'startMs': 0},
                    <String, Object?>{'text': '我们唱歌', 'startMs': 5000},
                  ],
                },
              ],
            },
            <String, Object?>{
              'id': 'long',
              'reference': <String, Object?>{
                'lines': <Object?>[
                  <String, Object?>{'text': '第一句', 'startMs': 0},
                  <String, Object?>{'text': '第二句', 'startMs': 5000},
                  <String, Object?>{'text': '第三句', 'startMs': 10000},
                  <String, Object?>{'text': '第四句', 'startMs': 15000},
                ],
              },
              'candidates': <Object?>[
                <String, Object?>{
                  'engine': 'fused',
                  'lines': <Object?>[
                    <String, Object?>{'text': '第一句', 'startMs': 0},
                    <String, Object?>{'text': '第二句', 'startMs': 5000},
                    <String, Object?>{'text': '第三句', 'startMs': 10000},
                    <String, Object?>{'text': '第四句', 'startMs': 15000},
                  ],
                },
              ],
            },
          ],
        }),
      );
      final fused =
          (report['overallByEngine']! as Map<String, dynamic>)['fused']!
              as Map<String, dynamic>;
      // 5 of 5 reference lines matched; averaging the songs would have given
      // (1.0 + 1.0) / 2 and hidden the two extra lines entirely.
      expect(fused['lineRecall'], 1.0);
      expect(fused['referenceLineCount'], 5);
      expect(fused['hypothesisLineCount'], 6);
      expect(fused['linePrecision'], closeTo(5 / 6, 1e-9));
    });

    test('unreviewed references and untimed sources produce warnings', () {
      final report = quality.evaluateQualityCorpus(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'songs': <Object?>[
            <String, Object?>{
              'id': 'plain',
              'reference': <String, Object>{
                'lines': <Object?>[
                  <String, Object?>{'text': '第一句'},
                ],
              },
              'candidates': <Object?>[
                <String, Object>{
                  'engine': 'fused',
                  'lines': <Object?>[
                    <String, Object?>{'text': '第一句'},
                  ],
                },
              ],
            },
          ],
        }),
      );
      final warnings = (report['warnings']! as List).cast<String>();
      expect(
        warnings.any((warning) => warning.contains('reviewed: true')),
        isTrue,
      );
      expect(
        warnings.any((warning) => warning.contains('no timestamps')),
        isTrue,
      );
    });

    test('rejects a wrong schema version and duplicate engines', () {
      expect(
        () => quality.evaluateQualityCorpus(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'songs': <Object?>[],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => quality.evaluateQualityCorpus(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'songs': <Object?>[
              <String, Object?>{
                'id': 'dup',
                'reference': <String, Object>{
                  'lines': <Object?>[
                    <String, Object?>{'text': '第一句'},
                  ],
                },
                'candidates': <Object?>[
                  <String, Object>{
                    'engine': 'fused',
                    'lines': <Object?>[
                      <String, Object?>{'text': '第一句'},
                    ],
                  },
                  <String, Object>{
                    'engine': 'fused',
                    'lines': <Object?>[
                      <String, Object?>{'text': '第一句'},
                    ],
                  },
                ],
              },
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('baseline comparison', () {
    final reference = <quality.QualityLine>[
      line('我们跳舞', 10000, 13000),
      line('唱一首歌', 20000, 24000),
    ];
    final cleanHypothesis = <quality.QualityLine>[
      line('我们跳舞', 10000, 13000),
      line('唱一首歌', 20000, 24000),
    ];
    final duplicatedHypothesis = <quality.QualityLine>[
      line('我们跳舞', 10000, 13000),
      line('跳舞', 10500, 11000),
      line('唱一首歌', 20000, 24000),
    ];

    test('flags inserted duplicates as a regression', () {
      final baseline = quality.singlePairReport(
        reference: reference,
        hypothesis: cleanHypothesis,
        engine: 'fused',
        songId: 'song-01',
      );
      final current = quality.singlePairReport(
        reference: reference,
        hypothesis: duplicatedHypothesis,
        engine: 'fused',
        songId: 'song-01',
      );
      final comparison = quality.compareQualityReports(baseline, current);
      expect(comparison['regressed'], isTrue);
      final metrics = (comparison['regressions']! as List)
          .cast<Map<String, Object?>>()
          .map((entry) => entry['metric'])
          .toSet();
      expect(metrics, contains('duplicateLineRate'));
      expect(metrics, contains('lineCountRatio'));
    });

    test('reports no regression when output is unchanged', () {
      final baseline = quality.singlePairReport(
        reference: reference,
        hypothesis: cleanHypothesis,
        engine: 'fused',
        songId: 'song-01',
      );
      final comparison = quality.compareQualityReports(baseline, baseline);
      expect(comparison['regressed'], isFalse);
      expect(comparison['regressions'], isEmpty);
    });

    test('names engines that disappeared from the current run', () {
      final baseline = quality.singlePairReport(
        reference: reference,
        hypothesis: cleanHypothesis,
        engine: 'whisper',
        songId: 'song-01',
      );
      final current = quality.singlePairReport(
        reference: reference,
        hypothesis: cleanHypothesis,
        engine: 'fused',
        songId: 'song-01',
      );
      final comparison = quality.compareQualityReports(baseline, current);
      expect(comparison['enginesOnlyInBaseline'], <String>['whisper']);
      expect(comparison['enginesOnlyInCurrent'], <String>['fused']);
      expect(comparison['regressed'], isFalse);
    });
  });

  group('report rendering', () {
    test('text report lists engines, songs and duplicate samples', () {
      final report = quality.singlePairReport(
        reference: <quality.QualityLine>[
          line('we are dancing through the night', 10000, 14000),
        ],
        hypothesis: <quality.QualityLine>[
          line('we are dancing through the night', 10000, 14000),
          line('dancing', 10500, 11500),
        ],
        engine: 'fused',
        songId: 'song-01',
      );
      final text = quality.formatQualityReport(report);
      expect(text, contains('# Lyric quality baseline'));
      expect(text, contains('| fused |'));
      expect(text, contains('## Duplicate lines'));
      expect(text, contains('we are dancing through the night'));
      expect(text, contains('not marked reviewed'));
    });

    test('report is deterministic across runs', () {
      final first = quality.singlePairReport(
        reference: <quality.QualityLine>[line('第一句', 1000)],
        hypothesis: <quality.QualityLine>[line('第一句', 1100)],
        engine: 'fused',
        songId: 'song-01',
      );
      final second = quality.singlePairReport(
        reference: <quality.QualityLine>[line('第一句', 1000)],
        hypothesis: <quality.QualityLine>[line('第一句', 1100)],
        engine: 'fused',
        songId: 'song-01',
      );
      expect(jsonEncode(first), jsonEncode(second));
    });
  });

  group('guards', () {
    test('an empty reference is rejected', () {
      expect(
        () => evaluate(
          reference: <quality.QualityLine>[],
          hypothesis: <quality.QualityLine>[line('第一句')],
        ),
        throwsFormatException,
      );
    });

    test('an empty hypothesis is rejected', () {
      expect(
        () => evaluate(
          reference: <quality.QualityLine>[line('第一句')],
          hypothesis: <quality.QualityLine>[],
        ),
        throwsFormatException,
      );
    });

    test('documents above the line cap are rejected', () {
      final tooLong = <quality.QualityLine>[
        for (var index = 0; index < 301; index++)
          line('第$index句', index * 1000),
      ];
      expect(
        () => evaluate(reference: tooLong, hypothesis: tooLong),
        throwsFormatException,
      );
    });
  });
}

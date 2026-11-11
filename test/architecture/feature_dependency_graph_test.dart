import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/feature_dependency_baseline.dart';
import 'support/feature_dependency_graph.dart';

void expectRatchet(Set<String> actual, Set<String> baseline, String evidence) {
  final added = actual.difference(baseline).toList()..sort();
  final removed = baseline.difference(actual).toList()..sort();
  expect(added, isEmpty, reason: 'New dependencies: $added\n$evidence');
  expect(
    removed,
    isEmpty,
    reason: 'Remove fixed baseline entries: $removed\n$evidence',
  );
}

void main() {
  group('feature graph contracts (#327)', () {
    late FeatureDependencyGraph graph;
    setUpAll(() {
      graph = FeatureDependencyGraph.scan(Directory('lib/features'));
    });

    test('scans the repository and reports SCC edges and source paths', () {
      expect(graph.scannedFiles, greaterThan(100));
      expect(
        graph.features,
        containsAll(['lyrics', 'player', 'project', 'transcription']),
      );
      if (graph.cycles.isNotEmpty) {
        expect(graph.describeCycles(), contains('SCC:'));
        expect(graph.describeCycles(), contains('lib/features/'));
      }
    });

    test('cyclic feature edges are a shrinking baseline', () {
      expectRatchet(
        graph.cyclicEdges,
        cyclicEdgeBaseline,
        graph.describeCycles(),
      );
    });

    test(
      'cross-feature presentation imports are a shrinking path baseline',
      () {
        expectRatchet(
          graph.presentationPaths,
          presentationImportBaseline,
          graph.describeCycles(),
        );
      },
    );
  });

  group('feature graph algorithm and directive parsing', () {
    test(
      'handles multiline, conditional, package, relative and export directives',
      () {
        const source = '''
        // import '../wrong/no.dart';
        /* nested /* export '../wrong/no.dart'; */ comment */
        import
          '../../b/domain/a.dart'
          if (dart.library.io) 'package:lyric_forge_ktv/features/c/data/b.dart';
        export '../../d/presentation/c.dart' show Thing;
        import 'package:other/ignored.dart';
      ''';
        final graph = FeatureDependencyGraph()
          ..addSource('lib/features/a/domain/a.dart', source);
        expect(
          graph.pathsByEdge.keys,
          containsAll(['a -> b', 'a -> c', 'a -> d']),
        );
        expect(graph.pathsByEdge.length, 3);
        expect(graph.presentationPaths, {
          'lib/features/a/domain/a.dart -> lib/features/d/presentation/c.dart',
        });
      },
    );

    test('ignores commented and quoted fake directives', () {
      final uris = directiveUris('''
        // import 'fake.dart';
        /* export 'fake2.dart'; */
        import 'real.dart';
        final text = "import 'fake3.dart';";
      ''');
      expect(uris, ['real.dart']);
    });

    test(
      'rejects annotations before directives instead of silently skipping them',
      () {
        expect(
          () => directiveUris("@deprecated import 'a.dart';"),
          throwsFormatException,
        );
      },
    );

    test('does not parse interpolated code after the directive section', () {
      final source = r'''import 'a.dart';
      final text = 'nested ${map['key']}';''';
      expect(directiveUris(source), ['a.dart']);
    });

    test('rejects escaped URIs rather than allowing a graph bypass', () {
      expect(
        () => directiveUris(r"import 'a\u002fb.dart';"),
        throwsFormatException,
      );
    });

    test('unrelated escaped strings do not fail parsing', () {
      expect(directiveUris(r"import 'real.dart'; final s = 'line\n';"), [
        'real.dart',
      ]);
    });

    test('acyclic feature graph has no cycle', () {
      final graph = FeatureDependencyGraph()
        ..addSource('lib/features/a/x.dart', "import '../b/y.dart';")
        ..addSource('lib/features/b/y.dart', "import '../c/z.dart';");
      expect(graph.cycles, isEmpty);
      expect(graph.cyclicEdges, isEmpty);
    });

    test(
      'a cycle across three features includes all internal edges and paths',
      () {
        final graph = FeatureDependencyGraph()
          ..addSource('lib/features/a/x.dart', "import '../b/y.dart';")
          ..addSource('lib/features/b/y.dart', "export '../c/z.dart';")
          ..addSource('lib/features/c/z.dart', "import '../a/x.dart';");
        expect(graph.cycles.single, {'a', 'b', 'c'});
        expect(graph.cyclicEdges, {'a -> b', 'b -> c', 'c -> a'});
        expect(
          graph.describeCycles(),
          contains('lib/features/b/y.dart -> lib/features/c/z.dart'),
        );
      },
    );

    test('separate SCCs and one-way bridge remain separate', () {
      final graph = FeatureDependencyGraph()
        ..addSource('lib/features/a/x.dart', "import '../b/x.dart';")
        ..addSource(
          'lib/features/b/x.dart',
          "import '../a/x.dart'; import '../c/x.dart';",
        )
        ..addSource('lib/features/c/x.dart', "import '../d/x.dart';")
        ..addSource('lib/features/d/x.dart', "import '../c/x.dart';");
      expect(graph.cycles.length, 2);
      expect(graph.cyclicEdges, {'a -> b', 'b -> a', 'c -> d', 'd -> c'});
      expect(graph.cyclicEdges, isNot(contains('b -> c')));
    });

    test('removing an edge breaks a cycle and makes baseline stale', () {
      final graph = FeatureDependencyGraph()
        ..addSource('lib/features/a/x.dart', "import '../b/x.dart';")
        ..addSource('lib/features/b/x.dart', '// removed import');
      expect(graph.cyclicEdges, isEmpty);
      expect({'a -> b', 'b -> a'}.difference(graph.cyclicEdges), hasLength(2));
    });

    test('same-feature and external imports are excluded', () {
      final graph = FeatureDependencyGraph()
        ..addSource(
          'lib/features/a/x.dart',
          "import 'local.dart'; import 'dart:io'; import 'package:third_party/foo.dart';",
        );
      expect(graph.pathsByEdge, isEmpty);
      expect(graph.features, {'a'});
    });

    test('backslash paths resolve consistently across hosts', () {
      final graph = FeatureDependencyGraph()
        ..addSource(r'lib\features\a\x.dart', "import '../b/y.dart';");
      expect(graph.pathsByEdge['a -> b'], {
        'lib/features/a/x.dart -> lib/features/b/y.dart',
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricManualEditMarkerService();

  LyricLine line(String text, {String? id, int startMs = 0, int endMs = 4000}) {
    return LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      id: id,
    );
  }

  LyricDocument document(
    List<LyricLine> lines, {
    Map<String, dynamic>? metadata,
  }) {
    return LyricDocument(
      language: 'zh',
      lines: lines,
      metadata: metadata ?? const {},
    );
  }

  group('assignMissingLineIds', () {
    test('为缺少标识的行分配唯一 id，并保留已有 id', () {
      final input = document([
        line('第一句', id: 'keep-1'),
        line('第二句'),
        line('第三句'),
      ]);

      final normalized = service.assignMissingLineIds(input);

      expect(normalized.lines[0].id, 'keep-1');
      expect(normalized.lines[1].id, isNotNull);
      expect(normalized.lines[2].id, isNotNull);
      expect(normalized.lines[1].id, isNot(normalized.lines[2].id));
    });

    test('全部已有标识时为幂等操作并返回同一对象', () {
      final input = document([line('第一句', id: 'a'), line('第二句', id: 'b')]);

      final normalized = service.assignMissingLineIds(input);

      expect(identical(normalized, input), isTrue);
    });
  });

  group('persist / restore / prune', () {
    test('persist 仅写入当前行集仍存在的标记，且保持其它 metadata', () {
      final doc = document(
        [line('第一句', id: 'a'), line('第二句', id: 'b')],
        metadata: const {'other': 1},
      );

      final metadata = service.persist(doc, {'b', 'deleted-line', 'a'});

      expect(metadata['other'], 1);
      expect(metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey], [
        'a',
        'b',
      ]);
    });

    test('persist 空标记写入空列表', () {
      final doc = document([line('第一句', id: 'a')]);
      final metadata = service.persist(doc, const {});
      expect(
        metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey],
        isEmpty,
      );
    });

    test('restore 过滤已不存在的行 id 与非字符串值', () {
      final doc = document(
        [line('第一句', id: 'a')],
        metadata: const {
          LyricManualEditMarkerService.manuallyEditedLineIdsKey: [
            'a',
            'gone',
            42,
          ],
        },
      );

      expect(service.restore(doc), {'a'});
    });

    test('restore 无标记键时返回空集合', () {
      expect(service.restore(document([line('第一句', id: 'a')])), isEmpty);
    });

    test('prune 只保留仍存在的 id', () {
      final doc = document([line('第一句', id: 'a')]);
      expect(service.prune(doc, {'a', 'b'}), {'a'});
    });
  });

  group('protectedIndices 按稳定标识定位', () {
    test('返回手工编辑行的当前索引，忽略无标识行', () {
      final doc = document([
        line('第一句', id: 'a'),
        line('第二句'),
        line('第三句', id: 'c'),
      ]);

      expect(service.protectedIndices(doc, {'c'}), {2});
      expect(service.protectedIndices(doc, {'a', 'c'}), {0, 2});
      expect(service.protectedIndices(doc, const {}), isEmpty);
    });

    test('前方插入新行后保护索引自动后移（无需索引平移）', () {
      final before = document([line('第一句', id: 'a'), line('第二句', id: 'b')]);
      // 会话内标记第二句。
      final markers = {'b'};
      expect(service.protectedIndices(before, markers), {1});

      // 在第一句前插入新行（编辑器会为新行分配新 id）。
      final after = document([
        line('新插入行', id: 'new'),
        line('第一句', id: 'a'),
        line('第二句', id: 'b'),
      ]);

      expect(service.protectedIndices(after, markers), {2});
    });

    test('删除受保护行之前的行后，保护索引自动前移', () {
      final doc = document([line('第一句', id: 'a'), line('第二句', id: 'b')]);
      final markers = {'b'};

      final afterDelete = document([line('第二句', id: 'b')]);

      expect(service.protectedIndices(afterDelete, markers), {0});
    });
  });

  test('保存重开往返：持久化标记可在重建文档后恢复并定位', () {
    // 会话中：第二行被手动改过。
    final session = document([line('第一句', id: 'a'), line('第二句改词', id: 'b')]);
    final saved = session.copyWith(metadata: service.persist(session, {'b'}));

    // 模拟工程保存 -> 重新打开（JSON 往返）。
    final reopened = LyricDocument.fromJson(saved.toJson());

    final restoredMarkers = service.restore(reopened);

    expect(restoredMarkers, {'b'});
    expect(service.protectedIndices(reopened, restoredMarkers), {1});
  });
}

import 'dart:io';

/// A conservative static dependency graph for feature libraries. All branches
/// of conditional imports/exports are included, regardless of the host OS.
class FeatureDependencyGraph {
  final Map<String, Set<String>> pathsByEdge = {};
  final Set<String> presentationPaths = {};
  final Set<String> features = {};
  int scannedFiles = 0;

  void addSource(String path, String source) {
    final importer = _normalize(path);
    final from = _feature(importer);
    if (from == null) return;
    features.add(from);
    scannedFiles++;
    for (final uri in directiveUris(source)) {
      final target = _resolve(importer, uri);
      if (target == null) continue;
      final to = _feature(target);
      if (to == null || from == to) continue;
      features.add(to);
      final edge = '$from -> $to';
      final evidence = '$importer -> $target';
      pathsByEdge.putIfAbsent(edge, () => <String>{}).add(evidence);
      if (target.startsWith('lib/features/$to/presentation/')) {
        presentationPaths.add(evidence);
      }
    }
  }

  static FeatureDependencyGraph scan(Directory root) {
    final graph = FeatureDependencyGraph();
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) {
        graph.addSource(file.path, file.readAsStringSync());
      }
    }
    return graph;
  }

  /// Tarjan SCCs; singletons without a cross-feature self-edge are omitted.
  List<Set<String>> get cycles {
    final neighbors = <String, Set<String>>{
      for (final feature in features) feature: <String>{},
    };
    for (final edge in pathsByEdge.keys) {
      final pair = edge.split(' -> ');
      neighbors[pair[0]]!.add(pair[1]);
    }
    var nextIndex = 0;
    final indices = <String, int>{};
    final low = <String, int>{};
    final stack = <String>[];
    final active = <String>{};
    final result = <Set<String>>[];
    void visit(String node) {
      indices[node] = nextIndex;
      low[node] = nextIndex++;
      stack.add(node);
      active.add(node);
      for (final neighbor in neighbors[node]!) {
        if (!indices.containsKey(neighbor)) {
          visit(neighbor);
          if (low[neighbor]! < low[node]!) low[node] = low[neighbor]!;
        } else if (active.contains(neighbor) && indices[neighbor]! < low[node]!) {
          low[node] = indices[neighbor]!;
        }
      }
      if (low[node] == indices[node]) {
        final component = <String>{};
        String member;
        do {
          member = stack.removeLast();
          active.remove(member);
          component.add(member);
        } while (member != node);
        if (component.length > 1) result.add(component);
      }
    }
    for (final feature in features.toList()..sort()) {
      if (!indices.containsKey(feature)) visit(feature);
    }
    return result;
  }

  Set<String> get cyclicEdges {
    final result = <String>{};
    for (final component in cycles) {
      for (final edge in pathsByEdge.keys) {
        final pair = edge.split(' -> ');
        if (component.contains(pair[0]) && component.contains(pair[1])) {
          result.add(edge);
        }
      }
    }
    return result;
  }

  String describeCycles() {
    final descriptions = <String>[];
    for (final component in cycles) {
      final members = component.toList()..sort();
      final lines = <String>['SCC: ${members.join(', ')}'];
      final edges = cyclicEdges.where((edge) {
        final pair = edge.split(' -> ');
        return component.contains(pair[0]) && component.contains(pair[1]);
      }).toList()..sort();
      for (final edge in edges) {
        lines.add('  $edge');
        for (final path in pathsByEdge[edge]!.toList()..sort()) {
          lines.add('    $path');
        }
      }
      descriptions.add(lines.join('\n'));
    }
    return descriptions.join('\n');
  }
}

String? _feature(String path) {
  final parts = path.split('/');
  return parts.length >= 4 && parts[0] == 'lib' && parts[1] == 'features'
      ? parts[2]
      : null;
}

String? _resolve(String importer, String uri) {
  const prefix = 'package:lyric_forge_ktv/';
  if (uri.startsWith(prefix)) return _normalize('lib/${uri.substring(prefix.length)}');
  if (uri.contains(':') || uri.startsWith('/')) return null;
  return _normalize('${importer.substring(0, importer.lastIndexOf('/'))}/$uri');
}

String _normalize(String path) {
  final result = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (result.isNotEmpty) result.removeLast();
    } else {
      result.add(part);
    }
  }
  return result.join('/');
}

class _Token {
  final String value;
  final bool isString;
  const _Token(this.value, {this.isString = false});
}

/// Extract directive URIs without matching comments or string contents.
/// Includes conditional alternatives and multiline directives. Dart import URI
/// literals are static; escaped URI characters are intentionally unsupported
/// and fail closed rather than silently bypassing the architecture check.
List<String> directiveUris(String source) {
  final tokens = _tokenize(source);
  final result = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].isString ||
        (tokens[i].value != 'import' && tokens[i].value != 'export')) {
      continue;
    }
    if (i + 1 >= tokens.length || !tokens[i + 1].isString) continue;
    var j = i + 1;
    while (j < tokens.length && tokens[j].value != ';') {
      if (tokens[j].isString) {
        if (tokens[j].value.startsWith('\u0000')) {
          throw FormatException('Escaped directive URI is not supported');
        }
        result.add(tokens[j].value);
      }
      j++;
    }
    if (j == tokens.length) throw FormatException('Unterminated import/export');
    i = j;
  }
  return result;
}

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var i = 0;
  bool identifier(int c) => (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 36;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final end = source.indexOf('\n', i + 2);
      i = end == -1 ? source.length : end + 1;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      var depth = 1;
      while (i < source.length && depth > 0) {
        if (i + 1 < source.length && source.substring(i, i + 2) == '/*') {
          depth++;
          i += 2;
        } else if (i + 1 < source.length && source.substring(i, i + 2) == '*/') {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) throw FormatException('Unterminated comment');
      continue;
    }
    final raw = (c == 'r' || c == 'R') && i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    if (c == "'" || c == '"' || raw) {
      if (raw) i++;
      final quote = source[i];
      final triple = i + 2 < source.length && source.substring(i, i + 3) == quote * 3;
      final delimiter = triple ? quote * 3 : quote;
      i += delimiter.length;
      final content = StringBuffer();
      var escaped = false;
      var terminated = false;
      while (i < source.length) {
        if (source.startsWith(delimiter, i)) {
          i += delimiter.length;
          terminated = true;
          break;
        }
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          escaped = true;
          content.write(source.substring(i, i + 2));
          i += 2;
        } else {
          content.write(source[i++]);
        }
      }
      if (!terminated) throw FormatException('Unterminated string');
      // Escaped strings are valid elsewhere; reject only if used as a URI.
      tokens.add(_Token(escaped ? '\u0000$content' : content.toString(), isString: true));
      continue;
    }
    if (identifier(source.codeUnitAt(i))) {
      final start = i++;
      while (i < source.length && identifier(source.codeUnitAt(i))) i++;
      tokens.add(_Token(source.substring(start, i)));
    } else {
      if (c == ';') tokens.add(const _Token(';'));
      i++;
    }
  }
  return tokens;
}

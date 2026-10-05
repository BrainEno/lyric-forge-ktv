import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart Scripts/ios_dev_inventory.dart '
      '<flutter|simctl|devicectl|details|runtimes>',
    );
    exitCode = 64;
    return;
  }

  final input = stdin.readAsStringSync();
  if (input.trim().isEmpty) return;

  late final dynamic decoded;
  try {
    decoded = jsonDecode(input);
  } on FormatException catch (error) {
    stderr.writeln('Unable to parse device JSON: ${error.message}');
    exitCode = 65;
    return;
  }

  switch (args.single) {
    case 'flutter':
      _emitFlutterDevices(decoded);
      return;
    case 'simctl':
      _emitSimulators(decoded);
      return;
    case 'devicectl':
      _emitDevicectlDevices(decoded);
      return;
    case 'details':
      _emitDeviceDetails(decoded);
      return;
    case 'runtimes':
      _emitRuntimes(decoded);
      return;
    default:
      stderr.writeln('Unknown parser mode: ${args.single}');
      exitCode = 64;
  }
}

void _emitFlutterDevices(dynamic decoded) {
  if (decoded is! List) return;

  for (final item in decoded) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final platform = _string(map['targetPlatform']).toLowerCase();
    if (platform != 'ios') continue;

    final id = _string(map['id']);
    final name = _string(map['name']);
    if (id.isEmpty || name.isEmpty) continue;

    final emulator = map['emulator'] == true;
    final supported = map['isSupported'] != false;
    final sdk = _string(map['sdk']);
    final kind = emulator ? 'simulator' : 'physical';
    final status = supported ? 'Ready' : 'Unsupported by Flutter';
    _line([id, name, kind, sdk, status, supported ? '1' : '0']);
  }
}

void _emitSimulators(dynamic decoded) {
  if (decoded is! Map) return;
  final devices = decoded['devices'];
  if (devices is! Map) return;

  for (final runtimeEntry in devices.entries) {
    final runtimeId = _string(runtimeEntry.key);
    if (!runtimeId.contains('.iOS-')) continue;
    final version = _runtimeVersion(runtimeId);
    final value = runtimeEntry.value;
    if (value is! List) continue;

    for (final item in value) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if (map['isAvailable'] == false) continue;

      final id = _string(map['udid']);
      final name = _string(map['name']);
      if (id.isEmpty || name.isEmpty) continue;
      final state = _string(map['state'], fallback: 'Unknown');
      _line([id, name, 'simulator', version, state]);
    }
  }
}

void _emitDevicectlDevices(dynamic decoded) {
  final devices = _findDeviceList(decoded);
  for (final item in devices) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);

    final name = _firstValue(map, const ['name', 'deviceName']);
    final id = _firstValue(
      map,
      const ['udid', 'identifier', 'deviceIdentifier', 'coreDeviceIdentifier'],
    );
    if (name.isEmpty || id.isEmpty) continue;

    final product = _firstValue(
      map,
      const ['productType', 'deviceType', 'modelName', 'deviceClass'],
    );
    final platform = _firstValue(
      map,
      const ['platform', 'operatingSystem', 'osName', 'targetPlatform'],
    );
    final haystack = '$product $platform'.toLowerCase();
    final isIos = haystack.contains('ios') ||
        haystack.contains('iphone') ||
        haystack.contains('ipad');
    final isOtherApplePlatform = haystack.contains('watchos') ||
        haystack.contains('tvos') ||
        haystack.contains('visionos') ||
        haystack.contains('macos');
    if (!isIos && isOtherApplePlatform) continue;
    if (!isIos && product.isEmpty && platform.isEmpty) continue;

    final os = _firstValue(
      map,
      const [
        'osVersionNumber',
        'operatingSystemVersion',
        'productVersion',
        'osVersion',
      ],
    );
    final state = _firstValue(
      map,
      const ['visibilityClass', 'availability', 'deviceState', 'state'],
    );
    final connection = _firstValue(
      map,
      const ['transportType', 'connectionType', 'connectionState'],
    );
    final developerMode = _firstValue(map, const ['developerModeStatus']);
    final pairing = _firstValue(map, const ['pairingState']);
    final locked = _firstValue(map, const ['isLocked', 'locked']);

    _line([
      id,
      name,
      'physical-system',
      os,
      state,
      connection,
      developerMode,
      pairing,
      locked,
    ]);
  }
}

void _emitDeviceDetails(dynamic decoded) {
  const keys = <String, String>{
    'udid': 'UDID',
    'identifier': 'Identifier',
    'producttype': 'Product type',
    'osversionnumber': 'iOS version',
    'operatingsystemversion': 'OS version',
    'developermodestatus': 'Developer Mode',
    'pairingstate': 'Pairing',
    'islocked': 'Locked',
    'locked': 'Locked',
    'transporttype': 'Connection',
    'connectiontype': 'Connection',
    'visibilityclass': 'Availability',
    'devicestate': 'Device state',
    'bootstate': 'Boot state',
  };

  final seen = <String>{};
  void visit(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = _string(entry.key).toLowerCase();
        final label = keys[key];
        if (label != null && !seen.contains(label)) {
          final value = _scalar(entry.value);
          if (value.isNotEmpty) {
            seen.add(label);
            _line([label, value]);
          }
        }
        visit(entry.value);
      }
    } else if (node is List) {
      for (final item in node) {
        visit(item);
      }
    }
  }

  visit(decoded);
}

void _emitRuntimes(dynamic decoded) {
  if (decoded is! Map) return;
  final runtimes = decoded['runtimes'];
  if (runtimes is! List) return;

  for (final item in runtimes) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final identifier = _string(map['identifier']);
    final name = _string(map['name']);
    final available = map['isAvailable'] != false;
    if (!identifier.contains('.iOS-') || !available) continue;
    _line([name.isEmpty ? identifier : name, identifier]);
  }
}

List<dynamic> _findDeviceList(dynamic decoded) {
  if (decoded is Map) {
    final result = decoded['result'];
    if (result is Map && result['devices'] is List) {
      return List<dynamic>.from(result['devices'] as List);
    }
    if (decoded['devices'] is List) {
      return List<dynamic>.from(decoded['devices'] as List);
    }
    for (final value in decoded.values) {
      final nested = _findDeviceList(value);
      if (nested.isNotEmpty) return nested;
    }
  } else if (decoded is List) {
    for (final value in decoded) {
      final nested = _findDeviceList(value);
      if (nested.isNotEmpty) return nested;
    }
  }
  return const [];
}

String _firstValue(Map<String, dynamic> map, List<String> keys) {
  final normalized = keys.map((key) => key.toLowerCase()).toSet();
  String search(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = _string(entry.key).toLowerCase();
        if (normalized.contains(key)) {
          final value = _scalar(entry.value);
          if (value.isNotEmpty) return value;
        }
      }
      for (final value in node.values) {
        final found = search(value);
        if (found.isNotEmpty) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = search(value);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  return search(map);
}

String _scalar(dynamic value) {
  if (value == null) return '';
  if (value is String || value is num || value is bool) {
    return _string(value);
  }
  return '';
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  return text.isEmpty ? fallback : text;
}

String _runtimeVersion(String runtimeId) {
  final match = RegExp(r'\.iOS-(\d+)-(\d+)(?:-(\d+))?$').firstMatch(runtimeId);
  if (match == null) return 'iOS';
  final parts = <String>[match.group(1)!, match.group(2)!];
  final patch = match.group(3);
  if (patch != null) parts.add(patch);
  return 'iOS ${parts.join('.')}';
}

void _line(List<String> values) {
  stdout.writeln(values.map((value) => _string(value)).join('\t'));
}

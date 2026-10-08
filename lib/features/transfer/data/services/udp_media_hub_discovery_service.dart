import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/media_hub_discovery.dart';
import '../../domain/services/media_hub_discovery_service.dart';

class UdpMediaHubDiscoveryService implements MediaHubDiscoveryService {
  static const int discoveryPort = 48518;
  static const int protocolVersion = 1;
  static const String serviceName = 'elysium-player-media-hub';

  final Uuid _uuid;

  UdpMediaHubDiscoveryService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Future<MediaHubDiscoveryResult?> discover(
    MediaHubConnection knownConnection, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deviceId = knownConnection.deviceId?.trim();
    final discoveryKey = knownConnection.discoveryKey?.trim();
    if (deviceId == null ||
        deviceId.isEmpty ||
        discoveryKey == null ||
        discoveryKey.isEmpty) {
      return null;
    }

    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? retryTimer;
    Timer? timeoutTimer;
    final completer = Completer<MediaHubDiscoveryResult?>();
    final requestId = _uuid.v4();
    final payload = utf8.encode(
      jsonEncode({
        'service': serviceName,
        'version': protocolVersion,
        'type': 'discover',
        'deviceId': deviceId,
        'discoveryKey': discoveryKey,
        'requestId': requestId,
      }),
    );

    Future<void> finish(MediaHubDiscoveryResult? result) async {
      if (!completer.isCompleted) completer.complete(result);
    }

    Future<void> sendProbe() async {
      final current = socket;
      if (current == null || completer.isCompleted) return;

      try {
        current.send(
          payload,
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      } catch (_) {
        // Some network stacks reject global broadcast; the known-host probe
        // below can still recover fixed/Tailscale endpoints.
      }

      try {
        final addresses = await InternetAddress.lookup(
          knownConnection.host,
          type: InternetAddressType.IPv4,
        );
        for (final address in addresses) {
          current.send(payload, address, discoveryPort);
        }
      } catch (_) {
        // Stale DHCP hostnames/IPs are expected during recovery.
      }
    }

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          try {
            final decoded = jsonDecode(utf8.decode(datagram!.data));
            if (decoded is! Map) continue;
            final body = Map<String, dynamic>.from(decoded);
            if (body['service'] != serviceName ||
                body['version'] != protocolVersion ||
                body['type'] != 'offer' ||
                body['deviceId'] != deviceId ||
                body['requestId'] != requestId) {
              continue;
            }
            final port = body['port'];
            final token = body['token'];
            if (port is! num ||
                port.toInt() <= 0 ||
                token is! String ||
                token.trim().isEmpty) {
              continue;
            }
            unawaited(
              finish(
                MediaHubDiscoveryResult(
                  deviceId: deviceId,
                  host: datagram!.address.address,
                  port: port.toInt(),
                  token: token.trim(),
                ),
              ),
            );
            break;
          } catch (_) {
            // Ignore unrelated/malformed UDP traffic.
          }
        }
      });

      await sendProbe();
      retryTimer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => unawaited(sendProbe()),
      );
      timeoutTimer = Timer(timeout, () => unawaited(finish(null)));
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      retryTimer?.cancel();
      timeoutTimer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }
}

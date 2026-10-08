import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/media_hub_device_identity.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_device_identity_store.dart';
import '../../domain/services/media_hub_service.dart';
import 'udp_media_hub_discovery_service.dart';

/// Adds a stable desktop identity and an authenticated-by-pairing UDP discovery
/// responder around the existing HTTP Media Hub.
///
/// The current HTTP access token is only returned in a unicast discovery offer
/// after the requester presents the discovery key it previously received via
/// the pairing URI. This is a convenience/recovery protocol for the same local
/// network trust model as the existing HTTP Media Hub; it is not TLS.
class DiscoverableMediaHubService implements MediaHubService {
  final MediaHubService delegate;
  final MediaHubDeviceIdentityStore identityStore;
  final StreamController<MediaHubState> _stateController =
      StreamController<MediaHubState>.broadcast();

  MediaHubState _state = const MediaHubState.stopped();
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;

  DiscoverableMediaHubService({
    required this.delegate,
    required this.identityStore,
  });

  @override
  Stream<MediaHubState> get stateStream => _stateController.stream;

  @override
  MediaHubState get currentState => _state;

  @override
  MediaHubSession? get currentSession => _state.session;

  @override
  bool get isRunning => _state.isRunning && delegate.isRunning;

  @override
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks) async {
    await stopSharing();
    _emit(const MediaHubState(status: MediaHubStatus.starting));

    try {
      final identity = await identityStore.loadOrCreate();
      final raw = await delegate.startSharing(tracks);
      final session = MediaHubSession(
        host: raw.host,
        port: raw.port,
        token: raw.token,
        startedAt: raw.startedAt,
        trackCount: raw.trackCount,
        endpoints: raw.endpoints,
        deviceId: identity.deviceId,
        discoveryKey: identity.discoveryKey,
      );
      await _startDiscoveryResponder(session, identity);
      _emit(
        MediaHubState(
          status: MediaHubStatus.running,
          session: session,
        ),
      );
      return session;
    } catch (error) {
      await _stopDiscoveryResponder();
      try {
        await delegate.stopSharing();
      } catch (_) {}
      _emit(
        MediaHubState(
          status: MediaHubStatus.failed,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> _startDiscoveryResponder(
    MediaHubSession session,
    MediaHubDeviceIdentity identity,
  ) async {
    await _stopDiscoveryResponder();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        UdpMediaHubDiscoveryService.discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket = socket;
      _discoverySubscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          _handleDiscoveryDatagram(
            socket,
            datagram!,
            session,
            identity,
          );
        }
      });
    } catch (_) {
      // Discovery is best-effort. Sharing must remain usable through QR/manual
      // pairing even when the UDP port is unavailable on this machine.
      await _stopDiscoveryResponder();
    }
  }

  void _handleDiscoveryDatagram(
    RawDatagramSocket socket,
    Datagram datagram,
    MediaHubSession session,
    MediaHubDeviceIdentity identity,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map) return;
      final body = Map<String, dynamic>.from(decoded);
      final requestId = body['requestId'];
      if (body['service'] != UdpMediaHubDiscoveryService.serviceName ||
          body['version'] != UdpMediaHubDiscoveryService.protocolVersion ||
          body['type'] != 'discover' ||
          body['deviceId'] != identity.deviceId ||
          body['discoveryKey'] != identity.discoveryKey ||
          requestId is! String ||
          requestId.trim().isEmpty) {
        return;
      }

      final payload = utf8.encode(
        jsonEncode({
          'service': UdpMediaHubDiscoveryService.serviceName,
          'version': UdpMediaHubDiscoveryService.protocolVersion,
          'type': 'offer',
          'deviceId': identity.deviceId,
          'requestId': requestId,
          'port': session.port,
          'token': session.token,
          'deviceName': Platform.localHostname,
        }),
      );
      socket.send(payload, datagram.address, datagram.port);
    } catch (_) {
      // Ignore unrelated/malformed UDP traffic.
    }
  }

  @override
  Future<void> stopSharing() async {
    await _stopDiscoveryResponder();
    await delegate.stopSharing();
    _emit(const MediaHubState.stopped());
  }

  Future<void> _stopDiscoveryResponder() async {
    final subscription = _discoverySubscription;
    _discoverySubscription = null;
    await subscription?.cancel();
    _discoverySocket?.close();
    _discoverySocket = null;
  }

  Future<void> dispose() async {
    await stopSharing();
    await _stateController.close();
  }

  void _emit(MediaHubState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}

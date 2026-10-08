import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/media_hub_device_identity.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_device_identity_store.dart';
import '../../domain/services/media_hub_service.dart';
import 'media_hub_discovery_auth.dart';
import 'udp_media_hub_discovery_service.dart';

/// Adds a stable desktop identity and authenticated UDP endpoint discovery
/// around the existing HTTP Media Hub.
///
/// The discovery secret is never transmitted over UDP. Requesters prove they
/// previously paired by signing a per-request nonce with HMAC-SHA256; offers are
/// signed too before a client accepts the current endpoint/session token.
class DiscoverableMediaHubService implements MediaHubService {
  static const Duration _requestReplayWindow = Duration(seconds: 30);

  final MediaHubService delegate;
  final MediaHubDeviceIdentityStore identityStore;
  final StreamController<MediaHubState> _stateController =
      StreamController<MediaHubState>.broadcast();

  MediaHubState _state = const MediaHubState.stopped();
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;
  final Map<String, DateTime> _seenDiscoveryRequests = <String, DateTime>{};

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
      final proof = body['proof'];
      if (body['service'] != UdpMediaHubDiscoveryService.serviceName ||
          body['version'] != UdpMediaHubDiscoveryService.protocolVersion ||
          body['type'] != 'discover' ||
          body['deviceId'] != identity.deviceId ||
          requestId is! String ||
          requestId.trim().isEmpty ||
          proof is! String ||
          proof.trim().isEmpty) {
        return;
      }

      final normalizedRequestId = requestId.trim();
      final expectedProof = mediaHubDiscoveryRequestProof(
        key: identity.discoveryKey,
        deviceId: identity.deviceId,
        requestId: normalizedRequestId,
      );
      if (!mediaHubDiscoveryProofMatches(proof, expectedProof)) return;
      if (!_acceptFreshRequest(normalizedRequestId)) return;

      final offerProof = mediaHubDiscoveryOfferProof(
        key: identity.discoveryKey,
        deviceId: identity.deviceId,
        requestId: normalizedRequestId,
        port: session.port,
        token: session.token,
      );
      final payload = utf8.encode(
        jsonEncode({
          'service': UdpMediaHubDiscoveryService.serviceName,
          'version': UdpMediaHubDiscoveryService.protocolVersion,
          'type': 'offer',
          'deviceId': identity.deviceId,
          'requestId': normalizedRequestId,
          'port': session.port,
          'token': session.token,
          'proof': offerProof,
          'deviceName': Platform.localHostname,
        }),
      );
      socket.send(payload, datagram.address, datagram.port);
    } catch (_) {
      // Ignore unrelated/malformed UDP traffic.
    }
  }

  bool _acceptFreshRequest(String requestId) {
    final now = DateTime.now();
    _seenDiscoveryRequests.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _requestReplayWindow,
    );
    if (_seenDiscoveryRequests.containsKey(requestId)) return false;
    _seenDiscoveryRequests[requestId] = now;
    return true;
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
    _seenDiscoveryRequests.clear();
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

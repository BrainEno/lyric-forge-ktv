import '../models/media_hub_connection.dart';
import '../models/media_hub_discovery.dart';

abstract class MediaHubDiscoveryService {
  Future<MediaHubDiscoveryResult?> discover(
    MediaHubConnection knownConnection, {
    Duration timeout = const Duration(seconds: 2),
  });
}

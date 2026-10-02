import '../models/media_hub_connection.dart';

abstract class MediaHubConnectionStore {
  Future<MediaHubConnection?> loadLastConnection();

  Future<void> saveConnection(MediaHubConnection connection);

  Future<void> clear();
}

import '../models/media_hub_device_identity.dart';

abstract class MediaHubDeviceIdentityStore {
  Future<MediaHubDeviceIdentity> loadOrCreate();
}

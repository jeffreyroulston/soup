/// Shared non-UI code for Soup apps.
///
/// The legacy app's offline cache and view models live apart, in
/// `package:soup_core/legacy.dart`.
library;

export 'src/data/jellyfin/discovery_client_factory.dart';
export 'src/data/jellyfin/jellyfin_api.dart';
export 'src/data/jellyfin/jellyfin_client_factory.dart';
export 'src/data/jellyfin/jellyfin_discovery.dart';
export 'src/data/jellyfin/lan_discovery.dart';
export 'src/data/playback/device_profile.dart';
export 'src/data/playback/playback_bridge.dart';
export 'src/data/session/auth_path_preferences_store.dart';
export 'src/data/session/connection_preferences_store.dart';
export 'src/data/session/session_store.dart';
export 'src/data/soup/soup_identity_flags.dart';
export 'src/data/soup/soup_session_store.dart';
export 'src/features/connectivity/connectivity_view_model.dart';
export 'src/features/playback/video_controller.dart';
export 'src/features/soup_auth/soup_device_link_view_model.dart';
export 'src/platform/android_network_interfaces.dart';

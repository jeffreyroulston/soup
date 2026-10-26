//
// Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_secure_storage_webos/flutter_secure_storage_webos_plugin.h>
#include <shared_preferences_webos/shared_preferences_webos_plugin.h>
#include <video_player_webos/video_player_web_os_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterSecureStorageWebosPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWebosPlugin"));
  SharedPreferencesWebosPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SharedPreferencesWebosPlugin"));
  VideoPlayerWebOsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VideoPlayerWebOsPlugin"));
}

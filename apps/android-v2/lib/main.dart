import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import 'src/app.dart';
import 'src/data/device_settings.dart';
import 'src/data/soup_device.dart';
import 'src/form_factor.dart';
import 'src/mock_app.dart';
import 'src/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final formFactor = await FormFactor.detect();
  if (isWebos) installWebosBackKey();
  if (formFactor.isTouch) {
    // Draw under the status and gesture bars; TouchFrame keeps them clear.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  final device = DeviceSettings(device: await SoupDevice.detect());
  await device.load();
  if (const bool.fromEnvironment('SOUP_MOCK')) {
    runApp(MockApp(formFactor: formFactor, device: device));
    return;
  }
  // libtailscale is only built for Android; webOS connects directly.
  final TailscaleClient tailscale;
  if (isWebos) {
    tailscale = UnavailableTailscaleClient();
  } else {
    final supportDirectory = await getApplicationSupportDirectory();
    const networkInterfaces = AndroidNetworkInterfaces();
    tailscale = NativeTailscaleClient(
      stateDirectory: '${supportDirectory.path}/tailscale',
      networkInterfaces: networkInterfaces.getJson,
    );
  }
  runApp(
    SoupApp(
      formFactor: formFactor,
      device: device,
      tailscaleClient: tailscale,
      discoveryService: DefaultJellyfinDiscoveryService(tailscale: tailscale),
    ),
  );
}

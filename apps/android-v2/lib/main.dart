import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final supportDirectory = await getApplicationSupportDirectory();
  const networkInterfaces = AndroidNetworkInterfaces();
  final tailscale = NativeTailscaleClient(
    stateDirectory: '${supportDirectory.path}/tailscale',
    networkInterfaces: networkInterfaces.getJson,
  );
  runApp(
    SoupApp(
      tailscaleClient: tailscale,
      discoveryService: DefaultJellyfinDiscoveryService(tailscale: tailscale),
    ),
  );
}

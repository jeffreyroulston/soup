import 'package:soup_core/soup_core.dart';

/// Production Soup Identity. Override for local dev with
/// `--dart-define=SOUP_IDENTITY_BASE_URL=http://10.0.2.2:8787`.
const soupIdentityFlags = SoupIdentityFlags(
  enabled: true,
  useMock: bool.fromEnvironment('SOUP_IDENTITY_MOCK'),
  connectTransportGrants: bool.fromEnvironment(
    'SOUP_TRANSPORT_AUTH_KEY',
    defaultValue: true,
  ),
  baseUrl: String.fromEnvironment(
    'SOUP_IDENTITY_BASE_URL',
    defaultValue: 'https://soup-idm.bestiestudios.com',
  ),
);

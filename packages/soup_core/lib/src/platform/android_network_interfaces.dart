import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

class AndroidNetworkInterfaces {
  const AndroidNetworkInterfaces();

  static const _channel = MethodChannel(
    'dev.michaelishri.soup/network_interfaces',
  );

  Future<String> getJson() async {
    return await _channel.invokeMethod<String>('getNetworkInterfaces') ?? '[]';
  }

  Future<List<({InternetAddress address, InternetAddress broadcast})>>
  broadcasts() async {
    final String raw;
    try {
      raw = await getJson();
    } on MissingPluginException {
      return _ioBroadcasts();
    }
    final json = jsonDecode(raw);
    if (json is! List) return const [];
    final result = <({InternetAddress address, InternetAddress broadcast})>[];
    for (final interface in json.whereType<Map>()) {
      if (interface['up'] != true ||
          interface['loopback'] == true ||
          interface['pointToPoint'] == true) {
        continue;
      }
      final addresses = interface['addrs'];
      if (addresses is! List) continue;
      for (final entry in addresses.whereType<Map>()) {
        final address = InternetAddress.tryParse(entry['ip']?.toString() ?? '');
        final broadcast = InternetAddress.tryParse(
          entry['broadcastAddress']?.toString() ?? '',
        );
        if (address?.type == InternetAddressType.IPv4 && broadcast != null) {
          result.add((address: address!, broadcast: broadcast));
        }
      }
    }
    return result;
  }

  /// Without the Android channel (webOS): every IPv4 interface, broadcasting
  /// to 255.255.255.255 since dart:io doesn't expose netmasks.
  Future<List<({InternetAddress address, InternetAddress broadcast})>>
  _ioBroadcasts() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback)
            (address: address, broadcast: InternetAddress('255.255.255.255')),
    ];
  }
}

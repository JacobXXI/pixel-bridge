import 'dart:convert';
import 'dart:io';

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('Pixel Bridge server running on ${server.address.address}:${server.port}');
  print('Tailscale IP: 100.89.202.14');
  print('Waiting for connections...');

  await for (final request in server) {
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    print('[${DateTime.now()}] ${request.method} ${request.uri.path} from $clientIp');

    request.response.headers.contentType = ContentType.json;
    request.response.headers.add('Access-Control-Allow-Origin', '*');

    if (request.uri.path == '/ping') {
      request.response.write('{"status":"ok","server":"chisa","time":"${DateTime.now().toIso8601String()}"}');
    } else if (request.uri.path == '/message') {
      if (request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        print('Received message: $body');
        request.response.write('{"received":true}');
      } else {
        request.response.write('{"error":"use POST"}');
      }
    } else {
      request.response.write('{"status":"pixel_bridge_server","endpoints":["/ping","/message"]}');
    }

    await request.response.close();
  }
}

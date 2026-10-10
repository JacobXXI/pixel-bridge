import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:mime/mime.dart';

final List<Map<String, dynamic>> _messages = [];
final Map<String, File> _files = {};
int _messageId = 0;

String _generateId() {
  return '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}';
}

void main() async {
  final uploadDir = Directory('${Directory.current.path}/uploads');
  if (!await uploadDir.exists()) {
    await uploadDir.create(recursive: true);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('Pixel Bridge server running on ${server.address.address}:${server.port}');
  print('Tailscale IP: 100.89.202.14');
  print('Uploads: ${uploadDir.path}');
  print('Waiting for connections...');

  await for (final request in server) {
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    print('[${DateTime.now()}] ${request.method} ${request.uri.path} from $clientIp');

    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      continue;
    }

    try {
      if (request.uri.path == '/ping') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'server': 'chisa',
          'time': DateTime.now().toIso8601String(),
        }));
      } else if (request.uri.path == '/messages') {
        request.response.headers.contentType = ContentType.json;
        final since = int.tryParse(request.uri.queryParameters['since'] ?? '0') ?? 0;
        final filtered = _messages.where((m) => (m['id'] as int) > since).toList();
        request.response.write(jsonEncode({'messages': filtered}));
      } else if (request.uri.path == '/message') {
        if (request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          _messageId++;
          final msg = {
            'id': _messageId,
            'text': data['text'] ?? '',
            'sender': data['sender'] ?? 'unknown',
            'timestamp': DateTime.now().toIso8601String(),
            'fileUrl': data['fileUrl'],
            'isFile': false,
          };
          _messages.add(msg);
          print('Message $_messageId from ${msg['sender']}: ${msg['text']}');
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'received': true, 'id': _messageId}));
        } else {
          request.response.statusCode = 405;
          request.response.write(jsonEncode({'error': 'use POST'}));
        }
      } else if (request.uri.path == '/upload') {
        if (request.method == 'POST') {
          final contentType = request.headers.contentType;
          if (contentType?.primaryType == 'multipart') {
            final boundary = contentType?.parameters['boundary'];
            if (boundary == null) {
              request.response.statusCode = 400;
              request.response.write(jsonEncode({'error': 'missing boundary'}));
            } else {
              final transformer = MimeMultipartTransformer(boundary);
              final parts = await request.cast<List<int>>().transform(transformer).toList();

              String? sender;
              String? filename;
              List<int>? fileBytes;

              for (final part in parts) {
                final disposition = part.headers['content-disposition'];
                if (disposition != null) {
                  final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(disposition);
                  final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);

                  if (filenameMatch != null) {
                    filename = filenameMatch.group(1);
                    fileBytes = await part.fold<List<int>>([], (p, e) => p..addAll(e));
                  } else if (nameMatch != null && nameMatch.group(1) == 'sender') {
                    sender = await utf8.decoder.bind(part).join();
                  }
                }
              }

              if (filename != null && fileBytes != null) {
                final fileId = _generateId();
                final filePath = '${uploadDir.path}/$fileId-$filename';
                final file = File(filePath);
                await file.writeAsBytes(fileBytes);
                _files[fileId] = file;

                final fileUrl = '/files/$fileId';
                _messageId++;
                final msg = {
                  'id': _messageId,
                  'text': filename,
                  'sender': sender ?? 'unknown',
                  'timestamp': DateTime.now().toIso8601String(),
                  'fileUrl': fileUrl,
                  'isFile': true,
                };
                _messages.add(msg);

                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode({
                  'received': true,
                  'id': _messageId,
                  'fileUrl': fileUrl,
                }));
              } else {
                request.response.statusCode = 400;
                request.response.write(jsonEncode({'error': 'missing file'}));
              }
            }
          } else {
            request.response.statusCode = 400;
            request.response.write(jsonEncode({'error': 'expected multipart/form-data'}));
          }
        } else {
          request.response.statusCode = 405;
          request.response.write(jsonEncode({'error': 'use POST'}));
        }
      } else if (request.uri.path.startsWith('/files/')) {
        final fileId = request.uri.pathSegments.last;
        final file = _files[fileId];
        if (file != null && await file.exists()) {
          final ext = file.path.split('.').last.toLowerCase();
          final mimeTypes = {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
            'pdf': 'application/pdf',
            'txt': 'text/plain',
          };
          request.response.headers.contentType = ContentType.parse(mimeTypes[ext] ?? 'application/octet-stream');
          await file.openRead().pipe(request.response);
          continue;
        } else {
          request.response.statusCode = 404;
          request.response.write(jsonEncode({'error': 'file not found'}));
        }
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'error': 'not found'}));
      }
    } catch (e, st) {
      print('Error handling request: $e\n$st');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': e.toString()}));
    }

    await request.response.close();
  }
}

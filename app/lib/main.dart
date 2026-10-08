import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PixelBridgeApp());
}

class PixelBridgeApp extends StatelessWidget {
  const PixelBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ConnectPage(),
    );
  }
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  static const String _defaultHost = 'chisa';
  static const String _defaultPort = '8080';
  static const String _prefsHostKey = 'server_host';
  static const String _prefsPortKey = 'server_port';

  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  String _status = 'Idle';
  String _response = '';
  bool _loading = false;
  bool _prefsReady = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString(_prefsHostKey) ?? _defaultHost;
      _portController.text = prefs.getString(_prefsPortKey) ?? _defaultPort;
      _prefsReady = true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsHostKey, _hostController.text.trim());
    await prefs.setString(_prefsPortKey, _portController.text.trim());
  }

  String get _baseUrl {
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    return 'http://$host:$port';
  }

  Future<void> _ping() async {
    await _savePrefs();
    setState(() {
      _loading = true;
      _status = 'Connecting...';
      _response = '';
    });

    final uri = Uri.parse('$_baseUrl/ping');

    try {
      final result = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));
      setState(() {
        _status = result.statusCode == 200 ? 'Connected' : 'Error ${result.statusCode}';
        _response = result.body;
      });
    } catch (e) {
      setState(() {
        _status = 'Failed';
        _response = e.toString();
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    await _savePrefs();
    final uri = Uri.parse('$_baseUrl/message');

    setState(() => _loading = true);

    try {
      final result = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': 'Hello from Pixel 8a',
              'time': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 5));
      setState(() {
        _status = result.statusCode == 200 ? 'Message sent' : 'Error ${result.statusCode}';
        _response = result.body;
      });
    } catch (e) {
      setState(() {
        _status = 'Failed';
        _response = e.toString();
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixel Bridge'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: !_prefsReady
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Server Host',
                      hintText: 'Tailscale machine name or IP',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.computer),
                    ),
                    onChanged: (_) => _savePrefs(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.settings_ethernet),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _savePrefs(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loading ? null : _ping,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('Test Connection'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                    label: const Text('Send Test Message'),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: $_status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_response.isNotEmpty)
                          Text(
                            _response,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }
}

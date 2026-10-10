import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const PixelBridgeApp());

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
      home: const ChatPage(),
    );
  }
}

class Message {
  final int id;
  final String text;
  final String sender;
  final String timestamp;
  final String? fileUrl;
  final bool isFile;

  Message({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.fileUrl,
    this.isFile = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as int,
      text: json['text'] as String,
      sender: json['sender'] as String,
      timestamp: json['timestamp'] as String,
      fileUrl: json['fileUrl'] as String?,
      isFile: json['isFile'] as bool? ?? false,
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _defaultHost = 'chisa';
  static const String _defaultPort = '8080';
  static const String _prefsHostKey = 'server_host';
  static const String _prefsPortKey = 'server_port';
  static const String _prefsDeviceIdKey = 'device_id';

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Message> _messages = [];
  String? _deviceId;
  String _host = _defaultHost;
  String _port = _defaultPort;
  bool _sending = false;
  int _lastMessageId = 0;
  Timer? _pollTimer;
  bool _prefsReady = false;
  String _connectionStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}';
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
    }
    setState(() {
      _host = prefs.getString(_prefsHostKey) ?? _defaultHost;
      _port = prefs.getString(_prefsPortKey) ?? _defaultPort;
      _prefsReady = true;
    });
    _startPolling();
  }

  String get _baseUrl => 'http://$_host:$_port';

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchMessages());
  }

  Future<void> _fetchMessages() async {
    try {
      final uri = Uri.parse('$_baseUrl/messages?since=$_lastMessageId');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final msgs = (data['messages'] as List).cast<Map<String, dynamic>>();
        if (msgs.isNotEmpty) {
          setState(() {
            for (final m in msgs) {
              _messages.add(Message.fromJson(m));
            }
            _messages.sort((a, b) => a.id.compareTo(b.id));
            _lastMessageId = _messages.last.id;
            _connectionStatus = 'Connected';
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      setState(() => _connectionStatus = 'Offline');
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() => _sending = true);

    try {
      final uri = Uri.parse('$_baseUrl/message');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'sender': _deviceId}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        await _fetchMessages();
      }
    } catch (e) {
      setState(() => _connectionStatus = 'Failed');
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _sending = true);

    try {
      final uri = Uri.parse('$_baseUrl/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['sender'] = _deviceId!
        ..files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));

      final response = await request.send().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        await _fetchMessages();
      }
    } catch (e) {
      setState(() => _connectionStatus = 'Upload failed');
    } finally {
      setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isMe(Message msg) => msg.sender == _deviceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixel Bridge'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_connectionStatus != 'Connected' && _connectionStatus != 'Idle')
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _connectionStatus,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade900, fontSize: 12),
              ),
            ),
          Expanded(
            child: !_prefsReady
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildBubble(_messages[index]),
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(Message msg) {
    final isMe = _isMe(msg);
    final time = DateTime.parse(msg.timestamp);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                msg.sender.length > 12 ? '${msg.sender.substring(0, 12)}...' : msg.sender,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (msg.isFile && msg.fileUrl != null)
              _buildFileWidget(msg)
            else
              SelectableText(msg.text),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileWidget(Message msg) {
    final ext = msg.text.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
    final url = '$_baseUrl${msg.fileUrl}';

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 100,
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, size: 48),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg.text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _sending ? null : _pickFile,
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                enabled: !_sending,
              ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
              ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) {
        final hostController = TextEditingController(text: _host);
        final portController = TextEditingController(text: _port);
        return AlertDialog(
          title: const Text('Connection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostController,
                decoration: const InputDecoration(labelText: 'Host'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_prefsHostKey, hostController.text.trim());
                await prefs.setString(_prefsPortKey, portController.text.trim());
                setState(() {
                  _host = hostController.text.trim();
                  _port = portController.text.trim();
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

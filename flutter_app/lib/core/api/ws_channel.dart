import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  final String host;
  final int port;
  final String token;
  WebSocketChannel? _channel;
  final _streamController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isManualDisconnect = false;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  WebSocketService({
    this.host = '127.0.0.1',
    this.port = 8765,
    this.token = '',
  });

  Stream<Map<String, dynamic>> get stream => _streamController.stream;
  bool get isConnected => _isConnected;

  void connect() {
    _isManualDisconnect = false;
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    try {
      final trimmed = host.trim();
      Uri wsUrl;
      if (trimmed.contains('trycloudflare') ||
          trimmed.contains('ngrok') ||
          trimmed.contains('loca.lt') ||
          trimmed.contains('pinggy') ||
          trimmed.startsWith('https://')) {
        String cleanHost = trimmed.replaceFirst('https://', '').replaceFirst('http://', '').replaceAll('/', '');
        if (cleanHost.contains(':')) {
          cleanHost = cleanHost.split(':').first;
        }
        wsUrl = Uri.parse('wss://$cleanHost/ws/stream?token=$token');
      } else if (trimmed.startsWith('http://')) {
        final authority = trimmed.replaceFirst('http://', '').replaceAll('/', '');
        final hostWithPort = authority.contains(':') ? authority : '$authority:$port';
        wsUrl = Uri.parse('ws://$hostWithPort/ws/stream?token=$token');
      } else {
        final hostWithPort = trimmed.contains(':') ? trimmed : '$trimmed:$port';
        wsUrl = Uri.parse('ws://$hostWithPort/ws/stream?token=$token');
      }
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        (data) {
          _isConnected = true;
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _streamController.add(parsed);
          } catch (_) {}
        },
        onError: (err) {
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isManualDisconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isManualDisconnect) {
        connect();
      }
    });
  }

  void sendApproval(String callId, bool approved) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'tool_approval_response',
        'call_id': callId,
        'approved': approved,
      }));
    }
  }

  void disconnect() {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}

import 'dart:io';

/// Class to handle NATS-text interaction
class TcpClient {
  final String host;
  final int port;

  TcpClient({required this.host, required this.port});

  /// Returns an observable of either a [Socket] or an [Exception]
  Future<Socket> connect() => Socket.connect(host, port);
}

import 'dart:io';
import '../constants.dart';
import '../model/connection_options.dart';
import 'package:logging/logging.dart';

class ProtocolHandler {
  final Socket socket;
  final Logger? log;

  ProtocolHandler({required this.socket, this.log});

  void connect({ConnectionOptions? opts}) {
    var messageBuffer = opts == null
        ? CONNECT + " {}" + CR_LF
        : CONNECT +
            ' {"verbose":${opts.verbose},' +
            '"pedantic":${opts.pedantic},' +
            '"tls_required":${opts.tlsRequired},' +
            '"name":${opts.name},' +
            '"lang":${opts.language},' +
            '"version":${opts.version},' +
            '"protocol":${opts.protocol},' +
            '"user":${opts.userName},' +
            '"pass":${opts.password}}' +
            CR_LF;
    socket.write(messageBuffer);
  }

  void publish(String message, String subject, {String? replyTo = ""}) {
    subject = subject.replaceAll(' ', '\\b');
    String messageBuffer =
        "$PUB $subject $replyTo ${message.length} $CR_LF$message$CR_LF";
    socket.write(messageBuffer);
  }

  void subscribe(
    String subscriberId,
    String subject, {
    String queueGroup = "",
  }) {
    String messageBuffer = "$SUB $subject $queueGroup $subscriberId$CR_LF";
    socket.write(messageBuffer);
  }

  void unsubscribe(String subscriberId, {int? waitUntilMessageCount}) {
    String messageBuffer =
        "$UNSUB $subscriberId ${waitUntilMessageCount ?? ''}$CR_LF";
    socket.write(messageBuffer);
  }

  void sendPong() {
    socket.write("$PONG$CR_LF");
  }

  void sendPing() {
    socket.write("$PING$CR_LF");
  }
}

import 'dart:async';

import 'package:nats/nats.dart';

StreamTransformer<String, String> createMessagesTransformer() {
  String buffer = '';

  void emitCompleteMessages(EventSink<String> sink) {
    while (buffer.isNotEmpty) {
      if (buffer.startsWith(CR_LF)) {
        buffer = buffer.substring(CR_LF.length);
        continue;
      }

      if (buffer.startsWith(OK)) {
        final int end = buffer.indexOf(CR_LF);
        if (end == -1) return;
        sink.add(buffer.substring(0, end + CR_LF.length).trim());
        buffer = buffer.substring(end + CR_LF.length);
        continue;
      }

      if (buffer.startsWith(PING) || buffer.startsWith(PONG)) {
        final int end = buffer.indexOf(CR_LF);
        if (end == -1) return;
        sink.add(buffer.substring(0, end + CR_LF.length).trim());
        buffer = buffer.substring(end + CR_LF.length);
        continue;
      }

      if (buffer.startsWith(INFO)) {
        final int end = buffer.indexOf(CR_LF);
        if (end == -1) return;
        sink.add(buffer.substring(0, end + CR_LF.length).trim());
        buffer = buffer.substring(end + CR_LF.length);
        continue;
      }

      if (buffer.startsWith(MSG)) {
        final int headerEnd = buffer.indexOf(CR_LF);
        if (headerEnd == -1) return;

        final String header = buffer.substring(0, headerEnd).trim();
        final List<String> parts = header.split(RegExp(r'\s+'));
        if (parts.length < 4) {
          return;
        }

        final int? payloadLength = int.tryParse(parts.last);
        if (payloadLength == null) {
          return;
        }

        final int totalLength =
            headerEnd + CR_LF.length + payloadLength + CR_LF.length;
        if (buffer.length < totalLength) {
          return;
        }

        sink.add(buffer.substring(0, totalLength));
        buffer = buffer.substring(totalLength);
        continue;
      }

      final int nextControl = buffer.indexOf(RegExp(r'(\+OK|INFO |MSG |PING|PONG)'));
      if (nextControl <= 0) {
        return;
      }
      buffer = buffer.substring(nextControl);
    }
  }

  return StreamTransformer<String, String>.fromHandlers(
    handleData: (String data, EventSink<String> sink) {
      buffer += data;
      emitCompleteMessages(sink);
    },
  );
}

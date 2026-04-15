import 'package:nats/nats.dart';

import 'parsed_alert_payload.dart';

class ReceivedAlert {
  const ReceivedAlert({
    required this.message,
    required this.parsed,
    required this.receivedAt,
  });

  final NatsMessage message;
  final ParsedAlertPayload parsed;
  final DateTime receivedAt;

  String get uniqueKey =>
      '${message.subject}|${receivedAt.microsecondsSinceEpoch}';
}

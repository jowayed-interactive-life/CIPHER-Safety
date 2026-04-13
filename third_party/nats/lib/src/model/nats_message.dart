class NatsMessage {
  String payload;
  String subject;
  String sid;
  String? replyTo;
  int length;

  NatsMessage({
    required this.payload,
    required this.subject,
    required this.sid,
    this.replyTo,
    required this.length,
  });
}

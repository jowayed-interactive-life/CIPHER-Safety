import "package:test/test.dart";
import 'package:nats/nats.dart';

void main() async {
  test("pub-sub works", () async {
    int messagesSent = 100;
    int messagesReceived = 0;

    var client1 = NatsClient("demo.nats.io", 4222);
    var client2 = NatsClient("demo.nats.io", 4222);
    await client1.connect();
    await client2.connect();

    client1.subscribe("sub-1", "foo").listen((msg) {
      messagesReceived++;
    });

    await Future.delayed(const Duration(seconds: 2));
    for (int i = 0; i < messagesSent; i++) {
      client2.publish("Hello world", "foo");
    }

    await Future.delayed(const Duration(seconds: 10));
    expect(messagesReceived, messagesSent);
  }, timeout: Timeout(Duration(seconds: 15)));
}

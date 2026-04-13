import 'package:test/test.dart';
import 'package:nats/nats.dart';

void main() {
  test("Default URL is nats://localhost:4222", () {
    expect(DEFAULT_URI, "nats://localhost:4222");
  });
}

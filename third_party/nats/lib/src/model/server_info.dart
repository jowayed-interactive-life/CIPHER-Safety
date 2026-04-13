class ServerInfo {
  String serverId;
  String version;
  String goVersion;
  int protocolVersion;
  String host;
  int port;
  int maxPayload;
  int clientId;
  bool? authRequired;
  bool? tlsRequired;
  bool? tlsVerify;
  List<String>? serverUrls;

  ServerInfo({
    required this.serverId,
    required this.version,
    required this.protocolVersion,
    required this.goVersion,
    required this.host,
    required this.port,
    required this.clientId,
    required this.maxPayload,
    this.serverUrls,
    this.tlsRequired,
    this.tlsVerify,
    this.authRequired,
  });
}

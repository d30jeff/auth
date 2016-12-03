import 'dart:convert';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_auth/angel_auth.dart';
import 'package:http/http.dart' as http;
import 'package:merge_map/merge_map.dart';
import 'package:test/test.dart';

final AngelAuth Auth = new AngelAuth();
Map headers = {HttpHeaders.ACCEPT: ContentType.JSON.mimeType};
AngelAuthOptions localOpts = new AngelAuthOptions(
    failureRedirect: '/failure', successRedirect: '/success');
Map sampleUser = {'hello': 'world'};

verifier(username, password) async {
  if (username == 'username' && password == 'password') {
    return sampleUser;
  } else
    return false;
}

wireAuth(Angel app) async {
  Auth.serializer = (user) async => 1337;
  Auth.deserializer = (id) async => sampleUser;

  Auth.strategies.add(new LocalAuthStrategy(verifier));
  await app.configure(Auth);
}

main() async {
  Angel app;
  http.Client client;
  String url;
  String basicAuthUrl;

  setUp(() async {
    client = new http.Client();
    app = new Angel(debug: true);
    await app.configure(wireAuth);
    app.get('/hello', 'Woo auth', middleware: [Auth.authenticate('local')]);
    app.post('/login', 'This should not be shown',
        middleware: [Auth.authenticate('local', localOpts)]);
    app.get('/success', "yep", middleware: ['auth']);
    app.get('/failure', "nope");

    app
      ..normalize()
      ..dumpTree();

    HttpServer server =
        await app.startServer(InternetAddress.LOOPBACK_IP_V4, 0);
    url = "http://${server.address.host}:${server.port}";
    basicAuthUrl =
        "http://username:password@${server.address.host}:${server.port}";
  });

  tearDown(() async {
    await app.httpServer.close(force: true);
    client = null;
    url = null;
    basicAuthUrl = null;
  });

  test('can use "auth" as middleware', () async {
    var response = await client
        .get("$url/success", headers: {'Accept': 'application/json'});
    print(response.body);
    expect(response.statusCode, equals(403));
  });

  test('successRedirect', () async {
    Map postData = {'username': 'username', 'password': 'password'};
    var response = await client.post("$url/login",
        body: JSON.encode(postData),
        headers: {HttpHeaders.CONTENT_TYPE: ContentType.JSON.mimeType});
    expect(response.statusCode, equals(200));
    expect(response.headers[HttpHeaders.LOCATION], equals('/success'));
  });

  test('failureRedirect', () async {
    Map postData = {'username': 'password', 'password': 'username'};
    var response = await client.post("$url/login",
        body: JSON.encode(postData),
        headers: {HttpHeaders.CONTENT_TYPE: ContentType.JSON.mimeType});
    print("Login response: ${response.body}");
    expect(response.headers[HttpHeaders.LOCATION], equals('/failure'));
    expect(response.statusCode, equals(401));
  });

  test('allow basic', () async {
    String authString = BASE64.encode("username:password".runes.toList());
    var response = await client.get("$url/hello",
        headers: {HttpHeaders.AUTHORIZATION: 'Basic $authString'});
    expect(response.body, equals('"Woo auth"'));
  });

  test('allow basic via URL encoding', () async {
    var response = await client.get("$basicAuthUrl/hello");
    expect(response.body, equals('"Woo auth"'));
  });

  test('force basic', () async {
    Auth.strategies.clear();
    Auth.strategies
        .add(new LocalAuthStrategy(verifier, forceBasic: true, realm: 'test'));
    var response = await client.get("$url/hello", headers: headers);
    print(response.headers);
    expect(response.headers[HttpHeaders.WWW_AUTHENTICATE],
        equals('Basic realm="test"'));
  });
}
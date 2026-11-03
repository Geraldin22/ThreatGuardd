import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:threatguard_server/src/app.dart';
import 'package:threatguard_server/src/auth.dart';
import 'package:threatguard_server/src/store.dart';

Future<void> main(List<String> arguments) async {
  final env = Platform.environment;
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: env['PORT'] ?? '8080')
    ..addOption('host', defaultsTo: env['HOST'] ?? '0.0.0.0',
        help: 'Interface to listen on. 0.0.0.0 lets phones on your network connect.')
    ..addOption('data', defaultsTo: env['THREATGUARD_DATA'] ?? 'data',
        help: 'Folder for the message store and API key.')
    ..addOption('web', defaultsTo: env['THREATGUARD_WEB'] ?? '../build/web',
        help: 'Folder with the Flutter web build (flutter build web).')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln('ThreatGuard server\n\n${parser.usage}');
    return;
  }

  final port = int.tryParse(args['port'] as String);
  if (port == null) {
    stderr.writeln('Invalid --port "${args['port']}".');
    exit(64);
  }
  final dataDir = args['data'] as String;
  final webDir = args['web'] as String;

  final store = Store.open(dataDir);
  final auth = Auth.load(dir: dataDir, envToken: env['THREATGUARD_TOKEN']);
  final pairing = auth.newPairingCode();

  final server = await io.serve(
    buildApp(
      store: store,
      auth: auth,
      webDir: webDir,
      log: (line) => stdout.writeln('${DateTime.now().toIso8601String()} $line'),
    ),
    args['host'] as String,
    port,
  );

  final hasWeb = Directory(webDir).existsSync();
  stdout.writeln('');
  stdout.writeln('ThreatGuard server $serverVersion · engine $engineName');
  stdout.writeln('Data folder : ${Directory(dataDir).absolute.path}');
  stdout.writeln(hasWeb
      ? 'Web app     : serving ${Directory(webDir).absolute.path}'
      : 'Web app     : not found at "$webDir" (run: flutter build web). API only.');
  stdout.writeln('');
  stdout.writeln('Link a phone: open one of these on it, on the same Wi-Fi.');
  stdout.writeln('The code works once and expires in 10 minutes.');
  final hosts = await _reachableHosts(args['host'] as String);
  for (final h in hosts) {
    stdout.writeln('  http://$h:${server.port}/?pair=${pairing.code}');
  }
  stdout.writeln('');
  stdout.writeln('API key for SMS forwarders / Shortcuts is in '
      '${File('$dataDir/auth.json').absolute.path}'
      '${env['THREATGUARD_TOKEN'] == null ? '' : ' (or THREATGUARD_TOKEN)'}');
  stdout.writeln('');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}

Future<List<String>> _reachableHosts(String bound) async {
  if (bound != '0.0.0.0' && bound != '::') return [bound];
  final hosts = <String>['localhost'];
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) hosts.add(a.address);
      }
    }
  } on SocketException {
    // No interface info; localhost is still printed.
  }
  return hosts;
}

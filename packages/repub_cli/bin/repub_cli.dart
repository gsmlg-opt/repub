import 'dart:io';

import 'package:repub_cli/repub_cli.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    printUsage();
    exit(1);
  }

  final command = args.first;
  final subArgs = args.length > 1 ? args.sublist(1) : <String>[];

  switch (command) {
    case 'serve':
      await runServe(subArgs);
    case 'migrate':
      await runMigrate();
    case 'token':
      await runTokenCommand(subArgs);
    case 'help':
    case '--help':
    case '-h':
      printUsage();
    default:
      print('Unknown command: $command');
      printUsage();
      exit(1);
  }
}

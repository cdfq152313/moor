import 'dart:io';

import 'package:coverage/coverage.dart';

Future main() async {
  Directory.current = Directory.current.parent;

  final resolver = Resolver(
    packagesPath: 'moor/.packages',
  );

  final coverage = await parseCoverage([
    File('moor/coverage.json'),
    File('sqlparser/coverage.json'),
  ], 1);

  // report coverage for the moor and moor_generator package
  final lcov = await LcovFormatter(
    resolver,
    reportOn: [
      'moor/lib/',
      'moor_generator/lib',
      'sqlparser/lib',
    ],
    basePath: '.',
  ).format(coverage);

  File('lcov.info').writeAsStringSync(lcov);
}

import 'dart:async';
import 'dart:io';

/// Runs before every test file: the folders the tests write their screenshots and reports to.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Directory('test_output/shots').createSync(recursive: true);
  Directory('test_output/eval').createSync(recursive: true);
  await testMain();
}

import 'dart:async';
import 'dart:io';

Future<String> receiveOAuthCode(HttpServer server, String expectedState) {
  final result = Completer<String>();
  final future = result.future;
  future.ignore();
  server.listen((request) async {
    final response = request.response;
    if (request.uri.path != '/oauth/callback') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final query = request.uri.queryParameters;
    if (query['state'] != expectedState) {
      response.statusCode = HttpStatus.badRequest;
      response.write('Authorization state did not match. Return to the app and try again.');
      await response.close();
      return;
    }
    final code = query['code'];
    final error = query['error'];
    response.statusCode = code != null ? HttpStatus.ok : HttpStatus.badRequest;
    response.headers.contentType = ContentType.html;
    response.write(code != null
        ? '<!doctype html><title>Connected</title><p>Authorization complete. Return to the app.</p>'
        : '<!doctype html><title>Not connected</title><p>Authorization was not completed. Return to the app.</p>');
    await response.close();
    if (result.isCompleted) return;
    if (error != null) {
      result.completeError(StateError('Authorization denied: $error'));
    } else if (code == null || code.isEmpty) {
      result.completeError(const FormatException('The server did not return an authorization code.'));
    } else {
      result.complete(code);
    }
  });
  return result.future;
}

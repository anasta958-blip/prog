import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/platform/workspace_address_state.dart';

void main() {
  for (final path in [
    '/catalog',
    '/company/documents',
    '/company/settings/configuration',
    '/company/settings/configuration/5',
    '/company/settings/legal',
    '/company/access',
    '/devices',
    '/kanban',
  ]) {
    test('refresh restores $path even after Flutter resets the fragment', () {
      var url = 'https://example.test/app/?lang=ru#$path';
      String? stored;
      WorkspaceAddressState boot() => WorkspaceAddressState(
        readUrl: () => url,
        replaceUrl: (value) => url = value,
        readStored: () => stored,
        writeStored: (value) => stored = value,
      );
      final state = boot()..initialize();
      url = 'https://example.test/app/?lang=ru#/';
      expect(state.read(), path);
      expect(boot().read(), path);
      state.write('/company/clients');
      expect(Uri.parse(url).queryParameters['lang'], 'ru');
      expect(Uri.parse(url).path, '/app/');
      expect(boot().read(), '/company/clients');
    });
  }
  test('explicit address wins over stored section', () {
    final state = WorkspaceAddressState(
      readUrl: () => 'https://example.test/#/catalog',
      replaceUrl: (_) {},
      readStored: () => '/company/documents',
      writeStored: (_) {},
    );
    expect(state.read(), '/catalog');
  });
  test('disabled storage and unknown addresses do not prevent startup', () {
    final state = WorkspaceAddressState(
      readUrl: () => 'https://example.test/#/unknown',
      replaceUrl: (_) {},
      readStored: () => throw StateError('disabled'),
      writeStored: (_) => throw StateError('disabled'),
    );
    expect(state.read(), '/kanban');
    state.write('/company/documents');
    expect(state.read(), '/company/documents');
    state.write('https://other.test');
    expect(state.read(), '/company/documents');
  });
  test('public links do not overwrite workspace state', () {
    var stored = '/company/documents';
    final state = WorkspaceAddressState(
      readUrl: () => 'https://example.test/?quoteAccessToken=token',
      replaceUrl: (_) => fail('public URL changed'),
      readStored: () => stored,
      writeStored: (value) => stored = value,
    );
    expect(state.read(), '');
    expect(stored, '/company/documents');
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  test('контроллер загружает конфигурацию и серверную страницу', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(
      config,
      auth,
      api: catalogApi,
      pageSize: 12,
    );

    await controller.initialize();

    expect(controller.configuration?.categories.single.name, 'Оборудование');
    expect(controller.items.single.name, 'Вентилятор');
    expect(catalogApi.lastPageSize, 12);
    expect(controller.error, isNull);

    controller.dispose();
    auth.dispose();
  });

  test('поиск откладывается и отправляется с первой страницы', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(config, auth, api: catalogApi);
    await controller.initialize();

    controller.updateSearch('вент');
    await Future<void>.delayed(const Duration(milliseconds: 420));

    expect(catalogApi.lastSearch, 'вент');
    expect(catalogApi.lastPage, 1);

    controller.dispose();
    auth.dispose();
  });

  test('повторная загрузка подхватывает назначенный справочник', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(config, auth, api: catalogApi);
    await controller.initialize();

    catalogApi.configuration = CatalogConfiguration(
      categories: [
        CatalogCategory(
          id: _category.id,
          name: _category.name,
          sortOrder: _category.sortOrder,
          fields: [
            ..._category.fields,
            const CatalogField(
              code: 'unit',
              label: 'Единица измерения',
              fieldType: 'dictionary',
              isVisible: true,
              isRequired: false,
              sortOrder: 3,
              dictionaryCode: 'units',
            ),
          ],
          sections: const [],
        ),
      ],
      dictionaries: const [
        CatalogDictionary(
          id: '33333333-3333-3333-3333-333333333333',
          code: 'units',
          name: 'Единицы измерения',
          sortOrder: 0,
          items: [],
        ),
      ],
    );

    await controller.reloadConfiguration();

    expect(
      controller.configuration!.categories.single.fields.last.dictionaryCode,
      'units',
    );
    expect(catalogApi.configurationRequests, 2);

    controller.dispose();
    auth.dispose();
  });

  test(
    'создание сохраняет карточку и обновляет только страницу данных',
    () async {
      final catalogApi = _MemoryCatalogGateway();
      final auth = _authorizedController(config);
      final controller = CatalogController(config, auth, api: catalogApi);
      await controller.initialize();

      final saved = await controller.save(
        CatalogItemDraft(
          categoryId: _category.id,
          name: 'Кондиционер',
          marking: 'K-1',
          values: {'base_price': 25000},
        ),
      );

      expect(saved, isTrue);
      expect(catalogApi.createdDraft?.name, 'Кондиционер');
      expect(controller.selectedItem?.name, 'Кондиционер');
      expect(
        controller.items.any((item) => item.name == 'Кондиционер'),
        isTrue,
      );

      controller.dispose();
      auth.dispose();
    },
  );

  test('связь сохраняет UUID выбранной карточки без количества', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(config, auth, api: catalogApi);
    await controller.initialize();
    controller.selectItem(controller.items.single);
    await controller.loadRelations(controller.items.single.id);

    final candidates = await controller.searchRelationCandidates(
      _dependency.id,
      'монтаж',
    );
    final added = await controller.addRelation(
      controller.items.single.id,
      _dependency,
      candidates.single,
    );

    expect(added, isTrue);
    expect(controller.relations.single.sourceName, 'Монтаж');
    expect(catalogApi.savedRelations.single.sourceItemId, _workCandidate.id);

    controller.dispose();
    auth.dispose();
  });

  test('массовая операция отправляет выбранные UUID и очищает выбор', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(config, auth, api: catalogApi);
    await controller.initialize();

    controller.toggleSelection(controller.items.single.id);
    final applied = await controller.applyBulk(
      action: 'set_status',
      status: 'approved',
    );

    expect(applied, isTrue);
    expect(catalogApi.bulkIds, [controller.items.single.id]);
    expect(catalogApi.bulkAction, 'set_status');
    expect(controller.selectedIds, isEmpty);

    controller.dispose();
    auth.dispose();
  });

  test('импорт XLSX обновляет страницу и показывает сводку', () async {
    final catalogApi = _MemoryCatalogGateway();
    final auth = _authorizedController(config);
    final controller = CatalogController(config, auth, api: catalogApi);
    await controller.initialize();

    final imported = await controller.importCatalog(
      fileName: 'catalog.xlsx',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(imported, isTrue);
    expect(catalogApi.importedFileName, 'catalog.xlsx');
    expect(controller.transferMessage, contains('Создано: 2'));

    controller.dispose();
    auth.dispose();
  });
}

AuthController _authorizedController(AppConfig config) => AuthController(
  config,
  api: _NoopAuthGateway(),
  tokens: _MemoryTokenRepository(),
)..accessToken = 'access-token';

final _category = CatalogCategory(
  id: '11111111-1111-1111-1111-111111111111',
  name: 'Оборудование',
  sortOrder: 0,
  fields: const [
    CatalogField(
      code: 'name',
      label: 'Наименование',
      fieldType: 'text',
      isVisible: true,
      isRequired: true,
      sortOrder: 0,
    ),
    CatalogField(
      code: 'marking',
      label: 'Маркировка / размер',
      fieldType: 'text',
      isVisible: true,
      isRequired: false,
      sortOrder: 1,
    ),
    CatalogField(
      code: 'base_price',
      label: 'Цена',
      fieldType: 'money',
      isVisible: true,
      isRequired: true,
      sortOrder: 2,
    ),
  ],
  sections: const [],
);

const _dependency = CatalogDependency(
  id: '44444444-4444-4444-4444-444444444444',
  clientId: 'works-to-equipment',
  sourceCategoryId: '55555555-5555-5555-5555-555555555555',
  targetCategoryId: '11111111-1111-1111-1111-111111111111',
  targetFieldCode: 'linked_services',
  sortOrder: 0,
);

const _workCandidate = CatalogRelationCandidate(
  id: '66666666-6666-6666-6666-666666666666',
  name: 'Монтаж',
  marking: 'M-1',
  status: 'approved',
);

CatalogItem _item({
  String id = '22222222-2222-2222-2222-222222222222',
  String name = 'Вентилятор',
  String marking = 'V-1',
}) => CatalogItem(
  id: id,
  categoryId: _category.id,
  sectionId: null,
  groupId: null,
  name: name,
  marking: marking,
  status: 'approved',
  values: const {'base_price': 10000},
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 2),
);

final class _MemoryCatalogGateway
    implements CatalogGateway, CatalogRelationGateway, CatalogTransferGateway {
  final items = <CatalogItem>[_item()];
  CatalogConfiguration configuration = CatalogConfiguration(
    categories: [_category],
    dictionaries: const [],
  );
  int configurationRequests = 0;
  int? lastPage;
  int? lastPageSize;
  String? lastSearch;
  CatalogItemDraft? createdDraft;
  List<CatalogItemRelation> savedRelations = const [];
  List<String> bulkIds = const [];
  String? bulkAction;
  String? importedFileName;

  @override
  Future<CatalogConfiguration> getConfiguration(String accessToken) async {
    configurationRequests++;
    return configuration;
  }

  @override
  Future<CatalogItemPage> getItems({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async {
    lastPage = page;
    lastPageSize = pageSize;
    lastSearch = search;
    return CatalogItemPage(
      items: List.unmodifiable(items),
      page: page,
      pageSize: pageSize,
      total: items.length,
    );
  }

  @override
  Future<CatalogItem> createItem(
    String accessToken,
    CatalogItemDraft draft,
  ) async {
    createdDraft = draft;
    final item = _item(
      id: '33333333-3333-3333-3333-333333333333',
      name: draft.name,
      marking: draft.marking,
    );
    items.insert(0, item);
    return item;
  }

  @override
  Future<CatalogItem> updateItem(
    String accessToken,
    String itemId,
    CatalogItemDraft draft,
  ) async => throw UnimplementedError();

  @override
  Future<void> deleteItem(String accessToken, String itemId) async {}

  @override
  Future<List<CatalogItemRelation>> getRelations(
    String accessToken,
    String itemId,
  ) async => savedRelations;

  @override
  Future<List<CatalogRelationCandidate>> searchRelationCandidates({
    required String accessToken,
    required String dependencyId,
    required String search,
  }) async => [_workCandidate];

  @override
  Future<List<CatalogItemRelation>> replaceRelations({
    required String accessToken,
    required String itemId,
    required List<CatalogItemRelation> relations,
  }) async {
    savedRelations = List.unmodifiable(relations);
    return savedRelations;
  }

  @override
  Future<CatalogBulkResult> applyBulk({
    required String accessToken,
    required List<String> itemIds,
    required String action,
    String? status,
  }) async {
    bulkIds = List.unmodifiable(itemIds);
    bulkAction = action;
    return CatalogBulkResult(
      requested: itemIds.length,
      affected: itemIds.length,
    );
  }

  @override
  Future<CatalogSpreadsheetDownload> downloadTemplate({
    required String accessToken,
    String? categoryId,
  }) async => CatalogSpreadsheetDownload(
    fileName: 'template.xlsx',
    bytes: Uint8List(0),
  );

  @override
  Future<CatalogSpreadsheetDownload> exportCatalog({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
  }) async =>
      CatalogSpreadsheetDownload(fileName: 'catalog.xlsx', bytes: Uint8List(0));

  @override
  Future<CatalogImportResult> importCatalog({
    required String accessToken,
    required String fileName,
    required Uint8List bytes,
  }) async {
    importedFileName = fileName;
    return const CatalogImportResult(totalRows: 3, created: 2, updated: 1);
  }

  @override
  void close() {}
}

final class _NoopAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  Future<dynamic> get(String path, String accessToken) async => null;
  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async => null;
  @override
  void close() {}
}

final class _MemoryTokenRepository implements TokenRepository {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String? value) async {}
}

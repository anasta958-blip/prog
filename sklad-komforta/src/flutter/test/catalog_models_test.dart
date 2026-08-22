import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

void main() {
  test('карточка каталога читает URL обложки из ответа API', () {
    final item = CatalogItem.fromJson({
      'id': 'item-1',
      'categoryId': 'category-1',
      'sectionId': null,
      'groupId': null,
      'name': 'Товар',
      'marking': 'М-1',
      'status': 'approved',
      'values': <String, dynamic>{},
      'createdAt': '2026-08-22T10:00:00Z',
      'updatedAt': '2026-08-22T10:00:00Z',
      'thumbnailUrl': 'http://localhost:9000/catalog/item-1/image.webp',
    });

    expect(
      item.thumbnailUrl,
      'http://localhost:9000/catalog/item-1/image.webp',
    );
  });
}

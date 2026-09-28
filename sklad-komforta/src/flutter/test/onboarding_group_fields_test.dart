import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  test('group field follows category structure without duplicates', () {
    final draft = OrganizationOnboardingDraft.initial();
    final category = CatalogCategoryDraft(
      clientId: 'equipment',
      name: 'Equipment',
      sections: [CatalogSectionDraft(name: 'Section', groups: [])],
      fields: [
        CatalogFieldDraft(fieldCode: 'name', isVisible: true, isRequired: true),
      ],
    );
    draft.categories.add(category);
    draft.syncGroupFields();
    expect(category.fields.map((field) => field.fieldCode), ['name']);

    category.sections.single.groups.add(CatalogGroupDraft('Group'));
    draft.syncGroupFields();
    final group = category.fields.first;
    expect(group.fieldCode, 'group');
    group.isVisible = false;
    category.fields.remove(group);
    category.fields.add(group);
    draft.syncGroupFields();
    expect(category.fields.map((field) => field.fieldCode), ['name', 'group']);
    expect(category.fields.last, same(group));
    expect(group.isVisible, isFalse);

    final selection = WorkflowCategoryDraft(
      categoryClientId: category.clientId,
      fieldCodes: ['name', 'group'],
    );
    draft.workflows.add(
      WorkflowDraft(
        code: 'quotes',
        name: 'Quotes',
        columns: [],
        transitions: [],
        categories: [selection],
      ),
    );
    final restored = OrganizationOnboardingDraft.fromJson(draft.toJson());
    expect(restored.categories.single.fields.last.fieldCode, 'group');
    expect(restored.categories.single.fields.last.isVisible, isFalse);

    category.sections.single.groups.clear();
    draft.toJson();
    expect(category.fields.map((field) => field.fieldCode), ['name']);
    expect(selection.fieldCodes, ['name']);
  });

  test('groups in any section enable only their category field', () {
    final draft = OrganizationOnboardingDraft.initial();
    for (final id in ['first', 'second']) {
      draft.categories.add(
        CatalogCategoryDraft(
          clientId: id,
          name: id,
          fields: [],
          sections: [
            CatalogSectionDraft(name: 'Empty', groups: []),
            CatalogSectionDraft(
              name: 'Grouped',
              groups: id == 'first'
                  ? [CatalogGroupDraft('One'), CatalogGroupDraft('Two')]
                  : [],
            ),
          ],
        ),
      );
    }
    draft.toJson();
    expect(draft.categories.first.fields.single.fieldCode, 'group');
    expect(draft.categories.last.fields, isEmpty);
  });
}

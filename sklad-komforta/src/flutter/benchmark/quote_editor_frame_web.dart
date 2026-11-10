// Standalone browser benchmark for the real editor in a profile Web build.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

const _config = AppConfig(
  apiBaseUrl: 'http://127.0.0.1:1/api/v1',
  environment: 'benchmark',
);
const _board = KanbanBoard(
  id: 'benchmark',
  code: 'benchmark',
  name: 'Benchmark',
  specialization: WorkflowSpecialization.quote,
  columns: [],
  transitions: [],
  categories: [
    KanbanCategory(
      categoryId: 'equipment',
      name: 'Equipment',
      sortOrder: 0,
      fields: [
        KanbanField(
          code: 'name',
          label: 'Name',
          fieldType: 'text',
          isRequired: true,
          sortOrder: 0,
          options: [],
        ),
        KanbanField(
          code: 'quantity',
          label: 'Quantity',
          fieldType: 'number',
          isRequired: true,
          sortOrder: 1,
          options: [],
        ),
        KanbanField(
          code: 'base_price',
          label: 'Price',
          fieldType: 'money',
          isRequired: true,
          sortOrder: 2,
          options: [],
        ),
      ],
      sections: [KanbanSection(id: 'rows', name: 'Rows', sortOrder: 0)],
    ),
  ],
);

Element? _findElement(Element root, bool Function(Widget) matches) {
  if (matches(root.widget)) return root;
  Element? found;
  root.visitChildElements((child) {
    found ??= _findElement(child, matches);
  });
  return found;
}

void main() {
  final rowCount = int.tryParse(Uri.base.queryParameters['rows'] ?? '') ?? 1000;
  final complex = Uri.base.queryParameters['complex'] != '0';
  final result = html.PreElement()..id = 'benchmark-result';
  result.text = 'BENCH loading';
  html.document.body!.append(result);
  final auth = AuthController(_config)..accessToken = 'benchmark';
  final controller = QuoteController(_config, auth);
  final editorKey = GlobalKey();
  final rows = [
    for (var index = 0; index < rowCount; index++)
      QuotePositionDraft(
        id: 'row-$index',
        name: 'Position $index',
        marking: '',
        unit: 'pcs',
        quantity: 1,
        basePrice: 10,
        values: {},
      ),
  ];
  final variant = QuoteVariantDraft(
    id: 'variant',
    name: 'Variant',
    categories: [
      QuoteCategoryDraft(
        id: 'category',
        catalogCategoryId: 'equipment',
        name: 'Equipment',
        sections: [
          QuoteSectionDraft(id: 'section', name: 'Rows', positions: rows),
        ],
      ),
    ],
  );
  final type = QuoteProposalTypeDraft(
    id: 'type',
    name: 'Type',
    variants: [variant],
  );
  controller
    ..catalog = CatalogConfiguration(
      categories: const [
        CatalogCategory(
          id: 'equipment',
          clientId: 'equipment',
          name: 'Equipment',
          sortOrder: 0,
          fields: [],
          sections: [],
        ),
      ],
      dictionaries: const [],
      moneyPipelines: complex
          ? [
              MoneyPipelineDraft(
                categoryClientId: 'equipment',
                basePriceFieldCode: 'base_price',
                quantityFieldCode: 'quantity',
                resultFieldCode: 'line_total',
              ),
            ]
          : const [],
      rules: complex
          ? [
              CalculationRuleDraft(
                clientId: 'variant-rule',
                name: 'Variant total',
                categoryClientId: 'equipment',
                eventType: 'variant_calculation',
                isEnabled: true,
                conditions: [],
                actions: [
                  RuleActionDraft(
                    actionType: 'set_field',
                    targetFieldCode: 'note',
                    sourceFieldCode: 'variant_total',
                  ),
                ],
              ),
            ]
          : const [],
    )
    ..draft = QuoteDraft(
      kind: QuoteKind.quote,
      title: 'Editor frame benchmark',
      clientId: 'client',
      executorCompanyId: 'executor',
      selectionMode: 'variant',
      proposalTypes: [type],
    )
    ..activeTypeId = type.id
    ..activeVariantId = variant.id;
  runApp(
    MaterialApp(
      home: Scaffold(
        body: QuoteEditorPage(
          key: editorKey,
          config: _config,
          authController: auth,
          board: _board,
          controller: controller,
          onBack: () {},
        ),
      ),
    ),
  );
  Future<void>.delayed(const Duration(seconds: 2), () async {
    try {
      final root = editorKey.currentContext as Element;
      final section = _findElement(
        root,
        (widget) => widget.key == const ValueKey('section'),
      );
      if (section == null) throw StateError('Section was not built');
      await Scrollable.ensureVisible(section);
      await SchedulerBinding.instance.endOfFrame;
      final firstRow = _findElement(
        root,
        (widget) => widget.key == const ValueKey('row-0'),
      );
      if (firstRow == null) throw StateError('First row was not built');
      await Scrollable.ensureVisible(firstRow, alignment: 0.5);
      await SchedulerBinding.instance.endOfFrame;
      final samples = <int>[];
      for (var index = 0; index < 65; index++) {
        final rowElement = _findElement(
          root,
          (widget) => widget.key == const ValueKey('row-0'),
        );
        if (rowElement == null) throw StateError('Visible row was unmounted');
        final increase = _findElement(
          rowElement,
          (widget) =>
              widget is IconButton && widget.tooltip == 'Увеличить на 1',
        );
        final button = increase?.widget as IconButton?;
        if (button?.onPressed == null) {
          throw StateError('Quantity button was not built');
        }
        final frame = Completer<void>();
        SchedulerBinding.instance.addPostFrameCallback((_) => frame.complete());
        final watch = Stopwatch()..start();
        button!.onPressed!();
        await frame.future.timeout(const Duration(seconds: 5));
        watch.stop();
        if (index >= 5) samples.add(watch.elapsedMicroseconds);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      samples.sort();
      result.text =
          'BENCH rows=$rowCount complex=$complex samples=${samples.length} '
          'action_to_frame_p50_us=${samples[samples.length ~/ 2]} '
          'action_to_frame_p95_us=${samples[(samples.length * 0.95).floor()]}';
    } on Object catch (error) {
      result.text = 'BENCH error=$error';
    }
  });
}

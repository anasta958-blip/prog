import 'package:flutter/material.dart';
import '../company/document_canvas_view.dart';
import 'package:sklad_komforta_app/core/widgets/collapse_toggle.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';

const _clientBackground = Color(0xFF0B1119);
const _clientSurface = Color(0xFF111A27);
const _clientBorder = Color(0xFF293A51);
const _clientMuted = Color(0xFF8FA4C2);
const _clientAccent = Color(0xFF4D8DFF);

/// Публичный экран одной защищённой ссылки. Он не запускает staff-auth и не
/// получает доступ к остальным пространствам организации.
final class QuoteClientAccessPage extends StatefulWidget {
  const QuoteClientAccessPage({
    required this.config,
    required this.accessToken,
    this.api,
    super.key,
  });

  final AppConfig config;
  final String accessToken;
  final QuoteClientAccessApi? api;

  @override
  State<QuoteClientAccessPage> createState() => _QuoteClientAccessPageState();
}

final class _QuoteClientAccessPageState extends State<QuoteClientAccessPage> {
  late final QuoteClientAccessApi api;
  final passwordController = TextEditingController();
  final Map<String, String> selectedVariants = {};

  /// Свёрнутые пользователем типы предложения.
  final Set<String> collapsedTypes = {};

  /// Свёрнутые пользователем варианты (внутри своих типов).
  final Set<String> collapsedVariants = {};
  String? sessionToken;
  String? selectedTypeId;
  QuoteClientView? quote;
  String? error;
  bool loading = false;
  bool submitted = false;

  @override
  void initState() {
    super.initState();
    api = widget.api ?? QuoteClientAccessApi(widget.config);
  }

  @override
  void dispose() {
    passwordController.dispose();
    api.close();
    super.dispose();
  }

  Future<void> _login() async {
    if (loading) return;
    if (passwordController.text.isEmpty) {
      setState(() => error = 'Введите пароль из сообщения со ссылкой.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api.login(
        widget.accessToken,
        passwordController.text,
      );
      if (!mounted) return;
      final restoreSelection = quote != null;
      final pendingVariants = Map<String, String>.of(selectedVariants);
      final pendingTypeId = selectedTypeId;
      FocusScope.of(context).unfocus();
      TextInput.finishAutofillContext(shouldSave: false);
      passwordController.clear();
      sessionToken = result.sessionToken;
      _applyQuote(result.quote);
      if (restoreSelection) {
        selectedVariants
          ..clear()
          ..addEntries(
            pendingVariants.entries.where(
              (entry) => result.quote.proposalTypes.any(
                (type) =>
                    type.id == entry.key &&
                    type.variants.any((variant) => variant.id == entry.value),
              ),
            ),
          );
        selectedTypeId =
            result.quote.proposalTypes.any((type) => type.id == pendingTypeId)
            ? pendingTypeId
            : null;
        submitted = false;
      }
    } on ApiException catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message;
          if (exception.statusCode == 401) sessionToken = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () =>
              error = 'Не удалось открыть предложение. Проверьте подключение.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submit() async {
    final current = quote;
    final token = sessionToken;
    if (current == null || token == null || loading) return;
    final typeMode = current.selectionMode == 'proposal_type';
    // В режиме «один вариант» выбор нужен хотя бы в одном типе: остальные
    // типы клиент может оставить без выбора.
    if ((typeMode && selectedTypeId == null) ||
        (!typeMode && selectedVariants.isEmpty)) {
      setState(
        () => error = typeMode
            ? 'Выберите один тип предложения.'
            : 'Выберите хотя бы один вариант.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final updated = await api.submitSelection(
        token,
        proposalTypeId: typeMode ? selectedTypeId : null,
        variants: typeMode ? const {} : selectedVariants,
      );
      if (!mounted) return;
      _applyQuote(updated);
      setState(() => submitted = true);
    } on ApiException catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message;
          if (exception.statusCode == 401) sessionToken = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => error = 'Не удалось сохранить выбор. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _refresh() async {
    final token = sessionToken;
    if (token == null || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final current = await api.getCurrent(token);
      if (mounted) _applyQuote(current);
    } on ApiException catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message;
          if (exception.statusCode == 401) sessionToken = null;
        });
      }
    } on Object {
      if (mounted) setState(() => error = 'Не удалось обновить предложение.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _applyQuote(QuoteClientView value) {
    selectedVariants
      ..clear()
      ..addEntries(
        value.proposalTypes
            .where((type) => type.selectedVariantId != null)
            .map((type) => MapEntry(type.id, type.selectedVariantId!)),
      );
    setState(() {
      quote = value;
      selectedTypeId = value.selectedProposalTypeId;
      submitted = value.selectionSubmittedAt != null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _clientBackground,
    body: SafeArea(
      child: sessionToken == null ? _loginView() : _quoteView(quote!),
    ),
  );

  Widget _loginView() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _clientSurface,
            border: Border.all(color: _clientBorder),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: _clientAccent,
                    size: 38,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Доступ к предложению',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Введите пароль, который вы получили вместе со ссылкой.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _clientMuted, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofocus: true,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !loading,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(labelText: 'Пароль'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    AutoDismissNotice(
                      message: error!,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFF748E)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: loading ? null : _login,
                    child: loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Открыть предложение'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _quoteView(QuoteClientView value) => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF0F1722),
          border: Border(bottom: BorderSide(color: _clientBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: _clientAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (submitted && MediaQuery.sizeOf(context).width < 400)
                    const Text(
                      'Выбор сохранён',
                      style: TextStyle(color: Color(0xFF83E8AD), fontSize: 11),
                    ),
                ],
              ),
            ),
            if (submitted && MediaQuery.sizeOf(context).width >= 400)
              const _StatusBadge(
                label: 'Выбор сохранён',
                icon: Icons.check_circle_outline,
              ),
            IconButton(
              tooltip: 'Обновить предложение',
              onPressed: loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 8 : 24,
                compact ? 12 : 24,
                compact ? 8 : 24,
                24,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  padding: EdgeInsets.all(compact ? 12 : 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(compact ? 8 : 12),
                  ),
                  child: Theme(
                    data: ThemeData(
                      brightness: Brightness.light,
                      colorScheme: const ColorScheme.light(
                        primary: _paperSelected,
                      ),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: _paperText,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      child: _document(value, compact),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: Color(0xFF0F1722),
          border: Border(top: BorderSide(color: _clientBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              AutoDismissNotice(
                message: error!,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFFF748E)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final hint = Text(
                  value.selectionMode == 'proposal_type'
                      ? 'Выберите один тип со всеми вариантами'
                      : 'Выберите по одному варианту в нужных типах',
                  style: const TextStyle(color: _clientMuted),
                );
                final button = FilledButton.icon(
                  onPressed: loading ? null : _submit,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    submitted ? 'Обновить выбор' : 'Подтвердить выбор',
                  ),
                );
                return constraints.maxWidth < 560
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [hint, const SizedBox(height: 10), button],
                      )
                    : Row(
                        children: [
                          Expanded(child: hint),
                          button,
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    ],
  );

  /// Документ в виде «листа», как предпросмотр у менеджера: шапка с заказчиком
  /// и исполнителем, сворачиваемые типы, варианты и таблицы позиций.
  Widget _document(QuoteClientView value, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        value.kind == 'prequote'
            ? 'ПРЕДВАРИТЕЛЬНОЕ КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ'
            : 'КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ',
        style: const TextStyle(
          color: _paperMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        value.title,
        style: TextStyle(
          fontSize: compact ? 22 : 30,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 12),
      if (value.headerDocument case final header?) ...[
        DocumentCanvasView(document: header, compact: true, clientLink: true),
        const SizedBox(height: 8),
      ],
      if (!value.proposalTypes.any(
        (type) => type.variants.any((variant) => variant.document != null),
      ))
        Wrap(
          spacing: 40,
          runSpacing: 12,
          children: [
            _metadata('Заказчик', value.clientName),
            _metadata('Исполнитель', value.executorName),
          ],
        ),
      if (value.additionalInformation case final text?
          when text.trim().isNotEmpty) ...[
        const SizedBox(height: 20),
        Container(
          key: const Key('client-quote-additional-information'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _paperHeader,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _paperBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Дополнительная информация',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(text.trim()),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      RadioGroup<String>(
        groupValue: selectedTypeId,
        onChanged: _selectType,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final type in value.proposalTypes)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _typeBlock(value, type),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _metadata(String label, String? text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _paperMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        text?.trim().isNotEmpty == true ? text!.trim() : 'Не указан',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );

  void _selectType(String? typeId) {
    if (loading) return;
    setState(() {
      selectedTypeId = typeId;
      submitted = false;
      error = null;
    });
  }

  /// Выбор варианта в режиме «один вариант». Повторное нажатие на выбранный
  /// вариант снимает выбор: тип можно оставить без выбора.
  void _selectVariant(QuoteClientProposalType type, String? variantId) {
    if (loading) return;
    setState(() {
      if (variantId == null || selectedVariants[type.id] == variantId) {
        selectedVariants.remove(type.id);
      } else {
        selectedVariants[type.id] = variantId;
      }
      submitted = false;
      error = null;
    });
  }

  void _toggleType(String typeId) => setState(() {
    if (!collapsedTypes.remove(typeId)) collapsedTypes.add(typeId);
  });

  void _toggleVariant(String variantId) => setState(() {
    if (!collapsedVariants.remove(variantId)) collapsedVariants.add(variantId);
  });

  Widget _typeBlock(QuoteClientView document, QuoteClientProposalType type) {
    final typeMode = document.selectionMode == 'proposal_type';
    final collapsed = collapsedTypes.contains(type.id);
    final chosenVariant = type.variants
        .where((variant) => variant.id == selectedVariants[type.id])
        .firstOrNull;
    final status = typeMode
        ? (selectedTypeId == type.id ? 'Тип выбран' : 'Выбирается тип целиком')
        : chosenVariant == null
        ? 'Вариант не выбран'
        : 'Выбран: ${chosenVariant.name}';
    return Column(
      key: Key('client-quote-type-${type.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _paperText,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(8),
            bottom: Radius.circular(collapsed ? 8 : 0),
          ),
          clipBehavior: Clip.antiAlias,
          // Нажатие на полосу выбирает тип (в режиме «тип целиком»);
          // сворачивает тип только стрелка.
          child: InkWell(
            key: Key('client-quote-type-bar-${type.id}'),
            onTap: typeMode && !loading ? () => _selectType(type.id) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 14, 2),
              child: Row(
                children: [
                  CollapseToggle(
                    key: Key('client-quote-type-toggle-${type.id}'),
                    expanded: !collapsed,
                    color: Colors.white,
                    expandTooltip: 'Развернуть тип',
                    collapseTooltip: 'Свернуть тип',
                    onPressed: () => _toggleType(type.id),
                  ),
                  if (typeMode)
                    Radio<String>(
                      value: type.id,
                      enabled: !loading,
                      fillColor: const WidgetStatePropertyAll(Colors.white),
                    )
                  else
                    const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      type.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Color(0xFFCED7E5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: _paperBorder),
                right: BorderSide(color: _paperBorder),
                bottom: BorderSide(color: _paperBorder),
              ),
            ),
            child: typeMode
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, variant) in type.variants.indexed)
                        _variantBlock(type, variant, typeMode, index),
                    ],
                  )
                : RadioGroup<String>(
                    groupValue: selectedVariants[type.id],
                    onChanged: (variantId) => _selectVariant(type, variantId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, variant) in type.variants.indexed)
                          _variantBlock(type, variant, typeMode, index),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _variantBlock(
    QuoteClientProposalType type,
    QuoteClientVariant variant,
    bool typeMode,
    int index,
  ) {
    final selected =
        (!typeMode && selectedVariants[type.id] == variant.id) ||
        (typeMode && selectedTypeId == type.id);
    final collapsed = collapsedVariants.contains(variant.id);
    return Column(
      key: Key('client-quote-variant-${variant.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected
              ? _paperSelectedBackground
              : index.isEven
              ? const Color(0xFFF1F5FB)
              : const Color(0xFFE5EDF7),
          shape: Border(
            left: BorderSide(
              color: selected ? _paperSelected : const Color(0xFF91A6C1),
              width: 4,
            ),
            top: BorderSide(
              color: index == 0 ? _paperBorder : const Color(0xFF91A6C1),
              width: index == 0 ? 1 : 2,
            ),
          ),
          child: InkWell(
            onTap: loading
                ? null
                : typeMode
                ? () => _selectType(type.id)
                : () => _selectVariant(type, variant.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 14, 2),
              child: Row(
                children: [
                  CollapseToggle(
                    key: Key('client-quote-variant-toggle-${variant.id}'),
                    expanded: !collapsed,
                    compact: true,
                    color: _paperMuted,
                    expandTooltip: 'Развернуть вариант',
                    collapseTooltip: 'Свернуть вариант',
                    onPressed: () => _toggleVariant(variant.id),
                  ),
                  if (!typeMode)
                    Radio<String>(
                      value: variant.id,
                      enabled: !loading,
                      toggleable: true,
                    )
                  else
                    const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          variant.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (variant.subtitle?.trim().isNotEmpty == true)
                          Text(
                            variant.subtitle!.trim(),
                            style: const TextStyle(
                              color: _paperMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Сумма и отметка выбора в столбик, чтобы строка помещалась
                  // и на узком телефоне.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(variant.total),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (selected)
                        const Text(
                          'ВЫБРАН',
                          style: TextStyle(
                            color: _paperSelected,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed && variant.document != null)
          DocumentCanvasView(
            document: variant.document!,
            compact: true,
            clientLink: true,
          ),
        if (!collapsed && variant.document == null)
          for (final category in variant.categories) ...[
            _categoryHeading(category.name),
            for (final section in category.sections)
              _positions(category.name, section),
          ],
        if (!collapsed && variant.document == null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: _paperHeader,
              border: Border(bottom: BorderSide(color: _paperBorder)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 22,
              runSpacing: 6,
              children: [
                const Text(
                  'Итого по варианту',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('Сумма без НДС: ${_money(variant.subtotal)}'),
                Text(
                  variant.vatRate == null
                      ? 'Без НДС'
                      : 'НДС ${_number(variant.vatRate!)}%: ${_money(variant.vatAmount)}',
                ),
                Text(
                  'Итого: ${_money(variant.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Таблица раздела с фиксированными колонками; на узком экране она
  /// прокручивается по горизонтали, а сумма раздела стоит над колонкой «Сумма».
  Widget _categoryHeading(String name) => Container(
    margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    color: const Color(0xFF243A56),
    child: Text(
      name,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
  );

  Widget _positions(String category, QuoteClientSection section) {
    final sectionTotal =
        section.total ??
        section.positions.fold<double>(
          0,
          (total, position) => total + position.lineTotal,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _tableWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    section.name.trim().toLowerCase() ==
                            category.trim().toLowerCase()
                        ? 'Позиции'
                        : section.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _money(sectionTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (section.columns != null && section.columns!.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (section.columns!.length * 150.0).clamp(
                  300.0,
                  double.infinity,
                ),
                child: Table(
                  border: TableBorder.all(color: _paperBorder),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    _row(section.columns!, header: true),
                    for (final position in section.positions)
                      _row(
                        List.generate(
                          section.columns!.length,
                          (index) => index < (position.cells?.length ?? 0)
                              ? position.cells![index]
                              : '',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (section.columns == null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth,
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder.all(color: _paperBorder),
                  columnWidths: {
                    for (final (index, width) in _columnWidths.indexed)
                      index: FixedColumnWidth(width),
                  },
                  children: [
                    _row(const [
                      '№',
                      'Наименование',
                      'Маркировка / размер',
                      'Кол-во',
                      'Ед.',
                      'Цена',
                      'Сумма',
                    ], header: true),
                    for (final (index, position) in section.positions.indexed)
                      _row([
                        '${index + 1}',
                        position.name,
                        position.marking,
                        _number(position.quantity),
                        position.unit,
                        _money(position.unitPrice),
                        _money(position.lineTotal),
                      ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _paperText = Color(0xFF172033);
const _paperMuted = Color(0xFF5E6B7E);
const _paperBorder = Color(0xFFD8DEE8);
const _paperHeader = Color(0xFFF0F4F9);
const _paperSelected = Color(0xFF2368C4);
const _paperSelectedBackground = Color(0xFFE8F1FF);

/// Колонки таблицы позиций: №, наименование, маркировка, кол-во, ед., цена, сумма.
const _columnWidths = <double>[38, 250, 160, 70, 60, 115, 125];

/// Сумма ширин [_columnWidths].
const double _tableWidth = 38.0 + 250 + 160 + 70 + 60 + 115 + 125;

TableRow _row(List<String> values, {bool header = false}) => TableRow(
  decoration: BoxDecoration(color: header ? _paperHeader : Colors.white),
  children: [
    for (final (index, value) in values.indexed)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          value,
          textAlign: index >= 5 ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: _paperText,
            fontSize: 12,
            fontWeight: header ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      ),
  ],
);

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF123728),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF58D68D)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF83E8AD),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

String _money(double value) => NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
).format(value);

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

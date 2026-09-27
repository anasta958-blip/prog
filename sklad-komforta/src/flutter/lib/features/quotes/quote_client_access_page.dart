import 'package:flutter/material.dart';
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
    if ((typeMode && selectedTypeId == null) ||
        (!typeMode &&
            selectedVariants.length != current.proposalTypes.length)) {
      setState(
        () => error = typeMode
            ? 'Выберите один тип предложения.'
            : 'Выберите по одному варианту в каждом типе.',
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    value.executorName,
                    style: const TextStyle(color: _clientMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (submitted)
              const _StatusBadge(
                label: 'Выбор сохранён',
                icon: Icons.check_circle_outline,
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            if (value.additionalInformation case final text?
                when text.trim().isNotEmpty)
              _ClientPanel(
                child: Text(
                  text,
                  style: const TextStyle(color: _clientMuted, height: 1.5),
                ),
              ),
            if (value.additionalInformation?.trim().isNotEmpty == true)
              const SizedBox(height: 14),
            RadioGroup<String>(
              groupValue: selectedTypeId,
              onChanged: _selectType,
              child: Column(
                children: value.proposalTypes
                    .map(
                      (type) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _typeCard(value, type),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
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
                      : 'Выберите один вариант в каждом типе',
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

  void _selectType(String? typeId) {
    if (loading) return;
    setState(() {
      selectedTypeId = typeId;
      submitted = false;
      error = null;
    });
  }

  Widget _typeCard(QuoteClientView document, QuoteClientProposalType type) {
    final typeMode = document.selectionMode == 'proposal_type';
    return _ClientPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: typeMode && !loading ? () => _selectType(type.id) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (typeMode)
                    Radio<String>(value: type.id, enabled: !loading),
                  Expanded(
                    child: Text(
                      type.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: _clientBorder),
          if (typeMode)
            ...type.variants.map(
              (variant) => _variantCard(type, variant, typeMode),
            )
          else
            RadioGroup<String>(
              groupValue: selectedVariants[type.id],
              onChanged: (variantId) {
                if (variantId != null && !loading) {
                  setState(() {
                    selectedVariants[type.id] = variantId;
                    submitted = false;
                    error = null;
                  });
                }
              },
              child: Column(
                children: type.variants
                    .map((variant) => _variantCard(type, variant, typeMode))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _variantCard(
    QuoteClientProposalType type,
    QuoteClientVariant variant,
    bool typeMode,
  ) => Container(
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0D151F),
      border: Border.all(
        color: !typeMode && selectedVariants[type.id] == variant.id
            ? _clientAccent
            : _clientBorder,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ExpansionTile(
      initiallyExpanded: true,
      shape: const Border(),
      title: Row(
        children: [
          if (!typeMode) Radio<String>(value: variant.id, enabled: !loading),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (variant.subtitle?.trim().isNotEmpty == true)
                  Text(
                    variant.subtitle!,
                    style: const TextStyle(color: _clientMuted, fontSize: 12),
                  ),
                Text(
                  _money(variant.total),
                  style: const TextStyle(
                    color: _clientAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      children: [
        for (final category in variant.categories)
          for (final section in category.sections)
            _positions(category.name, section),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 18,
            runSpacing: 8,
            children: [
              Text(
                'Без НДС: ${_money(variant.subtotal)}',
                style: const TextStyle(color: _clientMuted),
              ),
              Text(
                variant.vatRate == null
                    ? 'НДС: без НДС'
                    : 'НДС ${_number(variant.vatRate!)}%: ${_money(variant.vatAmount)}',
                style: const TextStyle(color: _clientMuted),
              ),
              Text(
                'Итого: ${_money(variant.total)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _positions(String category, QuoteClientSection section) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$category · ${section.name}',
          style: const TextStyle(
            color: _clientMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 42,
            dataRowMaxHeight: 64,
            columns: const [
              DataColumn(label: Text('Наименование')),
              DataColumn(label: Text('Маркировка')),
              DataColumn(label: Text('Кол-во')),
              DataColumn(label: Text('Ед.')),
              DataColumn(label: Text('Цена')),
              DataColumn(label: Text('Сумма')),
            ],
            rows: section.positions
                .map(
                  (position) => DataRow(
                    cells: [
                      DataCell(
                        SizedBox(width: 220, child: Text(position.name)),
                      ),
                      DataCell(
                        SizedBox(width: 140, child: Text(position.marking)),
                      ),
                      DataCell(Text(_number(position.quantity))),
                      DataCell(Text(position.unit)),
                      DataCell(Text(_money(position.unitPrice))),
                      DataCell(Text(_money(position.lineTotal))),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
}

final class _ClientPanel extends StatelessWidget {
  const _ClientPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _clientSurface,
      border: Border.all(color: _clientBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

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

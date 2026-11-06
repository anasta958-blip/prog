import 'package:flutter/material.dart';
import '../company/company_models.dart';

final class PartySearchOption {
  const PartySearchOption({
    required this.id,
    required this.title,
    required this.searchTerms,
    this.detail,
  });

  final String id;
  final String title;
  final String? detail;
  final List<String> searchTerms;

  String get label => detail == null ? title : '$title — $detail';

  bool matches(String query) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return true;
    if (searchTerms.any((term) => term.toLowerCase().contains(text))) {
      return true;
    }
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty &&
        searchTerms.any(
          (term) => term.replaceAll(RegExp(r'\D'), '').contains(digits),
        );
  }

  factory PartySearchOption.client(CompanyClientModel client) {
    final detail = client.companyType == 'person'
        ? _distinct(client.phone, client.name)
        : _distinct(client.companyName, client.name) ??
              _distinct(client.legalName, client.name);
    return PartySearchOption(
      id: client.id,
      title: client.name,
      detail: detail,
      searchTerms: [
        client.name,
        if (client.companyName != null) client.companyName!,
        if (client.legalName != null) client.legalName!,
        if (client.contactName != null) client.contactName!,
        if (client.phone != null) client.phone!,
        if (client.inn != null) client.inn!,
      ],
    );
  }

  factory PartySearchOption.executor(LegalEntityModel executor) =>
      PartySearchOption(
        id: executor.id,
        title: executor.name,
        detail: executor.companyType == 'person'
            ? _distinct(executor.phone, executor.name)
            : _distinct(executor.legalName, executor.name),
        searchTerms: [
          executor.name,
          if (executor.legalName != null) executor.legalName!,
          if (executor.phone != null) executor.phone!,
          if (executor.inn != null) executor.inn!,
        ],
      );
}

String? _distinct(String? value, String title) {
  final text = value?.trim();
  if (text == null ||
      text.isEmpty ||
      text.toLowerCase() == title.trim().toLowerCase()) {
    return null;
  }
  return text;
}

/// Search does not create a party: only choosing an existing row sets its id.
final class PartySearchField extends StatefulWidget {
  const PartySearchField({
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final String? value;
  final List<PartySearchOption> options;
  final String label;
  final ValueChanged<String?> onChanged;

  @override
  State<PartySearchField> createState() => _PartySearchFieldState();
}

final class _PartySearchFieldState extends State<PartySearchField> {
  final MenuController _menu = MenuController();
  final TextEditingController _search = TextEditingController();
  String _query = '';
  double? _width;

  @override
  void didUpdateWidget(covariant PartySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null) {
      _query = '';
      _search.clear();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options
        .where((item) => item.id == widget.value)
        .firstOrNull;
    final matches = widget.options
        .where((item) => item.matches(_query))
        .toList();
    final invalid = widget.value == null && _query.trim().isNotEmpty;
    return MenuAnchor(
      controller: _menu,
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(0, 4),
      style: _width == null
          ? null
          : MenuStyle(
              minimumSize: WidgetStatePropertyAll(Size(_width!, 0)),
              maximumSize: WidgetStatePropertyAll(
                Size(_width!, double.infinity),
              ),
            ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: Key('party-search-${widget.label}'),
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Название, ФИО или телефон',
              isDense: true,
            ),
            onChanged: (value) {
              setState(() => _query = value);
              if (widget.value != null) widget.onChanged(null);
            },
          ),
        ),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Совпадений нет'),
          ),
        for (final option in matches)
          MenuItemButton(
            closeOnActivate: true,
            onPressed: () {
              setState(() {
                _query = '';
                _search.clear();
              });
              widget.onChanged(option.id);
            },
            child: Text(
              option.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            final box = context.findRenderObject() as RenderBox;
            setState(() => _width = box.size.width);
            controller.open();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          isEmpty: selected == null && _query.isEmpty,
          isFocused: controller.isOpen,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: invalid ? 'Выберите запись из списка' : null,
            suffixIcon: Icon(
              controller.isOpen
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
          ),
          child: Text(
            invalid ? _query : selected?.label ?? 'Выберите из списка',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

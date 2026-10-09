import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF-документ для просмотра: ключ (повторное открытие того же документа
/// только выбирает его вкладку), название вкладки и загрузка содержимого.
final class PdfViewerSource {
  const PdfViewerSource({
    required this.id,
    required this.title,
    required this.load,
  });

  final String id;

  /// Название вкладки (обычно имя файла).
  final String title;

  /// Загружает байты документа; ошибка показывается внутри вкладки.
  final Future<Uint8List> Function() load;
}

/// Строит область просмотра загруженного PDF. Тесты подменяют её, чтобы не
/// требовать PDFium.
typedef PdfViewerBuilder =
    Widget Function(BuildContext context, Uint8List bytes, String title);

/// Просмотр PDF на PDFium (`pdfrx`): прокрутка страниц, масштаб и полосы
/// прокрутки.
Widget defaultPdfViewerBuilder(
  BuildContext context,
  Uint8List bytes,
  String title,
) => _PdfDocumentView(bytes: bytes, title: title);

final class _PdfDocumentView extends StatefulWidget {
  const _PdfDocumentView({required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  @override
  State<_PdfDocumentView> createState() => _PdfDocumentViewState();
}

final class _PdfDocumentViewState extends State<_PdfDocumentView> {
  final viewer = PdfViewerController();
  // PDFium загружается только при первом настоящем просмотре документа.
  static Future<void>? _initialization;
  late final ready = _initialization ??= pdfrxFlutterInitialize(
    dismissPdfiumWasmWarnings: true,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Не удалось загрузить модуль просмотра PDF.'),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return _viewer();
    },
  );

  Widget _viewer() => PdfViewer.data(
    widget.bytes,
    sourceName: widget.title,
    controller: viewer,
    params: PdfViewerParams(
      // Вертикальная полоса видна, когда документ не помещается по высоте,
      // горизонтальная — когда страница шире окна (узкое окно или масштаб).
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        PdfViewerScrollThumb(
          controller: viewer,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(10, 64),
          thumbBuilder: _thumb,
        ),
        PdfViewerScrollThumb(
          controller: viewer,
          orientation: ScrollbarOrientation.bottom,
          thumbSize: const Size(64, 10),
          thumbBuilder: _thumb,
        ),
      ],
    ),
  );

  static Widget _thumb(
    BuildContext context,
    Size thumbSize,
    int? pageNumber,
    PdfViewerController controller,
  ) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC8FA4C2),
        borderRadius: BorderRadius.circular(5),
      ),
    ),
  );
}

/// Открывает [documents] в плавающем окне просмотра. Окно не модальное:
/// программой можно пользоваться дальше, окно перемещается за заголовок,
/// меняет размер за края и закрывается только крестиком. Если окно уже
/// открыто, документы добавляются в него вкладками.
///
/// Окно живёт в ближайшем [PdfViewerHost] (рабочая область) и закрывается
/// вместе с ним, например при выходе. Без хоста — в корневом [Overlay].
void openPdfViewer(
  BuildContext context, {
  required List<PdfViewerSource> documents,
  int initialIndex = 0,
  PdfViewerBuilder viewerBuilder = defaultPdfViewerBuilder,
}) {
  if (documents.isEmpty) return;
  final windows =
      context.findAncestorStateOfType<_PdfViewerHostState>()?.windows ??
      _overlayWindows(context);
  windows.open(
    documents,
    initialIndex: initialIndex.clamp(0, documents.length - 1),
    viewerBuilder: viewerBuilder,
  );
}

final Expando<PdfViewerWindowController> _overlayControllers = Expando();

PdfViewerWindowController _overlayWindows(BuildContext context) {
  final overlay = Overlay.of(context, rootOverlay: true);
  return _overlayControllers[overlay] ??= () {
    final controller = PdfViewerWindowController();
    overlay.insert(
      OverlayEntry(builder: (_) => _PdfWindowLayer(controller: controller)),
    );
    return controller;
  }();
}

/// Область, поверх которой открываются окна просмотра PDF.
final class PdfViewerHost extends StatefulWidget {
  const PdfViewerHost({required this.child, super.key});

  final Widget child;

  @override
  State<PdfViewerHost> createState() => _PdfViewerHostState();
}

final class _PdfViewerHostState extends State<PdfViewerHost> {
  final windows = PdfViewerWindowController();

  @override
  void dispose() {
    windows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: widget.child),
      _PdfWindowLayer(controller: windows),
    ],
  );
}

/// Состояние окна просмотра: вкладки, выбранная вкладка, положение и размер.
final class PdfViewerWindowController extends ChangeNotifier {
  final List<PdfViewerSource> documents = [];
  int selected = 0;
  PdfViewerBuilder viewerBuilder = defaultPdfViewerBuilder;

  /// Положение и размер окна; `null` — ещё не размещено (займёт правую
  /// половину области).
  Rect? bounds;
  bool maximized = false;

  bool get isOpen => documents.isNotEmpty;

  void open(
    List<PdfViewerSource> sources, {
    required int initialIndex,
    required PdfViewerBuilder viewerBuilder,
  }) {
    this.viewerBuilder = viewerBuilder;
    String? focus;
    for (final (index, source) in sources.indexed) {
      if (!documents.any((item) => item.id == source.id)) {
        documents.add(source);
      }
      if (index == initialIndex) focus = source.id;
    }
    selected = documents.indexWhere((item) => item.id == focus);
    notifyListeners();
  }

  void select(int index) {
    selected = index;
    notifyListeners();
  }

  /// Закрывает вкладку; без вкладок окно закрывается.
  void closeTab(int index) {
    documents.removeAt(index);
    if (selected >= documents.length) selected = documents.length - 1;
    if (selected < 0) selected = 0;
    notifyListeners();
  }

  void close() {
    documents.clear();
    selected = 0;
    notifyListeners();
  }

  void toggleMaximized() {
    maximized = !maximized;
    notifyListeners();
  }

  void place(Rect value) {
    bounds = value;
    notifyListeners();
  }
}

const double _minWidth = 360;
const double _minHeight = 260;
const double _edge = 6;

final class _PdfWindowLayer extends StatelessWidget {
  const _PdfWindowLayer({required this.controller});

  final PdfViewerWindowController controller;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isOpen) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final area = Offset.zero & constraints.biggest;
            final rect = controller.maximized || area.width < 700
                ? area.deflate(8)
                : _fit(controller.bounds ?? _initial(area), area);
            // Пустое место слоя пропускает нажатия к программе под окном.
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: _PdfWindow(
                    controller: controller,
                    rect: rect,
                    area: area,
                    resizable: !controller.maximized && area.width >= 700,
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );

  static Rect _initial(Rect area) {
    final width = math.max(_minWidth, area.width * 0.48);
    return Rect.fromLTWH(area.right - width - 16, 16, width, area.height - 32);
  }

  /// Окно не меньше минимума и не уходит за пределы области (после
  /// изменения размера экрана тоже).
  static Rect _fit(Rect rect, Rect area) {
    final width = rect.width.clamp(_minWidth, math.max(_minWidth, area.width));
    final height = rect.height.clamp(
      _minHeight,
      math.max(_minHeight, area.height),
    );
    final left = rect.left.clamp(0.0, math.max(0.0, area.width - width));
    final top = rect.top.clamp(0.0, math.max(0.0, area.height - height));
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }
}

final class _PdfWindow extends StatelessWidget {
  const _PdfWindow({
    required this.controller,
    required this.rect,
    required this.area,
    required this.resizable,
  });

  final PdfViewerWindowController controller;
  final Rect rect;
  final Rect area;
  final bool resizable;

  /// Несколько событий указателя могут прийти до перестройки, поэтому
  /// сдвиги считаются от сохранённых границ, а не от [rect] этой сборки.
  Rect get _current => controller.bounds ?? rect;

  void _move(DragUpdateDetails details) => controller.place(
    _PdfWindowLayer._fit(_current.shift(details.delta), area),
  );

  void _resize(DragUpdateDetails details, Alignment side) {
    final current = _current;
    var left = current.left, top = current.top, right = current.right;
    var bottom = current.bottom;
    final delta = details.delta;
    if (side.x < 0) {
      left = math.min(left + delta.dx, right - _minWidth);
    }
    if (side.x > 0) right = math.max(right + delta.dx, left + _minWidth);
    if (side.y < 0) {
      top = math.min(top + delta.dy, bottom - _minHeight);
    }
    if (side.y > 0) bottom = math.max(bottom + delta.dy, top + _minHeight);
    controller.place(
      Rect.fromLTRB(
        math.max(0, left),
        math.max(0, top),
        math.min(area.right, right),
        math.min(area.bottom, bottom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = controller.documents;
    return Material(
      key: const Key('pdf-viewer-window'),
      elevation: 12,
      color: const Color(0xFF111A26),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            children: [
              _header(context),
              const Divider(height: 1),
              Expanded(
                child: IndexedStack(
                  index: controller.selected,
                  children: [
                    for (final document in documents)
                      _PdfViewerTab(
                        key: ValueKey(document.id),
                        source: document,
                        viewerBuilder: controller.viewerBuilder,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (resizable) ..._resizeHandles(),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => GestureDetector(
    key: const Key('pdf-viewer-drag'),
    behavior: HitTestBehavior.opaque,
    // Перемещение за заголовок. Двойного нажатия нет: оно задерживало бы
    // нажатия на вкладки на время ожидания второго касания.
    onPanUpdate: resizable ? _move : null,
    child: MouseRegion(
      cursor: resizable ? SystemMouseCursors.move : MouseCursor.defer,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.picture_as_pdf_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (index, document)
                        in controller.documents.indexed)
                      _TabChip(
                        key: ValueKey('pdf-viewer-tab-${document.id}'),
                        title: document.title,
                        selected: index == controller.selected,
                        onSelect: () => controller.select(index),
                        // Одиночный документ закрывается крестиком окна.
                        onClose: controller.documents.length > 1
                            ? () => controller.closeTab(index)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: controller.maximized ? 'Восстановить' : 'Развернуть',
              onPressed: controller.toggleMaximized,
              icon: Icon(
                controller.maximized ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
              ),
            ),
            IconButton(
              key: const Key('pdf-viewer-close'),
              tooltip: 'Закрыть',
              onPressed: controller.close,
              icon: const Icon(Icons.close, size: 20),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    ),
  );

  List<Widget> _resizeHandles() {
    Widget handle(Alignment side, MouseCursor cursor) {
      final horizontal = side.x == 0;
      final vertical = side.y == 0;
      return Positioned(
        left: side.x > 0 ? null : 0,
        right: side.x < 0 ? null : 0,
        top: side.y > 0 ? null : 0,
        bottom: side.y < 0 ? null : 0,
        width: horizontal ? null : _edge * (side.y == 0 ? 1 : 2),
        height: vertical ? null : _edge * (side.x == 0 ? 1 : 2),
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => _resize(details, side),
          ),
        ),
      );
    }

    return [
      handle(Alignment.centerLeft, SystemMouseCursors.resizeLeftRight),
      handle(Alignment.centerRight, SystemMouseCursors.resizeLeftRight),
      handle(Alignment.topCenter, SystemMouseCursors.resizeUpDown),
      handle(Alignment.bottomCenter, SystemMouseCursors.resizeUpDown),
      handle(Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
      handle(Alignment.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
      handle(Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
      handle(Alignment.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
    ];
  }
}

final class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.title,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  final String title;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Material(
      color: selected ? const Color(0xFF1E3A5F) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 6, onClose == null ? 10 : 2, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (onClose != null)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _PdfViewerTab extends StatefulWidget {
  const _PdfViewerTab({
    required this.source,
    required this.viewerBuilder,
    super.key,
  });

  final PdfViewerSource source;
  final PdfViewerBuilder viewerBuilder;

  @override
  State<_PdfViewerTab> createState() => _PdfViewerTabState();
}

final class _PdfViewerTabState extends State<_PdfViewerTab> {
  late Future<Uint8List> bytes = widget.source.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось открыть документ.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => bytes = widget.source.load()),
                child: const Text('Повторить'),
              ),
            ],
          ),
        );
      }
      final data = snapshot.data;
      if (data == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.viewerBuilder(context, data, widget.source.title);
    },
  );
}

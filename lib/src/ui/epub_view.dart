import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:epub_view/src/data/epub_parser.dart';
import 'package:epub_view/src/data/models/chapter.dart';
import 'package:epub_view/src/data/models/chapter_view_value.dart';
import 'package:epub_view/src/data/models/page_position.dart';
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:epub_view/src/helpers/size_reporting_widget.dart';
import 'package:epubx/src/schema/opf/epub_manifest_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../data/models/hightlight_text.dart';
import '../helpers/widget_onload_reporting.dart';

export 'package:epubx/epubx.dart' hide Image;

part '../epub_controller.dart';
part '../helpers/epub_view_builders.dart';

const _minTrailingEdge = 0.55;
const _minLeadingEdge = -0.05;

typedef ExternalLinkPressed = void Function(String href);

class EpubView extends StatefulWidget {
  const EpubView({
    required this.controller,
    this.onExternalLinkPressed,
    this.onChapterChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const EpubViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black,
    this.fontFamily,
    this.selectionToolbar,
    this.onSelectionChanged,
    this.initialPosition,
    this.highlights,
    this.onHighlightPressed,
    this.onPointerUp,
    this.isFullscreen = false,
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;

  final void Function(EpubChapterViewValue? value)? onChapterChanged;

  /// Called when a document is loaded
  final void Function(EpubBook document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;
  final void Function(PointerUpEvent event)? onPointerUp;

  /// Builders
  final EpubViewBuilders builders;

  final Color backgroundColor;
  final Color foregroundColor;
  final String? fontFamily;
  final TextSelectionControls? selectionToolbar;
  final Function(SelectedContent?)? onSelectionChanged;
  final EpubPagePosition? initialPosition;
  final List<HighlightedText>? highlights;
  final Function(HighlightedText?)? onHighlightPressed;

  final bool isFullscreen;

  @override
  State<EpubView> createState() => _EpubViewState();
}

class _EpubViewState extends State<EpubView> {
  Exception? _loadingError;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionListener;
  List<EpubChapter> _chapters = [];
  List<Paragraph> _paragraphs = [];
  // List<Capitulo> _capitulos = [];
  EpubCfiReader? _epubCfiReader;
  EpubChapterViewValue? _currentValue;
  final _chapterIndexes = <int>[];
  late final PageController pageController;
  ScrollController scrollController = ScrollController();
  // List<PageController> scrollControllers = [];

  List<EpubPage> get pages => widget.controller.pages;
  Map<String, GlobalKey> pagesKey = {};
  Map<int, GlobalKey> paragraphKeys = {};
  double pageWidth = 0;

  EpubController get _controller => widget.controller;
  List<HighlightedText> get highlights => widget.highlights ?? [];

  bool loadedInitialPage = false;

  num fontSize = 5;

  @override
  void initState() {
    super.initState();

    pageController = PageController();

    _itemScrollController = ItemScrollController();
    _itemPositionListener = ItemPositionsListener.create();
    _controller._attach(this);
    _controller.loadingState.addListener(() {
      switch (_controller.loadingState.value) {
        case EpubViewLoadingState.loading:
          break;
        case EpubViewLoadingState.success:
          widget.onDocumentLoaded?.call(_controller._document!);
          break;
        case EpubViewLoadingState.error:
          widget.onDocumentError?.call(_loadingError);
          break;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant EpubView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // _controller.isBookLoaded.value = false;
  }

  @override
  void dispose() {
    _itemPositionListener!.itemPositions.removeListener(_changeListener);
    _controller._detach();

    // for (var controller in scrollControllers) {
    //   controller.dispose();
    // }

    pageController.dispose();

    super.dispose();
  }

  Future<bool> init() async {
    if (_controller.isBookLoaded.value) {
      return true;
    }

    // for (var i = 0; i < pages.length; i++) {
    //   scrollControllers.add(PageController());
    // }

    _chapters = parseChapters(_controller._document!);

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: _controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );

    _itemPositionListener!.itemPositions.addListener(_changeListener);
    _controller.isBookLoaded.value = true;

    return true;
  }

  void update() {
    print('Atualizando o leitor');
    setState(() {});
  }

  // void _checkScrollPosition(int index) {
  //   log('_checkScrollPosition($index)');
  //   final scrollController = scrollControllers[index];
  //   int innerPages = (scrollController.position.maxScrollExtent / pageWidth).round();

  //   if (scrollController.position.pixels == scrollController.position.maxScrollExtent) {
  //     if (index == scrollControllers.length - 1) {
  //       pageController.nextPage(
  //         duration: const Duration(milliseconds: 300),
  //         curve: Curves.ease,
  //       );
  //     }
  //   }
  // }

  void nextPage() {
    log('nextPage()');
    if (pageController.hasClients) {
      pageController.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.ease);
    }

    // var scroll = scrollControllers[pageController.page!.round()];
    // if (scroll.position.pixels < scroll.position.maxScrollExtent) {
    //   print('avancando a page interna');
    //   scroll.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.ease);
    // } else {
    //   pageController.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.ease);
    // }

    // updatePagePosition();
  }

  void prevPage() {
    if (pageController.hasClients) {
      pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.ease);
    }
  }

  int get totalPages {
    log('totalPages');
    if (!pageController.hasClients) return 0;

    double viewport = pageController.position.viewportDimension;
    print(pageController.position.maxScrollExtent);
    return (pageController.position.maxScrollExtent ~/ pageWidth).round();
  }

  void updateTotalPages() {
    log('updateTotalPages');
    _controller.totalPages.value = totalPages;
  }

  void updatePagePosition() {
    if (!mounted) return;
    log('updatePagePosition()');

    if (pageController.hasClients) {
      _controller.currentPage.value = pageController.page!.round();
    } else {
      _controller.currentPage.value = 1;
    }
  }

  bool avancouPrimeiraPagina = false;
  Future<void> gotoInitialPage() async {
    if (avancouPrimeiraPagina) return;
    log('gotoInitialPage');

    if (widget.initialPosition != null) {
      if (widget.initialPosition!.page < totalPages) {
        pageController.jumpToPage(widget.initialPosition!.page);
      } else {
        pageController.jumpToPage(totalPages - 1);
      }
    }

    avancouPrimeiraPagina = true;
  }

  void navigateToParagraph(int index) {
    if (pageController.hasClients && paragraphKeys[index] != null) {
      Scrollable.ensureVisible(paragraphKeys[index]!.currentContext!);
    }
  }

  void navigateToPage(int page, [double? scroll]) {
    log('navigateToPage($page)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pageController.jumpToPage(page);
    });
  }

  void navigateToNamedPage(String filename) {
    log('navigateToNamedPage($filename)');
    var pageKey = pagesKey[filename];
    if (pageKey != null && pageController.hasClients) {
      Scrollable.ensureVisible(pageKey.currentContext!);
    }
  }

  void increaseFontSize() {
    log('increaseFontSize');
    setState(() {
      if (fontSize < 7) {
        fontSize += 1;
      }
    });
  }

  void decreaseFontSize() {
    log('decreaseFontSize');
    setState(() {
      if (fontSize > 1) {
        fontSize -= 1;
      }
    });
  }

  void _changeListener() {
    if (_paragraphs.isEmpty || _itemPositionListener!.itemPositions.value.isEmpty) {
      return;
    }
    final position = _itemPositionListener!.itemPositions.value.first;
    final chapterIndex = _getChapterIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    final paragraphIndex = _getParagraphIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    _currentValue = EpubChapterViewValue(
      chapter: chapterIndex >= 0 ? _chapters[chapterIndex] : null,
      chapterNumber: chapterIndex + 1,
      paragraphNumber: paragraphIndex + 1,
      position: position,
    );
    _controller.currentValueListenable.value = _currentValue;
    widget.onChapterChanged?.call(_currentValue);
  }

  void _gotoEpubCfi(
    String? epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubCfiReader?.epubCfi = epubCfi;
    final index = _epubCfiReader?.paragraphIndexByCfiFragment;

    if (index == null) {
      return;
    }

    _itemScrollController?.scrollTo(
      index: index,
      duration: duration,
      alignment: alignment,
      curve: curve,
    );
  }

  void _onLinkPressed(String href) {
    if (href.contains('://')) {
      widget.onExternalLinkPressed?.call(href);
    } else {
      href = href.replaceFirst('../', '');
      final page = _controller.pages.firstWhereOrNull((element) => element.fileName.endsWith(href));
      if (page != null) {
        navigateToPage(page.index - 1);
        setState(() {});
      }
    }
  }

  int _getChapterIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );
    final index = posIndex >= _chapterIndexes.last
        ? _chapterIndexes.length
        : _chapterIndexes.indexWhere((chapterIndex) {
            if (posIndex < chapterIndex) {
              return true;
            }
            return false;
          });

    return index - 1;
  }

  int _getParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );

    final index = _getChapterIndexBy(positionIndex: posIndex);

    if (index == -1) {
      return posIndex;
    }

    return posIndex - _chapterIndexes[index];
  }

  int _getAbsParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    int posIndex = positionIndex;
    if (trailingEdge != null && leadingEdge != null && trailingEdge < _minTrailingEdge && leadingEdge < _minLeadingEdge) {
      posIndex += 1;
    }

    return posIndex;
  }

  CustomRenderMatcher marcadorTagMatcher() => (context) {
        return (context.tree.element?.localName == 'span' && context.tree.element?.classes.contains('highlight') == true);
      };
  CustomRenderMatcher paragrafoTagMatcher() => (context) {
        List<String> tags = ['p', 'h3', 'h1', 'li'];
        bool isText = (tags.contains(context.tree.element?.localName) && (context.tree.element?.classes.contains('imagem') == false) ||
            (context.tree.element?.classes.contains('capitulo') == true));
        return isText;
      };
  List<InlineSpan> _getListElementChildren(ListStylePosition? position, Function() buildChildren) {
    List<InlineSpan> children = buildChildren.call();
    if (position == ListStylePosition.inside) {
      const tabSpan = WidgetSpan(
        child: Text("\t", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w400)),
      );
      children.insert(0, tabSpan);
    }
    return children;
  }

  Widget itemParagraph(Paragraph ph, int page) {
    return Listener(
      onPointerUp: widget.onPointerUp,
      onPointerDown: (event) => _controller.paragraphTouched = ph.paragraphIndex,
      child: SelectionArea(
        selectionControls: widget.selectionToolbar,
        onSelectionChanged: widget.onSelectionChanged,
        child: Html(
          shrinkWrap: true,
          data: ph.element.outerHtml,
          onLinkTap: (href, _, __, ___) => _onLinkPressed(href!),
          style: {
            '*': Style(
              color: widget.foregroundColor,
              fontFamily: widget.fontFamily,
              fontSize: numberToFontSize('$fontSize'),
              textAlign: TextAlign.justify,
            ),
            'a': Style(textDecoration: TextDecoration.none),
          },
          customRenders: {
            paragrafoTagMatcher(): CustomRender.inlineSpan(inlineSpan: (context, buildChildren) {
              var originalText = context.tree.element?.text.trim();

              if (originalText == null || originalText.trim() == "") {
                return const TextSpan();
              }

              // var originalText = (context.tree as TextContentElement).text?.trim();
              var marcacoesNaPage = highlights.where((element) => element.paragraphIndex == ph.paragraphIndex).toList();
              // caso não tenha nenhuma marcação, exibe apenas o texto limpo
              if (marcacoesNaPage.isEmpty) {
                return WidgetSpan(
                  child: CssBoxWidget(
                    key: context.key,
                    style: Style(),
                    shrinkWrap: context.parser.shrinkWrap,
                    child: CssBoxWidget.withInlineSpanChildren(
                      style: context.tree.style,
                      children: [
                        if (context.tree.element?.localName == 'li') const TextSpan(text: '\t•\t'),
                        TextSpan(
                          text: originalText,
                          style: context.style.generateTextStyle(),
                        )
                      ],
                    ),
                  ),
                );
              }

              String marcacoes = marcacoesNaPage.map((e) => e.text).map((e) => '($e)').join('|').toString();
              RegExp regex = RegExp(marcacoes);

              Iterable<Match> matches = regex.allMatches(originalText);

              int lastIndex = 0;
              List<InlineSpan> children = [];

              for (Match match in matches) {
                int startIndex = match.start;
                int endIndex = match.end;

                String? trechoAntes = originalText.substring(lastIndex, startIndex);
                String? trechoMarcado = match.group(0);

                var high = marcacoesNaPage.firstWhere((element) => element.text == trechoMarcado);

                Color textColor = Colors.black;

                if (high.color == const Color(0xFF003B65)) {
                  textColor = Colors.white;
                }

                children.add(TextSpan(text: trechoAntes));

                if (trechoMarcado != null && trechoMarcado != "") {
                  children.add(TextSpan(
                    text: trechoMarcado,
                    style: TextStyle(color: textColor, backgroundColor: high.color),
                    recognizer: TapGestureRecognizer()..onTap = () => widget.onHighlightPressed?.call(high),
                  ));

                  if (originalText.substring(match.end, (match.end < originalText.length ? match.end + 1 : originalText.length)) == " ") {
                    // adiciona um espaço
                    children.add(const TextSpan(text: '\r'));
                  }
                }

                lastIndex = endIndex;
              }

              if (lastIndex < (originalText.length)) {
                String trechoDepois = originalText.substring(lastIndex).trim();
                if (trechoDepois != "") {
                  children.add(TextSpan(text: trechoDepois));
                }
              }

              return WidgetSpan(
                child: CssBoxWidget(
                  key: context.key,
                  style: context.tree.style,
                  shrinkWrap: context.parser.shrinkWrap,
                  child: CssBoxWidget.withInlineSpanChildren(
                    style: context.tree.style,
                    children: [
                      if (context.tree.element?.localName == 'li') const TextSpan(text: '\t•\t'),
                      ...children,
                    ],
                  ),
                ),
              );
            }),
            tagMatcher('img'): CustomRender.widget(widget: (context, buildChildren) {
              final url = context.tree.element!.attributes['src']!.replaceAll('../', '');
              if (pages[ph.pageIndex].fileName.endsWith('capa.xhtml') ||
                  pages[ph.pageIndex].fileName.endsWith('rosto.xhtml') ||
                  pages[ph.pageIndex].fileName.contains('capa')) {
                return Container(
                  alignment: Alignment.center,
                  // height: constraints.maxHeight,
                  child: Image(
                    image: MemoryImage(Uint8List.fromList(widget.controller._document!.Content!.Images![url]!.Content!)),
                    fit: BoxFit.cover,
                  ),
                );
              }

              return Container(
                alignment: Alignment.center,
                child: Image(
                  image: MemoryImage(Uint8List.fromList(widget.controller._document!.Content!.Images![url]!.Content!)),
                  fit: BoxFit.cover,
                ),
              );
            }),
            marcadorTagMatcher(): CustomRender.inlineSpan(inlineSpan: (context, children) {
              final element = context.tree.element!;
              final highlightId = element.attributes['highlight-id'];
              // final textColor = element.attributes['text-color'];
              final Color textColor = Color(int.parse(element.attributes['text-color']!));
              final Color bgColor = Color(int.parse(element.attributes['bg-color']!));

              if (highlightId != null) {
                final highlight = highlights.firstWhereOrNull((element) => element.id == int.tryParse(highlightId));
                if (highlight != null) {
                  return TextSpan(
                    text: context.tree.element?.text ?? "",
                    style: context.style.generateTextStyle().copyWith(color: textColor, backgroundColor: bgColor),
                    recognizer: TapGestureRecognizer()..onTap = () => widget.onHighlightPressed?.call(highlight),
                  );
                }
              }

              return TextSpan(
                text: context.tree.element?.text ?? "",
                style: context.style.generateTextStyle(),
              );
            }),
          },
        ),
      ),
    );
  }

  List<Widget> pagesWidgetsFullscreen = [];
  List<Widget> pagesWidgets = [];

  Widget _buildLoaded(BuildContext context) {
    final defaultBuilder = widget.builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return Container(
      margin: !widget.isFullscreen ? const EdgeInsets.all(25) : const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        boxShadow: !widget.isFullscreen
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
        borderRadius: BorderRadius.circular(20),
        border: !widget.isFullscreen ? Border.all(color: Colors.grey.shade300) : null,
        color: widget.isFullscreen ? null : widget.backgroundColor,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          pageWidth = constraints.maxWidth;

          if (pagesWidgets.isEmpty && !widget.isFullscreen) {
            pagesWidgets = pages.map((page) {
              // adiciona uma key no Wrap e salva na lista com o nome da page
              if (pagesKey[page.fileName] == null) {
                pagesKey[page.fileName] = GlobalKey();
              }

              return SliverToBoxAdapter(
                child: Wrap(
                  key: pagesKey[page.fileName],
                  direction: Axis.vertical,
                  children: page.paragraphs.map((e) {
                    // adiciona a key para o paragraph específico
                    if (paragraphKeys[e.paragraphIndex] == null) {
                      paragraphKeys[e.paragraphIndex] = GlobalKey();
                    }

                    return SizedBox(
                      key: paragraphKeys[e.paragraphIndex],
                      width: constraints.maxWidth,
                      child: itemParagraph(e, page.index),
                    );
                  }).toList(),
                ),
              );
            }).toList();
          }

          if (pagesWidgetsFullscreen.isEmpty && widget.isFullscreen) {
            pagesWidgetsFullscreen = pages.map((page) {
              // adiciona uma key no Wrap e salva na lista com o nome da page
              if (pagesKey[page.fileName] == null) {
                pagesKey[page.fileName] = GlobalKey();
              }

              return SliverToBoxAdapter(
                child: Wrap(
                  key: pagesKey[page.fileName],
                  direction: Axis.vertical,
                  children: page.paragraphs.map((e) {
                    // adiciona a key para o paragraph específico
                    if (paragraphKeys[e.paragraphIndex] == null) {
                      paragraphKeys[e.paragraphIndex] = GlobalKey();
                    }

                    return SizedBox(
                      key: paragraphKeys[e.paragraphIndex],
                      width: constraints.maxWidth,
                      child: itemParagraph(e, page.index),
                    );
                  }).toList(),
                ),
              );
            }).toList();
          }

          return SizedBox(
            height: constraints.maxHeight,
            child: ValueListenableBuilder<bool>(
              valueListenable: _controller.isBookLoaded,
              builder: (_, isReady, child) => isReady ? child! : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              child: NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification notification) {
                  if (notification is ScrollEndNotification) {
                    updatePagePosition();
                  }

                  return true;
                },
                child: SizeReportingWidget(
                  onSizeChange: (_) {
                    gotoInitialPage();
                    Future.delayed(const Duration(seconds: 1), () => updateTotalPages());
                  },
                  child: CustomScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const PageScrollPhysics(),
                    controller: pageController,
                    slivers: pages.map((page) {
                      // adiciona uma key no Wrap e salva na lista com o nome da page
                      if (pagesKey[page.fileName] == null) {
                        pagesKey[page.fileName] = GlobalKey();
                      }

                      return SliverToBoxAdapter(
                        child: Wrap(
                          key: pagesKey[page.fileName],
                          direction: Axis.vertical,
                          children: page.paragraphs.map((e) {
                            // adiciona a key para o paragraph específico
                            if (paragraphKeys[e.paragraphIndex] == null) {
                              paragraphKeys[e.paragraphIndex] = GlobalKey();
                            }

                            return SizedBox(
                              key: paragraphKeys[e.paragraphIndex],
                              width: constraints.maxWidth,
                              child: itemParagraph(e, page.index),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _builder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubViewLoadingState state,
    WidgetBuilder loadedBuilder,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case EpubViewLoadingState.loading:
          return KeyedSubtree(
            key: const Key('epubx.root.loading'),
            child: builders.loaderBuilder?.call(context) ?? const SizedBox(),
          );
        case EpubViewLoadingState.error:
          return KeyedSubtree(
            key: const Key('epubx.root.error'),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: builders.errorBuilder?.call(context, loadingError!) ?? Center(child: Text(loadingError.toString())),
            ),
          );
        case EpubViewLoadingState.success:
          return KeyedSubtree(
            key: const Key('epubx.root.success'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _loadingError,
    );
  }
}

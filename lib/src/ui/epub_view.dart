import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:epub_view/src/data/epub_parser.dart';
import 'package:epub_view/src/data/models/chapter.dart';
import 'package:epub_view/src/data/models/chapter_view_value.dart';
import 'package:epub_view/src/data/models/page_position.dart';
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

export 'package:epubx/epubx.dart' hide Image;
import 'package:epubx/src/schema/opf/epub_manifest_item.dart';

import '../data/models/hightlight_text.dart';

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
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;

  final void Function(EpubChapterViewValue? value)? onChapterChanged;

  /// Called when a document is loaded
  final void Function(EpubBook document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;

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

  List<EpubPage> get pages => widget.controller.pages;

  EpubController get _controller => widget.controller;
  List<HighlightedText> get highlights => widget.highlights ?? [];

  @override
  void initState() {
    super.initState();

    pageController = PageController(initialPage: widget.initialPosition?.page ?? 0);
    if (widget.initialPosition != null) {
      updatePagePosition(widget.initialPosition!.page);
    }

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
  void dispose() {
    _itemPositionListener!.itemPositions.removeListener(_changeListener);
    _controller._detach();
    super.dispose();
  }

  Future<bool> _init() async {
    if (_controller.isBookLoaded.value) {
      return true;
    }

    scrollController.addListener(() => updateScrollPosition());

    _chapters = parseChapters(_controller._document!);

    // _capitulos = parseParagraphs(_chapters, _controller._document!.Content);
    // _paragraphs = _capitulos.fold([], (acc, next) {
    //   acc.addAll(next.paragraphs);
    //   return acc;
    // });

    // _paragraphs = parseParagraphsResult.flatParagraphs;
    // _chapterIndexes.addAll(parseParagraphsResult.chapterIndexes);
    // pageController.addListener(() {
    //   final currentPage = pages.firstWhereIndexedOrNull((i, a) => i == pageController.page?.round())?.fileName;
    //   if (currentPage != null) {
    //     final position = PagePosition(
    //       page: currentPage,
    //       scrollPosition: 0.0,
    //     );

    //     print(position.toJson());
    //   }
    // });

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: _controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );
    _itemPositionListener!.itemPositions.addListener(_changeListener);
    _controller.isBookLoaded.value = true;

    return true;
  }

  void updatePagePosition(int page) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.position.value = EpubPagePosition(
        page: page,
        totalPages: widget.controller.totalPages,
        scrollPosition: 0,
      );
    });
  }

  Timer? delayUpdateScroll;

  void updateScrollPosition() async {
    if (delayUpdateScroll != null) {
      delayUpdateScroll!.cancel();
    }

    delayUpdateScroll = Timer(const Duration(seconds: 1), () {
      log('delayUpdateScroll');
      delayUpdateScroll = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.position.value = EpubPagePosition(
          page: pageController.page?.round() ?? 0,
          totalPages: widget.controller.totalPages,
          scrollPosition: scrollController.offset.round(),
        );
      });
    });
  }

  void navigateToPage(int page, [int? scroll]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pageController.animateToPage(page, duration: const Duration(milliseconds: 350), curve: Curves.ease).then((value) {
        if (scroll != null) {
          scrollController.jumpTo(scroll.toDouble());
        }
      });
    });
  }

  void increaseFontSize() {}

  void decreaseFontSize() {}

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
      return;
    }

    // Chapter01.xhtml#ph1_1 -> [ph1_1, Chapter01.xhtml] || [ph1_1]
    String? hrefIdRef;
    String? hrefFileName;

    if (href.contains('#')) {
      final dividedHref = href.split('#');
      if (dividedHref.length == 1) {
        hrefIdRef = href;
      } else {
        hrefFileName = dividedHref[0];
        hrefIdRef = dividedHref[1];
      }
    } else {
      hrefFileName = href;
    }

    if (hrefIdRef == null) {
      final chapter = _chapterByFileName(hrefFileName);
      if (chapter != null) {
        final cfi = _epubCfiReader?.generateCfiChapter(
          book: _controller._document,
          chapter: chapter,
          additional: ['/4/2'],
        );

        _gotoEpubCfi(cfi);
      }
      return;
    } else {
      final paragraph = _paragraphByIdRef(hrefIdRef);
      final chapter = paragraph != null ? _chapters[paragraph.chapterIndex] : null;

      if (chapter != null && paragraph != null) {
        final paragraphIndex = _epubCfiReader?.getParagraphIndexByElement(paragraph.element);
        final cfi = _epubCfiReader?.generateCfi(
          book: _controller._document,
          chapter: chapter,
          paragraphIndex: paragraphIndex,
        );

        _gotoEpubCfi(cfi);
      }

      return;
    }
  }

  Paragraph? _paragraphByIdRef(String idRef) => _paragraphs.firstWhereOrNull((paragraph) {
        if (paragraph.element.id == idRef) {
          return true;
        }

        return paragraph.element.children.isNotEmpty && paragraph.element.children[0].id == idRef;
      });

  EpubChapter? _chapterByFileName(String? fileName) => _chapters.firstWhereOrNull((chapter) {
        if (fileName != null) {
          if (chapter.ContentFileName!.contains(fileName)) {
            return true;
          } else {
            return false;
          }
        }
        return false;
      });

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

  String parseHightlights(int page, String html) {
    final hightlightsToPage = highlights.where((element) => element.pagePosition.page == page);

    for (var high in hightlightsToPage) {
      Color textColor = widget.foregroundColor;
      if (high.color.computeLuminance() < .5) {
        textColor = widget.backgroundColor;
      }

      // print(high.text);
      html = html.replaceAll(high.text,
          '<span class="highlight" highlight-id="${high.id}" text-color="${textColor.value}" style="background-color: #${high.color.value.toRadixString(16).padLeft(6, '0')}; color: #${textColor.value.toRadixString(16).padLeft(6, '0')}">${high.text}</span>');
    }

    return html;
  }

  /*
ListView.builder(
              controller: scrollController,
              scrollDirection: Axis.vertical,
              itemCount: pages[c].paragraphs.length,
              itemBuilder: (_, p) => Html(
                shrinkWrap: true,
                data: parseHightlights(c, pages[c].paragraphs[p].element.outerHtml),
                onLinkTap: (href, _, __, ___) => _onLinkPressed(href!),
                style: {
                  'html': Style(
                    padding: options.paragraphPadding as EdgeInsets?,
                    color: widget.foregroundColor,
                    fontFamily: widget.fontFamily,
                  ).merge(Style.fromTextStyle(widget.controller.textStyle)),
                },
                customRenders: {
                  tagMatcher('img'): CustomRender.widget(widget: (context, buildChildren) {
                    final url = context.tree.element!.attributes['src']!.replaceAll('../', '');
                    return Image(
                      image: MemoryImage(
                        Uint8List.fromList(widget.controller._document!.Content!.Images![url]!.Content!),
                      ),
                      fit: BoxFit.cover,
                    );
                  }),
                },
              ),
            ),
  */

  Widget _buildLoaded(BuildContext context) {
    final defaultBuilder = widget.builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return PageView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: pages.length,
      controller: pageController,
      onPageChanged: updatePagePosition,
      itemBuilder: (_, c) => Container(
        // width: pageWidth,
        // height: widget.height,
        margin: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
          color: widget.backgroundColor,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.vertical,
            itemCount: pages[c].paragraphs.length,
            itemBuilder: (_, p) => SelectionArea(
              selectionControls: widget.selectionToolbar,
              onSelectionChanged: widget.onSelectionChanged,
              child: Html(
                shrinkWrap: true,
                data: parseHightlights(c, pages[c].paragraphs[p].element.outerHtml),
                onLinkTap: (href, _, __, ___) => _onLinkPressed(href!),
                style: {
                  'html': Style(
                    // padding: options.paragraphPadding as EdgeInsets?,
                    color: widget.foregroundColor,
                    fontFamily: widget.fontFamily,
                  ).merge(Style.fromTextStyle(widget.controller.textStyle)),
                },
                customRenders: {
                  tagMatcher('img'): CustomRender.widget(widget: (context, buildChildren) {
                    final url = context.tree.element!.attributes['src']!.replaceAll('../', '');
                    return Image(
                      image: MemoryImage(
                        Uint8List.fromList(widget.controller._document!.Content!.Images![url]!.Content!),
                      ),
                      fit: BoxFit.cover,
                    );
                  }),
                  tagMatcher('span'): CustomRender.widget(widget: (context, buildChildren) {
                    final element = context.tree.element!;
                    final highlightId = element.attributes['highlight-id'];
                    // final textColor = element.attributes['text-color'];

                    if (highlightId != null) {
                      final highlight = highlights.firstWhereOrNull((element) => element.id == int.tryParse(highlightId));
                      if (highlight != null) {
                        //   return GestureDetector(
                        //     onTap: () => widget.onHighlightPressed?.call(highlight),
                        //     child: RichText(
                        //       text: TextSpan(
                        //         text: element.text,
                        //         style: widget.controller.textStyle.copyWith(fontFamily: widget.fontFamily, color: Color(int.tryParse(textColor!)!)),
                        //       ),
                        //     ),
                        //   );
                        return GestureDetector(
                          onTap: () => widget.onHighlightPressed?.call(highlight),
                          child: Html(
                            data: element.outerHtml,
                            style: {
                              '*': Style(
                                padding: EdgeInsets.zero,
                                margin: Margins.zero,
                                display: Display.inline,
                                fontFamily: widget.fontFamily,
                              ).merge(Style.fromTextStyle(widget.controller.textStyle))
                            },
                          ),
                        );
                      }
                    }

                    return Html(data: element.outerHtml);
                  }),
                },
              ),
            ),
          ),
        ),
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

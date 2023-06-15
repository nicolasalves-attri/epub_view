import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as mat;
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:epub_view/src/data/epub_parser.dart';
import 'package:epub_view/src/data/models/chapter.dart';
import 'package:epub_view/src/data/models/chapter_view_value.dart';
import 'package:epub_view/src/data/models/page_position.dart';
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
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

  List<EpubPage> get pages => widget.controller.pages;

  EpubController get _controller => widget.controller;
  List<HighlightedText> get highlights => widget.highlights ?? [];

  num fontSize = 5;

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

  void navigateToNamedPage(String filename) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final page = pages.firstWhereOrNull((e) => e.fileName == filename);
      if (page != null) {
        pageController.animateToPage(page.index - 1, duration: const Duration(milliseconds: 350), curve: Curves.ease);
      }
    });
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
    return;

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

    RegExp exp = RegExp(r'<span\b[^>]*>(.*?)</span>', multiLine: true, caseSensitive: false);
    html = html.replaceAllMapped(exp, (match) => match.group(1) ?? "");

    for (var high in hightlightsToPage) {
      Color textColor = Colors.black;

      if (high.color == const Color(0xFF003B65)) {
        textColor = Colors.white;
      }

      // if (high.color == const Color(0xFFFFFF00)) {
      //   textColor = Colors.black;
      // }

      // if (high.color.computeLuminance() > .5) {
      //   textColor = widget.foregroundColor;
      // }

      // print(high.text);
      html = html.replaceAll(high.text,
          '<span class="highlight" highlight-id="${high.id}" text-color="${textColor.value}" bg-color="${high.color.value}" style="background-color: #${high.color.value.toRadixString(16).padLeft(6, '0')}; color: #${textColor.value.toRadixString(16).padLeft(6, '0')}">${high.text}</span>');
    }

    return html;
  }

  matchesHighlights(int page, String html) {
    final hightlightsToPage = highlights.where((element) => element.pagePosition.page == page);

    for (var high in hightlightsToPage) {
      Color textColor = Colors.black;

      if (high.color == const Color(0xFF003B65)) {
        textColor = Colors.white;
      }

      // if (high.color == const Color(0xFFFFFF00)) {
      //   textColor = Colors.black;
      // }

      // if (high.color.computeLuminance() > .5) {
      //   textColor = widget.foregroundColor;
      // }

      // print(high.text);
      html = html.replaceAll(high.text,
          '<span class="highlight" highlight-id="${high.id}" text-color="${textColor.value}" bg-color="${high.color.value}" style="background-color: #${high.color.value.toRadixString(16).padLeft(6, '0')}; color: #${textColor.value.toRadixString(16).padLeft(6, '0')}">${high.text}</span>');
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

  CustomRenderMatcher marcadorTagMatcher() => (context) {
        return (context.tree.element?.localName == 'span' && context.tree.element?.classes.contains('highlight') == true);
      };
  CustomRenderMatcher paragrafoTagMatcher() => (context) {
        List<String> tags = ['p', 'h3', 'h1', 'li'];
        bool isText = (tags.contains(context.tree.element?.localName) && context.tree.element?.classes.contains('imagem') == false) ||
            (context.tree.element?.classes.contains('capitulo') == true);
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
        margin: !widget.isFullscreen ? const EdgeInsets.all(25) : const EdgeInsets.symmetric(horizontal: 25),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.vertical,
                    itemCount: pages[c].paragraphs.length,
                    itemBuilder: (_, p) => SelectionArea(
                      selectionControls: widget.selectionToolbar,
                      onSelectionChanged: widget.onSelectionChanged,
                      child: Html(
                        shrinkWrap: true,
                        data: pages[c].paragraphs[p].element.outerHtml,
                        // data: parseHightlights(c, pages[c].paragraphs[p].element.outerHtml),
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
                          // tagMatcher('a'): CustomRender.widget(widget: (context, buildChildren) {
                          //   final String? url = context.tree.element?.attributes['href'];
                          //   if (url?.startsWith('.') == true) {
                          //     return GestureDetector(
                          //       onTap: () => _onLinkPressed(url),
                          //       child: Text(context.tree.element?.text ?? ""),
                          //     );
                          //   }

                          //   return buildChildren;
                          //   return Text(context.tree.element?.text ?? "");
                          // }),
                          paragrafoTagMatcher(): CustomRender.inlineSpan(inlineSpan: (context, buildChildren) {
                            var originalText = context.tree.element?.text.trim();

                            if (originalText == null || originalText.trim() == "") {
                              return const TextSpan();
                            }

                            // var originalText = (context.tree as TextContentElement).text?.trim();
                            var marcacoesNaPage = highlights.where((element) => element.pagePosition.page == c).toList();
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

                            // buildChildren()
                            //             .map((e) => TextSpan(text: originalText, style: context.tree.style.generateTextStyle()))
                            //             .toList(),

                            // print('full: ${jsonEncode(originalText)} / ${marcacoesNaPage.length}');

                            // for (var tr in marcacoesNaPage) {
                            //   print('tr: ${jsonEncode(tr.text)}');
                            // }

                            // caso a marcação seja o paragrafo inteiro
                            // final singleHigh = marcacoesNaPage.singleWhereOrNull((element) => element.text == originalText?.trim());

                            // if (singleHigh != null) {
                            //   var high = marcacoesNaPage.first;
                            //   Color textColor = Colors.black;

                            //   if (high.color == const Color(0xFF003B65)) {
                            //     textColor = Colors.white;
                            //   }

                            //   return TextSpan(
                            //     text: originalText,
                            //     style: TextStyle(color: textColor, backgroundColor: high.color),
                            //     recognizer: TapGestureRecognizer()..onTap = () => widget.onHighlightPressed?.call(high),
                            //   );
                            // }

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

                              // if (context.tree.element?.localName == 'li') children.add(const TextSpan(text: '•\t'));

                              children.add(TextSpan(text: trechoAntes));

                              if (trechoMarcado != null && trechoMarcado != "") {
                                children.add(TextSpan(
                                  text: trechoMarcado,
                                  style: TextStyle(color: textColor, backgroundColor: high.color),
                                  recognizer: TapGestureRecognizer()..onTap = () => widget.onHighlightPressed?.call(high),
                                ));

                                if (originalText.substring(match.end, (match.end < originalText.length ? match.end + 1 : originalText.length)) ==
                                    " ") {
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

                            // var matches = regex.allMatches(originalText ?? "");
                            // for (var match in matches) {
                            //   print(match.group(0));
                            // }
                            return WidgetSpan(
                              child: CssBoxWidget(
                                key: context.key,
                                style: Style(),
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

                            if (originalText == null || originalText.trim() == "") {
                              return const TextSpan();
                            } else {
                              // var originalText = parseHightlights(c, (context.tree as TextContentElement).text ?? "");

                              return TextSpan(
                                // text: originalText,
                                children: children,
                                style: context.style.generateTextStyle(),
                              );
                            }
                          }),
                          tagMatcher('11'): CustomRender.inlineSpan(
                            inlineSpan: (context, buildChildren) {
                              return WidgetSpan(
                                child: CssBoxWidget(
                                  key: context.key,
                                  style: context.tree.style,
                                  shrinkWrap: context.parser.shrinkWrap,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    textDirection: context.tree.style.direction,
                                    children: [
                                      context.tree.style.listStylePosition == ListStylePosition.outside
                                          ? Padding(
                                              padding: context.tree.style.padding?.nonNegative ??
                                                  EdgeInsets.only(
                                                      left: (context.tree.style.direction) != TextDirection.rtl ? 10.0 : 0.0,
                                                      right: (context.tree.style.direction) == TextDirection.rtl ? 10.0 : 0.0),
                                              child: context.style.markerContent)
                                          : const SizedBox(height: 0, width: 0),
                                      const Text("\u0020", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w400)),
                                      Expanded(
                                        child: Padding(
                                          padding: (context.tree.style.listStylePosition) == ListStylePosition.inside
                                              ? EdgeInsets.only(
                                                  left: (context.tree.style.direction) != TextDirection.rtl ? 10.0 : 0.0,
                                                  right: (context.tree.style.direction) == TextDirection.rtl ? 10.0 : 0.0)
                                              : EdgeInsets.zero,
                                          child: CssBoxWidget.withInlineSpanChildren(
                                            children: _getListElementChildren(context.tree.style.listStylePosition, buildChildren)
                                              ..insertAll(
                                                  0,
                                                  context.tree.style.listStylePosition == ListStylePosition.inside
                                                      ? [
                                                          WidgetSpan(
                                                              alignment: PlaceholderAlignment.middle,
                                                              child: context.style.markerContent ?? const SizedBox(height: 0, width: 0))
                                                        ]
                                                      : []),
                                            style: context.style,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          tagMatcher('img'): CustomRender.widget(widget: (context, buildChildren) {
                            final url = context.tree.element!.attributes['src']!.replaceAll('../', '');
                            if (pages[c].fileName.endsWith('capa.xhtml') ||
                                pages[c].fileName.endsWith('rosto.xhtml') ||
                                pages[c].fileName.contains('capa')) {
                              return Container(
                                alignment: Alignment.center,
                                height: constraints.maxHeight,
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
                  )),
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

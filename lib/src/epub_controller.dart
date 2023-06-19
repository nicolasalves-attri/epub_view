part of 'ui/epub_view.dart';

class EpubController {
  EpubController({
    required this.document,
    this.epubCfi,
    this.textStyle = const TextStyle(
      height: 1.25,
      fontSize: 16,
    ),
  });

  EpubBook document;
  // Future<EpubBook> document;
  final String? epubCfi;
  TextStyle textStyle;

  _EpubViewState? _epubViewState;
  List<EpubViewChapter>? _cacheTableOfContents;
  List<EpubContentFile> get pagesFiles => getFilesFromEpubSpine(_document!);
  List<EpubPage> get pages => _document != null ? parsePages(pagesFiles, _document!) : [];
  // int get totalPages => pages.length;
  int paragraphTouched = 0;

  // int get currentPage => _epubViewState?.pageController.page?.round() ?? 0;

  EpubBook? _document;

  EpubChapterViewValue? get currentValue => _epubViewState?._currentValue;

  final isBookLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<EpubViewLoadingState> loadingState = ValueNotifier(EpubViewLoadingState.loading);

  final currentValueListenable = ValueNotifier<EpubChapterViewValue?>(null);

  // late final position = ValueNotifier<EpubPagePosition>(EpubPagePosition(page: 0, totalPages: totalPages, scrollPosition: 0));

  final currentPage = ValueNotifier<int>(0);
  // int get currentPage => _currentPage.value;

  final totalPages = ValueNotifier<int>(0);
  // int get totalPages => _totalPages.value;

  void update() => _epubViewState?.update();

  void navigateToParagraph(int index) {
    _epubViewState?.navigateToParagraph(index);
  }

  void navigateToPage(int page, [double? scroll]) {
    _epubViewState?.navigateToPage(page, scroll);
  }

  void navigateToNamedPage(String filename) {
    _epubViewState?.navigateToNamedPage(filename);
  }

  void nextPage() {
    _epubViewState?.nextPage();
  }

  void prevPage() {
    _epubViewState?.prevPage();
  }

  void increaseFontSize() {
    _epubViewState?.increaseFontSize();
  }

  void decreaseFontSize() {
    _epubViewState?.decreaseFontSize();
  }

  final tableOfContentsListenable = ValueNotifier<List<EpubViewChapter>>([]);

  Future<void>? scrollTo({
    required int index,
    Duration duration = const Duration(milliseconds: 250),
    double alignment = 0,
    Curve curve = Curves.linear,
  }) =>
      _epubViewState?._itemScrollController?.scrollTo(
        index: index,
        duration: duration,
        alignment: alignment,
        curve: curve,
      );

  void gotoEpubCfi(
    String epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubViewState?._gotoEpubCfi(
      epubCfi,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }

  String? generateEpubCfi() => _epubViewState?._epubCfiReader?.generateCfi(
        book: _document,
        chapter: _epubViewState?._currentValue?.chapter,
        paragraphIndex: _epubViewState?._getAbsParagraphIndexBy(
          positionIndex: _epubViewState?._currentValue?.position.index ?? 0,
          trailingEdge: _epubViewState?._currentValue?.position.itemTrailingEdge,
          leadingEdge: _epubViewState?._currentValue?.position.itemLeadingEdge,
        ),
      );

  List<EpubViewChapter> tableOfContents() {
    if (_cacheTableOfContents != null) {
      return _cacheTableOfContents ?? [];
    }

    if (_document == null) {
      return [];
    }

    int index = -1;

    return _cacheTableOfContents = _document!.Chapters!.fold<List<EpubViewChapter>>(
      [],
      (acc, next) {
        index += 1;
        acc.add(EpubViewChapter(next.Title, _getChapterStartIndex(index)));
        for (final subChapter in next.SubChapters!) {
          index += 1;
          acc.add(EpubViewSubChapter(subChapter.Title, _getChapterStartIndex(index)));
        }
        return acc;
      },
    );
  }

  Future<void> loadDocument(EpubBook document) {
    this.document = document;
    return _loadDocument(document);
  }

  void dispose() {
    _epubViewState = null;
    isBookLoaded.dispose();
    currentValueListenable.dispose();
    tableOfContentsListenable.dispose();
  }

  Future<void> _loadDocument(EpubBook document) async {
    isBookLoaded.value = false;
    try {
      loadingState.value = EpubViewLoadingState.loading;
      _document = document;
      await _epubViewState!.init();

      tableOfContentsListenable.value = tableOfContents();
      loadingState.value = EpubViewLoadingState.success;
    } catch (error) {
      _epubViewState!._loadingError = error is Exception ? error : Exception('Desculpe, ocorreu uma falha no leitor.');
      loadingState.value = EpubViewLoadingState.error;
    }
  }

  int _getChapterStartIndex(int index) => index < _epubViewState!._chapterIndexes.length ? _epubViewState!._chapterIndexes[index] : 0;

  void _attach(_EpubViewState epubReaderViewState) {
    _epubViewState = epubReaderViewState;

    _loadDocument(document);
  }

  void _detach() {
    _epubViewState = null;
  }
}

List<EpubContentFile> getFilesFromEpubSpine(EpubBook epubBook) {
  return getSpineItemsFromEpub(epubBook)
      .map((chapter) {
        if (epubBook.Content?.AllFiles?.containsKey(chapter.Href!) != true) {
          return null;
        }

        return epubBook.Content!.AllFiles![chapter.Href]!;
      })
      .whereType<EpubTextContentFile>()
      .toList();
}

List<EpubManifestItem> getSpineItemsFromEpub(EpubBook epubBook) {
  return epubBook.Schema!.Package!.Spine!.Items!
      .map((item) => epubBook.Schema!.Package!.Manifest!.Items!.where((element) => element.Id == item.IdRef).first)
      .toList();
}

import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:html/dom.dart' as dom;

import 'models/paragraph.dart';

export 'package:epubx/epubx.dart' hide Image;

List<EpubChapter> parseChapters(EpubBook epubBook) => epubBook.Chapters!.fold<List<EpubChapter>>(
      [],
      (acc, next) {
        acc.add(next);
        next.SubChapters!.forEach(acc.add);
        return acc;
      },
    );

List<dom.Element> convertDocumentToElements(dom.Document document) => document.getElementsByTagName('body').first.children;

List<dom.Element> _removeAllDiv(List<dom.Element> elements) {
  final List<dom.Element> result = [];

  for (final node in elements) {
    if (node.localName == 'div' && node.children.length > 1) {
      result.addAll(_removeAllDiv(node.children));
    } else {
      result.add(node);
    }
  }

  return result;
}

List<Capitulo> parseParagraphs(
  List<EpubChapter> chapters,
  EpubContent? content,
) {
  String? filename = '';
  List<Capitulo> capitulos = [];
  List<int> chapterIndexes = [];
  int chapterIndex = 0;

  for (var next in chapters) {
    List<Paragraph> paragrafos = [];
    List<dom.Element> elmList = [];
    if (filename != next.ContentFileName) {
      filename = next.ContentFileName;
      final document = EpubCfiReader().chapterDocument(next);
      if (document != null) {
        final result = convertDocumentToElements(document);
        elmList = _removeAllDiv(result);
      }
    }

    chapterIndex++;
    paragrafos.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
    capitulos.add(Capitulo(index: chapterIndex, chapter: next, paragraphs: paragrafos));
    // chapterIndexes.add(acc.length);
    // acc.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
  }

  return capitulos;

  final paragraphs = chapters.fold<List<Paragraph>>(
    [],
    (acc, next) {
      print('paragraphs: ${acc.length}');

      List<dom.Element> elmList = [];
      if (filename != next.ContentFileName) {
        filename = next.ContentFileName;
        final document = EpubCfiReader().chapterDocument(next);
        if (document != null) {
          final result = convertDocumentToElements(document);
          elmList = _removeAllDiv(result);
        }
      }

      if (next.Anchor == null) {
        // last element from document index as chapter index
        chapterIndexes.add(acc.length);
        acc.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      } else {
        final index = elmList.indexWhere(
          (elm) => elm.outerHtml.contains(
            'id="${next.Anchor}"',
          ),
        );
        if (index == -1) {
          chapterIndexes.add(acc.length);
          acc.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
          return acc;
        }

        chapterIndexes.add(index);
        acc.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      }
    },
  );

  // return ParseParagraphsResult(paragraphs, chapterIndexes);
}

class ParseParagraphsResult {
  ParseParagraphsResult(this.flatParagraphs, this.chapterIndexes);

  final List<Paragraph> flatParagraphs;
  final List<int> chapterIndexes;
}

class ParseChapterResult {
  ParseChapterResult(this.chapter, this.paragraphs);
  final EpubChapter chapter;
  final List<Paragraph> paragraphs;
  // final List<int> chapterIndexes;
}

class Capitulo {
  final int index;
  final EpubChapter chapter;
  List<Paragraph> paragraphs;

  Capitulo({required this.index, required this.chapter, required this.paragraphs});

  void addParagraph(Paragraph paragraph) {
    paragraphs.add(paragraph);
  }
}

import 'dart:convert';
import 'dart:developer';

import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/dom.dart';

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

List<EpubPage> parsePages(List<EpubContentFile> contentPages, EpubBook epubBook) {
  String? filename = '';
  List<EpubPage> pages = [];
  List<int> chapterIndexes = [];
  int pageIndex = 0;

  for (var next in contentPages) {
    List<Paragraph> paragrafos = [];
    List<dom.Element> elmList = [];
    if (filename != next.FileName) {
      filename = next.FileName;
      final EpubContentFile? file = epubBook.Content?.AllFiles?[filename];
      String? content;

      if (file is EpubTextContentFile) {
        content = file.Content;
        final document = Document.html(content!);
        // final result = convertDocumentToElements(document);
        // elmList = _removeAllDiv(result);

        // String outerHtml = "";
        // for (var item in elmList) {
        //   // if (item.localName == 'p') {
        //   //   outerHtml += '<br>${item.text}<br>';
        //   // } else {
        //   // }
        //   outerHtml += item.outerHtml;
        // }

        final result = convertDocumentToElements(document);
        elmList = _removeAllDiv(result);
        // pages.add(EpubPage(index: pageIndex, fileName: filename!, paragraphs: [], content: outerHtml));
      }
    }

    pageIndex++;
    paragrafos.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
    pages.add(EpubPage(index: pageIndex, fileName: filename!, paragraphs: paragrafos));
    // chapterIndexes.add(acc.length);
    // acc.addAll(elmList.map((element) => Paragraph(element, chapterIndexes.length - 1)));
  }

  return pages;
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

class EpubPage {
  final int index;
  final String fileName;
  final String? content;
  List<Paragraph> paragraphs;

  EpubPage({required this.index, required this.fileName, required this.paragraphs, this.content});

  void addParagraph(Paragraph paragraph) {
    paragraphs.add(paragraph);
  }
}

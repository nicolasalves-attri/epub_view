import 'package:html/dom.dart' as dom;

class Paragraph {
  Paragraph(this.element, this.paragraphIndex, [this.pageIndex = 0]);

  final dom.Element element;
  final int paragraphIndex;
  final int pageIndex;
}

import 'dart:ui';
import 'package:equatable/equatable.dart';
import 'page_position.dart';

class HighlightedText extends Equatable {
  final int id;
  final String text;
  final Color color;
  // final EpubPagePosition pagePosition;
  final int paragraphIndex;
  final int currentPage;

  const HighlightedText({
    required this.id,
    required this.text,
    required this.color,
    // required this.pagePosition,
    required this.paragraphIndex,
    required this.currentPage,
  });

  factory HighlightedText.fromJson(Map json) => HighlightedText(
        id: json['id'],
        text: json['text'],
        color: Color(json['color']),
        // pagePosition: EpubPagePosition.fromJson(json['pagePosition']),
        paragraphIndex: json['paragraphIndex'],
        currentPage: json['currentPage'],
      );

  Map toJson() => {
        'id': id,
        'text': text,
        'color': color.value,
        // 'pagePosition': pagePosition.toJson(),
        'paragraphIndex': paragraphIndex,
        'currentPage': currentPage,
      };

  HighlightedText copyWith({
    int? id,
    String? text,
    Color? color,
    EpubPagePosition? pagePosition,
    int? paragraphIndex,
    int? currentPage,
  }) {
    return HighlightedText(
      id: id ?? this.id,
      text: text ?? this.text,
      color: color ?? this.color,
      // pagePosition: pagePosition ?? this.pagePosition,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      currentPage: currentPage ?? this.currentPage,
    );
  }

  @override
  List<Object?> get props => [id, text, paragraphIndex];
}

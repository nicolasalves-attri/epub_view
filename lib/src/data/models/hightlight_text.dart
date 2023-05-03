import 'dart:ui';

import 'package:equatable/equatable.dart';

import 'page_position.dart';

class HighlightedText extends Equatable {
  final int id;
  final String text;
  final Color color;
  final EpubPagePosition pagePosition;

  const HighlightedText({
    required this.id,
    required this.text,
    required this.color,
    required this.pagePosition,
  });

  factory HighlightedText.fromJson(Map json) => HighlightedText(
        id: json['id'],
        text: json['text'],
        color: Color(json['color']),
        pagePosition: EpubPagePosition.fromJson(json['pagePosition']),
      );

  Map toJson() => {
        'id': id,
        'text': text,
        'color': color.value,
        'pagePosition': pagePosition.toJson(),
      };

  HighlightedText copyWith({
    int? id,
    String? text,
    Color? color,
    EpubPagePosition? pagePosition,
  }) {
    return HighlightedText(
      id: id ?? this.id,
      text: text ?? this.text,
      color: color ?? this.color,
      pagePosition: pagePosition ?? this.pagePosition,
    );
  }

  @override
  List<Object?> get props => [id, text];
}

class EpubPagePosition {
  final int page;
  final int totalPages;
  final int scrollPosition;
  double get progress => (page / (totalPages - 1)) * 100;

  EpubPagePosition({
    required this.page,
    required this.totalPages,
    required this.scrollPosition,
  });

  factory EpubPagePosition.fromJson(Map json) => EpubPagePosition(
        page: json['page'],
        totalPages: json['totalPages'],
        scrollPosition: json['scrollPosition'],
      );

  Map toJson() => {
        'page': page,
        'totalPages': totalPages,
        'scrollPosition': scrollPosition,
      };

  EpubPagePosition copyWith({
    int? page,
    int? totalPages,
    int? scrollPosition,
  }) {
    return EpubPagePosition(
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      scrollPosition: scrollPosition ?? this.scrollPosition,
    );
  }
}

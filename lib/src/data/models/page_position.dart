class EpubPagePosition {
  final int page;
  final int innerPage;
  final int totalPages;
  final double scrollPosition;
  double get progress => (page / (totalPages - 1)) * 100;

  EpubPagePosition({
    required this.page,
    this.innerPage = 0,
    required this.totalPages,
    this.scrollPosition = 0,
  });

  factory EpubPagePosition.fromJson(Map json) => EpubPagePosition(
        page: json['page'],
        innerPage: json['innerPage'],
        totalPages: json['totalPages'],
        scrollPosition: json['scrollPosition'],
      );

  Map toJson() => {
        'page': page,
        'innerPage': innerPage,
        'totalPages': totalPages,
        'scrollPosition': scrollPosition,
      };

  EpubPagePosition copyWith({
    int? page,
    int? innerPage,
    int? totalPages,
    double? scrollPosition,
  }) {
    return EpubPagePosition(
      page: page ?? this.page,
      innerPage: innerPage ?? this.innerPage,
      totalPages: totalPages ?? this.totalPages,
      scrollPosition: scrollPosition ?? this.scrollPosition,
    );
  }
}

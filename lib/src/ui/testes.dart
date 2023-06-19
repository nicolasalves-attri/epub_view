NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification notification) {

                  if (notification is ScrollEndNotification) {
                    updatePagePosition(pageController.page!.round());
                  }

                  if (notification is OverscrollNotification) {
                    if (notification.metrics.pixels == 0) {
                      var prevPage = pageController.page!.round() > 0 ? pageController.page!.round() - 1 : 0;
                      scrollControllers[prevPage].jumpTo(scrollControllers[prevPage].position.maxScrollExtent);

                      pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    } else {
                      pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    }
                  }
                  // if (notification.depth == 0 && notification is ScrollUpdateNotification) {
                  //   final PageMetrics metrics = notification.metrics as PageMetrics;
                  //   final int currentPage = metrics.page!.round();
                  //   log('currentPage: $currentPage');
                  //   if (currentPage != _lastReportedPage) {
                  //     _lastReportedPage = currentPage;
                  //   }
                  // }

                  return false;
                },
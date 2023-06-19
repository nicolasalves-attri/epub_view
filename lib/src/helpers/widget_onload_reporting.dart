import 'package:flutter/material.dart';

class WidgetReporting extends StatefulWidget {
  const WidgetReporting({
    super.key,
    required this.onLoad,
    required this.child,
  });

  final Function onLoad;
  final Widget child;

  @override
  State<WidgetReporting> createState() => _WidgetReportingState();
}

class _WidgetReportingState extends State<WidgetReporting> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onLoad();
    });

    return widget.child;
  }
}

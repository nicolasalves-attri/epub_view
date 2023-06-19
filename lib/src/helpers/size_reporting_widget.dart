import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SizeReportingWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSizeChange;

  const SizeReportingWidget({
    Key? key,
    required this.child,
    required this.onSizeChange,
  }) : super(key: key);

  @override
  State<SizeReportingWidget> createState() => _SizeReportingWidgetState();
}

class _SizeReportingWidgetState extends State<SizeReportingWidget> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifySize());
    return widget.child;
  }

  void _notifySize() {
    if (!mounted) return;

    final size = context.size;
    if (_oldSize != size && size != null) {
      _oldSize = size;
      widget.onSizeChange(size);
    }
  }
}

class MeasureSizeRenderObject extends RenderProxyBox {
  MeasureSizeRenderObject(this.onChange);
  void Function(Size size) onChange;

  Size? _prevSize;
  @override
  void performLayout() {
    super.performLayout();
    Size? newSize = child?.size;
    if (_prevSize == newSize) return;
    _prevSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize!));
  }
}

class MeasurableWidget extends SingleChildRenderObjectWidget {
  const MeasurableWidget({Key? key, required this.onChange, required Widget child}) : super(key: key, child: child);
  final void Function(Size size) onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => MeasureSizeRenderObject(onChange);
}

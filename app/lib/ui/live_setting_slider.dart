import 'package:flutter/material.dart';

class LiveSettingSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double> onPreview;
  final Future<bool> Function(double) onCommit;
  final VoidCallback onCancel;
  const LiveSettingSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
  });
  @override
  State<LiveSettingSlider> createState() => _LiveSettingSliderState();
}

class _LiveSettingSliderState extends State<LiveSettingSlider> {
  late double value = widget.value;
  bool dragging = false, saving = false;
  int generation = 0;
  @override
  void didUpdateWidget(covariant LiveSettingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dragging && !saving) value = widget.value;
  }

  @override
  void dispose() {
    if (dragging) widget.onCancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Slider(
    value: value.clamp(widget.min, widget.max),
    min: widget.min,
    max: widget.max,
    onChangeStart: (_) {
      dragging = true;
      generation++;
    },
    onChanged: (next) {
      setState(() => value = next);
      widget.onPreview(next);
    },
    onChangeEnd: (next) async {
      dragging = false;
      saving = true;
      final token = generation;
      final ok = await widget.onCommit(next);
      if (mounted && token == generation) {
        setState(() {
          saving = false;
          if (!ok) value = widget.value;
        });
      }
    },
  );
}

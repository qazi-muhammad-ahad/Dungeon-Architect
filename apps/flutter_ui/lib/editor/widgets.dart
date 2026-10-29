import 'package:flutter/material.dart';

import 'theme.dart';

class NumericField extends StatefulWidget {
  const NumericField({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.error,
    this.enabled = true,
  });
  final String label, value, unit;
  final String? error;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<NumericField> {
  late final TextEditingController text = TextEditingController(
    text: widget.value,
  );
  final focus = FocusNode();
  @override
  void didUpdateWidget(NumericField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) text.text = widget.value;
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: text,
      focusNode: focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      style: TextStyle(fontFamily: 'Consolas', fontSize: 13),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.label,
        suffixText: widget.unit,
        errorText: widget.error,
      ),
      onTapOutside: (_) => focus.unfocus(),
    ),
  );
}

class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorColors.of(context).line)),
    ),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: EditorColors.of(context).muted,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

class Lantern extends StatefulWidget {
  const Lantern({super.key});
  @override
  State<Lantern> createState() => _LanternState();
}

class _LanternState extends State<Lantern> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) =>
        Opacity(opacity: .55 + controller.value * .4, child: child),
    child: Icon(
      Icons.flare_outlined,
      color: EditorColors.of(context).moss,
      size: 18,
    ),
  );
}

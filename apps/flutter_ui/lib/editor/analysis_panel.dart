import 'package:flutter/material.dart';

import 'analysis_controller.dart';
import 'project_controller.dart';
import 'trace_explanations.dart';

class AnalyzePanel extends StatefulWidget {
  const AnalyzePanel({
    super.key,
    required this.controller,
    this.canvasActions = const [],
  });
  final ProjectController controller;
  final List<Widget> canvasActions;
  @override
  State<AnalyzePanel> createState() => _AnalyzePanelState();
}

class _AnalyzePanelState extends State<AnalyzePanel> {
  static const speeds = [.5, 1.0, 2.0, 5.0, 10.0, 50.0, 100.0];
  bool customSpeed = false;
  String? speedError;
  final speedText = TextEditingController();
  ProjectController get c => widget.controller;
  @override
  void dispose() {
    speedText.dispose();
    super.dispose();
  }

  Widget small(String text) => Text(text, style: const TextStyle(fontSize: 11));
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: trace(),
    ),
  );
  Widget trace() {
    final p = c.playback;
    final selection = p.selection;
    final event = p.current;
    final decision = describeTrace(event, c.result?.document);
    final count = p.selectedEvents.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Trace', style: Theme.of(context).textTheme.titleMedium),
            DropdownButton<TraceSelection>(
              value: selection,
              items: [
                for (final option in TraceSelection.values)
                  DropdownMenuItem(
                    value: option,
                    child: Text(traceStage(option.name)),
                  ),
              ],
              onChanged: (value) => p.setSelection(value!),
            ),
            if (c.result != null)
              small(
                'Replay of completed run · accepted seed ${c.acceptedSeed ?? '—'}${c.stale
                    ? ' · STALE INPUTS'
                    : c.showingPreviousResult
                    ? ' · PREVIOUS RESULT'
                    : ''}',
              ),

            IconButton(
              tooltip: p.playing ? 'Pause trace' : 'Play trace',
              onPressed: count == 0 || c.busy || c.stale
                  ? null
                  : () => p.playing ? p.pause() : p.play(),
              icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Back',
              onPressed: p.cursor == 0 ? null : p.back,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: p.cursor == count ? null : p.step,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: 'Restart trace',
              onPressed: count == 0 ? null : p.restart,
              icon: const Icon(Icons.replay),
            ),
            small('Step ${p.cursor} / $count'),
            DropdownButton<double>(
              value: customSpeed || !speeds.contains(p.speed) ? 0 : p.speed,
              items: [
                for (final speed in speeds)
                  DropdownMenuItem(
                    value: speed,
                    child: small('${traceSpeed(speed)}×'),
                  ),
                DropdownMenuItem(value: 0.0, child: small('Custom speed')),
              ],
              onChanged: (value) {
                setState(() {
                  customSpeed = value == 0;
                  speedError = null;
                  if (customSpeed) speedText.text = traceSpeed(p.speed);
                });
                if (!customSpeed) p.setSpeed(value!);
              },
            ),
            small('${traceSpeed(p.speed)} target events/s'),
            ...widget.canvasActions,
            FilterChip(
              label: small('Reduce animation'),
              selected:
                  c.reduceTraceMotion ||
                  MediaQuery.disableAnimationsOf(context),
              onSelected: MediaQuery.disableAnimationsOf(context)
                  ? null
                  : c.setReduceTraceMotion,
            ),
          ],
        ),
        if (customSpeed)
          SizedBox(
            width: 230,
            child: TextField(
              controller: speedText,
              decoration: InputDecoration(
                labelText: 'Custom speed multiplier',
                errorText: speedError,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (text) {
                final value = double.tryParse(text.trim());
                final valid = value != null && value.isFinite && value > 0;
                setState(
                  () => speedError = valid
                      ? null
                      : 'Enter a finite positive speed.',
                );
                if (valid) p.setSpeed(value);
              },
            ),
          ),
        SizedBox(
          height: 30,
          child: Slider(
            semanticFormatterCallback: (value) =>
                'Trace step ${value.round()} of $count',
            value: p.cursor.toDouble(),
            max: count == 0 ? 1 : count.toDouble(),
            onChanged: count == 0 ? null : (value) => p.seek(value.round()),
          ),
        ),
        Tooltip(
          message: decision == null
              ? ''
              : '${decision.$2} · Final accepted map context',
          child: Text(
            decision != null
                ? '${traceStage(event!['stage'] as String)} · ${decision.$1} · ${decision.$2}'
                : count > 0
                ? 'Play or step through the trace. Drag to pan, scroll to zoom.'
                : c.result == null
                ? 'Generate a dungeon to capture a trace.'
                : 'No recorded events for ${traceStage(selection.name)}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (p.truncated || p.speed > 60)
          small(
            [
              if (p.truncated)
                'Capture truncated · ${p.dropped} events omitted',
              if (p.speed > 60)
                'Visual updates batched · all captured events can be stepped',
            ].join('  /  '),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

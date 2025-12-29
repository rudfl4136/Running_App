import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../running_provider.dart';

class RunningHud extends StatelessWidget {
  const RunningHud({super.key});

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();

    if (!running.hudAvailable) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${running.hudDistanceToNextTurnM?.toStringAsFixed(0)} m 후 '
            '${running.hudNextTurnLabel}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: running.hudCourseProgressRatio,
            backgroundColor: Colors.white24,
            color: Colors.greenAccent,
          ),
        ],
      ),
    );
  }
}

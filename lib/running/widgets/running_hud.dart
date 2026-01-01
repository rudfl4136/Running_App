import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../running_provider.dart';
import '../../models/course.dart';
import 'dart:math';
import 'dart:async'; // ✅ 이 줄 추가

/* ============================================================
   🏃‍♂️ 러닝 HUD 전체 컨테이너
   ============================================================ */

class RunningHud extends StatelessWidget {
  const RunningHud({super.key});

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();
    final course = running.currentCourse;

    if (!running.hudAvailable || course == null) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _buildHudByState(context),
    );
  }

  Widget _buildHudByState(BuildContext context) {
    final running = context.watch<RunningProvider>();
    final course = running.currentCourse;

    switch (running.effectiveHudState) {
      case HudNavState.wrongWay:
        return const WrongWayHud(key: ValueKey('wrongWay'));

      case HudNavState.offCourse:
        return const OffCourseHud(key: ValueKey('offCourse'));

      case HudNavState.lapDone:
        return const LapDoneHud(key: ValueKey('lapDone'));

      case HudNavState.onCourse:
        return course!.loopMode == CourseLoopMode.repeat
            ? const TrackHud(key: ValueKey('track'))
            : const NavigationHud(key: ValueKey('nav'));

      case HudNavState.inactive:
      default:
        return const SizedBox.shrink(key: ValueKey('empty'));
    }
  }
}

/* ============================================================
   🧭 일반 코스 네비게이션 HUD
   ============================================================ */

class NavigationHud extends StatefulWidget {
  const NavigationHud({super.key});

  @override
  State<NavigationHud> createState() => _NavigationHudState();
}

class _NavigationHudState extends State<NavigationHud>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scale;
  late HudNavState _prevHudState;
  HudNavState? _lastHudState;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _scale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  Duration _getRotationDuration(HudNavState? lastState) {
    if (lastState == HudNavState.offCourse ||
        lastState == HudNavState.wrongWay ||
        lastState == HudNavState.lapDone) {
      return const Duration(milliseconds: 80); // 스냅
    }
    return const Duration(milliseconds: 260); // 부드럽게
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final running = context.watch<RunningProvider>();
    final current = running.hudNavState;

    if ((_lastHudState == HudNavState.offCourse ||
            _lastHudState == HudNavState.wrongWay) &&
        current == HudNavState.onCourse) {
      // 🎯 복귀 순간
      _scaleController
        ..reset()
        ..forward();
    }

    _lastHudState = current;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();
    final stage = running.hudTurnStage;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _backgroundColor(stage),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running.effectiveHudArrowRotation != null) ...[
            ScaleTransition(
              scale: _scale,
              child: AnimatedRotation(
                turns: running.effectiveHudArrowRotation! / (2 * pi),
                duration: _getRotationDuration(_lastHudState),
                curve: Curves.easeOut,
                child: const Icon(
                  Icons.navigation,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          Text(
            _buildTurnText(running, stage),
            style: TextStyle(
              color: Colors.white,
              fontSize: stage == TurnAnnounceStage.immediate ? 24 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: running.hudCourseProgressRatio,
            minHeight: 6,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   🏃 트랙 / 반복 코스 HUD
   ============================================================ */

class TrackHud extends StatefulWidget {
  const TrackHud({super.key});

  @override
  State<TrackHud> createState() => _TrackHudState();
}

class _TrackHudState extends State<TrackHud>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scale;

  bool _isRotationLocked = false;
  bool _isColorHighlighted = false;

  double _lockedTurns = 0.0;

  Timer? _rotationLockTimer;
  Timer? _colorHighlightTimer;

  HudNavState? _lastHudState;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _scale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final running = context.watch<RunningProvider>();
    final current = running.hudNavState;

    if ((_lastHudState == HudNavState.offCourse ||
            _lastHudState == HudNavState.wrongWay ||
            _lastHudState == HudNavState.lapDone) &&
        current == HudNavState.onCourse) {
      // 3️⃣ HUD 바운스
      _scaleController
        ..reset()
        ..forward();

      // 4️⃣ 기준 bearing 캐싱
      _lockedTurns = (running.effectiveHudArrowRotation ?? 0) / (2 * pi);

      // 1️⃣ 회전 lock
      _isRotationLocked = true;
      _rotationLockTimer?.cancel();
      _rotationLockTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isRotationLocked = false;
          });
        }
      });

      // 2️⃣ 색상 강조
      _isColorHighlighted = true;
      _colorHighlightTimer?.cancel();
      _colorHighlightTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isColorHighlighted = false;
          });
        }
      });
    }

    _lastHudState = current;
  }

  @override
  void dispose() {
    _rotationLockTimer?.cancel();
    _colorHighlightTimer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();

    final double turns =
        _isRotationLocked
            ? _lockedTurns
            : (running.effectiveHudArrowRotation ?? 0) / (2 * pi);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(220),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lap ${running.currentLap}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (running.effectiveHudArrowRotation != null)
            ScaleTransition(
              scale: _scale,
              child: AnimatedRotation(
                turns: turns,
                duration:
                    _isRotationLocked
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(
                  Icons.navigation,
                  size: 52,
                  color:
                      _isColorHighlighted ? Colors.greenAccent : Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: running.lapProgress,
            minHeight: 6,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   🚨 코스 이탈 HUD
   ============================================================ */
class OffCourseHud extends StatelessWidget {
  const OffCourseHud({super.key});

  @override
  Widget build(BuildContext context) {
    final running = context.watch<RunningProvider>();
    final rotation = running.effectiveHudArrowRotation;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(220),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rotation != null) ...[
            AnimatedRotation(
              turns: rotation / (2 * pi),
              duration: const Duration(milliseconds: 120), // 🔥 빠른 스냅
              curve: Curves.easeOut,
              child: const Icon(
                Icons.navigation,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            '코스를 이탈했습니다',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('화살표 방향으로 복귀하세요', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

/* ============================================================
   🔁 랩 완료 HUD
   ============================================================ */

class LapDoneHud extends StatelessWidget {
  const LapDoneHud({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(220),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, color: Colors.white, size: 36),
          SizedBox(height: 8),
          Text(
            '랩 완료!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   ⛔ 역방향 HUD
   ============================================================ */
class WrongWayHud extends StatefulWidget {
  const WrongWayHud({super.key});

  @override
  State<WrongWayHud> createState() => _WrongWayHudState();
}

class _WrongWayHudState extends State<WrongWayHud>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<Color?> _bgColor;
  //late Animation<Offset> _shake;

  late Animation<double> _shake;

  //    🔁 180도 U턴
  static const double _uTurn = 0.5;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _bgColor = ColorTween(
      begin: Colors.redAccent.withAlpha(180),
      end: Colors.redAccent.withAlpha(255),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    // 🎬 진입 시 한 번만 실행
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shake.value, 0),
          child: ScaleTransition(scale: _scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgColor.value, // 🎯 pulse 적용
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            AnimatedRotation(
              turns: _uTurn,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: Icon(Icons.navigation, size: 44, color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              '역방향입니다',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('방향을 돌려주세요', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   🎨 헬퍼 함수
   ============================================================ */

Color _backgroundColor(TurnAnnounceStage? stage) {
  switch (stage) {
    case TurnAnnounceStage.approaching20:
      return Colors.orange.withAlpha(220);
    case TurnAnnounceStage.immediate:
      return Colors.redAccent.withAlpha(220);
    default:
      return Colors.black.withAlpha(200);
  }
}

String _buildTurnText(RunningProvider running, TurnAnnounceStage? stage) {
  final label = running.hudNextTurnLabel;
  final dist = running.hudDistanceToNextTurnM?.round() ?? 0;

  if (stage == TurnAnnounceStage.immediate) {
    return '지금 $label';
  }

  return '$dist m 후 $label';
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/finish_response.dart';
import 'running/run_detail_page.dart';
import 'running/running_provider.dart';
import 'pages/run_history_page.dart';
import 'pages/course/course_list_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RunningProvider(),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RunningPage(),
      ),
    );
  }
}

class RunningPage extends StatelessWidget {
  const RunningPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 👉 액션 호출용 (상태 감지 X)
    final running = context.read<RunningProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('러닝 타이머 (스트림 버전)')),

      /// 🔥 저장 중 여부에 따라 화면 전체 분기
      body: Selector<RunningProvider, bool>(
        selector: (_, p) => p.isSaving,
        builder: (_, isSaving, __) {
          if (isSaving) {
            return const Center(child: CircularProgressIndicator());
          }

          // ⬇️ 저장 중이 아닐 때 메인 UI
          return Center(
            child: SingleChildScrollView(
              //padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  //   🔥 자동 일시정지 안내 UI
                  Selector<RunningProvider, bool>(
                    selector: (_, p) => p.autoPaused,
                    builder: (_, autoPaused, __) {
                      if (!autoPaused) return const SizedBox();

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '움직임이 없어 자동으로 일시정지되었습니다',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      );
                    },
                  ),

                  const Text('경과 시간', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 40),

                  /// ⏱ 경과 시간
                  Selector<RunningProvider, int>(
                    selector: (_, p) => p.seconds,
                    builder:
                        (_, sec, __) => Text(
                          _formatTime(sec),
                          style: const TextStyle(
                            fontSize: 58,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  ),

                  const SizedBox(height: 18),

                  /// 📏 총 거리
                  Selector<RunningProvider, double>(
                    selector: (_, p) => p.displayDistanceKm,
                    builder:
                        (_, dist, __) => Text(
                          '총 거리: ${dist.toStringAsFixed(2)} km',
                          style: const TextStyle(fontSize: 18),
                        ),
                  ),

                  const SizedBox(height: 8),

                  Selector<RunningProvider, double>(
                    selector: (_, p) => p.averagePaceSec,
                    builder: (_, pace, __) {
                      if (pace == 0) return const Text('평균 페이스: -');

                      final min = (pace ~/ 60);
                      final sec = (pace % 60).round();

                      return Text(
                        '평균 페이스: ${min}:${sec.toString().padLeft(2, '0')} /km',
                        style: const TextStyle(fontSize: 16),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  /// ▶️ 버튼 영역 (🔥 핵심)
                  Selector<RunningProvider, RunningStatus>(
                    selector: (_, p) => p.status,
                    builder: (_, status, __) {
                      if (status == RunningStatus.running) {
                        return ElevatedButton(
                          onPressed: running.pause,
                          child: const Text('일시정지'),
                        );
                      }

                      if (status == RunningStatus.paused) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: running.resume,
                              child: const Text('재시작'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () async {
                                final response = await running.finish();
                                if (!context.mounted) return;
                                if (response.result == FinishResult.success &&
                                    response.record != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => RunDetailPage(
                                            record: response.record!,
                                          ),
                                    ),
                                  ).then((_) {
                                    running.reset(); // 🔥 여기서 reset
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        response.result == FinishResult.noData
                                            ? '저장할 데이터가 없습니다'
                                            : '저장에 실패했습니다',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('종료'),
                            ),
                          ],
                        );
                      }

                      return ElevatedButton(
                        onPressed: running.start,
                        child: const Text('시작'),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  /// 📋 기록 보기 버튼
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RunHistoryPage(),
                        ),
                      );
                    },
                    child: const Text('러닝 기록 보기'),
                  ),

                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CourseListPage(),
                        ),
                      );
                    },
                    child: const Text('코스 둘러보기'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// ⏱ 시간 포맷 (초 → MM:SS)
  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}

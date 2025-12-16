import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'running_provider.dart';
import 'running_map_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
    final running = context.watch<RunningProvider>();
    final recent = running.route.reversed.take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('러닝 타이머 (스트림 버전)')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('경과 시간', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),

              /// 타이머 표시
              Text(
                _formatTime(running.seconds),
                style: const TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 18),

              /// 총 거리
              Text(
                '총 거리: ${running.distanceKm.toStringAsFixed(2)} km',
                style: const TextStyle(fontSize: 18),
              ),

              const SizedBox(height: 8),

              /// 저장된 경로 포인트 수
              Text(
                '저장된 위치 포인트: ${running.route.length}',
                style: const TextStyle(fontSize: 14),
              ),

              const SizedBox(height: 16),

              /// 최근 5개 포인트 보여주기
              if (recent.isNotEmpty) ...[
                const Text(
                  '최근 5개 포인트',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Column(
                  children: [
                    for (int i = 0; i < recent.length; i++)
                      Text(
                        '${i + 1}. lat: ${recent[i].lat.toStringAsFixed(6)}, '
                        'lng: ${recent[i].lng.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              /// 시작 / 정지 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: running.isRunning ? running.stop : running.start,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(running.isRunning ? '정지' : '시작'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: running.reset,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('리셋'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// 현재 위치 테스트 버튼
              ElevatedButton(
                onPressed: running.getCurrentLocationOnce,
                child: const Text('현재 위치 테스트'),
              ),

              const SizedBox(height: 20),

              /// 📍 지도 보기 버튼 (여기가 중요!!)
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RunningMapPage()),
                  );
                },
                child: const Text("지도에서 경로 보기"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 시간 포맷 (SS → MM:SS)
  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

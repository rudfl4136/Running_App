import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../running/run_detail_page.dart';
import '../models/run_record.dart';

class RunHistoryPage extends StatelessWidget {
  const RunHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('러닝 기록')),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('users')
                .doc('temp_user') // 🔥 나중에 Auth uid로 교체
                .collection('running_records')
                .orderBy('date', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          /// 📭 기록 없음 상태
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_run, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('아직 러닝 기록이 없어요', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          /// 📃 러닝 기록 리스트
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              final distanceKm = (data['distanceMeters'] as num) / 1000;
              final durationSec = data['durationSeconds'] as int;
              final avgpaceSec = (data['averagePaceSec'] as num?)?.toInt() ?? 0;
              final date = (data['date'] as Timestamp).toDate();

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final record = RunRecord.fromJson(
                        docs[index].data() as Map<String, dynamic>,
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RunDetailPage(record: record),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// 📅 날짜
                          Text(
                            '${date.month}월 ${date.day}일 러닝',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// 📊 거리 / 시간 / 페이스
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _InfoItem(
                                label: '거리',
                                value: '${distanceKm.toStringAsFixed(2)} km',
                              ),
                              _InfoItem(
                                label: '시간',
                                value: _formatTime(durationSec),
                              ),
                              _InfoItem(
                                label: '페이스',
                                value:
                                    avgpaceSec == 0
                                        ? '-'
                                        : '${_formatPace(avgpaceSec)} /km',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
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

  /// 🏃 페이스 포맷 (초/km → M'SS")
  String _formatPace(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}\'${s.toString().padLeft(2, '0')}\"';
  }
}

/// 📊 리스트 아이템용 정보 위젯
class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

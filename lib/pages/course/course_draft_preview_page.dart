import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/run_record.dart';
import '../../models/course_draft.dart';
import 'course_publish_page.dart';

class CourseDraftPreviewPage extends StatefulWidget {
  final RunRecord original;
  final CourseDraft draft;

  const CourseDraftPreviewPage({
    super.key,
    required this.original,
    required this.draft,
  });

  @override
  State<CourseDraftPreviewPage> createState() => _CourseDraftPreviewPageState();
}

class _CourseDraftPreviewPageState extends State<CourseDraftPreviewPage> {
  bool _showOriginal = false;
  bool _showDraft = true;

  List<LatLng> get _originalRoute =>
      widget.original.route.map((p) => LatLng(p.lat, p.lng)).toList();

  List<LatLng> get _draftRoute =>
      widget.draft.route.map((p) => LatLng(p.lat, p.lng)).toList();

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints([..._originalRoute, ..._draftRoute]);

    return Scaffold(
      appBar: AppBar(title: const Text('코스 미리보기')),
      body: Column(
        children: [
          // 🗺 지도 영역
          SizedBox(
            height: 360, // ⭐ 핵심 (기기 기준 적당한 높이)
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(40),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.running',
                ),

                PolylineLayer(
                  polylines: [
                    if (_showOriginal)
                      Polyline(
                        points: _originalRoute,
                        strokeWidth: 4,
                        color: Colors.yellow.shade700, // ⭐ 변경
                      ),
                    if (_showDraft)
                      Polyline(
                        points: _draftRoute,
                        strokeWidth: 4,
                        color: Colors.greenAccent,
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 🔀 토글 바
          _buildToggleBar(),

          // 📝 설명 + 버튼 영역
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoBox(
                  originalCount: widget.original.route.length,
                  draftCount: widget.draft.route.length,
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: () async {
                    final success = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CoursePublishPage(draft: widget.draft),
                      ),
                    );

                    if (success == true && context.mounted) {
                      Navigator.pop(context); // 미리보기 페이지 종료
                    }
                  },
                  child: const Text('이 코스를 공유할게요'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🔀 원본 / 가공 토글 UI
  Widget _buildToggleBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilterChip(
          label: const Text('원본 경로'),
          selected: _showOriginal,
          onSelected: (v) {
            setState(() => _showOriginal = v);
          },
        ),
        const SizedBox(width: 12),
        FilterChip(
          label: const Text('코스 경로'),
          selected: _showDraft,
          onSelected: (v) {
            setState(() => _showDraft = v);
          },
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final int originalCount;
  final int draftCount;

  const _InfoBox({required this.originalCount, required this.draftCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '원본 경로 $originalCount개 → '
        '코스 경로 $draftCount개로 정리되었습니다.\n'
        '러닝 중 보기 좋은 경로로 자동 보정했어요.',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

class _NextStepPlaceholder extends StatelessWidget {
  const _NextStepPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('다음 단계')),
      body: const Center(child: Text('여기서 제목 / 공개 설정을 하게 됩니다')),
    );
  }
}

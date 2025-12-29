import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/course_metrics.dart';
import 'course_detail_page.dart';

import '../../models/course.dart';

class CourseListPage extends StatelessWidget {
  const CourseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('코스'),
          bottom: const TabBar(
            tabs: [Tab(text: '전체 코스'), Tab(text: '내가 만든 코스')],
          ),
          actions: [
            PopupMenuButton<CourseSort>(
              onSelected: (v) {
                // 이 값은 PublicCourseTab에서 받아야 함
              },
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: CourseSort.latest, child: Text('최신순')),
                    PopupMenuItem(
                      value: CourseSort.distance,
                      child: Text('거리순'),
                    ),
                  ],
            ),
          ],
        ),
        body: TabBarView(children: [PublicCourseTab(), MyCourseTab()]),
      ),
    );
  }
}

enum NearbyRadius { km3, km5, unlimited }

enum CourseSort { latest, distance }

class PublicCourseTab extends StatefulWidget {
  const PublicCourseTab({super.key});

  @override
  State<PublicCourseTab> createState() => _PublicCourseTabState();
}

class _PublicCourseTabState extends State<PublicCourseTab> {
  bool _nearbyOnly = true;
  NearbyRadius _radius = NearbyRadius.km3;
  CourseSort _sort = CourseSort.latest;

  Position? _myPosition;
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadMyLocation();
  }

  Future<void> _loadMyLocation() async {
    setState(() => _loadingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _nearbyOnly = false;
        });
        return;
      }

      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _nearbyOnly = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        _myPosition = pos;
      });
    } catch (e) {
      // 🔥 위치 실패 시에도 앱은 살아야 한다
      setState(() {
        _nearbyOnly = false;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  double get _maxDistanceKm {
    switch (_radius) {
      case NearbyRadius.km3:
        return 3;
      case NearbyRadius.km5:
        return 5;
      case NearbyRadius.unlimited:
        return double.infinity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [_buildFilterBar(), Expanded(child: _buildCourseList())],
    );
  }

  // 🔝 상단 필터 바
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('내 주변'),
            selected: _nearbyOnly,
            onSelected: (v) => setState(() => _nearbyOnly = v),
          ),
          const SizedBox(width: 12),

          if (_nearbyOnly)
            DropdownButton<NearbyRadius>(
              value: _radius,
              onChanged: (v) {
                if (v != null) setState(() => _radius = v);
              },
              items: const [
                DropdownMenuItem(
                  value: NearbyRadius.km3,
                  child: Text('3km 이내'),
                ),
                DropdownMenuItem(
                  value: NearbyRadius.km5,
                  child: Text('5km 이내'),
                ),
                DropdownMenuItem(
                  value: NearbyRadius.unlimited,
                  child: Text('제한 없음'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 📋 코스 리스트
  Widget _buildCourseList() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('courses')
              .where('isPublic', isEqualTo: true)
              //.orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('공유된 코스가 없어요'));
        }

        var courses =
            snapshot.data!.docs.map((doc) {
              return Course.fromJson(
                doc.id,
                doc.data() as Map<String, dynamic>,
              );
            }).toList();

        // 📍 내 주변 필터 (위치 있을 때만!)
        if (_nearbyOnly && _myPosition != null) {
          courses =
              courses.where((c) {
                if (c.route.isEmpty) return false;

                final start = c.route.first;
                final distanceKm =
                    Geolocator.distanceBetween(
                      _myPosition!.latitude,
                      _myPosition!.longitude,
                      start.lat,
                      start.lng,
                    ) /
                    1000;

                return distanceKm <= _maxDistanceKm;
              }).toList();
        }

        if (courses.isEmpty) {
          return const Center(child: Text('조건에 맞는 코스가 없어요'));
        }

        return ListView.builder(
          itemCount: courses.length,
          itemBuilder:
              (_, i) =>
                  _CourseCard(course: courses[i], myPosition: _myPosition),
        );
      },
    );
  }
}

//  📋 코스 카드
class _CourseCard extends StatelessWidget {
  final Course course;
  final Position? myPosition;

  const _CourseCard({required this.course, this.myPosition});

  @override
  Widget build(BuildContext context) {
    // 📍 내 위치와의 거리
    double? distanceFromMeKm;
    if (myPosition != null && course.route.isNotEmpty) {
      final start = course.route.first;
      distanceFromMeKm = calculateDistanceFromMeKm(
        myLat: myPosition!.latitude,
        myLng: myPosition!.longitude,
        startLat: start.lat,
        startLng: start.lng,
      );
    }

    // 📏 코스 길이
    final courseLengthKm = calculateCourseLengthKm(course.route);

    // 🔄 회전 수 (복잡도)
    final turnCount = course.turns.length;
    /*
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🏷 코스 제목
            Text(
              course.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // 📊 메트릭 줄
            Row(
              children: [
                _MetricChip(
                  icon: Icons.place,
                  label:
                      distanceFromMeKm != null
                          ? '${distanceFromMeKm.toStringAsFixed(1)} km'
                          : '-',
                ),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: Icons.route,
                  label: '${courseLengthKm.toStringAsFixed(1)} km',
                ),
                const SizedBox(width: 8),
                _MetricChip(icon: Icons.sync_alt, label: '회전 $turnCount회'),
              ],
            ),
          ],
        ),
      ),
    );
    */
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🏷 코스 제목
              Text(
                course.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // 📊 메트릭 줄
              Row(
                children: [
                  _MetricChip(
                    icon: Icons.place,
                    label:
                        distanceFromMeKm != null
                            ? '${distanceFromMeKm.toStringAsFixed(1)} km'
                            : '-',
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: Icons.route,
                    label: '${courseLengthKm.toStringAsFixed(1)} km',
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(icon: Icons.sync_alt, label: '회전 $turnCount회'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class MyCourseTab extends StatelessWidget {
  const MyCourseTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('courses')
              .where('createdBy', isEqualTo: 'temp_user') // 🔥 핵심
              //.orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('내가 만든 코스가 없어요'));
        }

        final courses =
            snapshot.data!.docs.map((doc) {
              return Course.fromJson(
                doc.id,
                doc.data() as Map<String, dynamic>,
              );
            }).toList();

        return ListView.builder(
          itemCount: courses.length,
          itemBuilder: (_, i) => _CourseCard(course: courses[i]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/course_draft.dart';
import '../../models/course.dart';

class CoursePublishPage extends StatefulWidget {
  final CourseDraft draft;

  const CoursePublishPage({super.key, required this.draft});

  @override
  State<CoursePublishPage> createState() => _CoursePublishPageState();
}

class _CoursePublishPageState extends State<CoursePublishPage> {
  final _titleController = TextEditingController();
  bool _isPublic = true;
  bool _isSaving = false;

  final _firestore = FirebaseFirestore.instance;

  Future<void> _publish() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('코스 이름을 입력해주세요')));
      return;
    }

    setState(() => _isSaving = true);

    final doc = _firestore.collection('courses').doc();

    final course = Course(
      id: doc.id,
      title: _titleController.text.trim(),
      route: widget.draft.route,
      turns: widget.draft.turns,
      isPublic: _isPublic,
      createdAt: DateTime.now(),
      createdBy: 'temp_user', // 🔥 나중에 FirebaseAuth uid
    );

    await doc.set(course.toJson());

    setState(() => _isSaving = false);

    if (!mounted) return;

    Navigator.pop(context, true); // 성공
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('코스 공유하기')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('코스 이름', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '예) 한강 야경 러닝 코스',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            SwitchListTile(
              title: const Text('코스 공개'),
              subtitle: Text(
                _isPublic ? '다른 사람들이 이 코스를 볼 수 있어요' : '나만 볼 수 있어요',
              ),
              value: _isPublic,
              onChanged: (v) {
                setState(() => _isPublic = v);
              },
            ),

            const Spacer(),

            ElevatedButton(
              onPressed: _isSaving ? null : _publish,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child:
                  _isSaving
                      ? const CircularProgressIndicator()
                      : const Text('코스 공유하기'),
            ),
          ],
        ),
      ),
    );
  }
}

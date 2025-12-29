import 'run_record.dart';

/// 🏁 FinishResponse
enum FinishResult { success, noData, saveFailed }

class FinishResponse {
  final FinishResult result;
  final RunRecord? record;

  const FinishResponse({required this.result, this.record});

  bool get isSuccess => result == FinishResult.success;
}

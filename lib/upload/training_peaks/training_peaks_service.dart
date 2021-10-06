import '../../export/json/json_export.dart';
import '../../persistence/models/activity.dart';
import '../../persistence/models/record.dart';
import '../../persistence/secret.dart';
import '../upload_service.dart';
import 'training_peaks.dart';

class TrainingPeaksService implements UploadService {
  final TrainingPeaks _trainingPeaks =
      TrainingPeaks(TRAINING_PEAKS_CLIENT_ID, TRAINING_PEAKS_SECRET);

  @override
  Future<bool> login() async {
    return await _trainingPeaks.oauth(_trainingPeaks.clientId, _trainingPeaks.secret);
  }

  @override
  Future<bool> hasValidToken() async {
    return await _trainingPeaks.hasValidToken();
  }

  @override
  Future<int> deAuthorize() async {
    return await _trainingPeaks.deAuthorize(_trainingPeaks.clientId);
  }

  @override
  Future<int> upload(Activity activity, List<Record> records) async {
    if (records.isEmpty) {
      return 404;
    }

    final exporter = JsonExport();
    final fileGzip = await exporter.getExport(activity, records, false, false);
    return await _trainingPeaks.uploadActivity(
      activity,
      fileGzip,
      exporter,
      _trainingPeaks.clientId,
    );
  }
}
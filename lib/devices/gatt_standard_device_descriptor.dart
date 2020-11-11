import '../persistence/models/activity.dart';
import '../persistence/models/record.dart';
import 'device_descriptor.dart';
import 'short_metric_descriptor.dart';

class CadenceData {
  final int seconds;
  int revolutions;

  CadenceData({this.seconds, this.revolutions});
}

class GattStandardDeviceDescriptor extends DeviceDescriptor {
  final ShortMetricDescriptor time;
  final ShortMetricDescriptor calories;
  final ShortMetricDescriptor speed;
  final ShortMetricDescriptor power;
  final ShortMetricDescriptor cadence;

  List<CadenceData> _cadenceData;

  GattStandardDeviceDescriptor({
    fourCC,
    vendorName,
    modelName,
    fullName = '',
    namePrefix,
    nameStart,
    manufacturer,
    model,
    primaryMeasurementServiceId,
    primaryMeasurementId,
    canPrimaryMeasurementProcessed,
    cadenceMeasurementServiceId,
    cadenceMeasurementId,
    canCadenceMeasurementProcessed,
    heartRate,
    this.time,
    this.calories,
    this.speed,
    this.power,
    this.cadence,
  }) : super(
          fourCC: fourCC,
          vendorName: vendorName,
          modelName: modelName,
          fullName: fullName,
          namePrefix: namePrefix,
          nameStart: nameStart,
          manufacturer: manufacturer,
          model: model,
          primaryMeasurementServiceId: primaryMeasurementServiceId,
          primaryMeasurementId: primaryMeasurementId,
          canPrimaryMeasurementProcessed: canPrimaryMeasurementProcessed,
          cadenceMeasurementServiceId: cadenceMeasurementServiceId,
          cadenceMeasurementId: cadenceMeasurementId,
          canCadenceMeasurementProcessed: canCadenceMeasurementProcessed,
          heartRate: heartRate,
        );

  double getTime(List<int> data) {
    return time.getMeasurementValue(data);
  }

  double getCalories(List<int> data) {
    return calories.getMeasurementValue(data);
  }

  double getSpeed(List<int> data) {
    return speed.getMeasurementValue(data);
  }

  double getPower(List<int> data) {
    return power.getMeasurementValue(data);
  }

  double getCadence(List<int> data) {
    return cadence.getMeasurementValue(data);
  }

  double getHeartRate(List<int> data) {
    return data[heartRate].toDouble();
  }

  @override
  Record processPrimaryMeasurement(
    Activity activity,
    int lastElapsed,
    Duration idleDuration,
    double speed,
    double distance,
    List<int> data,
    Record supplement,
  ) {
    final elapsed = data != null ? getTime(data).toInt() : lastElapsed;
    double dD = 0;
    if (speed > 0) {
      final dT = elapsed - lastElapsed;
      if (dT > 0) {
        dD = dT > 0 ? speed / DeviceDescriptor.MS2KMH * dT : 0.0;
      }
    }
    final elapsedDuration = Duration(seconds: elapsed);
    final timeStamp =
        activity.startDateTime.add(idleDuration).add(elapsedDuration);
    if (data != null) {
      return Record(
        activityId: activity.id,
        timeStamp: timeStamp.millisecondsSinceEpoch,
        distance: distance + dD,
        elapsed: elapsed,
        calories: getCalories(data).toInt(),
        power: getPower(data).toInt(),
        speed: getSpeed(data),
        cadence: getCadence(data).toInt(),
        heartRate: getHeartRate(data).toInt(),
      );
    } else {
      return Record(
        activityId: activity.id,
        timeStamp: timeStamp.millisecondsSinceEpoch,
        distance: distance + dD,
        elapsed: supplement.elapsed,
        calories: supplement.calories,
        power: supplement.power,
        speed: speed,
        cadence: supplement.cadence,
        heartRate: supplement.heartRate,
      );
    }
  }

  @override
  int processCadenceMeasurement(List<int> data) {
    if (!canCadenceMeasurementProcessed(data)) return 0;


    return 0;
  }
}
import 'package:flutter_blue/flutter_blue.dart';
import 'metric_descriptor.dart';

class DeviceDescriptor {
  final String fullName;
  final String namePrefix;
  final List<int> nameStart;
  final List<int> manufacturer;
  final List<int> model;
  final Guid measurementServiceGuid;
  final Guid equipmentTypeGuid;
  final Guid equipmentStateGuid;
  final Guid measurementGuid;
  final int byteCount;
  final List<int> measurementPrefix;
  final MetricDescriptor time;
  final MetricDescriptor calories;
  final MetricDescriptor speed;
  final MetricDescriptor power;
  final MetricDescriptor cadence;
  final int heartRate;

  DeviceDescriptor(
      {this.fullName,
      this.namePrefix,
      this.nameStart,
      this.manufacturer,
      this.model,
      this.measurementServiceGuid,
      this.equipmentTypeGuid,
      this.equipmentStateGuid,
      this.measurementGuid,
      this.byteCount,
      this.measurementPrefix,
      this.time,
      this.calories,
      this.speed,
      this.power,
      this.cadence,
      this.heartRate});

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
}
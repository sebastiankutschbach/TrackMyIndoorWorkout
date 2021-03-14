import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:preferences/preferences.dart';
import '../devices/cadence_sensor.dart';
import '../devices/heart_rate_monitor.dart';
import '../persistence/models/activity.dart';
import '../persistence/models/record.dart';
import '../persistence/preferences.dart';
import 'byte_metric_descriptor.dart';
import 'device_descriptor.dart';
import 'short_metric_descriptor.dart';
import 'three_byte_metric_descriptor.dart';

abstract class FitnessMachineDescriptor extends DeviceDescriptor {
  // Primary metrics
  int _featuresFlag;

  int _byteCounter;
  double _residueCalories;

  ListQueue<int> _strokeRates;
  int _strokeRateWindowSize = STROKE_RATE_SMOOTHING_DEFAULT_INT;
  int _strokeRateSum;
  int _lastPositiveCadence; // #101
  double _lastPositiveCalories; // #111
  bool _calorieCarryoverWorkaround = CALORIE_CARRYOVER_WORKAROUND_DEFAULT;
  bool _hasTotalCalorieCounting;

  FitnessMachineDescriptor({
    @required sport,
    @required fourCC,
    @required vendorName,
    @required modelName,
    fullName = '',
    @required namePrefix,
    manufacturer,
    model,
    primaryServiceId,
    primaryMeasurementId,
    canMeasureHeartRate = true,
    heartRateByteIndex,
    calorieFactor = 1.0,
    distanceFactor = 1.0,
  }) : super(
          sport: sport,
          fourCC: fourCC,
          vendorName: vendorName,
          modelName: modelName,
          fullName: fullName,
          namePrefix: namePrefix,
          manufacturer: manufacturer,
          model: model,
          primaryServiceId: primaryServiceId,
          primaryMeasurementId: primaryMeasurementId,
          canMeasureHeartRate: canMeasureHeartRate,
          heartRateByteIndex: heartRateByteIndex,
          calorieFactor: calorieFactor,
          distanceFactor: distanceFactor,
        ) {
    _strokeRates = ListQueue<int>();
    _strokeRateSum = 0;
    _featuresFlag = 0;
    _residueCalories = 0;
    _lastPositiveCadence = 0;
    _lastPositiveCalories = 0.0;
    _hasTotalCalorieCounting = false;
    _byteCounter = 0;
  }

  processFlag(int flag) {
    clearMetrics();
    _byteCounter = 2;
  }

  @override
  bool canPrimaryMeasurementProcessed(List<int> data) {
    final dataLength = data?.length ?? 0;
    return _byteCounter > 2 ? dataLength == _byteCounter : dataLength > 2;
  }

  readSettings() {
    final strokeRateWindowSizeString = PrefService.getString(STROKE_RATE_SMOOTHING_TAG);
    _strokeRateWindowSize = int.tryParse(strokeRateWindowSizeString);
  }

  clearStrokeRates() {
    _strokeRates.clear();
    _strokeRateSum = 0;
  }

  @override
  restartWorkout() {
    _calorieCarryoverWorkaround = PrefService.getBool(CALORIE_CARRYOVER_WORKAROUND_TAG);
    _residueCalories = 0.0;
    _lastPositiveCalories = 0.0;
    clearStrokeRates();
  }

  int processSpeedFlag(int flag, bool negated) {
    if (flag % 2 == (negated ? 0 : 1)) {
      if (speedMetric == null) {
        // UInt16, km/h with 0.01 resolution
        speedMetric =
            ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1, divider: 100.0);
      }
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processCadenceFlag(int flag) {
    if (flag % 2 == 1) {
      // UInt16, revolutions / minute with 0.5 resolution
      if (cadenceMetric == null) {
        cadenceMetric =
            ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1, divider: 2.0);
      }
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processTotalDistanceFlag(int flag) {
    if (flag % 2 == 1) {
      // UInt24, meters
      distanceMetric = ThreeByteMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 2);
      _byteCounter += 3;
    }
    flag ~/= 2;
    return flag;
  }

  int processResistanceLevelFlag(int flag) {
    if (flag % 2 == 1) {
      // SInt16
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processPowerFlag(int flag) {
    if (flag % 2 == 1) {
      if (powerMetric == null) {
        // SInt16, Watts
        powerMetric = ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1);
      }
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processExpandedEnergyFlag(int flag) {
    if (flag % 2 == 1) {
      // Total Energy: UInt16
      caloriesMetric = ShortMetricDescriptor(
        lsb: _byteCounter,
        msb: _byteCounter + 1,
        optional: true,
      );
      // Energy / hour UInt16
      _byteCounter += 2;
      caloriesPerHourMetric = ShortMetricDescriptor(
        lsb: _byteCounter,
        msb: _byteCounter + 1,
        optional: true,
      );
      // Energy / minute UInt8
      _byteCounter += 2;
      caloriesPerMinuteMetric = ByteMetricDescriptor(
        lsb: _byteCounter,
        optional: true,
      );
      _byteCounter++;
    }
    flag ~/= 2;
    return flag;
  }

  int processHeartRateFlag(int flag) {
    if (flag % 2 == 1) {
      // UInt8
      heartRateByteIndex = _byteCounter;
      _byteCounter++;
    }
    flag ~/= 2;
    return flag;
  }

  int processMetabolicEquivalentFlag(int flag) {
    if (flag % 2 == 1) {
      // UInt8
      _byteCounter++;
    }
    flag ~/= 2;
    return flag;
  }

  int processElapsedTimeFlag(int flag) {
    if (flag % 2 == 1) {
      timeMetric = ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1);
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processRemainingTimeFlag(int flag) {
    if (flag % 2 == 1) {
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processStrokeRateFlag(int flag, bool negated) {
    if (flag % 2 == (negated ? 0 : 1)) {
      // UByte with 0.5 resolution
      strokeRateMetric = ByteMetricDescriptor(lsb: _byteCounter, divider: 2.0);
      _byteCounter++;
      strokeCountMetric = ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1);
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  int processAverageStrokeRateFlag(int flag) {
    if (flag % 2 == 1) {
      if (strokeRateMetric != null) {
        // UByte with 0.5 resolution
        strokeRateMetric = ByteMetricDescriptor(lsb: _byteCounter, divider: 2.0);
      }
      _byteCounter++;
    }
    flag ~/= 2;
    return flag;
  }

  int processPaceFlag(int flag) {
    if (flag % 2 == 1) {
      // UInt16, seconds with 1 resolution
      if (paceMetric == null) {
        paceMetric = ShortMetricDescriptor(lsb: _byteCounter, msb: _byteCounter + 1);
      }
      _byteCounter += 2;
    }
    flag ~/= 2;
    return flag;
  }

  @override
  Record processPrimaryMeasurement(
    Activity activity,
    Duration idleDuration,
    Record lastRecord,
    List<int> data,
    HeartRateMonitor hrm,
    CadenceSensor cadenceSensor,
  ) {
    if ((data?.length ?? 0) > 2) {
      var flag = data[0] + 256 * data[1];
      if (flag != _featuresFlag) {
        _calorieCarryoverWorkaround = PrefService.getBool(CALORIE_CARRYOVER_WORKAROUND_TAG);
        _featuresFlag = flag;
        processFlag(flag);
        readSettings();
      }
    }

    int elapsedMillis =
        DateTime.now().subtract(idleDuration).difference(activity.startDateTime).inMilliseconds;
    double elapsed = elapsedMillis / 1000.0;
    Duration elapsedDuration = Duration(milliseconds: elapsedMillis);
    // When the equipment supplied multiple data read per second but the Fitness Machine
    // standard only supplies second resolution elapsed time the delta time becomes zero
    // Therefore the FTMS elapsed time reading is kinda useless, causes problems.
    // With this fix the calorie zeroing bug is revealed. Calorie preserving workaround can be
    // toggled in the settings now. Only the distance perseverance could pose a glitch. #94
    if (data != null && timeMetric != null && _hasTotalCalorieCounting) {
      elapsed = getTime(data);
    }

    double newDistance = 0;
    final dT = (elapsedMillis - lastRecord.elapsedMillis) / 1000.0;
    if (data != null && distanceMetric != null) {
      newDistance = getDistance(data);
    } else {
      double dD = 0;
      if (lastRecord.speed > 0) {
        if (dT > 0) {
          dD = lastRecord.speed * DeviceDescriptor.KMH2MS * distanceFactor * dT;
        }
      }
      newDistance = lastRecord.distance + dD;
    }
    final timeStamp = activity.startDateTime.add(idleDuration).add(elapsedDuration);
    if (data != null) {
      final pace = getPace(data);

      var cadence = lastRecord.cadence;
      if (cadenceMetric != null) {
        cadence = getCadence(data).toInt();
      } else if (strokeRateMetric != null) {
        final stroke = getStrokeRate(data);
        if (stroke == null || stroke == 0) {
          cadence = 0;
          clearStrokeRates();
        } else {
          if (_strokeRateWindowSize <= 1) {
            cadence = stroke;
          } else {
            _strokeRates.add(stroke);
            _strokeRateSum += stroke;
            if (_strokeRates.length > _strokeRateWindowSize) {
              _strokeRateSum -= _strokeRates.first;
              _strokeRates.removeFirst();
            }
            cadence = _strokeRates.length > 0 ? (_strokeRateSum / _strokeRates.length).round() : 0;
          }
        }
        // #101
        if ((cadence == null || cadence == 0) &&
            (pace != null && pace > 0 && pace < 120) &&
            _lastPositiveCadence > 0) {
          cadence = _lastPositiveCadence;
        } else if (cadence != null && cadence > 0) {
          _lastPositiveCadence = cadence;
        }
      }
      double power = getPower(data);
      double calories = 0;
      if (caloriesMetric != null) {
        calories = getCalories(data);
        if (calories != null && calories > 0) {
          _hasTotalCalorieCounting = true;
        }
      }
      if (calories == 0 || calories == null) {
        double deltaCalories = 0;
        if (caloriesPerHourMetric != null) {
          final calPerHour = getCaloriesPerHour(data);
          if (calPerHour != null) {
            deltaCalories = calPerHour / (60 * 60) * dT;
          }
        }
        if (deltaCalories == 0 && caloriesPerMinuteMetric != null) {
          final calPerMinute = getCaloriesPerMinute(data);
          if (calPerMinute != null) {
            deltaCalories = calPerMinute / 60 * dT;
          }
        }
        if (deltaCalories == 0 && power != null) {
          // Instead of dT fractional second we use 1s to boost calorie counting
          // Due to #35. On top of that
          deltaCalories = power * dT * DeviceDescriptor.J2KCAL * calorieFactor;
        }
        if (deltaCalories > 0) {
          _residueCalories += deltaCalories;
          calories = (lastRecord.calories ?? 0) + _residueCalories;
          if (calories.floor() > lastRecord.calories) {
            _residueCalories = calories - calories.floor();
          }
        }
      }
      // #101
      if ((calories == null || calories == 0) &&
          (pace != null && pace > 0 && pace < 120) &&
          _lastPositiveCalories > 0) {
        calories = _lastPositiveCalories;
      } else if (calories != null && calories > 0) {
        _lastPositiveCalories = calories;
      }
      if (_calorieCarryoverWorkaround &&
          lastRecord.calories != null &&
          lastRecord.calories > 0 &&
          (calories == null || lastRecord.calories > calories)) {
        calories = lastRecord.calories.toDouble();
      }

      var heartRate = 0;
      if (hrm != null) {
        heartRate = hrm.metric;
      }
      if (heartRate == 0) {
        heartRate = getHeartRate(data).toInt();
      }
      // #93
      if (heartRate == 0 && lastRecord.heartRate > 0) {
        heartRate = lastRecord.heartRate;
      }
      return RecordWithSport(
        activityId: activity.id,
        timeStamp: timeStamp.millisecondsSinceEpoch,
        distance: newDistance,
        elapsed: elapsed.toInt(),
        calories: calories?.floor() ?? 0,
        power: power.toInt(),
        speed: getSpeed(data),
        cadence: cadence,
        heartRate: heartRate,
        pace: pace,
        elapsedMillis: elapsedMillis,
        sport: sport,
      );
    } else {
      return RecordWithSport(
        activityId: activity.id,
        timeStamp: timeStamp.millisecondsSinceEpoch,
        distance: newDistance,
        elapsed: lastRecord.elapsed,
        calories: lastRecord.calories,
        power: lastRecord.power,
        speed: lastRecord.speed,
        cadence: lastRecord.cadence,
        heartRate: lastRecord.heartRate,
        pace: lastRecord.pace,
        elapsedMillis: elapsedMillis,
        sport: sport,
      );
    }
  }
}

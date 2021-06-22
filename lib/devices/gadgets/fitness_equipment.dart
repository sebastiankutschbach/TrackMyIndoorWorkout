import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pref/pref.dart';
import 'package:rxdart/rxdart.dart';
import '../../persistence/models/activity.dart';
import '../../persistence/models/record.dart';
import '../../persistence/preferences.dart';
import '../../utils/constants.dart';
import '../device_descriptors/device_descriptor.dart';
import '../bluetooth_device_ex.dart';
import '../gatt_constants.dart';
import 'device_base.dart';
import 'heart_rate_monitor.dart';

typedef RecordHandlerFunction = Function(Record data);

class FitnessEquipment extends DeviceBase {
  DeviceDescriptor? descriptor;
  String? manufacturerName;
  double _residueCalories = 0.0;
  int _lastPositiveCadence = 0; // #101
  bool _cadenceGapWorkaround = CADENCE_GAP_WORKAROUND_DEFAULT;
  double _lastPositiveCalories = 0.0; // #111
  bool hasTotalCalorieCounting = false;
  Timer? _timer;
  late Record lastRecord;
  HeartRateMonitor? heartRateMonitor;
  String _heartRateGapWorkaround = HEART_RATE_GAP_WORKAROUND_DEFAULT;
  int _heartRateUpperLimit = HEART_RATE_UPPER_LIMIT_DEFAULT;
  String _heartRateLimitingMethod = HEART_RATE_LIMITING_NO_LIMIT;
  bool _preferHrmBasedCalories = PREFER_HRM_BASED_CALORIES_DEFAULT;
  Activity? _activity;
  bool measuring = false;
  bool calibrating = false;
  Random _random = Random();
  double? slowPace;
  bool equipmentDiscovery = false;

  FitnessEquipment({this.descriptor, device})
      : super(
          serviceId: descriptor?.dataServiceId ?? FITNESS_MACHINE_ID,
          characteristicsId: descriptor?.dataCharacteristicId,
          device: device,
        ) {
    readConfiguration();
    lastRecord = RecordWithSport.getBlank(sport, uxDebug, _random);
  }

  String get sport => _activity?.sport ?? (descriptor?.defaultSport ?? ActivityType.Ride);
  double get powerFactor => _activity?.powerFactor ?? (descriptor?.powerFactor ?? 1.0);
  double get calorieFactor => _activity?.calorieFactor ?? (descriptor?.calorieFactor ?? 1.0);
  double get residueCalories => _residueCalories;
  double get lastPositiveCalories => _lastPositiveCalories;

  Stream<Record> get _listenToData async* {
    if (!attached || characteristic == null || descriptor == null) return;

    await for (var byteString in characteristic!.value.throttleTime(Duration(milliseconds: 450))) {
      if (!descriptor!.canDataProcessed(byteString)) continue;
      if (!measuring && !calibrating) continue;

      final record = descriptor!.stubRecord(byteString);
      if (record == null) continue;
      yield record;
    }
  }

  void pumpData(RecordHandlerFunction recordHandlerFunction) {
    if (uxDebug) {
      _timer = Timer(
        Duration(seconds: 1),
        () {
          final record = processRecord(RecordWithSport.getRandom(sport, _random));
          recordHandlerFunction(record);
          pumpData(recordHandlerFunction);
        },
      );
    } else {
      subscription = _listenToData.listen((recordStub) {
        final record = processRecord(recordStub);
        recordHandlerFunction(record);
      });
    }
  }

  void setHeartRateMonitor(HeartRateMonitor heartRateMonitor) {
    this.heartRateMonitor = heartRateMonitor;
  }

  void setActivity(Activity activity) {
    _activity = activity;
    lastRecord = RecordWithSport.getBlank(sport, uxDebug, _random);
    readConfiguration();
  }

  Future<bool> connectOnDemand({identify = false}) async {
    await connect();

    return await discover(identify: identify);
  }

  Future<bool> discover({bool identify = false, bool retry = false}) async {
    if (uxDebug) return true;

    final success = await super.discover(retry: retry);
    if (identify || !success) return success;

    if (equipmentDiscovery || descriptor == null) return false;

    equipmentDiscovery = true;
    // Check manufacturer name
    if (manufacturerName == null) {
      final deviceInfo = BluetoothDeviceEx.filterService(services, DEVICE_INFORMATION_ID);
      final nameCharacteristic =
          BluetoothDeviceEx.filterCharacteristic(deviceInfo?.characteristics, MANUFACTURER_NAME_ID);
      if (nameCharacteristic == null) {
        return false;
      }

      try {
        final nameBytes = await nameCharacteristic.read();
        manufacturerName = String.fromCharCodes(nameBytes);
      } on PlatformException catch (e, stack) {
        debugPrint("$e");
        debugPrintStack(stackTrace: stack, label: "trace:");
        // 2nd try
        try {
          final nameBytes = await nameCharacteristic.read();
          manufacturerName = String.fromCharCodes(nameBytes);
        } on PlatformException catch (e, stack) {
          debugPrint("$e");
          debugPrintStack(stackTrace: stack, label: "trace:");
        }
      }
    }

    equipmentDiscovery = false;
    return manufacturerName == descriptor!.manufacturer || descriptor!.manufacturer == "Unknown";
  }

  Record processRecord(Record stub) {
    final now = DateTime.now();
    int elapsedMillis = now.difference(_activity?.startDateTime ?? now).inMilliseconds;
    double elapsed = elapsedMillis / 1000.0;
    // When the equipment supplied multiple data read per second but the Fitness Machine
    // standard only supplies second resolution elapsed time the delta time becomes zero
    // Therefore the FTMS elapsed time reading is kinda useless, causes problems.
    // With this fix the calorie zeroing bug is revealed. Calorie preserving workaround can be
    // toggled in the settings now. Only the distance perseverance could pose a glitch. #94
    hasTotalCalorieCounting = hasTotalCalorieCounting ||
        (stub.calories != null && stub.calories! > 0) ||
        (heartRateMonitor != null && (heartRateMonitor?.record?.calories ?? 0) > 0);
    if (hasTotalCalorieCounting &&
        ((stub.calories != null && stub.calories! > 0) ||
            (heartRateMonitor != null && (heartRateMonitor?.record?.calories ?? 0) > 0))) {
      elapsed = stub.elapsed!.toDouble();
    }

    if (stub.elapsed == null || stub.elapsed == 0) {
      stub.elapsed = elapsed.round();
    }

    if (stub.elapsedMillis == null || stub.elapsedMillis == 0) {
      stub.elapsedMillis = elapsedMillis;
    }

    final dT = (elapsedMillis - lastRecord.elapsedMillis!) / 1000.0;
    if ((stub.distance ?? 0.0) < EPS) {
      stub.distance = (lastRecord.distance ?? 0);
      if ((stub.speed ?? 0.0) > 0 && dT > EPS) {
        // Speed possibly already has powerFactor effect
        double dD = (stub.speed ?? 0.0) * DeviceDescriptor.KMH2MS * dT;
        stub.distance = stub.distance! + dD;
      }
    }

    var calories1 = 0.0;
    if (stub.calories != null && stub.calories! > 0) {
      calories1 = stub.calories!.toDouble();
      hasTotalCalorieCounting = true;
    }
    var calories2 = 0.0;
    if (heartRateMonitor != null && (heartRateMonitor?.record?.calories ?? 0) > 0) {
      calories2 = heartRateMonitor?.record?.calories?.toDouble() ?? 0.0;
      hasTotalCalorieCounting = true;
    }

    var calories = 0.0;
    if (calories1 > EPS && (!_preferHrmBasedCalories || calories2 < EPS)) {
      calories = calories1;
    } else if (calories2 > EPS && (_preferHrmBasedCalories || calories1 < EPS)) {
      calories = calories2;
    } else {
      var deltaCalories = 0.0;
      if (stub.caloriesPerHour != null && stub.caloriesPerHour! > EPS) {
        deltaCalories = stub.caloriesPerHour! / (60 * 60) * dT;
      }

      if (deltaCalories < EPS && stub.caloriesPerMinute != null && stub.caloriesPerMinute! > EPS) {
        deltaCalories = stub.caloriesPerMinute! / 60 * dT;
      }

      if (deltaCalories < EPS && stub.power != null && stub.power! > EPS) {
        deltaCalories = stub.power! * dT * DeviceDescriptor.J2KCAL * calorieFactor;
      }

      _residueCalories += deltaCalories;
      final lastCalories = lastRecord.calories ?? 0.0;
      calories = lastCalories + _residueCalories;
      if (calories.floor() > lastCalories) {
        _residueCalories = calories - calories.floor();
      }
    }

    if (stub.pace != null && stub.pace! > 0 && slowPace != null && stub.pace! < slowPace! ||
        stub.speed != null && stub.speed! > EPS) {
      // #101, #122
      if ((stub.cadence == null || stub.cadence == 0) &&
          _lastPositiveCadence > 0 &&
          _cadenceGapWorkaround) {
        stub.cadence = _lastPositiveCadence;
      } else if (stub.cadence != null && stub.cadence! > 0) {
        _lastPositiveCadence = stub.cadence!;
      }
    }

    // #111
    if (calories < EPS && _lastPositiveCalories > 0) {
      calories = _lastPositiveCalories;
    } else {
      _lastPositiveCalories = calories;
    }

    stub.calories = calories.floor();

    if ((stub.heartRate == null || stub.heartRate == 0) &&
        (heartRateMonitor?.record?.heartRate ?? 0) > 0) {
      stub.heartRate = heartRateMonitor!.record!.heartRate;
    }

    // #93, #113
    if ((stub.heartRate == null || stub.heartRate == 0) &&
        lastRecord.heartRate != null &&
        lastRecord.heartRate! > 0 &&
        _heartRateGapWorkaround == DATA_GAP_WORKAROUND_LAST_POSITIVE_VALUE) {
      stub.heartRate = lastRecord.heartRate;
    }

    // #114
    if (_heartRateUpperLimit > 0 &&
        (stub.heartRate ?? 0) > _heartRateUpperLimit &&
        _heartRateLimitingMethod != HEART_RATE_LIMITING_NO_LIMIT) {
      if (_heartRateLimitingMethod == HEART_RATE_LIMITING_CAP_AT_LIMIT) {
        stub.heartRate = _heartRateUpperLimit;
      } else {
        stub.heartRate = 0;
      }
    }

    stub.activityId = _activity?.id ?? 0;
    stub.sport = descriptor?.defaultSport ?? ActivityType.Ride;
    return stub;
  }

  void readConfiguration() {
    final prefService = Get.find<BasePrefService>();
    _cadenceGapWorkaround =
        prefService.get<bool>(CADENCE_GAP_WORKAROUND_TAG) ?? CADENCE_GAP_WORKAROUND_DEFAULT;
    uxDebug = prefService.get<bool>(APP_DEBUG_MODE_TAG) ?? APP_DEBUG_MODE_DEFAULT;
    _heartRateGapWorkaround =
        prefService.get<String>(HEART_RATE_GAP_WORKAROUND_TAG) ?? HEART_RATE_GAP_WORKAROUND_DEFAULT;
    _heartRateUpperLimit =
        prefService.get<int>(HEART_RATE_UPPER_LIMIT_INT_TAG) ?? HEART_RATE_UPPER_LIMIT_DEFAULT;
    _heartRateLimitingMethod =
        prefService.get<String>(HEART_RATE_LIMITING_METHOD_TAG) ?? HEART_RATE_LIMITING_NO_LIMIT;
    _preferHrmBasedCalories =
        prefService.get<bool>(PREFER_HRM_BASED_CALORIES_TAG) ?? PREFER_HRM_BASED_CALORIES_DEFAULT;
  }

  void startWorkout() {
    readConfiguration();
    _residueCalories = 0.0;
    _lastPositiveCalories = 0.0;
    lastRecord = RecordWithSport.getBlank(sport, uxDebug, _random);
  }

  void stopWorkout() {
    readConfiguration();
    _residueCalories = 0.0;
    _lastPositiveCalories = 0.0;
    _timer?.cancel();
    descriptor?.stopWorkout();
  }
}

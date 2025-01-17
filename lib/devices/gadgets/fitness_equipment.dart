import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pref/pref.dart';
import '../../preferences/app_debug_mode.dart';
import '../../preferences/athlete_age.dart';
import '../../preferences/athlete_body_weight.dart';
import '../../preferences/athlete_gender.dart';
import '../../preferences/athlete_vo2max.dart';
import '../../preferences/cadence_data_gap_workaround.dart';
import '../../persistence/database.dart';
import '../../preferences/extend_tuning.dart';
import '../../preferences/heart_rate_gap_workaround.dart';
import '../../preferences/heart_rate_limiting.dart';
import '../../preferences/log_level.dart';
import '../../persistence/models/activity.dart';
import '../../persistence/models/record.dart';
import '../../preferences/use_heart_rate_based_calorie_counting.dart';
import '../../preferences/use_hr_monitor_reported_calories.dart';
import '../../utils/constants.dart';
import '../../utils/delays.dart';
import '../../utils/guid_ex.dart';
import '../../utils/hr_based_calories.dart';
import '../../utils/logging.dart';
import '../device_descriptors/data_handler.dart';
import '../device_descriptors/device_descriptor.dart';
import '../bluetooth_device_ex.dart';
import '../gatt_constants.dart';
import 'device_base.dart';
import 'heart_rate_monitor.dart';
import 'running_cadence_sensor.dart';

typedef RecordHandlerFunction = Function(RecordWithSport data);

// State Machine for #231 and #235
// (intelligent start and elapsed time tracking)
enum WorkoutState {
  waitingForFirstMove,
  moving,
  justStopped,
  stopped,
}

class FitnessEquipment extends DeviceBase {
  DeviceDescriptor? descriptor;
  Map<int, DataHandler> dataHandlers = {};
  String? manufacturerName;
  double _residueCalories = 0.0;
  int _lastPositiveCadence = 0; // #101
  bool _cadenceGapWorkaround = cadenceGapWorkaroundDefault;
  double _lastPositiveCalories = 0.0; // #111
  bool firstCalories; // #197 #234 #259
  double _startingCalories = 0.0;
  bool firstDistance; // #197 #234 #259
  double _startingDistance = 0.0;
  bool firstTime; // #197 #234 #259
  int _startingElapsed = 0;
  bool hasTotalCalorieReporting = false;
  bool hasTotalDistanceReporting = false;
  bool hasTotalTimeReporting = false;
  Timer? _timer;
  late RecordWithSport lastRecord;
  HeartRateMonitor? heartRateMonitor;
  RunningCadenceSensor? _runningCadenceSensor;
  String _heartRateGapWorkaround = heartRateGapWorkaroundDefault;
  int _heartRateUpperLimit = heartRateUpperLimitDefault;
  String _heartRateLimitingMethod = heartRateLimitingMethodDefault;
  double powerFactor = 1.0;
  double calorieFactor = 1.0;
  double hrCalorieFactor = 1.0;
  double hrmCalorieFactor = 1.0;
  bool _useHrmReportedCalories = useHrMonitorReportedCaloriesDefault;
  bool _useHrBasedCalorieCounting = useHeartRateBasedCalorieCountingDefault;
  int _weight = athleteBodyWeightDefault;
  int _age = athleteAgeDefault;
  bool _isMale = true;
  int _vo2Max = athleteVO2MaxDefault;
  Activity? _activity;
  bool measuring = false;
  WorkoutState workoutState = WorkoutState.waitingForFirstMove;
  bool calibrating = false;
  final Random _random = Random();
  double? slowPace;
  bool _equipmentDiscovery = false;
  bool _extendTuning = false;
  int _logLevel = logLevelDefault;

  // For Throttling + deduplication #234
  final Duration _throttleDuration = const Duration(milliseconds: ftmsDataThreshold);
  Map<int, List<int>> _listDeduplicationMap = {};
  Timer? _throttleTimer;

  FitnessEquipment(
      {this.descriptor,
      device,
      this.firstCalories = true,
      this.firstDistance = true,
      this.firstTime = true})
      : super(
          serviceId: descriptor?.dataServiceId ?? fitnessMachineUuid,
          characteristicsId: descriptor?.dataCharacteristicId,
          device: device,
        ) {
    readConfiguration();
    lastRecord = RecordWithSport.getZero(sport);
  }

  String get sport => _activity?.sport ?? (descriptor?.defaultSport ?? ActivityType.ride);
  double get residueCalories => _residueCalories;
  double get lastPositiveCalories => _lastPositiveCalories;
  bool get shouldMerge => dataHandlers.length > 1;

  int keySelector(List<int> l) {
    if (l.isEmpty) {
      return 0;
    }

    if (l.length == 1) {
      return l[0];
    }

    return l[1] * 256 + l[0];
  }

  /// Data streaming with custom multi-type packet aware throttling logic
  ///
  /// Stages SB20, Yesoul S3 and several other machines don't gather up
  /// all the relevant feature data into one packet, but instead supply
  /// various packets with distinct features. For example:
  /// * Stages has three packet types: 1. speed, 2. distance, 3.
  ///   cadence + power
  /// * Yesoul has two: 1. speed + elapsed time 2. cadence + distance +
  ///   power + calories
  ///
  /// This behavior is fundamentally different than other machines like
  /// Schwinn IC4 or Precor Spinner Chrono Power.
  /// * With multi-type packets I cannot tell if the workout is stopped
  ///   (like if I ony get a distance packet).
  /// * Creating a stub record from fragments of features results in a
  ///   spotty record. We'd need to fill the gaps from last known positive
  ///   values.
  /// * Since feature flags rotate we'd want to avoid the constant
  ///   re-interpretation of feature bits and construction of metric mapping.
  ///   So instead of having just one DataHandler (part of DeviceBase parent
  ///   class) we'd manage a set of DataHandlers, basically caching the
  ///   feature computation
  /// * With need our own throttling, since the throttle logic should
  ///   distinguish packets by features and should be able to gather the latest
  ///   from each.
  /// * As an extra win the throttling logic can already check the worthy-ness
  ///   of a packet and drop it without disturbing the throttling (timer).
  ///   Apparently Precor Spinner Chrono Power sometimes sprinkles in unworthy
  ///   packets into the comm. If the throttle timing is in interference it could
  ///   only pickup those unworthy packets so the app would be numb. With the
  ///   worthy-ness check before anything else we could just yeet the garbage
  ///   before it'd load or disturb anything.
  /// * When it's time to yield we merge the various feature packets together.
  ///   Merge logic simply sets a value if it's null. There's still extra care
  ///   needed about first positive values and workout start and stop conditions
  ///   in processRecord
  Stream<RecordWithSport> get _listenToData async* {
    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "listenToData",
        "attached $attached characteristic $characteristic descriptor $descriptor",
      );
    }
    if (!attached || characteristic == null || descriptor == null) return;

    await for (final byteList in characteristic!.value) {
      if (_logLevel >= logLevelInfo) {
        Logging.log(
          _logLevel,
          logLevelInfo,
          "FITNESS_EQUIPMENT",
          "listenToData",
          "measuring $measuring calibrating $calibrating",
        );
      }
      if (!measuring && !calibrating) continue;

      final key = keySelector(byteList);
      if (_logLevel >= logLevelInfo) {
        Logging.log(
          _logLevel,
          logLevelInfo,
          "FITNESS_EQUIPMENT",
          "listenToData",
          "key $key byteList $byteList",
        );
      }
      if (key <= 0) continue;

      if (!dataHandlers.containsKey(key)) {
        if (_logLevel >= logLevelInfo) {
          Logging.log(
            _logLevel,
            logLevelInfo,
            "FITNESS_EQUIPMENT",
            "listenToData",
            "Cloning handler for $key",
          );
        }
        dataHandlers[key] = descriptor!.clone();
      }

      final dataHandler = dataHandlers[key]!;
      if (!dataHandler.isDataProcessable(byteList)) continue;

      _listDeduplicationMap[key] = byteList;

      final shouldYield = !(_throttleTimer?.isActive ?? false);
      if (_logLevel >= logLevelInfo) {
        Logging.log(
          _logLevel,
          logLevelInfo,
          "FITNESS_EQUIPMENT",
          "listenToData",
          "Processable, shouldYield $shouldYield",
        );
      }
      _throttleTimer ??= Timer(_throttleDuration, () => {_throttleTimer = null});

      if (shouldYield) {
        final values = _listDeduplicationMap.entries
            .map((entry) => dataHandlers[entry.key]!.wrappedStubRecord(entry.value))
            .whereNotNull();

        _listDeduplicationMap = {};
        if (values.isEmpty) {
          if (_logLevel >= logLevelInfo) {
            Logging.log(
              _logLevel,
              logLevelInfo,
              "FITNESS_EQUIPMENT",
              "listenToData",
              "Skipping!!",
            );
          }
          continue;
        }

        final merged = values.skip(1).fold<RecordWithSport>(
              values.first,
              (prev, element) => prev.merge(element, true, true),
            );
        if (_logLevel >= logLevelInfo) {
          Logging.log(
            _logLevel,
            logLevelInfo,
            "FITNESS_EQUIPMENT",
            "listenToData",
            "merged $merged",
          );
        }
        yield merged;
      }
    }
  }

  void pumpData(RecordHandlerFunction recordHandlerFunction) {
    if (uxDebug) {
      _timer = Timer(
        const Duration(seconds: 1),
        () {
          final record = processRecord(RecordWithSport.getRandom(sport, _random));
          recordHandlerFunction(record);
          pumpData(recordHandlerFunction);
        },
      );
    } else {
      _runningCadenceSensor?.pumpData(null);
      subscription = _listenToData.listen((recordStub) {
        final record = processRecord(recordStub);
        recordHandlerFunction(record);
      });
    }
  }

  void setHeartRateMonitor(HeartRateMonitor heartRateMonitor) {
    this.heartRateMonitor = heartRateMonitor;
  }

  Future<void> additionalSensorsOnDemand() async {
    await refreshFactors();

    if (_runningCadenceSensor != null && _runningCadenceSensor?.device?.id.id != device?.id.id) {
      await _runningCadenceSensor?.detach();
      _runningCadenceSensor = null;
    }
    if (sport == ActivityType.run) {
      if (services.firstWhereOrNull(
              (service) => service.uuid.uuidString() == runningCadenceServiceUuid) !=
          null) {
        _runningCadenceSensor = RunningCadenceSensor(device, powerFactor);
        _runningCadenceSensor?.services = services;
        _runningCadenceSensor?.discoverCore();
        await _runningCadenceSensor?.attach();
      }
    }
  }

  void setActivity(Activity activity) {
    _activity = activity;
    lastRecord = RecordWithSport.getZero(sport);
    workoutState = WorkoutState.waitingForFirstMove;
    dataHandlers = {};
    readConfiguration();
  }

  Future<bool> connectOnDemand({identify = false}) async {
    await connect();

    return await discover(identify: identify);
  }

  /// Needed to check if any of the last seen data stubs for each
  /// combination indicated movement. #234 #259
  bool wasNotMoving() {
    if (dataHandlers.isEmpty) {
      return true;
    }

    return dataHandlers.values.skip(1).fold<bool>(
          dataHandlers.values.first.lastNotMoving,
          (prev, element) => prev && element.lastNotMoving,
        );
  }

  @override
  Future<bool> discover({bool identify = false, bool retry = false}) async {
    if (uxDebug) return true;

    final success = await super.discover(retry: retry);
    if (identify || !success) return success;

    if (_equipmentDiscovery || descriptor == null) return false;

    _equipmentDiscovery = true;
    // Check manufacturer name
    if (manufacturerName == null) {
      final deviceInfo = BluetoothDeviceEx.filterService(services, deviceInformationUuid);
      final nameCharacteristic =
          BluetoothDeviceEx.filterCharacteristic(deviceInfo?.characteristics, manufacturerNameUuid);
      if (nameCharacteristic == null) {
        return false;
      }

      try {
        final nameBytes = await nameCharacteristic.read();
        manufacturerName = String.fromCharCodes(nameBytes);
      } on PlatformException catch (e, stack) {
        if (_logLevel > logLevelNone) {
          Logging.logException(
            _logLevel,
            "FITNESS_EQUIPMENT",
            "discover",
            "Could not read name",
            e,
            stack,
          );
        }

        if (kDebugMode) {
          debugPrint("$e");
          debugPrintStack(stackTrace: stack, label: "trace:");
        }

        // 2nd try
        try {
          final nameBytes = await nameCharacteristic.read();
          manufacturerName = String.fromCharCodes(nameBytes);
        } on PlatformException catch (e, stack) {
          if (_logLevel > logLevelNone) {
            Logging.logException(
              _logLevel,
              "FITNESS_EQUIPMENT",
              "discover",
              "Could not read name 2nd try",
              e,
              stack,
            );
          }

          if (kDebugMode) {
            debugPrint("$e");
            debugPrintStack(stackTrace: stack, label: "trace:");
          }
        }
      }
    }

    _equipmentDiscovery = false;
    return manufacturerName!.contains(descriptor!.manufacturerPrefix) ||
        descriptor!.manufacturerPrefix == "Unknown";
  }

  @visibleForTesting
  void setFactors(powerFactor, calorieFactor, hrCalorieFactor, hrmCalorieFactor, extendTuning) {
    this.powerFactor = powerFactor;
    this.calorieFactor = calorieFactor;
    this.hrCalorieFactor = hrCalorieFactor;
    this.hrmCalorieFactor = hrmCalorieFactor;
    _extendTuning = extendTuning;
  }

  RecordWithSport processRecord(RecordWithSport stub) {
    final now = DateTime.now();
    // State Machine for #231 and #235
    // (intelligent start and elapsed time tracking)
    bool isNotMoving = stub.isNotMoving();
    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "processRecord",
        "workoutState $workoutState isNotMoving $isNotMoving",
      );
    }
    if (workoutState == WorkoutState.waitingForFirstMove) {
      if (isNotMoving) {
        return lastRecord;
      } else {
        dataHandlers = {};
        workoutState = WorkoutState.moving;
        // Null activity should only happen in UX simulation mode
        if (_activity != null) {
          _activity!.startDateTime = now;
          _activity!.start = now.millisecondsSinceEpoch;
          if (Get.isRegistered<AppDatabase>()) {
            final database = Get.find<AppDatabase>();
            database.activityDao.updateActivity(_activity!);
          }
        }
      }
    } else {
      // merged stub can be isNotMoving if due to timing interference
      // only such packets gathered which don't contain moving data
      // (such as distance, calories, elapsed time).
      // The only way to be sure in case of multi packet type machines
      // is to check if all of the data handlers report non movement.
      // Once all types of packets indicate non movement we can be sure
      // that the workout is stopped.
      if (isNotMoving && wasNotMoving()) {
        if (workoutState == WorkoutState.moving) {
          workoutState = WorkoutState.justStopped;
        } else if (workoutState == WorkoutState.justStopped) {
          workoutState = WorkoutState.stopped;
        }
      } else {
        workoutState = WorkoutState.moving;
      }
    }

    if (descriptor != null) {
      stub = descriptor!.adjustRecord(stub, powerFactor, calorieFactor, _extendTuning);
      if (_logLevel >= logLevelInfo) {
        Logging.log(
          _logLevel,
          logLevelInfo,
          "FITNESS_EQUIPMENT",
          "processRecord",
          "adjusted stub $stub",
        );
      }
    }

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "processRecord",
        "_residueCalories $_residueCalories, "
            "_lastPositiveCadence $_lastPositiveCadence, "
            "_lastPositiveCalories $_lastPositiveCalories, "
            "firstCalories $firstCalories, "
            "_startingCalories $_startingCalories, "
            "firstDistance $firstDistance, "
            "_startingDistance $_startingDistance, "
            "firstTime $firstTime, "
            "_startingElapsed $_startingElapsed, "
            "hasTotalCalorieReporting $hasTotalCalorieReporting, "
            "hasTotalDistanceReporting $hasTotalDistanceReporting, "
            "hasTotalTimeReporting $hasTotalTimeReporting",
      );
    }

    int elapsedMillis = now.difference(_activity?.startDateTime ?? now).inMilliseconds;
    double elapsed = elapsedMillis / 1000.0;
    // When the equipment supplied multiple data read per second but the Fitness Machine
    // standard only supplies second resolution elapsed time the delta time becomes zero
    // Therefore the FTMS elapsed time reading is kinda useless, causes problems.
    // With this fix the calorie zeroing bug is revealed. Calorie preserving workaround can be
    // toggled in the settings now. Only the distance perseverance could pose a glitch. #94
    final deviceReportsTotalCalories = stub.calories != null;
    final hrmRecord = heartRateMonitor?.record != null
        ? descriptor!.adjustRecord(
            heartRateMonitor!.record!,
            powerFactor,
            hrmCalorieFactor,
            _extendTuning,
          )
        : null;
    final hrmReportsCalories = hrmRecord?.calories != null;
    // All of these starting* and hasTotal* codes have to come before the (optional) merge
    // and after tuning / factoring adjustments #197
    hasTotalCalorieReporting =
        hasTotalCalorieReporting || deviceReportsTotalCalories || hrmReportsCalories;
    if (firstCalories && hasTotalCalorieReporting) {
      if (_useHrmReportedCalories) {
        if ((hrmRecord?.calories ?? 0) >= 1) {
          _startingCalories = hrmRecord!.calories!.toDouble();
          firstCalories = false;
        }
      } else if ((stub.calories ?? 0) >= 1) {
        _startingCalories = stub.calories!.toDouble();
        firstCalories = false;
      }
    }

    hasTotalDistanceReporting |= stub.distance != null;
    if (hasTotalDistanceReporting && firstDistance && (stub.distance ?? 0.0) >= 50.0) {
      _startingDistance = stub.distance!;
      firstDistance = false;
    }

    hasTotalTimeReporting |= stub.elapsed != null;
    if (hasTotalTimeReporting && firstTime && (stub.elapsed ?? 0) > 2) {
      _startingElapsed = stub.elapsed!;
      firstTime = false;
    }

    if (shouldMerge) {
      stub.merge(
        lastRecord,
        _cadenceGapWorkaround,
        _heartRateGapWorkaround == dataGapWorkaroundLastPositiveValue,
      );
    }

    if (hasTotalCalorieReporting && stub.elapsed != null) {
      elapsed = stub.elapsed!.toDouble();
    }

    if (stub.elapsed == null || stub.elapsed == 0) {
      stub.elapsed = elapsed.round();
    }

    if (stub.elapsedMillis == null || stub.elapsedMillis == 0) {
      stub.elapsedMillis = elapsedMillis;
    }

    // #197
    if (_startingElapsed > 0) {
      stub.elapsed = stub.elapsed! - _startingElapsed;
    }

    if (workoutState == WorkoutState.stopped) {
      // We have to track the time ticking still #235
      lastRecord.elapsed = stub.elapsed;
      lastRecord.elapsedMillis = stub.elapsedMillis;
      return lastRecord;
    }

    RecordWithSport? rscRecord;
    if (sport == ActivityType.run &&
        _runningCadenceSensor != null &&
        (_runningCadenceSensor?.attached ?? false)) {
      if (_runningCadenceSensor?.record != null) {
        rscRecord = descriptor!.adjustRecord(
          _runningCadenceSensor!.record!,
          powerFactor,
          calorieFactor,
          _extendTuning,
        );
      }

      if ((stub.cadence == null || stub.cadence == 0) && (rscRecord?.cadence ?? 0) > 0) {
        stub.cadence = rscRecord!.cadence;
      }

      if ((stub.speed == null || stub.speed == 0) && (rscRecord?.speed ?? 0.0) > eps) {
        stub.speed = rscRecord!.speed;
      }

      if ((stub.distance == null || stub.distance == 0) && (rscRecord?.distance ?? 0.0) > eps) {
        stub.distance = rscRecord!.distance;
      }
    }

    final dTMillis = elapsedMillis - (lastRecord.elapsedMillis ?? 0);
    final dT = dTMillis / 1000.0;
    if ((stub.distance ?? 0.0) < eps) {
      stub.distance = (lastRecord.distance ?? 0);
      if ((stub.speed ?? 0.0) > 0 && dT > eps) {
        // Speed possibly already has powerFactor effect
        double dD = (stub.speed ?? 0.0) * DeviceDescriptor.kmh2ms * dT;
        stub.distance = stub.distance! + dD;
      }
    }

    // #235
    stub.movingTime = lastRecord.movingTime + dTMillis;
    // #197 After 2 seconds we assume all types of feature packets showed up
    // and it should have been decided if there's total distance / calories
    // time reporting or not
    if (stub.movingTime >= 2000) {
      firstDistance = false;
      firstTime = false;
      firstCalories = false;
    }

    // #197
    stub.distance ??= 0.0;
    if (_startingDistance > eps) {
      stub.distance = stub.distance! - _startingDistance;
    }

    if ((stub.heartRate == null || stub.heartRate == 0) && (hrmRecord?.heartRate ?? 0) > 0) {
      stub.heartRate = hrmRecord!.heartRate;
    }

    // #93, #113
    if ((stub.heartRate == null || stub.heartRate == 0) &&
        (lastRecord.heartRate ?? 0) > 0 &&
        _heartRateGapWorkaround == dataGapWorkaroundLastPositiveValue) {
      stub.heartRate = lastRecord.heartRate;
    }

    // #114
    if (_heartRateUpperLimit > 0 &&
        (stub.heartRate ?? 0) > _heartRateUpperLimit &&
        _heartRateLimitingMethod != heartRateLimitingNoLimit) {
      if (_heartRateLimitingMethod == heartRateLimitingCapAtLimit) {
        stub.heartRate = _heartRateUpperLimit;
      } else {
        stub.heartRate = 0;
      }
    }

    var calories1 = 0.0;
    if (stub.calories != null && stub.calories! > 0) {
      calories1 = stub.calories!.toDouble();
    }

    var calories2 = 0.0;
    if ((hrmRecord?.calories ?? 0) > 0) {
      calories2 = hrmRecord?.calories?.toDouble() ?? 0.0;
    }

    var calories = 0.0;
    if (calories1 > eps &&
        (!_useHrmReportedCalories || calories2 < eps) &&
        (!_useHrBasedCalorieCounting || stub.heartRate == null || stub.heartRate == 0)) {
      calories = calories1;
    } else if (calories2 > eps &&
        (_useHrmReportedCalories || calories1 < eps) &&
        (!_useHrBasedCalorieCounting || stub.heartRate == null || stub.heartRate == 0)) {
      calories = calories2;
    } else {
      var deltaCalories = 0.0;
      if (_useHrBasedCalorieCounting && stub.heartRate != null && stub.heartRate! > 0) {
        stub.caloriesPerMinute =
            hrBasedCaloriesPerMinute(stub.heartRate!, _weight, _age, _isMale, _vo2Max) *
                hrCalorieFactor;
      }

      if (deltaCalories < eps && stub.caloriesPerHour != null && stub.caloriesPerHour! > eps) {
        deltaCalories = stub.caloriesPerHour! / (60 * 60) * dT;
      }

      if (deltaCalories < eps && stub.caloriesPerMinute != null && stub.caloriesPerMinute! > eps) {
        deltaCalories = stub.caloriesPerMinute! / 60 * dT;
      }

      // Supplement power from calories https://www.braydenwm.com/calburn.htm
      if ((stub.power ?? 0) < eps) {
        if ((stub.caloriesPerMinute ?? 0.0) > eps) {
          stub.power = (stub.caloriesPerMinute! * 50.0 / 3.0).round(); // 60 * 1000 / 3600
        } else if ((stub.caloriesPerHour ?? 0.0) > eps) {
          stub.power = (stub.caloriesPerHour! * 5.0 / 18.0).round(); // 1000 / 3600
        }

        if (stub.power != null) {
          stub.power = (stub.power! * powerFactor).round();
        }
      }

      // Should we only use power based calorie integration if sport == ActivityType.ride?
      if (deltaCalories < eps && stub.power != null && stub.power! > eps) {
        deltaCalories =
            stub.power! * dT * jToKCal * calorieFactor * DeviceDescriptor.powerCalorieFactorDefault;
      }

      _residueCalories += deltaCalories;
      final lastCalories = lastRecord.calories ?? 0.0;
      calories = lastCalories + _residueCalories;
      if (calories.floor() > lastCalories) {
        _residueCalories = calories - calories.floor();
      }
    }

    if (stub.pace != null && stub.pace! > 0 && slowPace != null && stub.pace! < slowPace! ||
        stub.speed != null && stub.speed! > eps) {
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
    if (calories < eps && _lastPositiveCalories > 0) {
      calories = _lastPositiveCalories;
    } else {
      _lastPositiveCalories = calories;
    }

    // #197
    if (_startingCalories > eps) {
      if (kDebugMode) {
        assert(hasTotalCalorieReporting);
      }

      if (_logLevel >= logLevelInfo) {
        Logging.log(
          _logLevel,
          logLevelInfo,
          "FITNESS_EQUIPMENT",
          "processRecord",
          "starting calorie adj $calories - $_startingCalories",
        );
      }

      calories -= _startingCalories;
    }

    stub.calories = calories.floor();
    stub.activityId = _activity?.id ?? 0;
    stub.sport = descriptor?.defaultSport ?? ActivityType.ride;

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "processRecord",
        "stub before cumul $stub",
      );
    }

    stub.cumulativeMetricsEnforcements(
      lastRecord,
      forDistance: !firstDistance,
      forTime: !firstTime,
      forCalories: !firstCalories,
    );

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "processRecord",
        "stub after cumul $stub",
      );
    }

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "processRecord",
        "_residueCalories $_residueCalories, "
            "_lastPositiveCadence $_lastPositiveCadence, "
            "_lastPositiveCalories $_lastPositiveCalories, "
            "firstCalories $firstCalories, "
            "_startingCalories $_startingCalories, "
            "firstDistance $firstDistance, "
            "_startingDistance $_startingDistance, "
            "firstTime $firstTime, "
            "_startingElapsed $_startingElapsed, "
            "hasTotalCalorieReporting $hasTotalCalorieReporting, "
            "hasTotalDistanceReporting $hasTotalDistanceReporting, "
            "hasTotalTimeReporting $hasTotalTimeReporting",
      );
    }

    lastRecord = stub;
    return stub;
  }

  Future<void> refreshFactors() async {
    if (!Get.isRegistered<AppDatabase>()) {
      return;
    }

    final database = Get.find<AppDatabase>();
    final factors = await database.getFactors(device?.id.id ?? "");
    powerFactor = factors.item1;
    calorieFactor = factors.item2;
    hrCalorieFactor = factors.item3;
    hrmCalorieFactor =
        await database.calorieFactorValue(heartRateMonitor?.device?.id.id ?? "", true);

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "refreshFactors",
        "powerFactor $powerFactor, "
            "calorieFactor $calorieFactor, "
            "hrCalorieFactor $hrCalorieFactor, "
            "hrmCalorieFactor $hrmCalorieFactor",
      );
    }
  }

  void readConfiguration() {
    final prefService = Get.find<BasePrefService>();
    _cadenceGapWorkaround =
        prefService.get<bool>(cadenceGapWorkaroundTag) ?? cadenceGapWorkaroundDefault;
    uxDebug = prefService.get<bool>(appDebugModeTag) ?? appDebugModeDefault;
    _heartRateGapWorkaround =
        prefService.get<String>(heartRateGapWorkaroundTag) ?? heartRateGapWorkaroundDefault;
    _heartRateUpperLimit =
        prefService.get<int>(heartRateUpperLimitIntTag) ?? heartRateUpperLimitDefault;
    _heartRateLimitingMethod =
        prefService.get<String>(heartRateLimitingMethodTag) ?? heartRateLimitingMethodDefault;
    _useHrmReportedCalories = prefService.get<bool>(useHrMonitorReportedCaloriesTag) ??
        useHrMonitorReportedCaloriesDefault;
    _useHrBasedCalorieCounting = prefService.get<bool>(useHeartRateBasedCalorieCountingTag) ??
        useHeartRateBasedCalorieCountingDefault;
    _weight = prefService.get<int>(athleteBodyWeightIntTag) ?? athleteBodyWeightDefault;
    _age = prefService.get<int>(athleteAgeTag) ?? athleteAgeDefault;
    _isMale =
        (prefService.get<String>(athleteGenderTag) ?? athleteGenderDefault) == athleteGenderMale;
    _vo2Max = prefService.get<int>(athleteVO2MaxTag) ?? athleteVO2MaxDefault;
    _useHrBasedCalorieCounting &= (_weight > athleteBodyWeightMin && _age > athleteAgeMin);
    _extendTuning = prefService.get<bool>(extendTuningTag) ?? extendTuningDefault;
    _logLevel = prefService.get<int>(logLevelTag) ?? logLevelDefault;

    if (_logLevel >= logLevelInfo) {
      Logging.log(
        _logLevel,
        logLevelInfo,
        "FITNESS_EQUIPMENT",
        "readConfiguration",
        "cadenceGapWorkaround $_cadenceGapWorkaround, "
            "uxDebug $uxDebug, "
            "heartRateGapWorkaround $_heartRateGapWorkaround, "
            "heartRateUpperLimit $_heartRateUpperLimit, "
            "heartRateLimitingMethod $_heartRateLimitingMethod, "
            "useHrmReportedCalories $_useHrmReportedCalories, "
            "useHrBasedCalorieCounting $_useHrBasedCalorieCounting, "
            "weight $_weight, "
            "age $_age, "
            "isMale $_isMale, "
            "vo2Max $_vo2Max, "
            "useHrBasedCalorieCounting $_useHrBasedCalorieCounting, "
            "extendTuning $_extendTuning, "
            "logLevel $_logLevel",
      );
    }

    refreshFactors();
  }

  void startWorkout() {
    readConfiguration();
    _residueCalories = 0.0;
    _lastPositiveCalories = 0.0;
    firstCalories = true;
    firstDistance = true;
    firstTime = true;
    _startingCalories = 0.0;
    _startingDistance = 0.0;
    _startingElapsed = 0;
    dataHandlers = {};
    lastRecord = RecordWithSport.getZero(sport);
  }

  void stopWorkout() {
    readConfiguration();
    _residueCalories = 0.0;
    _lastPositiveCalories = 0.0;
    _timer?.cancel();
    descriptor?.stopWorkout();
  }

  @override
  Future<void> detach() async {
    await super.detach();
    await _runningCadenceSensor?.detach();
  }
}

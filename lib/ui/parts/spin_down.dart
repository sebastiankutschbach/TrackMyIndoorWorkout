import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:pref/pref.dart';
import 'package:rxdart/rxdart.dart';
import 'package:spinner_input/spinner_input.dart';
import 'package:tuple/tuple.dart';
import '../../devices/gadgets/fitness_equipment.dart';
import '../../devices/bluetooth_device_ex.dart';
import '../../devices/gatt_constants.dart';
import '../../preferences/athlete_body_weight.dart';
import '../../preferences/unit_system.dart';
import '../../utils/constants.dart';
import '../../utils/delays.dart';
import '../../utils/display.dart';
import '../../utils/theme_manager.dart';

class SpinDownBottomSheet extends StatefulWidget {
  const SpinDownBottomSheet({Key? key}) : super(key: key);

  @override
  _SpinDownBottomSheetState createState() => _SpinDownBottomSheetState();
}

enum CalibrationState {
  preInit,
  initializing,
  readyToWeighIn,
  weightSubmitting,
  weighInProblem,
  weighInSuccess,
  readyToCalibrate,
  calibrationStarting,
  calibrationInProgress,
  calibrationOver,
  calibrationSuccess,
  calibrationFail,
  notSupported,
}

class _SpinDownBottomSheetState extends State<SpinDownBottomSheet> {
  static const stepWeightInput = 0;
  static const stepCalibrating = 1;
  static const stepDone = 2;
  static const stepNotSupported = 3;

  FitnessEquipment? _fitnessEquipment;
  double _sizeDefault = 10.0;
  TextStyle _smallerTextStyle = const TextStyle();
  TextStyle _largerTextStyle = const TextStyle();
  bool _si = unitSystemDefault;
  int _step = stepWeightInput;
  int _weight = 80;
  int _oldWeightLsb = 0;
  int _oldWeightMsb = 0;
  int _newWeightLsb = 0;
  int _newWeightMsb = 0;
  BluetoothCharacteristic? _weightData;
  StreamSubscription? _weightDataSubscription;
  BluetoothCharacteristic? _controlPoint;
  StreamSubscription? _controlPointSubscription;
  BluetoothCharacteristic? _fitnessMachineStatus;
  StreamSubscription? _statusSubscription;
  CalibrationState _calibrationState = CalibrationState.preInit;
  double _targetSpeedHigh = 0.0;
  double _targetSpeedLow = 0.0;
  double _currentSpeed = 0.0;
  String _targetSpeedHighString = "...";
  String _targetSpeedLowString = "...";
  String _currentSpeedString = "...";
  final ThemeManager _themeManager = Get.find<ThemeManager>();
  bool _isLight = true;
  int _preferencesWeight = athleteBodyWeightDefault;
  bool _rememberLastWeight = rememberAthleteBodyWeightDefault;

  bool get _spinDownPossible =>
      _weightData != null &&
      _controlPoint != null &&
      _fitnessMachineStatus != null &&
      _fitnessEquipment?.characteristic != null;
  bool get _canSubmitWeight =>
      _spinDownPossible && _calibrationState == CalibrationState.readyToWeighIn;

  Tuple2<int, int> getWeightBytes(int weight) {
    final weightTransport = (weight * (_si ? 1.0 : lbToKg) * 200).round();
    return Tuple2<int, int>(weightTransport % maxUint8, weightTransport ~/ maxUint8);
  }

  int getWeightFromBytes(int weightLsb, int weightMsb) {
    return (weightLsb + weightMsb * maxUint8) / (_si ? 1.0 : lbToKg) ~/ 200;
  }

  @override
  void initState() {
    _fitnessEquipment = Get.isRegistered<FitnessEquipment>() ? Get.find<FitnessEquipment>() : null;
    final prefService = Get.find<BasePrefService>();
    _si = prefService.get<bool>(unitSystemTag) ?? unitSystemDefault;
    _rememberLastWeight =
        prefService.get<bool>(rememberAthleteBodyWeightTag) ?? rememberAthleteBodyWeightDefault;
    _preferencesWeight = prefService.get<int>(athleteBodyWeightIntTag) ?? athleteBodyWeightDefault;
    _weight = (_preferencesWeight * (_si ? 1.0 : kgToLb)).round();
    final weightBytes = getWeightBytes(_weight);
    _oldWeightLsb = weightBytes.item1;
    _oldWeightMsb = weightBytes.item2;
    _newWeightLsb = weightBytes.item1;
    _newWeightMsb = weightBytes.item2;
    _isLight = !_themeManager.isDark();
    _smallerTextStyle = Get.textTheme.headline5!.apply(
      fontFamily: fontFamily,
      color: _themeManager.getProtagonistColor(),
    );
    _sizeDefault = _smallerTextStyle.fontSize!;
    _largerTextStyle = Get.textTheme.headline2!.apply(
      fontFamily: fontFamily,
      color: _themeManager.getProtagonistColor(),
    );
    _prepareSpinDown();
    super.initState();
  }

  // Crazy! https://stackoverflow.com/a/50337157/292502
  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    } else {
      debugPrint("Turd in the punch bowl!");
    }
  }

  Future<bool> _prepareSpinDownCore() async {
    if (_fitnessEquipment == null || _fitnessEquipment?.device == null) return false;

    if (!(_fitnessEquipment?.connected ?? false)) {
      await _fitnessEquipment?.connect();
    }

    if (!(_fitnessEquipment?.connected ?? false)) return false;

    if (!(_fitnessEquipment?.discovered ?? false)) {
      await _fitnessEquipment?.discover();
    }

    if (!(_fitnessEquipment?.discovered ?? false)) return false;

    final userData =
        BluetoothDeviceEx.filterService(_fitnessEquipment?.services ?? [], userDataServiceUuid);
    _weightData =
        BluetoothDeviceEx.filterCharacteristic(userData?.characteristics, weightCharacteristicUuid);
    if (_weightData == null) return false;

    final fitnessMachine =
        BluetoothDeviceEx.filterService(_fitnessEquipment?.services ?? [], fitnessMachineUuid);
    _controlPoint = BluetoothDeviceEx.filterCharacteristic(
        fitnessMachine?.characteristics, fitnessMachineControlPointUuid);
    _fitnessMachineStatus = BluetoothDeviceEx.filterCharacteristic(
        fitnessMachine?.characteristics, fitnessMachineStatusUuid);
    if (_controlPoint == null || _fitnessMachineStatus == null) return false;

    // #117 Attach the handler way ahead of the actual weight write
    try {
      await _weightData?.setNotifyValue(true);
    } on PlatformException catch (e, stack) {
      debugPrint("$e");
      debugPrintStack(stackTrace: stack, label: "trace:");
    }

    _weightDataSubscription = _weightData?.value
        .throttleTime(
      const Duration(milliseconds: spinDownThreshold),
      leading: false,
      trailing: true,
    )
        .listen((response) async {
      if (response.length == 1 && _calibrationState == CalibrationState.weightSubmitting) {
        if (response[0] != weightSuccessOpcode) {
          setState(() {
            _calibrationState = CalibrationState.weighInProblem;
          });
        }
      } else if (response.length == 2) {
        if (_calibrationState == CalibrationState.readyToWeighIn) {
          setState(() {
            _calibrationState = CalibrationState.weighInProblem;
            _oldWeightLsb = response[0];
            _oldWeightMsb = response[1];
            _weight = getWeightFromBytes(_oldWeightLsb, _oldWeightMsb);
          });
        } else {
          if (response[0] == _newWeightLsb && response[1] == _newWeightMsb) {
            setState(() {
              _step = stepCalibrating;
              _calibrationState = CalibrationState.readyToCalibrate;
            });
          } else {
            setState(() {
              _calibrationState = CalibrationState.weighInProblem;
            });
          }
        }
      } else if (_calibrationState == CalibrationState.weightSubmitting) {
        try {
          await _weightData?.write([_newWeightLsb, _newWeightMsb]);
        } on PlatformException catch (e, stack) {
          debugPrint("$e");
          debugPrintStack(stackTrace: stack, label: "trace:");
          setState(() {
            _calibrationState = CalibrationState.weighInProblem;
          });
        }
      }
    });

    // #117 Attach the handler way ahead of the spin down start command write
    try {
      await _controlPoint?.setNotifyValue(true); // Is this what needed for indication?
    } on PlatformException catch (e, stack) {
      debugPrint("$e");
      debugPrintStack(stackTrace: stack, label: "trace:");
    }

    _controlPointSubscription = _controlPoint?.value
        .throttleTime(
      const Duration(milliseconds: spinDownThreshold),
      leading: false,
      trailing: true,
    )
        .listen((data) async {
      if (data.length == 1) {
        if (data[0] != spinDownOpcode) {
          setState(() {
            _step = stepDone;
            _calibrationState = CalibrationState.calibrationFail;
          });
        }
      }

      if (data.length == 7) {
        if (data[0] != controlOpcode || data[1] != spinDownOpcode || data[2] != successResponse) {
          setState(() {
            _step = stepDone;
            _calibrationState = CalibrationState.calibrationFail;
          });
          return;
        }
        setState(() {
          _calibrationState = CalibrationState.calibrationInProgress;
          _targetSpeedHigh = (data[3] * maxUint8 + data[4]) / 100;
          _targetSpeedHighString = speedOrPaceString(
              _targetSpeedHigh, _si, _fitnessEquipment?.sport ?? ActivityType.ride);
          _targetSpeedLow = (data[5] * maxUint8 + data[6]) / 100;
          _targetSpeedLowString = speedOrPaceString(
              _targetSpeedLow, _si, _fitnessEquipment?.sport ?? ActivityType.ride);
        });
      }
    });

    return _spinDownPossible;
  }

  Future<void> _prepareSpinDown() async {
    final success = await _prepareSpinDownCore();
    setState(() {
      if (!success) {
        _step = stepNotSupported;
        _calibrationState = CalibrationState.notSupported;
      } else {
        _calibrationState = CalibrationState.readyToWeighIn;
      }
    });
  }

  ButtonStyle _buttonBackgroundStyle() {
    var backColor = _isLight ? Colors.black12 : Colors.black87;
    if (_calibrationState == CalibrationState.weighInProblem ||
        _calibrationState == CalibrationState.calibrationFail ||
        _calibrationState == CalibrationState.notSupported) {
      backColor = _isLight ? Colors.red.shade50 : Colors.red.shade900;
    } else if (_calibrationState == CalibrationState.readyToWeighIn ||
        _calibrationState == CalibrationState.weighInSuccess ||
        _calibrationState == CalibrationState.readyToCalibrate ||
        _calibrationState == CalibrationState.calibrationSuccess) {
      backColor = _isLight ? Colors.lightGreen.shade100 : Colors.green.shade900;
    }

    return ElevatedButton.styleFrom(primary: backColor);
  }

  String _weightInputButtonText() {
    if (_calibrationState == CalibrationState.weighInSuccess) return 'Next >';
    if (_calibrationState == CalibrationState.readyToWeighIn) return 'Submit';
    if (_calibrationState == CalibrationState.weighInProblem) return 'Retry';

    return 'Wait...';
  }

  TextStyle _weightInputButtonTextStyle() {
    return _smallerTextStyle.merge(TextStyle(
        color: _calibrationState == CalibrationState.weighInSuccess || _canSubmitWeight
            ? (_isLight ? Colors.black : Colors.white)
            : (_isLight ? Colors.black87 : Colors.white70)));
  }

  ButtonStyle _weightInputButtonStyle() {
    return ElevatedButton.styleFrom(
      primary: _calibrationState == CalibrationState.weighInSuccess || _canSubmitWeight
          ? (_isLight ? Colors.lightGreen.shade100 : Colors.green.shade900)
          : (_isLight ? Colors.black12 : Colors.black87),
    );
  }

  Future<void> _onWeightInputButtonPressed() async {
    if (_calibrationState == CalibrationState.weighInSuccess) {
      return;
    }

    if (_calibrationState == CalibrationState.preInit ||
        _calibrationState == CalibrationState.initializing) {
      Get.snackbar("Please wait", "Initializing equipment for calibration...");
      return;
    }
    if (_calibrationState == CalibrationState.weightSubmitting) {
      Get.snackbar("Please wait", "Weight submission is in progress...");
      return;
    }

    setState(() {
      _calibrationState = CalibrationState.weightSubmitting;
    });
    final newWeightBytes = getWeightBytes(_weight);
    _newWeightLsb = newWeightBytes.item1;
    _newWeightMsb = newWeightBytes.item2;
    try {
      if (_rememberLastWeight) {
        final weightKg = _weight * (_si ? 1.0 : lbToKg);
        final prefService = Get.find<BasePrefService>();
        await prefService.set<int>(athleteBodyWeightTag, weightKg.round());
      }

      await _weightData?.write([_newWeightLsb, _newWeightMsb]);
    } on PlatformException catch (e, stack) {
      debugPrint("$e");
      debugPrintStack(stackTrace: stack, label: "trace:");
      setState(() {
        _calibrationState = CalibrationState.weighInProblem;
      });
    }
  }

  String _calibrationInstruction() {
    if (_calibrationState == CalibrationState.readyToCalibrate) {
      return "READY!";
    }

    if (_calibrationState == CalibrationState.calibrationStarting) {
      return "START!";
    }

    if (_calibrationState == CalibrationState.calibrationInProgress) {
      if (_currentSpeed < eps || _currentSpeed < _targetSpeedLow) {
        return "FASTER";
      } else if (_currentSpeed > _targetSpeedHigh) {
        return "SLOWER";
      } else {
        return "_";
      }
    }
    return "STOP!";
  }

  TextStyle _calibrationInstructionStyle() {
    var color = _themeManager.getRedColor();

    if (_calibrationState == CalibrationState.readyToCalibrate ||
        _calibrationState == CalibrationState.calibrationStarting) {
      color = _themeManager.getGreenColor();
    }

    if (_calibrationState == CalibrationState.calibrationInProgress) {
      color = _themeManager.getBlueColor();
    }

    return _largerTextStyle.merge(TextStyle(color: color));
  }

  String _calibrationButtonText() {
    if (_calibrationState == CalibrationState.readyToCalibrate) return 'Start';

    if (_calibrationState == CalibrationState.calibrationStarting) return 'Wait...';

    return 'Stop';
  }

  Future<void> onCalibrationButtonPressed() async {
    if (_calibrationState == CalibrationState.calibrationStarting) {
      Get.snackbar("Calibration", "Wait for instructions!");
      return;
    }
    setState(() {
      _calibrationState = CalibrationState.calibrationStarting;
    });

    try {
      await _controlPoint?.write([spinDownOpcode, spinDownStartCommand]);
      await _fitnessMachineStatus?.setNotifyValue(true);
    } on PlatformException catch (e, stack) {
      debugPrint("$e");
      debugPrintStack(stackTrace: stack, label: "trace:");
    }

    _statusSubscription = _fitnessMachineStatus?.value
        .throttleTime(
      const Duration(milliseconds: ftmsStatusThreshold),
      leading: false,
      trailing: true,
    )
        .listen((status) {
      if (status.length == 2 && status[0] == spinDownStatus) {
        if (status[1] == spinDownStatusSuccess) {
          _reset();
          setState(() {
            _step = stepDone;
            _calibrationState = CalibrationState.calibrationSuccess;
          });
        }
        if (status[1] == spinDownStatusError) {
          _reset();
          setState(() {
            _step = stepDone;
            _calibrationState = CalibrationState.calibrationFail;
          });
        }
        if (status[1] == spinDownStatusStopPedaling) {
          setState(() {
            _calibrationState = CalibrationState.calibrationOver;
          });
        }
      }
    });

    await _fitnessEquipment?.attach();
    _fitnessEquipment?.calibrating = true;
    _fitnessEquipment?.pumpData((record) async {
      setState(() {
        _currentSpeed = record.speed ?? 0.0;
        _currentSpeedString =
            record.speedOrPaceStringByUnit(_si, _fitnessEquipment?.sport ?? ActivityType.ride);
      });
    });
  }

  Future<void> _detachControlPoint() async {
    await _controlPoint?.setNotifyValue(false);
    _controlPointSubscription?.cancel();
  }

  Future<void> _detachWeightData() async {
    await _weightData?.setNotifyValue(false);
    _weightDataSubscription?.cancel();
  }

  Future<void> _detachFitnessMachineStatus() async {
    _fitnessMachineStatus?.setNotifyValue(false);
    _statusSubscription?.cancel();
  }

  Future<void> _detachFitnessMachine() async {
    _fitnessEquipment?.calibrating = false;
    await _fitnessEquipment?.detach();
  }

  Future<void> _reset() async {
    await _detachControlPoint();
    await _detachWeightData();
    await _detachFitnessMachineStatus();
    await _detachFitnessMachine();
  }

  @override
  void dispose() {
    _reset();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: IndexedStack(
          index: _step,
          children: [
            // 0 - STEP_WEIGHT_INPUT
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("Weight (${_si ? "kg" : "lbs"}):", style: _smallerTextStyle),
                  SpinnerInput(
                    spinnerValue: _weight.toDouble(),
                    minValue: 1,
                    maxValue: 800,
                    middleNumberStyle: _largerTextStyle,
                    plusButton: SpinnerButtonStyle(
                      height: _sizeDefault * 2,
                      width: _sizeDefault * 2,
                      child: Icon(Icons.add, size: _sizeDefault * 2 - 10),
                    ),
                    minusButton: SpinnerButtonStyle(
                      height: _sizeDefault * 2,
                      width: _sizeDefault * 2,
                      child: Icon(Icons.remove, size: _sizeDefault * 2 - 10),
                    ),
                    onChange: (newValue) {
                      setState(() {
                        _weight = newValue.toInt();
                      });
                    },
                  ),
                  ElevatedButton(
                    child: Text(
                      _weightInputButtonText(),
                      style: _weightInputButtonTextStyle(),
                    ),
                    style: _weightInputButtonStyle(),
                    onPressed: () async => await _onWeightInputButtonPressed(),
                  ),
                ],
              ),
            ),
            // 1 - STEP_CALIBRATING
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(_targetSpeedLowString, style: _smallerTextStyle),
                      Icon(Icons.compare_arrows, size: _sizeDefault),
                      Text(_targetSpeedHighString, style: _smallerTextStyle),
                    ],
                  ),
                  Text(_currentSpeedString,
                      style:
                          _largerTextStyle.merge(TextStyle(color: _themeManager.getBlueColor()))),
                  Text(_calibrationInstruction(), style: _calibrationInstructionStyle()),
                  ElevatedButton(
                    child: Text(_calibrationButtonText(), style: _smallerTextStyle),
                    style: _buttonBackgroundStyle(),
                    onPressed: () async => await onCalibrationButtonPressed(),
                  ),
                ],
              ),
            ),
            // 2 - STEP_END
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                      _calibrationState == CalibrationState.calibrationSuccess
                          ? "SUCCESS"
                          : "ERROR",
                      style: _largerTextStyle),
                  ElevatedButton(
                    child: Text(
                        _calibrationState == CalibrationState.calibrationSuccess
                            ? 'Close'
                            : 'Retry',
                        style: _smallerTextStyle),
                    style: _buttonBackgroundStyle(),
                    onPressed: () {
                      if (_calibrationState == CalibrationState.calibrationSuccess) {
                        Get.close(1);
                      } else {
                        _fitnessEquipment?.detach();
                        setState(() {
                          _calibrationState = CalibrationState.readyToWeighIn;
                          _step = stepWeightInput;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            // 3 - STEP_NOT_SUPPORTED
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                softWrap: true,
                text: TextSpan(
                  text: "${_fitnessEquipment?.device?.name} doesn't seem to support calibration",
                  style: _smallerTextStyle,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton:
          _themeManager.getBlueFab(Icons.clear, false, false, "Close", 0, () => Get.close(1)),
    );
  }
}

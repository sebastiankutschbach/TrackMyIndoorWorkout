import '../../../utils/constants.dart';
import '../../export_model.dart';
import '../enums/fit_event.dart';
import '../enums/fit_event_type.dart';
import '../enums/fit_lap_trigger.dart';
import '../fit_base_type.dart';
import '../fit_data.dart';
import '../fit_definition_message.dart';
import '../fit_field.dart';
import '../fit_message.dart';
import '../fit_serializable.dart';
import '../fit_sport.dart';

class FitLap extends FitDefinitionMessage {
  FitLap(localMessageType) : super(localMessageType, FitMessage.Lap) {
    fields = [
      FitField(254, FitBaseTypes.uint16Type), // MessageIndex: 0
      FitField(253, FitBaseTypes.uint32Type), // Timestamp (Lap end time)
      FitField(0, FitBaseTypes.enumType), // Event
      FitField(1, FitBaseTypes.enumType), // EventType
      FitField(2, FitBaseTypes.uint32Type), // StartTime
      FitField(3, FitBaseTypes.sint32Type), // StartPositionLat
      FitField(4, FitBaseTypes.sint32Type), // StartPositionLong
      FitField(5, FitBaseTypes.sint32Type), // EndPositionLat
      FitField(6, FitBaseTypes.sint32Type), // EndPositionLong
      FitField(7, FitBaseTypes.uint32Type), // TotalElapsedTime (1/1000s)
      FitField(9, FitBaseTypes.uint32Type), // TotalDistance (1/100 m)
      FitField(11, FitBaseTypes.uint16Type), // TotalCalories (kcal)
      FitField(13, FitBaseTypes.uint16Type), // AvgSpeed (1/1000 m/s)
      FitField(14, FitBaseTypes.uint16Type), // MaxSpeed (1/1000 m/s)
      FitField(15, FitBaseTypes.uint8Type), // AvgHeartRate (bpm)
      FitField(16, FitBaseTypes.uint8Type), // MaxHeartRate (bpm)
      FitField(17, FitBaseTypes.uint8Type), // AvgCadence (rpm or spm)
      FitField(18, FitBaseTypes.uint8Type), // MaxCadence (rpm or spm)
      FitField(19, FitBaseTypes.uint16Type), // AvgPower (Watts)
      FitField(20, FitBaseTypes.uint16Type), // MaxPower (Watts)
      FitField(24, FitBaseTypes.enumType), // LapTrigger
      FitField(25, FitBaseTypes.enumType), // Sport
      FitField(39, FitBaseTypes.enumType), // Sub-Sport
    ];
  }

  @override
  List<int> serializeData(dynamic parameter) {
    ExportModel model = parameter;

    final first = model.records.first;
    final last = model.records.last;
    var data = FitData();
    data.output = [localMessageType];
    data.addShort(0);
    data.addLong(FitSerializable.fitTimeStamp(last.record.timeStamp));
    data.addByte(FitEvent.Lap);
    data.addByte(FitEventType.Stop);
    data.addLong(FitSerializable.fitTimeStamp(first.record.timeStamp));
    data.addGpsCoordinate(first.latitude);
    data.addGpsCoordinate(first.longitude);
    data.addGpsCoordinate(last.latitude);
    data.addGpsCoordinate(last.longitude);
    data.addLong(model.activity.elapsed * 1000);
    data.addLong((model.activity.distance * 100).ceil());
    data.addShort(model.activity.calories > 0
        ? model.activity.calories
        : FitBaseTypes.uint16Type.invalidValue);
    data.addShort(model.averageSpeed > EPS
        ? (model.averageSpeed * 1000).round()
        : FitBaseTypes.uint16Type.invalidValue);
    data.addShort(model.maximumSpeed > EPS
        ? (model.maximumSpeed * 1000).round()
        : FitBaseTypes.uint16Type.invalidValue);
    data.addByte(
        model.averageHeartRate > 0 ? model.averageHeartRate : FitBaseTypes.uint8Type.invalidValue);
    data.addByte(
        model.maximumHeartRate > 0 ? model.maximumHeartRate : FitBaseTypes.uint8Type.invalidValue);
    data.addByte(
        model.averageCadence > 0 ? model.averageCadence : FitBaseTypes.uint8Type.invalidValue);
    data.addByte(
        model.maximumCadence > 0 ? model.maximumCadence : FitBaseTypes.uint8Type.invalidValue);
    data.addShort(model.averagePower > EPS
        ? model.averagePower.round()
        : FitBaseTypes.uint16Type.invalidValue);
    data.addShort(model.maximumPower > EPS
        ? model.maximumPower.round()
        : FitBaseTypes.uint16Type.invalidValue);
    data.addByte(FitLapTrigger.SessionEnd);
    final fitSport = toFitSport(model.activity.sport);
    data.addByte(fitSport.item1);
    data.addByte(fitSport.item2);

    return data.output;
  }
}

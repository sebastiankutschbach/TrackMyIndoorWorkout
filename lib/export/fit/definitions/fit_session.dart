import '../../../utils/constants.dart';
import '../../export_model.dart';
import '../enums/fit_event.dart';
import '../enums/fit_event_type.dart';
import '../enums/fit_session_trigger.dart';
import '../fit_base_type.dart';
import '../fit_data.dart';
import '../fit_definition_message.dart';
import '../fit_field.dart';
import '../fit_message.dart';
import '../fit_serializable.dart';
import '../fit_sport.dart';

class FitSession extends FitDefinitionMessage {
  FitSession(localMessageType) : super(localMessageType, FitMessage.Session) {
    fields = [
      FitField(254, FitBaseTypes.uint16Type), // MessageIndex: 0
      FitField(253, FitBaseTypes.uint32Type), // Session end time
      FitField(0, FitBaseTypes.enumType), // Event
      FitField(1, FitBaseTypes.enumType), // EventType
      FitField(2, FitBaseTypes.uint32Type), // StartTime
      FitField(3, FitBaseTypes.sint32Type), // StartPositionLat
      FitField(4, FitBaseTypes.sint32Type), // StartPositionLong
      FitField(5, FitBaseTypes.enumType), // Sport
      FitField(6, FitBaseTypes.enumType), // Sub-Sport
      FitField(7, FitBaseTypes.uint32Type), // TotalElapsedTime (1/1000s)
      FitField(9, FitBaseTypes.uint32Type), // TotalDistance (1/100 m)
      FitField(11, FitBaseTypes.uint16Type), // TotalCalories (1/100 m)
      FitField(14, FitBaseTypes.uint16Type), // AvgSpeed (1/1000 m/s)
      FitField(15, FitBaseTypes.uint16Type), // MaxSpeed (1/1000 m/s)
      FitField(16, FitBaseTypes.uint8Type), // AvgHeartRate (bpm)
      FitField(17, FitBaseTypes.uint8Type), // MaxHeartRate (bpm)
      FitField(18, FitBaseTypes.uint8Type), // AvgCadence (rpm or spm)
      FitField(19, FitBaseTypes.uint8Type), // MaxCadence (rpm or spm)
      FitField(20, FitBaseTypes.uint16Type), // AvgPower (Watts)
      FitField(21, FitBaseTypes.uint16Type), // MaxPower (Watts)
      FitField(28, FitBaseTypes.enumType), // Trigger (Activity End)
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
    data.addLong(FitSerializable.fitTimeStamp(last.timeStampInteger));
    data.addByte(FitEvent.Lap);
    data.addByte(FitEventType.Stop);
    data.addLong(FitSerializable.fitTimeStamp(first.timeStampInteger));
    data.addGpsCoordinate(first.latitude);
    data.addGpsCoordinate(first.longitude);
    final fitSport = toFitSport(model.activity.sport);
    data.addByte(fitSport.item1);
    data.addByte(fitSport.item2);
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
    data.addByte(FitSessionTrigger.ActivityEnd);

    return data.output;
  }
}

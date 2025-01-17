const preferencesPrefix = "pref_";

const preferencesVersionTag = "version";
const preferencesVersionSportThresholds = 1;
const preferencesVersionEquipmentRemembrancePerSport = 2;
const preferencesVersionSpinners = 3;
const preferencesVersionDefaultingDataConnection = 4;
const preferencesVersionIncreaseWatchdogDefault = 5;
const preferencesVersionDefault = preferencesVersionIncreaseWatchdogDefault;
const preferencesVersionNext = preferencesVersionDefault + 1;

const intTagPostfix = "_int";

extension DurationDisplay on Duration {
  String toDisplay() {
    return toString().split('.').first.padLeft(8, "0");
  }
}

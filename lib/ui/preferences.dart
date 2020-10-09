import 'package:flutter/material.dart';
import 'package:preferences/preferences.dart';
import '../persistence/preferences.dart';

RegExp intListRule = RegExp(r'^\d+(,\d+)*$');

class PreferencesScreen extends StatelessWidget {
  bool isPositiveInteger(String str) {
    int integer = int.tryParse(str);
    return integer != null && integer > 0;
  }

  bool isMonotoneIncreasingList(String zonesSpecStr) {
    if (!intListRule.hasMatch(zonesSpecStr)) return false;
    List<int> intList = zonesSpecStr
        .split(',')
        .map((zs) => int.tryParse(zs))
        .toList(growable: false);
    for (int i = 0; i < intList.length - 1; i++) {
      if (intList[i] >= intList[i + 1]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> appPreferences = [];
    preferencesSpecs.forEach((prefSpec) {
      appPreferences.addAll([
        PreferenceTitle(prefSpec.title),
        TextFieldPreference(
          THRESHOLD_CAPITAL + prefSpec.fullTitle,
          prefSpec.thresholdTag,
          defaultVal: prefSpec.thresholdDefault,
          validator: (str) {
            if (!isPositiveInteger(str)) {
              return "Invalid threshold";
            }
            return null;
          },
        ),
        TextFieldPreference(
          prefSpec.title + ZONES_CAPITAL,
          prefSpec.zonesTag,
          defaultVal: prefSpec.zonesDefault,
          validator: (str) {
            if (!isMonotoneIncreasingList(str)) {
              return "Invalid zones";
            }
            return null;
          },
        ),
      ]);
    });

    appPreferences.addAll([
      PreferenceTitle(DEVICE_FILTERING),
      SwitchPreference(
        DEVICE_FILTERING,
        DEVICE_FILTERING_TAG,
        defaultVal: DEVICE_FILTERING_DEFAULT,
      ),
    ]);

    return Scaffold(
      appBar: AppBar(title: Text('Preferences')),
      body: PreferencePage(appPreferences)
    );
  }
}

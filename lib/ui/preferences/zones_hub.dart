import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:track_my_indoor_exercise/ui/preferences/zone_index_display.dart';
import '../../persistence/preferences.dart';
import '../../utils/constants.dart';
import '../../utils/sound.dart';
import 'measurement_zones.dart';

class ZonesHubScreen extends StatefulWidget {
  static String shortTitle = "Zones";

  @override
  State<StatefulWidget> createState() => ZonesHubScreenState();
}

class ZonesHubScreenState extends State<ZonesHubScreen> {
  double _mediaWidth;
  double _sizeDefault;
  TextStyle _textStyle;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<SoundService>()) {
      Get.put<SoundService>(SoundService());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = Get.mediaQuery.size.width;
    if (_mediaWidth == null || (_mediaWidth - mediaWidth).abs() > EPS) {
      _mediaWidth = mediaWidth;
      _sizeDefault = Get.mediaQuery.size.width / 5;
      _textStyle = TextStyle(
        fontFamily: FONT_FAMILY,
        fontSize: _sizeDefault / 2,
        color: Colors.black,
      );
    }
    final buttonStyle = ElevatedButton.styleFrom(primary: Colors.grey.shade200);

    List<Widget> items = PreferencesSpec.SPORT_PREFIXES.map((sport) {
      return Container(
        padding: const EdgeInsets.all(5.0),
        margin: const EdgeInsets.all(5.0),
        child: ElevatedButton(
          onPressed: () => Get.to(MeasurementZonesPreferencesScreen(sport)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextOneLine(
                sport,
                style: _textStyle,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              Icon(Icons.chevron_right, size: _sizeDefault, color: Colors.indigo),
            ],
          ),
          style: buttonStyle,
        ),
      );
    }).toList();

    items.add(Container(
      padding: const EdgeInsets.all(5.0),
      margin: const EdgeInsets.all(5.0),
      child: ElevatedButton(
        onPressed: () => Get.to(ZoneIndexDisplayPreferencesScreen()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TextOneLine(
              ZoneIndexDisplayPreferencesScreen.shortTitle,
              style: _textStyle,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            Icon(Icons.chevron_right, size: _sizeDefault, color: Colors.indigo),
          ],
        ),
        style: buttonStyle,
      ),
    ));

    return Scaffold(
      appBar: AppBar(title: Text('Zones Preferences')),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      ),
    );
  }
}

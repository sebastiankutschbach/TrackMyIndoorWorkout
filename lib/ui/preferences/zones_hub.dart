import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../preferences/preferences_spec.dart';
import '../../utils/constants.dart';
import '../../utils/sound.dart';
import 'measurement_zones.dart';
import 'zone_index_display.dart';

class ZonesHubScreen extends StatefulWidget {
  static String shortTitle = "Zones";

  const ZonesHubScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => ZonesHubScreenState();
}

class ZonesHubScreenState extends State<ZonesHubScreen> {
  double _sizeDefault = 10.0;
  TextStyle _textStyle = const TextStyle();

  @override
  void initState() {
    super.initState();
    _textStyle = Get.textTheme.headline5!.apply(
      fontFamily: fontFamily,
      color: Colors.white,
    );
    _sizeDefault = _textStyle.fontSize! * 2;
    if (!Get.isRegistered<SoundService>()) {
      Get.put<SoundService>(SoundService(), permanent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> items = PreferencesSpec.sportPrefixes.map((sport) {
      return Container(
        padding: const EdgeInsets.all(5.0),
        margin: const EdgeInsets.all(5.0),
        child: ElevatedButton(
          onPressed: () => Get.to(() => MeasurementZonesPreferencesScreen(sport)),
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
              Icon(Icons.chevron_right, size: _sizeDefault),
            ],
          ),
        ),
      );
    }).toList();

    items.add(Container(
      padding: const EdgeInsets.all(5.0),
      margin: const EdgeInsets.all(5.0),
      child: ElevatedButton(
        onPressed: () => Get.to(() => const ZoneIndexDisplayPreferencesScreen()),
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
            Icon(Icons.chevron_right, size: _sizeDefault),
          ],
        ),
      ),
    ));

    return Scaffold(
      appBar: AppBar(title: const Text('Zones Preferences')),
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

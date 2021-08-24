import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import '../../utils/theme_manager.dart';

class PortalChoiceDescriptor {
  final String name;
  final String assetName;
  final Color color;

  PortalChoiceDescriptor(this.name, this.assetName, this.color);
}

class UploadPortalPickerBottomSheet extends StatefulWidget {
  @override
  UploadPortalPickerBottomSheetState createState() => UploadPortalPickerBottomSheetState();
}

class UploadPortalPickerBottomSheetState extends State<UploadPortalPickerBottomSheet> {
  int _portalIndex = 0;
  List<String> _portalNames = [
    "Strava",
    "SUUNTO",
    "MapMyFitness",
  ];
  ThemeManager _themeManager = Get.find<ThemeManager>();
  List<PortalChoiceDescriptor> _portalChoices = [];
  TextStyle _largerTextStyle = TextStyle();
  TextStyle _selectedTextStyle = TextStyle();

  @override
  void initState() {
    super.initState();
    _portalChoices = [
      PortalChoiceDescriptor(_portalNames[0], "assets/strava.svg", _themeManager.getOrangeColor()),
      PortalChoiceDescriptor(
          _portalNames[1], "assets/suunto.svg", _themeManager.getSuuntoRedColor()),
      PortalChoiceDescriptor(
          _portalNames[2], "assets/under-armour.svg", _themeManager.getSuuntoRedColor()),
    ];
    _portalIndex = max(0, _portalNames.indexOf("Strava"));
    _largerTextStyle = Get.textTheme.headline4!;
    _selectedTextStyle = _largerTextStyle.apply(color: _themeManager.getProtagonistColor());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _portalChoices
              .asMap()
              .entries
              .map(
                (e) => Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale: 2,
                      child: Radio(
                        value: e.key,
                        groupValue: _portalIndex,
                        onChanged: (value) {
                          setState(() {
                            _portalIndex = value as int;
                          });
                        },
                      ),
                    ),
                    e.value.assetName.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                _portalIndex = e.key;
                              });
                            },
                            child: SvgPicture.asset(
                              e.value.assetName,
                              color: e.value.color,
                              height: _largerTextStyle.fontSize,
                              semanticsLabel: '${e.value.name} Logo',
                            ),
                          )
                        : Container(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _portalIndex = e.key;
                        });
                      },
                      child: Text("/${e.value.name}",
                          style: _portalIndex == e.key ? _selectedTextStyle : _largerTextStyle),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: _themeManager.getGreenFab(
          Icons.check, false, false, "", 0, () => Get.back(result: _portalNames[_portalIndex])),
    );
  }
}

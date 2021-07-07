import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../utils/theme_manager.dart';

class DataFormatPickerBottomSheet extends StatefulWidget {
  @override
  DataFormatPickerBottomSheetState createState() => DataFormatPickerBottomSheetState();
}

class DataFormatPickerBottomSheetState extends State<DataFormatPickerBottomSheet> {
  int _formatIndex = 0;
  List<String> _formatChoices = ["FIT", "TCX", "CSV"];
  ThemeManager _themeManager = Get.find<ThemeManager>();
  TextStyle _largerTextStyle = TextStyle();
  TextStyle _selectedTextStyle = TextStyle();

  @override
  void initState() {
    super.initState();
    _formatIndex = max(0, _formatChoices.indexOf("FIT"));
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
          children: _formatChoices
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
                        groupValue: _formatIndex,
                        onChanged: (value) {
                          setState(() {
                            _formatIndex = value as int;
                          });
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _formatIndex = e.key;
                        });
                      },
                      child: Text(e.value,
                          style: _formatIndex == e.key ? _selectedTextStyle : _largerTextStyle),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: _themeManager.getGreenFab(
          Icons.check, () => Get.back(result: _formatChoices[_formatIndex])),
    );
  }
}

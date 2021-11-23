import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:pref/pref.dart';
import '../../persistence/preferences.dart';
import '../../upload/constants.dart';
import '../../upload/upload_service.dart';
import '../../utils/preferences.dart';
import '../../utils/theme_manager.dart';

class IntegrationPreferencesScreen extends StatefulWidget {
  static String shortTitle = "Integrations";
  static String title = "$shortTitle Preferences";

  const IntegrationPreferencesScreen({Key? key}) : super(key: key);

  @override
  IntegrationPreferencesScreenState createState() => IntegrationPreferencesScreenState();
}

class IntegrationPreferencesScreenState extends State<IntegrationPreferencesScreen> {
  final ThemeManager _themeManager = Get.find<ThemeManager>();
  TextStyle _largerTextStyle = const TextStyle();
  Map<String, bool> integrationStates = {};

  @override
  void initState() {
    super.initState();
    _largerTextStyle = Get.textTheme.headline4!;
    for (final portalName in portalNames) {
      integrationStates[portalName] = UploadService.isIntegrationEnabled(portalName);
    }
  }

  Future<bool> toggleIntegration(String portalName) async {
    if (!await hasInternetConnection()) {
      Get.snackbar("Warning", "No data connection detected, try again later!");
      return false;
    }

    UploadService uploadService = UploadService.getInstance(portalName);
    var success = false;
    if (UploadService.isIntegrationEnabled(portalName)) {
      final returnCode = await uploadService.logout();
      debugPrint("Logout (deauthorization) return code: $returnCode");
      if (returnCode >= 200 && returnCode < 300) {
        Get.snackbar("Success", "Successful $portalName logout");
        success = true;
      } else {
        Get.snackbar("Warning", "$portalName logout unsuccessful");
      }
    } else {
      final loginSuccess = await uploadService.login();
      if (loginSuccess) {
        Get.snackbar("Success", "Successful $portalName login");
        success = true;
      } else {
        Get.snackbar("Warning", "$portalName login unsuccessful");
      }
    }

    if (success) {
      setState(() {
        integrationStates[portalName] = UploadService.isIntegrationEnabled(portalName);
      });
    }

    return success;
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> integrationPreferences = [
      const PrefCheckbox(
        title: Text(INSTANT_UPLOAD),
        subtitle: Text(INSTANT_UPLOAD_DESCRIPTION),
        pref: INSTANT_UPLOAD_TAG,
      ),
      const PrefLabel(
        title: Text("Available Integrations:"),
      ),
    ];

    integrationPreferences.addAll(
      getPortalChoices(_themeManager).asMap().entries.map(
            (e) => PrefButton(
              child: GestureDetector(
                onTap: () async {
                  await toggleIntegration(e.value.name);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      (integrationStates[e.value.name] ?? false) ? Icons.link : Icons.link_off,
                      size: _largerTextStyle.fontSize! * 1.5,
                      color: _themeManager.getProtagonistColor(),
                    ),
                    SvgPicture.asset(
                      e.value.assetName,
                      color: e.value.color,
                      height: _largerTextStyle.fontSize! * e.value.heightMultiplier,
                      semanticsLabel: '${e.value.name} Logo',
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(IntegrationPreferencesScreen.title)),
      body: PrefPage(children: integrationPreferences),
    );
  }
}
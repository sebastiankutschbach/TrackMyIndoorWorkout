import 'package:flutter/material.dart';
import 'package:pref/pref.dart';
import '../../preferences/lap_counter.dart';
import '../../preferences/leaderboard_and_rank.dart';
import 'preferences_base.dart';

class LeaderboardPreferencesScreen extends PreferencesScreenBase {
  static String shortTitle = "Leaderboard";
  static String title = "$shortTitle Preferences";

  const LeaderboardPreferencesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Widget> leaderboardPreferences = [
      PrefCheckbox(
        title: const Text(leaderboardFeature),
        subtitle: const Text(leaderboardFeatureDescription),
        pref: leaderboardFeatureTag,
        onChange: (value) {
          if (!value) {
            PrefService.of(context).set(rankRibbonVisualizationTag, false);
            PrefService.of(context).set(rankTrackVisualizationTag, false);
            PrefService.of(context).set(rankingForDeviceTag, false);
            PrefService.of(context).set(rankingForSportTag, false);
          }
        },
      ),
      PrefCheckbox(
        title: const Text(rankRibbonVisualization),
        subtitle: const Text(rankRibbonVisualizationDescription),
        pref: rankRibbonVisualizationTag,
        onChange: (value) {
          if (value) {
            PrefService.of(context).set(leaderboardFeatureTag, true);
          }
        },
      ),
      PrefCheckbox(
        title: const Text(rankTrackVisualization),
        subtitle: const Text(rankTrackVisualizationDescription),
        pref: rankTrackVisualizationTag,
        onChange: (value) {
          if (value) {
            PrefService.of(context).set(leaderboardFeatureTag, true);
          }
        },
      ),
      PrefCheckbox(
        title: const Text(rankInfoOnTrack),
        subtitle: const Text(rankInfoOnTrackDescription),
        pref: rankInfoOnTrackTag,
        onChange: (value) {
          if (value) {
            PrefService.of(context).set(rankTrackVisualizationTag, true);
            PrefService.of(context).set(leaderboardFeatureTag, true);
          }
        },
      ),
      PrefCheckbox(
        title: const Text(rankingForDevice),
        subtitle: const Text(rankingForDeviceDescription),
        pref: rankingForDeviceTag,
        onChange: (value) {
          if (value) {
            PrefService.of(context).set(leaderboardFeatureTag, true);
          }
        },
      ),
      PrefCheckbox(
        title: const Text(rankingForSport),
        subtitle: const Text(rankingForSportDescription),
        pref: rankingForSportTag,
        onChange: (value) {
          if (value) {
            PrefService.of(context).set(leaderboardFeatureTag, true);
          }
        },
      ),
      const PrefCheckbox(
        title: Text(displayLapCounter),
        subtitle: Text(displayLapCounterDescription),
        pref: displayLapCounterTag,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PrefPage(children: leaderboardPreferences),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../export/activity_export.dart';
import '../../persistence/models/activity.dart';
import '../../persistence/database.dart';

import 'constants.dart';
import 'strava_status_code.dart';
import 'fault.dart';
import 'strava_status_text.dart';
import 'strava_token.dart';
import 'upload_activity.dart';

abstract class Upload {
  /// Tested with gpx and tcx
  /// For the moment the parameters
  ///
  /// trainer and commute are set to false
  ///
  /// statusCode:
  /// 201 activity created
  /// 400 problem could be that activity already uploaded
  ///
  Future<Fault> uploadActivity(
    Activity activity,
    List<int> fileContent,
    ActivityExport exporter,
  ) async {
    debugPrint('Starting to upload activity');

    final postUri = Uri.parse(uploadsEndpoint);
    final persistenceValues = exporter.getPersistenceValues(activity, true);
    var request = http.MultipartRequest("POST", postUri);
    request.fields['data_type'] = exporter.fileExtension(true);
    request.fields['trainer'] = 'false';
    request.fields['commute'] = 'false';
    request.fields['name'] = persistenceValues["name"];
    request.fields['external_id'] = 'strava_flutter';
    request.fields['description'] = persistenceValues["description"];

    if (!Get.isRegistered<StravaToken>()) {
      debugPrint('Token not yet known');
      return Fault(StravaStatusCode.statusTokenNotKnownYet, 'Token not yet known');
    }

    final stravaToken = Get.find<StravaToken>();
    final header = stravaToken.getAuthorizationHeader();

    if (header.containsKey('88') == true) {
      debugPrint('Token not yet known');
      return Fault(StravaStatusCode.statusTokenNotKnownYet, 'Token not yet known');
    }

    request.headers.addAll(header);

    request.files.add(http.MultipartFile.fromBytes('file', fileContent,
        filename: persistenceValues["fileName"], contentType: MediaType("application", "x-gzip")));
    debugPrint(request.toString());

    final streamedResponse = await request.send();

    debugPrint('Response: ${streamedResponse.statusCode} ${streamedResponse.reasonPhrase}');

    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      // response.statusCode indicates problem
      debugPrint('Error while uploading the activity');
      debugPrint('${streamedResponse.statusCode} - ${streamedResponse.reasonPhrase}');
    } else {
      // Upload is processed by the server
      // now wait for the upload to be finished
      //----------------------------------------
      // response.statusCode == 201
      debugPrint('Activity successfully created');

      final response = await http.Response.fromStream(streamedResponse);
      final body = response.body;
      debugPrint(body);
      final Map<String, dynamic> bodyMap = json.decode(body);
      final decodedResponse = ResponseUploadActivity.fromJson(bodyMap);

      if (decodedResponse.id > 0) {
        final database = Get.find<AppDatabase>();
        activity.markUploaded(decodedResponse.id);
        await database.activityDao.updateActivity(activity);
        debugPrint('id ${decodedResponse.id}');

        final reqCheckUpgrade = '$uploadsEndpoint/${decodedResponse.id}';
        final uri = Uri.parse(reqCheckUpgrade);
        String? reasonPhrase = StravaStatusText.processed;
        while (reasonPhrase == StravaStatusText.processed) {
          final resp = await http.get(uri, headers: header);
          reasonPhrase = resp.reasonPhrase;
          debugPrint('Check Status $reasonPhrase ${resp.statusCode}');

          // Everything is fine the file has been loaded
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            // resp.statusCode == 200
            debugPrint('Check Body: ${resp.body}');
          }

          // 404 the temp id does not exist anymore
          // Activity has been probably already loaded
          if (resp.statusCode == 404) {
            debugPrint('---> 404 activity already loaded  $reasonPhrase');
          }

          if (reasonPhrase != null) {
            if (reasonPhrase.compareTo(StravaStatusText.ready) == 0) {
              debugPrint('---> Activity successfully uploaded');
            }

            if (reasonPhrase.compareTo(StravaStatusText.notFound) == 0 ||
                reasonPhrase.compareTo(StravaStatusText.errorMsg) == 0) {
              debugPrint('---> Error while checking status upload');
            }

            if (reasonPhrase.compareTo(StravaStatusText.deleted) == 0) {
              debugPrint('---> Activity deleted');
            }

            if (reasonPhrase.compareTo(StravaStatusText.processed) == 0) {
              debugPrint('---> try another time');
            }
          } else {
            debugPrint('---> Unknown error');
          }
        }
      }
    }

    return Fault(streamedResponse.statusCode, streamedResponse.reasonPhrase ?? "Unknown reason");
  }
}

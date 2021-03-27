import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:charts_common/common.dart' as common;
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:listview_utils/listview_utils.dart';
import 'package:preferences/preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../devices/device_descriptors/device_descriptor.dart';
import '../devices/device_map.dart';
import '../persistence/models/activity.dart';
import '../persistence/models/record.dart';
import '../persistence/database.dart';
import '../persistence/preferences.dart';
import '../utils/display.dart';
import '../utils/statistics_accumulator.dart';
import 'models/display_record.dart';
import 'models/histogram_data.dart';
import 'models/measurement_counter.dart';
import 'models/tile_configuration.dart';
import 'find_devices.dart';

class RecordsScreen extends StatefulWidget {
  final Activity activity;
  final Size size;
  RecordsScreen({
    Key key,
    @required this.activity,
    @required this.size,
  })  : assert(activity != null),
        assert(size != null),
        super(key: key);

  @override
  State<StatefulWidget> createState() {
    return RecordsScreenState(activity: activity, size: size);
  }
}

class RecordsScreenState extends State<RecordsScreen> {
  RecordsScreenState({
    @required this.activity,
    @required this.size,
  })  : assert(activity != null),
        assert(size != null);

  final Activity activity;
  final Size size;
  int _pointCount;
  List<Record> _allRecords;
  List<DisplayRecord> _sampledRecords;
  Map<String, TileConfiguration> _tileConfigurations;
  List<String> _tiles;
  bool _initialized;
  List<String> _selectedTimes;
  List<String> _selectedValues;
  bool _si;
  DeviceDescriptor _descriptor;
  List<PreferencesSpec> _preferencesSpecs;

  double _sizeDefault;
  double _sizeDefault2;
  TextStyle _measurementStyle;
  TextStyle _textStyle;
  TextStyle _unitStyle;
  TextStyle _selectionStyle;
  TextStyle _selectionTextStyle;

  @override
  void initState() {
    super.initState();
    _initialized = false;
    _tileConfigurations = {};
    _tiles = [];
    _selectedTimes = [];
    _selectedValues = [];
    _si = PrefService.getBool(UNIT_SYSTEM_TAG);
    _descriptor = deviceMap[activity.fourCC];
    _preferencesSpecs = PreferencesSpec.getPreferencesSpecs(_si, _descriptor);
    activity.hydrate();
    $FloorAppDatabase
        .databaseBuilder('app_database.db')
        .addMigrations([migration1to2, migration2to3])
        .build()
        .then((db) async {
          _allRecords = await db.recordDao.findAllActivityRecords(activity.id);

          setState(() {
            _pointCount = size.width.toInt() - 20;
            if (_allRecords.length < _pointCount) {
              _sampledRecords =
                  _allRecords.map((r) => r.hydrate().display()).toList(growable: false);
            } else {
              final nth = _allRecords.length / _pointCount;
              _sampledRecords = List.generate(
                  _pointCount, (i) => _allRecords[((i + 1) * nth - 1).round()].hydrate().display());
            }
            final measurementCounter = MeasurementCounter(si: _si, sport: _descriptor.defaultSport);
            _allRecords.forEach((record) {
              measurementCounter.processRecord(record);
            });

            var accu = StatisticsAccumulator(
              si: _si,
              sport: _descriptor.defaultSport,
              calculateAvgPower: measurementCounter.hasPower,
              calculateMaxPower: measurementCounter.hasPower,
              calculateAvgSpeed: measurementCounter.hasSpeed,
              calculateMaxSpeed: measurementCounter.hasSpeed,
              calculateAvgCadence: measurementCounter.hasCadence,
              calculateMaxCadence: measurementCounter.hasCadence,
              calculateAvgHeartRate: measurementCounter.hasHeartRate,
              calculateMaxHeartRate: measurementCounter.hasHeartRate,
            );
            _allRecords.forEach((record) {
              accu.processRecord(record);
            });

            if (measurementCounter.hasPower) {
              _tiles.add("power");
              _selectedTimes.add("--");
              _selectedValues.add("--");
              var prefSpec = _preferencesSpecs[0];
              var tileConfig = TileConfiguration(
                title: prefSpec.fullTitle,
                histogramTitle: prefSpec.histogramTitle,
                dataFn: _getPowerData,
                dataStringFn: _getPowerString,
                selectionListener: _powerSelectionListener,
                maxString: accu.maxPower.toStringAsFixed(2),
                avgString: accu.avgPower.toStringAsFixed(2),
              );
              prefSpec.calculateBounds(
                  measurementCounter.minPower.toDouble(), measurementCounter.maxPower.toDouble());
              tileConfig.histogram = prefSpec.zoneUpper
                  .asMap()
                  .entries
                  .map(
                    (entry) => HistogramData(index: entry.key, upper: entry.value),
                  )
                  .toList();
              _tileConfigurations["power"] = tileConfig;
            }
            if (measurementCounter.hasSpeed) {
              _tiles.add("speed");
              _selectedTimes.add("--");
              _selectedValues.add("--");
              var prefSpec = _preferencesSpecs[1];
              var tileConfig = TileConfiguration(
                title: prefSpec.fullTitle,
                histogramTitle: prefSpec.histogramTitle,
                dataFn: _getSpeedData,
                dataStringFn: _getSpeedString,
                selectionListener: _speedSelectionListener,
                maxString: paceString(accu.maxSpeed),
                avgString: paceString(accu.avgSpeed),
              );
              prefSpec.calculateBounds(measurementCounter.minSpeed, measurementCounter.maxSpeed);
              tileConfig.histogram = prefSpec.zoneUpper
                  .asMap()
                  .entries
                  .map(
                    (entry) => HistogramData(index: entry.key, upper: entry.value),
                  )
                  .toList();
              _tileConfigurations["speed"] = tileConfig;
            }
            if (measurementCounter.hasCadence) {
              _tiles.add("cadence");
              _selectedTimes.add("--");
              _selectedValues.add("--");
              var prefSpec = _preferencesSpecs[2];
              var tileConfig = TileConfiguration(
                title: prefSpec.fullTitle,
                histogramTitle: prefSpec.histogramTitle,
                dataFn: _getCadenceData,
                dataStringFn: _getCadenceString,
                selectionListener: _cadenceSelectionListener,
                maxString: "${accu.maxCadence}",
                avgString: "${accu.avgCadence}",
              );
              prefSpec.calculateBounds(measurementCounter.minCadence.toDouble(),
                  measurementCounter.maxCadence.toDouble());
              tileConfig.histogram = prefSpec.zoneUpper
                  .asMap()
                  .entries
                  .map(
                    (entry) => HistogramData(index: entry.key, upper: entry.value),
                  )
                  .toList();
              _tileConfigurations["cadence"] = tileConfig;
            }
            if (measurementCounter.hasHeartRate) {
              _tiles.add("hr");
              _selectedTimes.add("--");
              _selectedValues.add("--");
              var prefSpec = _preferencesSpecs[3];
              var tileConfig = TileConfiguration(
                title: prefSpec.fullTitle,
                histogramTitle: prefSpec.histogramTitle,
                dataFn: _getHrData,
                dataStringFn: _getHrString,
                selectionListener: _hrSelectionListener,
                maxString: "${accu.maxHeartRate}",
                avgString: "${accu.avgHeartRate}",
              );
              prefSpec.calculateBounds(
                  measurementCounter.minHr.toDouble(), measurementCounter.maxHr.toDouble());
              tileConfig.histogram = prefSpec.zoneUpper
                  .asMap()
                  .entries
                  .map(
                    (entry) => HistogramData(index: entry.key, upper: entry.value),
                  )
                  .toList();
              _tileConfigurations["hr"] = tileConfig;
            }
            _allRecords.forEach((record) {
              if (measurementCounter.hasPower) {
                if (record.power > 0) {
                  var tileConfig = _tileConfigurations["power"];
                  tileConfig.count++;
                  final binIndex = _preferencesSpecs[0].binIndex(record.power);
                  tileConfig.histogram[binIndex].increment();
                }
              }
              if (measurementCounter.hasSpeed) {
                if (record.speed > 0) {
                  var tileConfig = _tileConfigurations["speed"];
                  tileConfig.count++;
                  final binIndex = _preferencesSpecs[1]
                      .binIndex(record.speedByUnit(_si, _descriptor.defaultSport));
                  tileConfig.histogram[binIndex].increment();
                }
              }
              if (measurementCounter.hasCadence) {
                if (record.cadence > 0) {
                  var tileConfig = _tileConfigurations["cadence"];
                  tileConfig.count++;
                  final binIndex = _preferencesSpecs[2].binIndex(record.cadence);
                  tileConfig.histogram[binIndex].increment();
                }
              }
              if (measurementCounter.hasHeartRate) {
                if (record.heartRate > 0) {
                  var tileConfig = _tileConfigurations["hr"];
                  tileConfig.count++;
                  final binIndex = _preferencesSpecs[3].binIndex(record.heartRate);
                  tileConfig.histogram[binIndex].increment();
                }
              }
            });
            if (measurementCounter.hasPower) {
              var tileConfig = _tileConfigurations["power"];
              tileConfig.histogram.forEach((h) {
                h.calculatePercent(tileConfig.count);
              });
              tileConfig.histogramFn = _getPowerHistogram;
            }
            if (measurementCounter.hasSpeed) {
              var tileConfig = _tileConfigurations["speed"];
              tileConfig.histogram.forEach((h) {
                h.calculatePercent(tileConfig.count);
              });
              tileConfig.histogramFn = _getSpeedHistogram;
            }
            if (measurementCounter.hasCadence) {
              var tileConfig = _tileConfigurations["cadence"];
              tileConfig.histogram.forEach((h) {
                h.calculatePercent(tileConfig.count);
              });
              tileConfig.histogramFn = _getCadenceHistogram;
            }
            if (measurementCounter.hasHeartRate) {
              var tileConfig = _tileConfigurations["hr"];
              tileConfig.histogram.forEach((h) {
                h.calculatePercent(tileConfig.count);
              });
              tileConfig.histogramFn = _getHrHistogram;
            }
            _allRecords = null;
            _initialized = true;
          });
        });

    _sizeDefault = Get.mediaQuery.size.width / 7;
    _sizeDefault2 = _sizeDefault / 1.5;
    _measurementStyle = TextStyle(
      fontFamily: FONT_FAMILY,
      fontSize: _sizeDefault,
    );
    _textStyle = TextStyle(
      fontSize: _sizeDefault2,
    );
    _unitStyle = TextStyle(
      fontFamily: FONT_FAMILY,
      fontSize: _sizeDefault2 / 2,
      color: Colors.indigo,
    );
    _selectionStyle = TextStyle(
      fontFamily: FONT_FAMILY,
      fontSize: _sizeDefault2 / 2,
    );
    _selectionTextStyle = TextStyle(
      fontSize: _sizeDefault2 / 2,
    );
  }

  List<charts.Series<DisplayRecord, DateTime>> _getPowerData() {
    return <charts.Series<DisplayRecord, DateTime>>[
      charts.Series<DisplayRecord, DateTime>(
        id: 'power',
        colorFn: (DisplayRecord record, __) => _preferencesSpecs[0].fgColorByValue(record.power),
        domainFn: (DisplayRecord record, _) => record.dt,
        measureFn: (DisplayRecord record, _) => record.power,
        data: _sampledRecords,
      ),
    ];
  }

  String _getPowerString(DisplayRecord record) {
    return record.power.toString();
  }

  void _powerSelectionListener(charts.SelectionModel<DateTime> model) {
    final selectionData = _tileConfigurations["power"].getSelectionData(model);

    setState(() {
      _selectedTimes[0] = selectionData.time.difference(activity.startDateTime).toDisplay();
      _selectedValues[0] = selectionData.value;
    });
  }

  List<charts.Series<HistogramData, double>> _getPowerHistogram() {
    return <charts.Series<HistogramData, double>>[
      charts.Series<HistogramData, double>(
        id: 'powerHistogram',
        colorFn: (HistogramData data, __) => _preferencesSpecs[0].fgColorByBin(data.index),
        domainFn: (HistogramData data, _) => data.upper,
        measureFn: (HistogramData data, _) => data.percent,
        data: _tileConfigurations["power"].histogram,
        labelAccessorFn: (HistogramData data, _) => 'Z${data.index}: ${data.percent}%',
      ),
    ];
  }

  List<charts.Series<DisplayRecord, DateTime>> _getSpeedData() {
    return <charts.Series<DisplayRecord, DateTime>>[
      charts.Series<DisplayRecord, DateTime>(
        id: 'speed',
        colorFn: (DisplayRecord record, __) =>
            _preferencesSpecs[1].fgColorByValue(record.speedByUnit(_si, _descriptor.defaultSport)),
        domainFn: (DisplayRecord record, _) => record.dt,
        measureFn: (DisplayRecord record, _) => record.speedByUnit(_si, _descriptor.defaultSport),
        data: _sampledRecords,
      ),
    ];
  }

  String _getSpeedString(DisplayRecord record) {
    return speedOrPaceString(record.speed, _si, _descriptor.defaultSport);
  }

  void _speedSelectionListener(charts.SelectionModel<DateTime> model) {
    final selectionData = _tileConfigurations["speed"].getSelectionData(model);

    setState(() {
      _selectedTimes[1] = selectionData.time.difference(activity.startDateTime).toDisplay();
      _selectedValues[1] = selectionData.value;
    });
  }

  List<charts.Series<HistogramData, double>> _getSpeedHistogram() {
    return <charts.Series<HistogramData, double>>[
      charts.Series<HistogramData, double>(
        id: 'speedHistogram',
        colorFn: (HistogramData data, __) => _preferencesSpecs[1].fgColorByBin(data.index),
        domainFn: (HistogramData data, _) => data.upper,
        measureFn: (HistogramData data, _) => data.percent,
        data: _tileConfigurations["speed"].histogram,
        labelAccessorFn: (HistogramData data, _) => 'Z${data.index}: ${data.percent}%',
      ),
    ];
  }

  List<charts.Series<DisplayRecord, DateTime>> _getCadenceData() {
    return <charts.Series<DisplayRecord, DateTime>>[
      charts.Series<DisplayRecord, DateTime>(
        id: 'cadence',
        colorFn: (DisplayRecord record, __) => _preferencesSpecs[2].fgColorByValue(record.cadence),
        domainFn: (DisplayRecord record, _) => record.dt,
        measureFn: (DisplayRecord record, _) => record.cadence,
        data: _sampledRecords,
      ),
    ];
  }

  String _getCadenceString(DisplayRecord record) {
    return record.cadence.toString();
  }

  void _cadenceSelectionListener(charts.SelectionModel<DateTime> model) {
    final selectionData = _tileConfigurations["cadence"].getSelectionData(model);

    setState(() {
      _selectedTimes[2] = selectionData.time.difference(activity.startDateTime).toDisplay();
      _selectedValues[2] = selectionData.value;
    });
  }

  List<charts.Series<HistogramData, double>> _getCadenceHistogram() {
    return <charts.Series<HistogramData, double>>[
      charts.Series<HistogramData, double>(
        id: 'cadenceHistogram',
        colorFn: (HistogramData data, __) => _preferencesSpecs[2].fgColorByBin(data.index),
        domainFn: (HistogramData data, _) => data.upper,
        measureFn: (HistogramData data, _) => data.percent,
        data: _tileConfigurations["cadence"].histogram,
        labelAccessorFn: (HistogramData data, _) => 'Z${data.index}: ${data.percent}%',
      ),
    ];
  }

  List<charts.Series<DisplayRecord, DateTime>> _getHrData() {
    return <charts.Series<DisplayRecord, DateTime>>[
      charts.Series<DisplayRecord, DateTime>(
        id: 'hr',
        colorFn: (DisplayRecord record, __) =>
            _preferencesSpecs[3].fgColorByValue(record.heartRate),
        domainFn: (DisplayRecord record, _) => record.dt,
        measureFn: (DisplayRecord record, _) => record.heartRate,
        data: _sampledRecords,
      ),
    ];
  }

  String _getHrString(DisplayRecord record) {
    return record.heartRate.toString();
  }

  void _hrSelectionListener(charts.SelectionModel<DateTime> model) {
    final selectionData = _tileConfigurations["hr"].getSelectionData(model);

    setState(() {
      _selectedTimes[3] = selectionData.time.difference(activity.startDateTime).toDisplay();
      _selectedValues[3] = selectionData.value;
    });
  }

  List<charts.Series<HistogramData, double>> _getHrHistogram() {
    return <charts.Series<HistogramData, double>>[
      charts.Series<HistogramData, double>(
        id: 'hrHistogram',
        colorFn: (HistogramData data, __) => _preferencesSpecs[3].fgColorByBin(data.index),
        domainFn: (HistogramData data, _) => data.upper,
        measureFn: (HistogramData data, _) => data.percent,
        data: _tileConfigurations["hr"].histogram,
        labelAccessorFn: (HistogramData data, _) => 'Z${data.index}: ${data.percent}%',
      ),
    ];
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Activities'),
        actions: [
          IconButton(
            icon: Icon(Icons.help),
            onPressed: () async {
              if (await canLaunch(HELP_URL)) {
                launch(HELP_URL);
              } else {
                Get.snackbar("Attention", "Cannot open URL");
              }
            },
          ),
        ],
      ),
      body: !_initialized
          ? Text('Initializing...')
          : CustomListView(
              paginationMode: PaginationMode.offset,
              initialOffset: 0,
              loadingBuilder: CustomListLoading.defaultBuilder,
              header: Card(
                elevation: 6,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_bike,
                          color: Colors.indigo,
                          size: _sizeDefault,
                        ),
                        Expanded(
                          child: TextOneLine(
                            activity.deviceName,
                            style: _textStyle,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timer,
                          color: Colors.indigo,
                          size: _sizeDefault,
                        ),
                        Spacer(),
                        Text(
                          activity.elapsedString,
                          style: _measurementStyle,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_road,
                          color: Colors.indigo,
                          size: _sizeDefault,
                        ),
                        Spacer(),
                        Text(
                          activity.distanceString(_si),
                          style: _measurementStyle,
                        ),
                        SizedBox(
                          width: _sizeDefault,
                          child: Text(
                            _si ? 'm' : 'mi',
                            style: _unitStyle,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.whatshot,
                          color: Colors.indigo,
                          size: _sizeDefault,
                        ),
                        Spacer(),
                        Text(
                          '${activity.calories}',
                          style: _measurementStyle,
                        ),
                        SizedBox(
                          width: _sizeDefault,
                          child: Text(
                            'cal',
                            style: _unitStyle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              adapter: StaticListAdapter(data: _tiles),
              itemBuilder: (context, index, item) {
                List<common.AnnotationSegment> annotationSegments = [];
                if (_initialized) {
                  annotationSegments.addAll(List.generate(
                    _preferencesSpecs[index].binCount,
                    (i) => charts.RangeAnnotationSegment(
                      _preferencesSpecs[index].zoneLower[i],
                      _preferencesSpecs[index].zoneUpper[i],
                      charts.RangeAnnotationAxisType.measure,
                      color: _preferencesSpecs[index].bgColorByBin(i),
                      startLabel: _preferencesSpecs[index].zoneLower[i].toString(),
                      labelAnchor: charts.AnnotationLabelAnchor.start,
                    ),
                  ));
                  annotationSegments.addAll(List.generate(
                    _preferencesSpecs[index].binCount,
                    (i) => charts.LineAnnotationSegment(
                      _preferencesSpecs[index].zoneUpper[i],
                      charts.RangeAnnotationAxisType.measure,
                      startLabel: _preferencesSpecs[index].zoneUpper[i].toString(),
                      labelAnchor: charts.AnnotationLabelAnchor.end,
                      strokeWidthPx: 1.0,
                      color: charts.MaterialPalette.black,
                    ),
                  ));
                }

                return Card(
                  elevation: 6,
                  child: ExpandablePanel(
                    header: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _tileConfigurations[item].title,
                              style: _textStyle,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              _preferencesSpecs[index].icon,
                              color: Colors.indigo,
                              size: _sizeDefault2,
                            ),
                            Text("MAX", style: _unitStyle),
                            Spacer(),
                            Text(
                              _tileConfigurations[item].maxString,
                              style: _measurementStyle,
                            ),
                            Spacer(),
                            Text(
                              _preferencesSpecs[index].multiLineUnit,
                              textAlign: TextAlign.left,
                              maxLines: 2,
                              style: _unitStyle,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              _preferencesSpecs[index].icon,
                              color: Colors.indigo,
                              size: _sizeDefault2,
                            ),
                            Text("AVG", style: _unitStyle),
                            Spacer(),
                            Text(
                              _tileConfigurations[item].avgString,
                              style: _measurementStyle,
                            ),
                            Spacer(),
                            Text(
                              _preferencesSpecs[index].multiLineUnit,
                              textAlign: TextAlign.left,
                              maxLines: 2,
                              style: _unitStyle,
                            ),
                          ],
                        ),
                      ],
                    ),
                    expanded: Column(children: [
                      SizedBox(
                        width: size.width,
                        height: size.height / 2,
                        child: charts.TimeSeriesChart(
                          _tileConfigurations[item].dataFn(),
                          animate: false,
                          primaryMeasureAxis: charts.NumericAxisSpec(
                            renderSpec: charts.NoneRenderSpec(),
                          ),
                          behaviors: [
                            charts.LinePointHighlighter(
                              showHorizontalFollowLine:
                                  charts.LinePointHighlighterFollowLineType.nearest,
                              showVerticalFollowLine:
                                  charts.LinePointHighlighterFollowLineType.nearest,
                            ),
                            charts.SelectNearest(eventTrigger: charts.SelectionTrigger.tapAndDrag),
                            charts.RangeAnnotation(annotationSegments),
                          ],
                          selectionModels: [
                            charts.SelectionModelConfig(
                              type: charts.SelectionModelType.info,
                              changedListener: _tileConfigurations[item].selectionListener,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(_selectedValues[index], style: _selectionStyle),
                          Text(" ", style: _selectionTextStyle),
                          Text(_preferencesSpecs[index].unit, style: _unitStyle),
                          Text(" @ ", style: _selectionTextStyle),
                          Text(_selectedTimes[index], style: _selectionStyle),
                        ],
                      ),
                      Divider(height: 20, thickness: 2),
                      Text(
                        _tileConfigurations[item].histogramTitle,
                        style: _textStyle,
                      ),
                      SizedBox(
                        width: size.width,
                        height: size.height / 3,
                        child: charts.PieChart(
                          _tileConfigurations[item].histogramFn(),
                          animate: false,
                          defaultRenderer: charts.ArcRendererConfig(
                              arcWidth: 60, arcRendererDecorators: [charts.ArcLabelDecorator()]),
                          behaviors: [
                            charts.DatumLegend(
                              position: charts.BehaviorPosition.start,
                              horizontalFirst: false,
                              cellPadding: EdgeInsets.only(right: 4.0, bottom: 4.0),
                              showMeasures: true,
                              legendDefaultMeasure: charts.LegendDefaultMeasure.firstValue,
                              measureFormatter: (num value) {
                                return value == null ? '-' : '$value %';
                              },
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import '../lib/persistence/models/record.dart';
import '../lib/utils/statistics_accumulator.dart';
import 'utils.dart';

void main() {
  group('StatisticsAccumulator calculates avg power when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateAvgPower: true);
      final count = rnd.nextInt(99) + 1;
      double sum = 0.0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(power: number, sport: sport));
        sum += number;
      });
      test("$count ($sport) -> $sum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, true);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, sum);
        expect(accu.powerCount, count);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
        expect(accu.avgPower, sum / count);
      });
    });
  });

  group('StatisticsAccumulator calculates max power when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateMaxPower: true);
      final count = rnd.nextInt(99) + 1;
      int maximum = 0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(power: number, sport: sport));
        maximum = max(number, maximum);
      });
      test("$count ($sport) -> $maximum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, true);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, maximum);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
      });
    });
  });

  group('StatisticsAccumulator calculates avg speed when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateAvgSpeed: true);
      final count = rnd.nextInt(99) + 1;
      double sum = 0.0;
      getRandomDoubles(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(speed: number, sport: sport));
        sum += number;
      });
      test("$count ($sport) -> $sum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, true);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, sum);
        expect(accu.speedCount, count);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
        expect(accu.avgSpeed, sum / count);
      });
    });
  });

  group('StatisticsAccumulator calculates max speed when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateMaxSpeed: true);
      final count = rnd.nextInt(99) + 1;
      double maximum = 0.0;
      getRandomDoubles(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(speed: number, sport: sport));
        maximum = max(number, maximum);
      });
      test("$count ($sport) -> $maximum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, true);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, maximum);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
      });
    });
  });

  group('StatisticsAccumulator calculates avg hr when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateAvgHeartRate: true);
      final count = rnd.nextInt(99) + 1;
      int sum = 0;
      int cnt = 0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(heartRate: number, sport: sport));
        sum += number;
        if (number > 0) {
          cnt += 1;
        }
      });
      test("$count ($sport) -> $sum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, true);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, sum);
        expect(accu.heartRateCount, cnt);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
        expect(accu.avgHeartRate, sum ~/ cnt);
      });
    });
  });

  group('StatisticsAccumulator calculates max hr when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateMaxHeartRate: true);
      final count = rnd.nextInt(99) + 1;
      int maximum = 0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(heartRate: number, sport: sport));
        maximum = max(number, maximum);
      });
      test("$count ($sport) -> $maximum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, true);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, maximum);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, null);
      });
    });
  });

  group('StatisticsAccumulator calculates avg cadence when requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateAvgCadence: true);
      final count = rnd.nextInt(99) + 1;
      int sum = 0;
      int cnt = 0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(cadence: number, sport: sport));
        sum += number;
        if (number > 0) {
          cnt += 1;
        }
      });
      test("$count ($sport) -> $sum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, true);
        expect(accu.calculateMaxCadence, false);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, sum);
        expect(accu.cadenceCount, cnt);
        expect(accu.maxCadence, null);
        expect(accu.avgCadence, sum ~/ cnt);
      });
    });
  });

  group('StatisticsAccumulator initializes max cadence when max requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(calculateMaxCadence: true);
      final count = rnd.nextInt(99) + 1;
      int maximum = 0;
      getRandomInts(count, 100, rnd).forEach((number) {
        accu.processRecord(RecordWithSport(cadence: number, sport: sport));
        maximum = max(number, maximum);
      });
      test("$count ($sport) -> $maximum", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, false);
        expect(accu.calculateMaxPower, false);
        expect(accu.calculateAvgSpeed, false);
        expect(accu.calculateMaxSpeed, false);
        expect(accu.calculateAvgCadence, false);
        expect(accu.calculateMaxCadence, true);
        expect(accu.calculateAvgHeartRate, false);
        expect(accu.calculateMaxHeartRate, false);
        expect(accu.powerSum, null);
        expect(accu.powerCount, null);
        expect(accu.maxPower, null);
        expect(accu.speedSum, null);
        expect(accu.speedCount, null);
        expect(accu.maxSpeed, null);
        expect(accu.heartRateSum, null);
        expect(accu.heartRateCount, null);
        expect(accu.maxHeartRate, null);
        expect(accu.cadenceSum, null);
        expect(accu.cadenceCount, null);
        expect(accu.maxCadence, maximum);
      });
    });
  });

  group('StatisticsAccumulator initializes everything when all requested', () {
    final rnd = Random();
    SPORTS.forEach((sport) {
      final accu = StatisticsAccumulator(
        calculateAvgPower: true,
        calculateMaxPower: true,
        calculateAvgSpeed: true,
        calculateMaxSpeed: true,
        calculateAvgCadence: true,
        calculateMaxCadence: true,
        calculateAvgHeartRate: true,
        calculateMaxHeartRate: true,
      );
      final count = rnd.nextInt(99) + 1;
      int powerSum = 0;
      int maxPower = 0;
      final powers = getRandomInts(count, 100, rnd);
      double speedSum = 0.0;
      double maxSpeed = 0.0;
      final speeds = getRandomDoubles(count, 100, rnd);
      int cadenceSum = 0;
      int cadenceCount = 0;
      int maxCadence = 0;
      final cadences = getRandomInts(count, 100, rnd);
      int hrSum = 0;
      int hrCount = 0;
      int maxHr = 0;
      final hrs = getRandomInts(count, 100, rnd);
      List<int>.generate(count, (index) {
        accu.processRecord(RecordWithSport(
          power: powers[index],
          speed: speeds[index],
          cadence: cadences[index],
          heartRate: hrs[index],
          sport: sport,
        ));
        powerSum += powers[index];
        maxPower = max(powers[index], maxPower);
        speedSum += speeds[index];
        maxSpeed = max(speeds[index], maxSpeed);
        cadenceSum += cadences[index];
        if (cadences[index] > 0) {
          cadenceCount += 1;
        }
        maxCadence = max(cadences[index], maxCadence);
        hrSum += hrs[index];
        if (hrs[index] > 0) {
          hrCount += 1;
        }
        maxHr = max(hrs[index], maxHr);
        return index;
      });
      test("$count ($sport) -> $powerSum, $maxPower, $speedSum, $maxSpeed", () {
        expect(accu.si, null);
        expect(accu.sport, null);
        expect(accu.calculateAvgPower, true);
        expect(accu.calculateMaxPower, true);
        expect(accu.calculateAvgSpeed, true);
        expect(accu.calculateMaxSpeed, true);
        expect(accu.calculateAvgCadence, true);
        expect(accu.calculateMaxCadence, true);
        expect(accu.calculateAvgHeartRate, true);
        expect(accu.calculateMaxHeartRate, true);
        expect(accu.powerSum, powerSum);
        expect(accu.powerCount, count);
        expect(accu.maxPower, maxPower);
        expect(accu.speedSum, speedSum);
        expect(accu.speedCount, count);
        expect(accu.maxSpeed, maxSpeed);
        expect(accu.heartRateSum, hrSum);
        expect(accu.heartRateCount, hrCount);
        expect(accu.maxHeartRate, maxHr);
        expect(accu.cadenceSum, cadenceSum);
        expect(accu.cadenceCount, cadenceCount);
        expect(accu.maxCadence, maxCadence);
        expect(accu.avgPower, powerSum / count);
        expect(accu.avgSpeed, speedSum / count);
        expect(accu.avgHeartRate, hrSum ~/ hrCount);
        expect(accu.avgCadence, cadenceSum ~/ cadenceCount);
      });
    });
  });
}

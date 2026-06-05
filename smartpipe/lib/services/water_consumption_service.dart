import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_management_service.dart';

class WaterConsumptionService extends ChangeNotifier {
  // Singleton pattern
  static final WaterConsumptionService _instance =
      WaterConsumptionService._internal();
  factory WaterConsumptionService() => _instance;
  WaterConsumptionService._internal();

  // Constants
  static const double flowToLitersConversion =
      5.0; // 1 flow rate unit = 5 liters

  // Database references
  final _database = FirebaseDatabase.instance.ref();

  // Device management service
  final DeviceManagementService _deviceService = DeviceManagementService();

  // Device information - will be populated dynamically
  List<String> _deviceIds = [];
  Map<String, String> _deviceLabels = {};

  // Consumption tracking
  final Map<String, double> _dailyConsumption = {};
  final Map<String, double> _weeklyConsumption = {};
  final Map<String, double> _monthlyConsumption = {};
  final Map<String, double> _yearlyConsumption = {};
  Timer? _midnightTimer;

  // Initialize the service
  Future<void> initialize() async {
    // Initialize device management service first
    await _deviceService.initialize();

    // Get device information from the service
    _deviceIds = List.from(_deviceService.deviceIds);
    _deviceLabels = Map.from(_deviceService.deviceLabels);

    // Add listener for device changes
    _deviceService.addListener(_onDevicesChanged);

    // Initialize consumption maps for all devices
    for (final deviceId in _deviceIds) {
      _dailyConsumption[deviceId] = 0.0;
      _weeklyConsumption[deviceId] = 0.0;
      _monthlyConsumption[deviceId] = 0.0;
      _yearlyConsumption[deviceId] = 0.0;
    }

    // Load last report date
    final prefs = await SharedPreferences.getInstance();
    final lastReportDate = prefs.getString('last_report_date');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // If last report wasn't today, reset daily consumption counters
    if (lastReportDate != today) {
      await _resetDailyConsumption();
    }

    // Load saved consumption data
    await _loadConsumptionData();

    // Start listening to flow data
    _startListeningToFlowData();

    // Schedule midnight report
    _scheduleMidnightReport();
  }

  // Load consumption data from SharedPreferences
  Future<void> _loadConsumptionData() async {
    final prefs = await SharedPreferences.getInstance();

    for (final deviceId in _deviceIds) {
      // Load daily consumption
      _dailyConsumption[deviceId] =
          prefs.getDouble('daily_consumption_$deviceId') ?? 0.0;

      // Load weekly consumption
      _weeklyConsumption[deviceId] =
          prefs.getDouble('weekly_consumption_$deviceId') ?? 0.0;

      // Load monthly consumption
      _monthlyConsumption[deviceId] =
          prefs.getDouble('monthly_consumption_$deviceId') ?? 0.0;

      // Load yearly consumption
      _yearlyConsumption[deviceId] =
          prefs.getDouble('yearly_consumption_$deviceId') ?? 0.0;
    }
  }

  // Start listening to flow data for all devices
  void _startListeningToFlowData() {
    for (final deviceId in _deviceIds) {
      _listenToDeviceFlow(deviceId);
    }
  }

  // Listen to flow data for a specific device
  void _listenToDeviceFlow(String deviceId) {
    // Updated path to look for data in readings/deviceId/data
    // This will listen for new children added to the data node
    _database.child('readings/$deviceId/data').limitToLast(1).onChildAdded.listen((
      event,
    ) {
      try {
        // Safely handle the data from Firebase
        if (event.snapshot.value == null) return;

        debugPrint('New reading received for $deviceId: ${event.snapshot.key}');

        // Extract flow value safely
        dynamic snapshotValue = event.snapshot.value;
        dynamic flowValue;

        // The value should be a Map with a 'flowRate' or 'flow' field
        if (snapshotValue is Map<dynamic, dynamic>) {
          // Check for flowRate (new field name) first, then fall back to flow (backward compatibility)
          flowValue = snapshotValue['flowRate'] ?? snapshotValue['flow'];
          debugPrint('Flow value from map: $flowValue');
        } else {
          // If it's not a map, try to access it as a dynamic object
          try {
            flowValue =
                (snapshotValue as dynamic)['flowRate'] ??
                (snapshotValue as dynamic)['flow'];
            debugPrint('Flow value from dynamic: $flowValue');
          } catch (e) {
            debugPrint('Error accessing flow value: $e');
            return;
          }
        }

        if (flowValue == null) return;

        // Convert to double safely
        final flow = double.tryParse(flowValue.toString()) ?? 0.0;

        // Convert flow rate to liters
        final liters = flow * flowToLitersConversion;

        // Update all consumption periods with safe null checks
        _dailyConsumption[deviceId] =
            (_dailyConsumption[deviceId] ?? 0.0) + liters;
        _weeklyConsumption[deviceId] =
            (_weeklyConsumption[deviceId] ?? 0.0) + liters;
        _monthlyConsumption[deviceId] =
            (_monthlyConsumption[deviceId] ?? 0.0) + liters;
        _yearlyConsumption[deviceId] =
            (_yearlyConsumption[deviceId] ?? 0.0) + liters;

        // Save updated consumption
        _saveAllConsumptionData();

        // Notify listeners so UI updates with new consumption totals
        notifyListeners();
      } catch (e) {
        debugPrint('Error processing flow data: $e');
      }
    });
  }

  // Schedule the midnight report
  void _scheduleMidnightReport() {
    // Cancel any existing timer
    _midnightTimer?.cancel();

    // Calculate time until next midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    debugPrint(
      'Scheduling next report at midnight (in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m)',
    );

    // Schedule the report
    _midnightTimer = Timer(timeUntilMidnight, () async {
      debugPrint(
        'Midnight reached - generating daily report and resetting consumption',
      );

      try {
        // Generate the report
        final report = await generateDailyReport();

        // Log the report generation
        debugPrint(
          'Daily report generated successfully with ${report.length} devices',
        );

        // Notify any listeners that a new report was generated
        notifyListeners();
      } catch (e) {
        debugPrint('Error generating midnight report: $e');
      } finally {
        // Always reschedule for the next day, even if there was an error
        _scheduleMidnightReport();
      }
    });
  }

  // Generate the daily consumption report
  Future<Map<String, double>> generateDailyReport() async {
    final dailyReport = Map<String, double>.from(_dailyConsumption);
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);

    // Save the daily report to Firebase with the date as the key
    await _database.child('reports/daily/$date').set({
      'timestamp': ServerValue.timestamp,
      'consumption': dailyReport,
      'date': date, // Add the date explicitly for clarity
      'report_type': 'daily',
    });

    // Check if it's the end of the week (Sunday)
    if (now.weekday == DateTime.sunday) {
      final weeklyReport = Map<String, double>.from(_weeklyConsumption);
      final weekNumber = (now.day / 7).ceil();
      final weekId = '${now.year}-${now.month}-$weekNumber';

      // Save weekly report
      await _database.child('reports/weekly/$weekId').set({
        'timestamp': ServerValue.timestamp,
        'consumption': weeklyReport,
        'start_date': DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(Duration(days: now.weekday - 1))),
        'end_date': date,
        'report_type': 'weekly',
      });

      // Reset weekly counters
      for (final deviceId in _deviceIds) {
        _weeklyConsumption[deviceId] = 0.0;
      }
    }

    // Check if it's the end of the month
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (tomorrow.month != now.month) {
      final monthlyReport = Map<String, double>.from(_monthlyConsumption);
      final monthId = '${now.year}-${now.month}';

      // Save monthly report
      await _database.child('reports/monthly/$monthId').set({
        'timestamp': ServerValue.timestamp,
        'consumption': monthlyReport,
        'month': now.month,
        'year': now.year,
        'report_type': 'monthly',
      });

      // Reset monthly counters
      for (final deviceId in _deviceIds) {
        _monthlyConsumption[deviceId] = 0.0;
      }
    }

    // Check if it's the end of the year
    if (tomorrow.year != now.year) {
      final yearlyReport = Map<String, double>.from(_yearlyConsumption);
      final yearId = '${now.year}';

      // Save yearly report
      await _database.child('reports/yearly/$yearId').set({
        'timestamp': ServerValue.timestamp,
        'consumption': yearlyReport,
        'year': now.year,
        'report_type': 'yearly',
      });

      // Reset yearly counters
      for (final deviceId in _deviceIds) {
        _yearlyConsumption[deviceId] = 0.0;
      }
    }

    // Create a notification about the daily report
    await _createReportNotification(dailyReport, date);

    // Reset consumption counters for the new day
    await _resetDailyConsumption();

    // Save all updated consumption data
    await _saveAllConsumptionData();

    return dailyReport;
  }

  // Create a notification about the daily report
  Future<void> _createReportNotification(
    Map<String, double> report, [
    String? reportDate,
  ]) async {
    final date = reportDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final formattedDate = DateFormat(
      'EEEE, MMMM d, yyyy',
    ).format(DateFormat('yyyy-MM-dd').parse(date));

    // Build notification message
    String message = 'Water Consumption Report for $formattedDate:\n';
    double totalConsumption = 0;

    for (final entry in report.entries) {
      final deviceId = entry.key;
      final liters = entry.value;
      final deviceName = _deviceLabels[deviceId] ?? deviceId;

      message += '• $deviceName: ${liters.toStringAsFixed(1)} liters\n';
      totalConsumption += liters;
    }

    message +=
        '\nTotal consumption for this day: ${totalConsumption.toStringAsFixed(1)} liters';

    // Save notification to Firebase
    await _database.child('notifications').push().set({
      'title': 'Daily Water Consumption Report',
      'message': message,
      'timestamp': timestamp,
      'read': false,
      'type': 'report',
      'date': date,
      'report_date': date, // Add the specific date this report is for
    });

    // Queue email summary for recipients
    await _queueDailyConsumptionEmail(
      report: report,
      reportDate: date,
      totalConsumption: totalConsumption,
    );
  }

  // Reset daily consumption counters
  Future<void> _resetDailyConsumption() async {
    debugPrint(
      'Resetting daily consumption counters for ${_deviceIds.length} devices',
    );

    for (final deviceId in _deviceIds) {
      _dailyConsumption[deviceId] = 0.0;
    }

    // Update last report date
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await prefs.setString('last_report_date', today);

    // Log the reset time
    await prefs.setString('last_reset_time', DateTime.now().toIso8601String());

    // Save reset consumption values
    await _saveDailyConsumption();

    // Notify listeners that consumption has been reset
    notifyListeners();

    debugPrint('Daily consumption reset completed');
  }

  // Get the time of the next scheduled reset
  DateTime getNextResetTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1); // Next midnight
  }

  // Get the time of the last reset
  Future<DateTime?> getLastResetTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResetTimeStr = prefs.getString('last_reset_time');

    if (lastResetTimeStr != null) {
      try {
        return DateTime.parse(lastResetTimeStr);
      } catch (e) {
        debugPrint('Error parsing last reset time: $e');
      }
    }

    return null;
  }

  // Save all consumption data to SharedPreferences
  Future<void> _saveAllConsumptionData() async {
    final prefs = await SharedPreferences.getInstance();

    // Save daily consumption
    for (final entry in _dailyConsumption.entries) {
      await prefs.setDouble('daily_consumption_${entry.key}', entry.value);
    }

    // Save weekly consumption
    for (final entry in _weeklyConsumption.entries) {
      await prefs.setDouble('weekly_consumption_${entry.key}', entry.value);
    }

    // Save monthly consumption
    for (final entry in _monthlyConsumption.entries) {
      await prefs.setDouble('monthly_consumption_${entry.key}', entry.value);
    }

    // Save yearly consumption
    for (final entry in _yearlyConsumption.entries) {
      await prefs.setDouble('yearly_consumption_${entry.key}', entry.value);
    }
  }

  Future<List<String>> _fetchEmailRecipients() async {
    try {
      final snapshot = await _database.child('email_settings/recipients').get();
      final recipients = <String>[];

      if (snapshot.exists) {
        final value = snapshot.value;
        if (value is List) {
          for (final item in value) {
            if (item is String && item.trim().isNotEmpty) {
              recipients.add(item.trim());
            }
          }
        } else if (value is Map) {
          for (final entry in value.values) {
            if (entry is String && entry.trim().isNotEmpty) {
              recipients.add(entry.trim());
            }
          }
        }
      }

      return recipients.toSet().toList();
    } catch (e) {
      debugPrint('Error fetching email recipients: $e');
      return [];
    }
  }

  Future<void> _queueDailyConsumptionEmail({
    required Map<String, double> report,
    required String reportDate,
    required double totalConsumption,
  }) async {
    final recipients = await _fetchEmailRecipients();
    if (recipients.isEmpty) {
      debugPrint('⚠️ No recipients configured for daily consumption email.');
      return;
    }

    final formattedDate = DateFormat(
      'EEEE, MMMM d, yyyy',
    ).format(DateFormat('yyyy-MM-dd').parse(reportDate));

    final buffer = StringBuffer();
    buffer.writeln(
      '<p>Hello,</p><p>Here is the water consumption summary for <strong>$formattedDate</strong>:</p>',
    );
    buffer.writeln(
      '<table style="width:100%;border-collapse:collapse;">'
      '<thead>'
      '<tr style="background-color:#f3f4f6;">'
      '<th style="text-align:left;padding:8px;border:1px solid #e5e7eb;">Device</th>'
      '<th style="text-align:right;padding:8px;border:1px solid #e5e7eb;">Liters</th>'
      '</tr>'
      '</thead><tbody>',
    );

    report.entries.forEach((entry) {
      final deviceName = _deviceLabels[entry.key] ?? entry.key;
      buffer.writeln(
        '<tr>'
        '<td style="padding:8px;border:1px solid #e5e7eb;">$deviceName</td>'
        '<td style="text-align:right;padding:8px;border:1px solid #e5e7eb;">${entry.value.toStringAsFixed(1)}</td>'
        '</tr>',
      );
    });

    buffer.writeln(
      '<tr style="font-weight:bold;background-color:#f9fafb;">'
      '<td style="padding:8px;border:1px solid #e5e7eb;">Total</td>'
      '<td style="text-align:right;padding:8px;border:1px solid #e5e7eb;">${totalConsumption.toStringAsFixed(1)}</td>'
      '</tr>',
    );
    buffer.writeln('</tbody></table>');
    buffer.writeln('<p>Thank you,<br/>SmartPipe Water Management System</p>');

    await _database.child('notifications/reports').push().set({
      'recipients': recipients,
      'subject': 'Daily Water Consumption Report - $formattedDate',
      'message': buffer.toString(),
      'reportPeriod': 'Daily Consumption',
      'status': 'pending',
      'createdAt': ServerValue.timestamp,
      'type': 'daily_consumption',
      'date': reportDate,
      'totalConsumption': totalConsumption,
    });

    debugPrint(
      '📧 Daily consumption email queued for ${recipients.length} recipient(s).',
    );
  }

  // Save daily consumption to SharedPreferences (legacy method)
  Future<void> _saveDailyConsumption() async {
    // Call the new method instead
    await _saveAllConsumptionData();
  }

  // Get current consumption for all devices
  Map<String, double> getCurrentConsumption({String period = 'daily'}) {
    try {
      Map<String, double> result = {};

      // Get the appropriate consumption map based on period
      Map<String, double> sourceMap;
      switch (period) {
        case 'weekly':
          sourceMap = _weeklyConsumption;
          break;
        case 'monthly':
          sourceMap = _monthlyConsumption;
          break;
        case 'yearly':
          sourceMap = _yearlyConsumption;
          break;
        case 'daily':
        default:
          sourceMap = _dailyConsumption;
          break;
      }

      // Safely copy values to ensure they are all doubles
      for (final deviceId in _deviceIds) {
        result[deviceId] = sourceMap[deviceId] ?? 0.0;
      }

      return result;
    } catch (e) {
      // Return empty map on error
      debugPrint('Error retrieving consumption map: $e');
      return {};
    }
  }

  // Get consumption for a specific device
  double getDeviceConsumption(String deviceId, {String period = 'daily'}) {
    try {
      double result = 0.0;

      // Get the value based on the period
      switch (period) {
        case 'weekly':
          result = _weeklyConsumption[deviceId] ?? 0.0;
          break;
        case 'monthly':
          result = _monthlyConsumption[deviceId] ?? 0.0;
          break;
        case 'yearly':
          result = _yearlyConsumption[deviceId] ?? 0.0;
          break;
        case 'daily':
        default:
          result = _dailyConsumption[deviceId] ?? 0.0;
          break;
      }

      // No need for type check since result is already declared as double

      return result;
    } catch (e) {
      debugPrint('Error getting device consumption for $deviceId: $e');
      return 0.0;
    }
  }

  // Manually trigger a report (for testing) without resetting counters
  Future<Map<String, double>> generateReportNow() async {
    final dailyReport = Map<String, double>.from(_dailyConsumption);
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);

    // Save the daily report to Firebase with the date as the key
    await _database.child('reports/daily/$date').set({
      'timestamp': ServerValue.timestamp,
      'consumption': dailyReport,
      'date': date, // Add the date explicitly for clarity
      'report_type': 'daily',
    });

    // Create a notification about the daily report
    await _createReportNotification(dailyReport, date);

    return dailyReport;
  }

  // Handle device changes
  void _onDevicesChanged() {
    // Get updated device information
    final newDeviceIds = _deviceService.deviceIds;

    // Check for new devices
    for (final deviceId in newDeviceIds) {
      if (!_deviceIds.contains(deviceId)) {
        // Add new device to our tracking
        _deviceIds.add(deviceId);

        // Initialize consumption maps for the new device
        _dailyConsumption[deviceId] = 0.0;
        _weeklyConsumption[deviceId] = 0.0;
        _monthlyConsumption[deviceId] = 0.0;
        _yearlyConsumption[deviceId] = 0.0;

        // Start listening to flow data for the new device
        _listenToDeviceFlow(deviceId);
      }
    }

    // Update device labels
    _deviceLabels = Map.from(_deviceService.deviceLabels);
  }

  // Get device IDs (for external use)
  List<String> get deviceIds => List.unmodifiable(_deviceIds);

  // Get device labels (for external use)
  Map<String, String> get deviceLabels => Map.unmodifiable(_deviceLabels);

  // Dispose resources
  @override
  void dispose() {
    _midnightTimer?.cancel();
    _deviceService.removeListener(_onDevicesChanged);
    super.dispose();
  }
}

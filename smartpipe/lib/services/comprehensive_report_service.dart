import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pdf_service.dart';
import 'device_management_service.dart';
import '../theme/app_theme.dart';
import 'database_email_service.dart';

// Enum for report periods
enum ReportPeriod { today, weekly, monthly, summary }

class ComprehensiveReportService {
  static final DeviceManagementService _deviceService =
      DeviceManagementService();

  // Show report period selection dialog
  static Future<ReportPeriod?> showReportPeriodDialog(
    BuildContext context,
  ) async {
    return showDialog<ReportPeriod>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Select Report Period',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPeriodOption(
                context,
                ReportPeriod.today,
                'Today\'s Report',
                'Generate report for today\'s data only',
                Icons.today,
              ),
              const SizedBox(height: 12),
              _buildPeriodOption(
                context,
                ReportPeriod.weekly,
                'Weekly Report',
                'Generate report for the current week',
                Icons.view_week,
              ),
              const SizedBox(height: 12),
              _buildPeriodOption(
                context,
                ReportPeriod.monthly,
                'Monthly Report',
                'Generate report for the current month',
                Icons.calendar_month,
              ),
              const SizedBox(height: 12),
              _buildPeriodOption(
                context,
                ReportPeriod.summary,
                'Summary Report',
                'Generate comprehensive summary of all data',
                Icons.summarize,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.errorColor),
              ),
            ),
          ],
        );
      },
    );
  }

  // Build period option widget
  static Widget _buildPeriodOption(
    BuildContext context,
    ReportPeriod period,
    String title,
    String description,
    IconData icon,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(period),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.primaryColor.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // Generate comprehensive report for all devices and periods
  static Future<void> generateAndDownloadComprehensiveReport(
    BuildContext context,
  ) async {
    // Show period selection dialog first
    final selectedPeriod = await showReportPeriodDialog(context);
    if (selectedPeriod == null) return; // User cancelled

    await _generateReportForPeriod(context, selectedPeriod);
  }

  // Generate report for specific period
  static Future<void> _generateReportForPeriod(
    BuildContext context,
    ReportPeriod period,
  ) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Initialize device service if not already done
      await _deviceService.initialize();
      final deviceLabels = _deviceService.deviceLabels;
      final deviceIds = deviceLabels.keys.toList();

      // Collect water quality data for all devices
      final Map<String, Map<String, dynamic>> waterQualityData = {};

      for (final deviceId in deviceIds) {
        try {
          final dataRef = FirebaseDatabase.instance
              .ref()
              .child('readings')
              .child(deviceId)
              .child('data');

          final snapshot = await dataRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final List<Map<String, dynamic>> history = [];

            // Filter data based on period
            final filteredData = _filterDataByPeriod(data, period);

            if (filteredData.isNotEmpty) {
              // Sort by timestamp (latest first)
              final sortedKeys =
                  filteredData.keys.toList()
                    ..sort((a, b) => b.toString().compareTo(a.toString()));

              double? latestPh;
              String latestTurbidity = 'N/A';

              // Process the filtered data (limit to 3 entries for all reports to prevent TooManyPagesException)
              final historyLimit = 3;
              for (int i = 0; i < sortedKeys.length && i < historyLimit; i++) {
                final key = sortedKeys[i];
                final entry = filteredData[key] as Map<dynamic, dynamic>;

                if (i == 0) {
                  // Get the latest values
                  latestPh =
                      entry['ph'] != null
                          ? double.tryParse(entry['ph'].toString())
                          : null;
                  latestTurbidity =
                      entry['turbidity'] != null
                          ? entry['turbidity'].toString()
                          : 'N/A';
                }

                // Add to history with formatted timestamp
                String formattedTime = _formatTimestamp(key.toString());
                debugPrint(
                  'Original key: ${key.toString()}, Formatted: $formattedTime',
                );

                history.add({
                  'time': formattedTime,
                  'ph': entry['ph'] != null ? entry['ph'].toString() : 'N/A',
                  'turbidity':
                      entry['turbidity'] != null
                          ? entry['turbidity'].toString()
                          : 'N/A',
                  'rawTimestamp':
                      key.toString(), // Keep raw timestamp for sorting if needed
                });
              }

              // Store the data for this device
              waterQualityData[deviceId] = {
                'ph': latestPh,
                'turbidityStatus': latestTurbidity,
                'history': history,
              };
            }
          }
        } catch (e) {
          debugPrint(
            'Error fetching water quality data for device $deviceId: $e',
          );
          // Continue with other devices even if one fails
        }
      }

      // Collect water consumption data for the selected period
      final Map<String, Map<String, double>> waterConsumptionData = {};

      // Determine which periods to include based on selection
      List<String> periodsToInclude = [];
      switch (period) {
        case ReportPeriod.today:
          periodsToInclude = ['daily'];
          break;
        case ReportPeriod.weekly:
          periodsToInclude = ['daily', 'weekly'];
          break;
        case ReportPeriod.monthly:
          periodsToInclude = ['daily', 'weekly', 'monthly'];
          break;
        case ReportPeriod.summary:
          periodsToInclude = ['daily', 'weekly', 'monthly', 'yearly'];
          break;
      }

      // Collect leak detection data
      final Map<String, List<Map<String, dynamic>>> leakData = {};

      // Collect leak data for each device
      for (final deviceId in deviceIds) {
        try {
          final leakRef = FirebaseDatabase.instance
              .ref()
              .child('leak_history')
              .child(deviceId);

          final snapshot = await leakRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final List<Map<String, dynamic>> leaks = [];

            data.forEach((key, value) {
              if (value is Map) {
                final leak = Map<String, dynamic>.from(value);

                // Add the leak data to the list
                leaks.add({
                  'timestamp': leak['timestamp'] ?? 0,
                  'reason': leak['reason'] ?? 'Unknown',
                  'flow': leak['flow'] ?? 0.0,
                  'time': leak['time'] ?? 'Unknown',
                  'date': leak['date'] ?? 'Unknown',
                  'valve_state': leak['valve_state'] ?? false,
                  'message':
                      leak['reason'] ?? 'Leak detected', // For PDF display
                  'flow_rate':
                      '${(leak['flow'] ?? 0.0).toStringAsFixed(2)} L/min', // For PDF display
                });
              }
            });

            // Sort leaks by timestamp (newest first)
            leaks.sort(
              (a, b) =>
                  (b['timestamp'] as int).compareTo(a['timestamp'] as int),
            );

            // Filter leaks based on the selected period
            final now = DateTime.now();
            final filteredLeaks = <Map<String, dynamic>>[];

            for (final leak in leaks) {
              final timestamp = leak['timestamp'] as int;
              final leakDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
              final daysDifference = now.difference(leakDate).inDays;

              bool includeLeak = false;
              switch (period) {
                case ReportPeriod.today:
                  includeLeak = daysDifference == 0;
                  break;
                case ReportPeriod.weekly:
                  includeLeak = daysDifference <= 7;
                  break;
                case ReportPeriod.monthly:
                  includeLeak = daysDifference <= 30;
                  break;
                case ReportPeriod.summary:
                  includeLeak = true; // Include all leaks for summary
                  break;
              }

              if (includeLeak) {
                filteredLeaks.add(leak);
              }
            }

            if (filteredLeaks.isNotEmpty) {
              leakData[deviceId] = filteredLeaks;
              debugPrint('✅ Collected ${filteredLeaks.length} leaks for device $deviceId');
            } else {
              debugPrint('⚠️ No filtered leaks for device $deviceId (total: ${leaks.length}, period: $period)');
            }
          } else {
            debugPrint('⚠️ No leak data found in Firebase for device $deviceId at leak_history/$deviceId');
          }
        } catch (e) {
          debugPrint('❌ Error fetching leak data for device $deviceId: $e');
        }
      }
      
      debugPrint('📊 Total leak data collected: ${leakData.length} devices, ${leakData.values.fold<int>(0, (sum, leaks) => sum + leaks.length)} total leaks');

      // Collect manual activities data
      final Map<String, List<Map<String, dynamic>>> manualActivitiesData = {};

      // Collect manual activities data for each device
      for (final deviceId in deviceIds) {
        try {
          final manualActivitiesRef = FirebaseDatabase.instance
              .ref()
              .child('readings')
              .child(deviceId)
              .child('manual-activities');

          final snapshot = await manualActivitiesRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final List<Map<String, dynamic>> activities = [];

            data.forEach((key, value) {
              if (value is Map) {
                final activity = Map<String, dynamic>.from(value);

                // Add the manual activity data to the list
                activities.add({
                  'timestamp': activity['timestamp'] ?? 0,
                  'reason': activity['reason'] ?? 'Unknown',
                  'flow': activity['flow'] ?? 0.0,
                  'time': activity['time'] ?? 'Unknown',
                  'date': activity['date'] ?? 'Unknown',
                  'device_id': activity['device_id'] ?? deviceId,
                  'message':
                      activity['reason'] ??
                      'Manual activity detected', // For PDF display
                  'flow_rate':
                      '${(activity['flow'] ?? 0.0).toStringAsFixed(2)} L/min', // For PDF display
                });
              }
            });

            // Sort activities by timestamp (newest first)
            activities.sort(
              (a, b) =>
                  (b['timestamp'] as int).compareTo(a['timestamp'] as int),
            );

            // Filter activities based on the selected period
            final now = DateTime.now();
            final filteredActivities = <Map<String, dynamic>>[];

            for (final activity in activities) {
              final timestamp = activity['timestamp'] as int;
              final activityDate = DateTime.fromMillisecondsSinceEpoch(
                timestamp,
              );
              final daysDifference = now.difference(activityDate).inDays;

              bool includeActivity = false;
              switch (period) {
                case ReportPeriod.today:
                  includeActivity = daysDifference == 0;
                  break;
                case ReportPeriod.weekly:
                  includeActivity = daysDifference <= 7;
                  break;
                case ReportPeriod.monthly:
                  includeActivity = daysDifference <= 30;
                  break;
                case ReportPeriod.summary:
                  includeActivity = true; // Include all activities for summary
                  break;
              }

              if (includeActivity) {
                filteredActivities.add(activity);
              }
            }

            if (filteredActivities.isNotEmpty) {
              manualActivitiesData[deviceId] = filteredActivities;
              debugPrint('✅ Collected ${filteredActivities.length} manual activities for device $deviceId');
            } else {
              debugPrint('⚠️ No filtered manual activities for device $deviceId (total: ${activities.length}, period: $period)');
            }
          } else {
            debugPrint('⚠️ No manual activities found in Firebase for device $deviceId at readings/$deviceId/manual-activities');
          }
        } catch (e) {
          debugPrint(
            '❌ Error fetching manual activities data for device $deviceId: $e',
          );
        }
      }
      
      debugPrint('📊 Total manual activities collected: ${manualActivitiesData.length} devices, ${manualActivitiesData.values.fold<int>(0, (sum, activities) => sum + activities.length)} total activities');

      // Collect water consumption data
      for (final periodKey in periodsToInclude) {
        try {
          final consumptionRef = FirebaseDatabase.instance
              .ref()
              .child('consumption')
              .child(periodKey);

          final snapshot = await consumptionRef.get();
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final Map<String, double> consumption = {};

            data.forEach((deviceId, value) {
              if (value is num) {
                consumption[deviceId.toString()] = value.toDouble();
              }
            });

            if (consumption.isNotEmpty) {
              waterConsumptionData[periodKey] = consumption;
            }
          }
        } catch (e) {
          debugPrint('Error fetching consumption data for $periodKey: $e');
        }
      }

      // Debug: Log what we're passing to PDF
      debugPrint('📤 Passing to PDF - Period: $period');
      debugPrint('📤 leakData: ${leakData.length} devices');
      debugPrint('📤 manualActivitiesData: ${manualActivitiesData.length} devices');
      for (final entry in leakData.entries) {
        debugPrint('   - ${entry.key}: ${entry.value.length} leaks');
      }
      for (final entry in manualActivitiesData.entries) {
        debugPrint('   - ${entry.key}: ${entry.value.length} activities');
      }

      // Check if we have any data
      if (waterQualityData.isEmpty && waterConsumptionData.isEmpty && leakData.isEmpty && manualActivitiesData.isEmpty) {
        // Close loading dialog
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        // Show error message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data available for the selected period'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Generate comprehensive PDF with period information
      final pdfPath = await PdfService.generateComprehensiveReport(
        waterQualityData: waterQualityData,
        waterConsumptionData: waterConsumptionData,
        deviceLabels: deviceLabels,
        leakData: leakData,
        manualActivitiesData: manualActivitiesData,
        reportPeriod: period,
      );

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Open the PDF file
      await PdfService.openPdfFile(pdfPath);

      // Queue email with the generated report
      final recipientsCount = await _sendReportEmail(
        pdfPath: pdfPath,
        period: period,
        deviceLabels: deviceLabels,
        waterQualityData: waterQualityData,
        waterConsumptionData: waterConsumptionData,
        leakData: leakData,
        manualActivitiesData: manualActivitiesData,
      );

      // Show success message
      if (context.mounted) {
        final emailNotice =
            recipientsCount > 0
                ? '\nEmail queued for $recipientsCount recipient(s).'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_getPeriodDisplayName(period)} saved to: $pdfPath$emailNotice',
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  static Future<int> _sendReportEmail({
    required String pdfPath,
    required ReportPeriod period,
    required Map<String, String> deviceLabels,
    required Map<String, Map<String, dynamic>> waterQualityData,
    required Map<String, Map<String, double>> waterConsumptionData,
    required Map<String, List<Map<String, dynamic>>> leakData,
    required Map<String, List<Map<String, dynamic>>> manualActivitiesData,
  }) async {
    try {
      final recipients = await _fetchEmailRecipients();
      if (recipients.isEmpty) {
        debugPrint('⚠️ No email recipients configured for reports.');
        return 0;
      }

      final base64Pdf = await PdfService.encodeFileToBase64(pdfPath);
      final fileName = File(pdfPath).uri.pathSegments.last;
      final periodName = _getPeriodDisplayName(period);

      final totalLeaks = leakData.values.fold<int>(
        0,
        (sum, leaks) => sum + leaks.length,
      );
      final totalManual = manualActivitiesData.values.fold<int>(
        0,
        (sum, activities) => sum + activities.length,
      );

      final deviceCount = deviceLabels.length;
      final nowFormatted = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(DateTime.now());

      // Calculate total consumption from waterConsumptionData
      final totalConsumption = <String, double>{};
      for (final entry in waterConsumptionData.entries) {
        final deviceId = entry.key;
        final deviceConsumption = entry.value.values.fold<double>(
          0.0,
          (sum, value) => sum + value,
        );
        if (deviceConsumption > 0) {
          totalConsumption[deviceId] = deviceConsumption;
        }
      }

      final summaryMessage = '''
<p>Attached is the <strong>$periodName</strong> generated on <strong>$nowFormatted</strong>.</p>
<p>
Devices included: <strong>$deviceCount</strong><br/>
Total leak events: <strong>$totalLeaks</strong><br/>
Manual switch events: <strong>$totalManual</strong>
</p>
<p>Please review the attached PDF for full details.</p>
''';

      await DatabaseEmailService.sendReportEmail(
        recipients: recipients,
        subject: 'SmartPipe $periodName',
        message: summaryMessage,
        attachmentBase64: base64Pdf,
        fileName: fileName,
        reportPeriod: periodName,
        deviceCount: deviceCount,
        totalLeaks: totalLeaks,
        totalManual: totalManual,
        consumption: totalConsumption.isNotEmpty ? totalConsumption : null,
        deviceLabels: deviceLabels,
      );

      debugPrint(
        '📧 Comprehensive report email queued for ${recipients.length} recipient(s).',
      );
      return recipients.length;
    } catch (e) {
      debugPrint('❌ Failed to queue report email: $e');
      return 0;
    }
  }

  static Future<List<String>> _fetchEmailRecipients() async {
    try {
      final snapshot =
          await FirebaseDatabase.instance
              .ref('email_settings/recipients')
              .get();
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
      debugPrint('❌ Failed to fetch email recipients: $e');
      return [];
    }
  }

  // Filter data based on selected period
  static Map<dynamic, dynamic> _filterDataByPeriod(
    Map<dynamic, dynamic> data,
    ReportPeriod period,
  ) {
    final now = DateTime.now();
    final filteredData = <dynamic, dynamic>{};

    data.forEach((key, value) {
      final timestamp = _parseTimestamp(key.toString());
      if (timestamp != null) {
        bool shouldInclude = false;

        switch (period) {
          case ReportPeriod.today:
            shouldInclude = _isSameDay(timestamp, now);
            break;
          case ReportPeriod.weekly:
            shouldInclude = _isSameWeek(timestamp, now);
            break;
          case ReportPeriod.monthly:
            shouldInclude = _isSameMonth(timestamp, now);
            break;
          case ReportPeriod.summary:
            shouldInclude = true; // Include all data for summary
            break;
        }

        if (shouldInclude) {
          filteredData[key] = value;
        }
      }
    });

    return filteredData;
  }

  // Parse timestamp from Firebase key
  static DateTime? _parseTimestamp(String timestampKey) {
    final normalizedKey = _normalizeSanitizedIso(timestampKey);
    try {
      // Check if it's a Unix timestamp (seconds)
      if (timestampKey.contains(RegExp(r'^\d+$'))) {
        final timestamp = int.tryParse(timestampKey);
        if (timestamp != null) {
          // If the timestamp is in seconds (10 digits or less), convert to milliseconds
          final isSeconds = timestampKey.length <= 10;
          return isSeconds
              ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
              : DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }

      // Try ISO-8601 formats (e.g., 2025-11-12T12:04:40Z)
      try {
        return DateTime.parse(normalizedKey);
      } catch (_) {
        // continue to other formats
      }

      // Try other formats if needed
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check if two dates are the same day
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // Check if two dates are in the same week
  static bool _isSameWeek(DateTime date1, DateTime date2) {
    final week1 = date1.difference(DateTime(date1.year)).inDays ~/ 7;
    final week2 = date2.difference(DateTime(date2.year)).inDays ~/ 7;
    return date1.year == date2.year && week1 == week2;
  }

  // Check if two dates are in the same month
  static bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  // Get display name for report period
  static String _getPeriodDisplayName(ReportPeriod period) {
    switch (period) {
      case ReportPeriod.today:
        return 'Today\'s Report';
      case ReportPeriod.weekly:
        return 'Weekly Report';
      case ReportPeriod.monthly:
        return 'Monthly Report';
      case ReportPeriod.summary:
        return 'Summary Report';
    }
  }

  // Helper method to format timestamp from Firebase key to readable date/time
  static String _formatTimestamp(String timestampKey) {
    final normalizedKey = _normalizeSanitizedIso(timestampKey);
    try {
      // ISO-8601 format with time component (e.g., 2025-11-12T12:04:40Z)
      if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(normalizedKey)) {
        final dateTime = DateTime.parse(normalizedKey).toLocal();
        return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
      }

      // Firebase keys are often in format: YYYY-MM-DD_HH-MM-SS or similar
      // Try to parse different timestamp formats

      // Check if it's a Unix timestamp (seconds)
      if (timestampKey.contains(RegExp(r'^\d+$'))) {
        final timestamp = int.tryParse(timestampKey);
        if (timestamp != null) {
          // If the timestamp is in seconds (10 digits or less), convert to milliseconds
          final isSeconds = timestampKey.length <= 10;
          final dateTime =
              isSeconds
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
                  : DateTime.fromMillisecondsSinceEpoch(timestamp);
          return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
        }
      }

      // Check if it's in YYYY-MM-DD_HH-MM-SS format
      if (timestampKey.contains('_') && timestampKey.contains('-')) {
        final parts = timestampKey.split('_');
        if (parts.length == 2) {
          final datePart = parts[0]; // YYYY-MM-DD
          final timePart = parts[1].replaceAll('-', ':'); // HH:MM:SS

          try {
            final dateTime = DateTime.parse('$datePart $timePart');
            return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
          } catch (e) {
            // If parsing fails, continue to other formats
          }
        }
      }

      // Check if it's in YYYY-MM-DD format (date only)
      if (timestampKey.contains('-') && timestampKey.split('-').length == 3) {
        try {
          final dateTime = DateTime.parse(timestampKey);
          return DateFormat('MMM dd, yyyy').format(dateTime);
        } catch (e) {
          // If parsing fails, continue
        }
      }

      // Check if it's in YYYYMMDD_HHMMSS format
      if (timestampKey.length >= 8) {
        try {
          String formatted = timestampKey;

          // If it contains underscore, split date and time parts
          if (formatted.contains('_')) {
            final parts = formatted.split('_');
            final datePart = parts[0];
            final timePart = parts.length > 1 ? parts[1] : '';

            // Format date part: YYYYMMDD -> YYYY-MM-DD
            if (datePart.length == 8) {
              final year = datePart.substring(0, 4);
              final month = datePart.substring(4, 6);
              final day = datePart.substring(6, 8);

              // Format time part: HHMMSS -> HH:MM:SS
              String timeFormatted = '';
              if (timePart.length >= 6) {
                final hour = timePart.substring(0, 2);
                final minute = timePart.substring(2, 4);
                final second = timePart.substring(4, 6);
                timeFormatted = ' $hour:$minute:$second';
              }

              final dateTime = DateTime.parse(
                '$year-$month-$day$timeFormatted',
              );
              return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
            }
          }
        } catch (e) {
          // If parsing fails, continue
        }
      }

      // If all parsing attempts fail, return the original key with some formatting
      return timestampKey.replaceAll('_', ' ').replaceAll('-', ':');
    } catch (e) {
      // If any error occurs, return the original timestamp
      return timestampKey;
    }
  }

  static String _normalizeSanitizedIso(String timestampKey) {
    final sanitizedIsoPattern = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?(Z)?$',
    );
    final match = sanitizedIsoPattern.firstMatch(timestampKey);
    if (match != null) {
      final datePart = match.group(1)!;
      final hour = match.group(2)!;
      final minute = match.group(3)!;
      final second = match.group(4)!;
      final millis = match.group(5);
      final suffix = match.group(6) ?? '';

      final buffer = StringBuffer()
        ..write('${datePart}T$hour:$minute:$second');
      if (millis != null) {
        buffer.write('.$millis');
      }
      buffer.write(suffix);
      return buffer.toString();
    }

    return timestampKey;
  }
}

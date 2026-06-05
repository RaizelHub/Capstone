import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';

// Import the ReportPeriod enum
import 'comprehensive_report_service.dart';

class PdfService {
  // Generate and save a comprehensive report PDF combining water quality, consumption, and leak data
  static Future<String> generateComprehensiveReport({
    required Map<String, Map<String, dynamic>> waterQualityData,
    required Map<String, Map<String, double>> waterConsumptionData,
    required Map<String, String> deviceLabels,
    Map<String, List<Map<String, dynamic>>> leakData = const {},
    Map<String, List<Map<String, dynamic>>> manualActivitiesData = const {},
    ReportPeriod? reportPeriod,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);
    final formattedTime = DateFormat('HH:mm:ss').format(now);

    // Get period display name
    final periodName = _getPeriodDisplayName(reportPeriod);

    // Create PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        maxPages:
            reportPeriod == ReportPeriod.summary
                ? 100
                : 20, // Higher limit for summary to ensure leak/manual sections render
        header:
            (context) => _buildHeader(
              title: 'SmartPipe $periodName',
              date: formattedDate,
              time: formattedTime,
            ),
        footer: (context) => _buildFooter(),
        build: (pw.Context context) {
          // Debug: Log what data we have
          debugPrint('📄 PDF Generation - Report Period: $reportPeriod');
          debugPrint(
            '📊 leakData: ${leakData.length} devices, ${leakData.values.fold<int>(0, (sum, leaks) => sum + leaks.length)} total leaks',
          );
          debugPrint(
            '📊 manualActivitiesData: ${manualActivitiesData.length} devices, ${manualActivitiesData.values.fold<int>(0, (sum, activities) => sum + activities.length)} total activities',
          );

          final List<pw.Widget> content = <pw.Widget>[
            // Summary Section
            _buildSummarySection(
              waterQualityData: waterQualityData,
              waterConsumptionData: waterConsumptionData,
              deviceLabels: deviceLabels,
              periodName: periodName,
              leakData: leakData,
              manualActivitiesData: manualActivitiesData,
            ),
            pw.SizedBox(height: 30),
          ];

          // For summary reports, prioritize leak and manual sections by adding them first
          if (reportPeriod == ReportPeriod.summary) {
            // Add leak and manual sections immediately after summary for summary reports
            // This ensures they're rendered before hitting page limits

            // Leak Detection Section (always show, even if empty)
            debugPrint(
              '🔍 PDF: Adding Leak Detection Section for period: $reportPeriod (PRIORITIZED)',
            );
            debugPrint(
              '🔍 PDF: leakData.isEmpty = ${leakData.isEmpty}, leakData.length = ${leakData.length}',
            );
            debugPrint(
              '🔍 PDF: Current content count before leak section: ${content.length}',
            );

            // Reduced spacing for summary reports to prevent TooManyPagesException
            final sectionSpacing = 10.0; // Reduced from 20 for summary
            content.addAll([
              pw.SizedBox(height: sectionSpacing),
              pw.Divider(color: PdfColors.grey400, thickness: 2),
              pw.SizedBox(height: sectionSpacing),
              _buildSectionHeader('LEAK DETECTION REPORT', PdfColors.red700),
              pw.SizedBox(height: sectionSpacing),
            ]);
            debugPrint(
              '🔍 PDF: Content count after adding leak section header: ${content.length}',
            );

            if (leakData.isEmpty) {
              debugPrint('⚠️ PDF: leakData is empty, showing empty message');
              content.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'No leak alerts found for the selected period.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              );
            } else {
              debugPrint(
                '✅ PDF: leakData has ${leakData.length} devices with ${leakData.values.fold<int>(0, (sum, leaks) => sum + leaks.length)} total leaks',
              );

              final leakDeviceLimit =
                  2; // Limit to 2 devices for summary to prevent TooManyPagesException
              final leakDeviceEntries = leakData.entries.take(leakDeviceLimit);
              for (final entry in leakDeviceEntries) {
                final deviceId = entry.key;
                final leaks = entry.value;
                if (leaks.isNotEmpty) {
                  final deviceName = deviceLabels[deviceId] ?? deviceId;
                  final limitedLeaks =
                      leaks
                          .take(5)
                          .toList(); // Limit to 5 leaks per device for summary
                  debugPrint(
                    '📝 PDF: Adding leak section widget for device $deviceName with ${limitedLeaks.length} leaks',
                  );
                  content.addAll([
                    _buildLeakDetectionSection(
                      deviceName: deviceName,
                      leaks: limitedLeaks,
                      totalCount: leaks.length,
                    ),
                    pw.SizedBox(height: 8), // Reduced spacing for summary
                  ]);
                  debugPrint(
                    '📝 PDF: Content count after adding leak section: ${content.length}',
                  );
                }
              }

              if (leakData.length > leakDeviceLimit) {
                content.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border.all(color: PdfColors.red300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Note: Showing leak data for first $leakDeviceLimit of ${leakData.length} devices.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.red700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }
            }

            // Manual Activities Section (always show, even if empty)
            debugPrint(
              '🔍 PDF: Adding Manual Activities Section for period: $reportPeriod (PRIORITIZED)',
            );
            debugPrint(
              '🔍 PDF: manualActivitiesData.isEmpty = ${manualActivitiesData.isEmpty}, manualActivitiesData.length = ${manualActivitiesData.length}',
            );
            debugPrint(
              '🔍 PDF: Current content count before manual section: ${content.length}',
            );

            // Reduced spacing for summary reports to prevent TooManyPagesException
            final manualSectionSpacing = 10.0; // Reduced from 20 for summary
            content.addAll([
              pw.SizedBox(height: manualSectionSpacing),
              pw.Divider(color: PdfColors.grey400, thickness: 2),
              pw.SizedBox(height: manualSectionSpacing),
              _buildSectionHeader(
                'MANUAL ACTIVITIES REPORT',
                PdfColors.orange700,
              ),
              pw.SizedBox(height: manualSectionSpacing),
            ]);
            debugPrint(
              '🔍 PDF: Content count after adding manual section header: ${content.length}',
            );

            if (manualActivitiesData.isEmpty) {
              debugPrint(
                '⚠️ PDF: manualActivitiesData is empty, showing empty message',
              );
              content.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'No manual activities found for the selected period.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              );
            } else {
              debugPrint(
                '✅ PDF: manualActivitiesData has ${manualActivitiesData.length} devices with ${manualActivitiesData.values.fold<int>(0, (sum, activities) => sum + activities.length)} total activities',
              );

              final manualDeviceLimit =
                  2; // Limit to 2 devices for summary to prevent TooManyPagesException
              final manualDeviceEntries = manualActivitiesData.entries.take(
                manualDeviceLimit,
              );
              for (final entry in manualDeviceEntries) {
                final deviceId = entry.key;
                final activities = entry.value;
                if (activities.isNotEmpty) {
                  final deviceName = deviceLabels[deviceId] ?? deviceId;
                  // Limit to most recent 5 activities for summary to prevent TooManyPagesException
                  final limitedActivities = activities.take(5).toList();
                  debugPrint(
                    '📝 PDF: Adding manual activities section widget for device $deviceName with ${limitedActivities.length} activities',
                  );
                  content.addAll([
                    _buildManualActivitiesSection(
                      deviceName: deviceName,
                      activities: limitedActivities,
                      totalCount: activities.length,
                    ),
                    pw.SizedBox(height: 8), // Reduced spacing for summary
                  ]);
                  debugPrint(
                    '📝 PDF: Content count after adding manual activities section: ${content.length}',
                  );
                }
              }

              if (manualActivitiesData.length > manualDeviceLimit) {
                content.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange50,
                      border: pw.Border.all(color: PdfColors.orange300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Note: Showing manual activities for first $manualDeviceLimit of ${manualActivitiesData.length} devices.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.orange700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }
            }
          }

          // For summary reports, skip detailed sections to prevent TooManyPagesException
          // Skip water quality section entirely for summary reports to save space for leak/manual sections
          if (reportPeriod != ReportPeriod.summary) {
            content.addAll([
              // Water Quality Section
              _buildSectionHeader('WATER QUALITY REPORT', PdfColors.blue700),
              pw.SizedBox(height: 20),
            ]);

            // Add each device's water quality data (limit to first 5 devices for summary reports)
            final deviceLimit = reportPeriod == ReportPeriod.monthly ? 10 : 999;
            final deviceEntries = waterQualityData.entries.take(deviceLimit);
            for (final entry in deviceEntries) {
              final deviceId = entry.key;
              final data = entry.value;
              final deviceName = deviceLabels[deviceId] ?? deviceId;
              final double? ph = data['ph'];
              final String turbidityStatus = data['turbidityStatus'] ?? 'N/A';
              final List<Map<String, dynamic>> history = data['history'] ?? [];

              content.addAll([
                _buildDeviceInfo(deviceId: deviceId, deviceName: deviceName),
                pw.SizedBox(height: 15),
                _buildWaterQualityParameters(
                  ph: ph,
                  turbidityStatus: turbidityStatus,
                ),
                pw.SizedBox(height: 15),
                // Skip history for summary reports to save space
                if (history.isNotEmpty) ...[
                  // Limit to most recent 3 entries to prevent TooManyPagesException
                  _buildWaterQualityHistory(
                    history: history.take(3).toList(),
                    totalCount: history.length,
                  ),
                  pw.SizedBox(height: 15),
                ],
                pw.Divider(color: PdfColors.grey300, thickness: 1),
                pw.SizedBox(height: 20),
              ]);
            }
          }
          // Note: For summary reports, we skip the water quality section entirely
          // to prioritize leak and manual activities sections which are added earlier

          // Water Consumption Section (skip for summary to save space)
          if (waterConsumptionData.isNotEmpty &&
              reportPeriod != ReportPeriod.summary) {
            content.addAll([
              _buildSectionHeader(
                'WATER CONSUMPTION REPORT',
                PdfColors.green700,
              ),
              pw.SizedBox(height: 20),
            ]);

            // Add each period's consumption data
            final periods = {
              'daily': 'Daily Report',
              'weekly': 'Weekly Report',
              'monthly': 'Monthly Report',
              'yearly': 'Yearly Report',
            };

            waterConsumptionData.forEach((periodKey, consumption) {
              if (consumption.isNotEmpty) {
                // Calculate total consumption for this period
                final totalConsumption = consumption.values.fold(
                  0.0,
                  (sum, value) => sum + value,
                );

                // Convert to liters
                final totalLiters = (totalConsumption * 5).toStringAsFixed(
                  2,
                ); // 1 flowrate unit = 5 liters

                // Get period display name
                final periodName = periods[periodKey] ?? periodKey;

                content.addAll([
                  _buildPeriodHeader(periodName),
                  pw.SizedBox(height: 15),
                  _buildTotalConsumption(totalLiters: totalLiters),
                  pw.SizedBox(height: 15),
                  _buildDeviceConsumptionTable(
                    consumption: consumption,
                    deviceLabels: deviceLabels,
                  ),
                  pw.Divider(color: PdfColors.grey300, thickness: 1),
                  pw.SizedBox(height: 20),
                ]);
              }
            });
          }

          // Leak Detection Section (always show, even if empty)
          // Skip for summary reports since we already added them earlier
          if (reportPeriod != ReportPeriod.summary) {
            debugPrint(
              '🔍 PDF: Adding Leak Detection Section for period: $reportPeriod',
            );
            debugPrint(
              '🔍 PDF: leakData.isEmpty = ${leakData.isEmpty}, leakData.length = ${leakData.length}',
            );
            debugPrint(
              '🔍 PDF: Current content count before leak section: ${content.length}',
            );

            // Add a visible separator before leak section to ensure it's rendered
            content.addAll([
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey400, thickness: 2),
              pw.SizedBox(height: 20),
              _buildSectionHeader('LEAK DETECTION REPORT', PdfColors.red700),
              pw.SizedBox(height: 20),
            ]);
            debugPrint(
              '🔍 PDF: Content count after adding leak section header: ${content.length}',
            );

            // Debug: Check if leak data exists
            if (leakData.isEmpty) {
              debugPrint('⚠️ PDF: leakData is empty, showing empty message');
              content.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'No leak alerts found for the selected period.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              );
            } else {
              debugPrint(
                '✅ PDF: leakData has ${leakData.length} devices with ${leakData.values.fold<int>(0, (sum, leaks) => sum + leaks.length)} total leaks',
              );

              // Add leak data for each device (limit devices and entries)
              final leakDeviceLimit =
                  reportPeriod == ReportPeriod.summary
                      ? 3
                      : (reportPeriod == ReportPeriod.monthly ? 5 : 999);
              final leakDeviceEntries = leakData.entries.take(leakDeviceLimit);
              for (final entry in leakDeviceEntries) {
                final deviceId = entry.key;
                final leaks = entry.value;
                if (leaks.isNotEmpty) {
                  final deviceName = deviceLabels[deviceId] ?? deviceId;
                  // Limit to most recent 10 leaks to prevent TooManyPagesException
                  final limitedLeaks = leaks.take(10).toList();
                  debugPrint(
                    '📝 PDF: Adding leak section widget for device $deviceName with ${limitedLeaks.length} leaks',
                  );
                  content.addAll([
                    _buildLeakDetectionSection(
                      deviceName: deviceName,
                      leaks: limitedLeaks,
                      totalCount: leaks.length,
                    ),
                    pw.SizedBox(height: 15),
                  ]);
                  debugPrint(
                    '📝 PDF: Content count after adding leak section: ${content.length}',
                  );
                }
              }

              // Add note if devices were limited
              if (leakData.length > leakDeviceLimit) {
                content.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border.all(color: PdfColors.red300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Note: Showing leak data for first $leakDeviceLimit of ${leakData.length} devices.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.red700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }
            }
          }

          // Manual Activities Section (always show, even if empty)
          // Skip for summary reports since we already added them earlier
          if (reportPeriod != ReportPeriod.summary) {
            debugPrint(
              '🔍 PDF: Adding Manual Activities Section for period: $reportPeriod',
            );
            debugPrint(
              '🔍 PDF: manualActivitiesData.isEmpty = ${manualActivitiesData.isEmpty}, manualActivitiesData.length = ${manualActivitiesData.length}',
            );
            debugPrint(
              '🔍 PDF: Current content count before manual section: ${content.length}',
            );

            // Add a visible separator before manual activities section to ensure it's rendered
            content.addAll([
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey400, thickness: 2),
              pw.SizedBox(height: 20),
              _buildSectionHeader(
                'MANUAL ACTIVITIES REPORT',
                PdfColors.orange700,
              ),
              pw.SizedBox(height: 20),
            ]);
            debugPrint(
              '🔍 PDF: Content count after adding manual section header: ${content.length}',
            );

            // Debug: Check if manual activities data exists
            if (manualActivitiesData.isEmpty) {
              debugPrint(
                '⚠️ PDF: manualActivitiesData is empty, showing empty message',
              );
              content.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'No manual activities found for the selected period.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              );
            } else {
              debugPrint(
                '✅ PDF: manualActivitiesData has ${manualActivitiesData.length} devices with ${manualActivitiesData.values.fold<int>(0, (sum, activities) => sum + activities.length)} total activities',
              );

              // Add manual activities data for each device (limit devices and entries)
              final manualDeviceLimit =
                  reportPeriod == ReportPeriod.summary
                      ? 3
                      : (reportPeriod == ReportPeriod.monthly ? 5 : 999);
              final manualDeviceEntries = manualActivitiesData.entries.take(
                manualDeviceLimit,
              );
              for (final entry in manualDeviceEntries) {
                final deviceId = entry.key;
                final activities = entry.value;
                if (activities.isNotEmpty) {
                  final deviceName = deviceLabels[deviceId] ?? deviceId;
                  // Limit to most recent 10 activities to prevent TooManyPagesException
                  final limitedActivities = activities.take(10).toList();
                  debugPrint(
                    '📝 PDF: Adding manual activities section widget for device $deviceName with ${limitedActivities.length} activities',
                  );
                  content.addAll([
                    _buildManualActivitiesSection(
                      deviceName: deviceName,
                      activities: limitedActivities,
                      totalCount: activities.length,
                    ),
                    pw.SizedBox(height: 15),
                  ]);
                  debugPrint(
                    '📝 PDF: Content count after adding manual activities section: ${content.length}',
                  );
                }
              }

              // Add note if devices were limited
              if (manualActivitiesData.length > manualDeviceLimit) {
                content.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange50,
                      border: pw.Border.all(color: PdfColors.orange300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Note: Showing manual activities for first $manualDeviceLimit of ${manualActivitiesData.length} devices.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.orange700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }
            }
          }

          // Final debug: Log total content items and structure
          debugPrint(
            '📄 PDF: Total content items before return: ${content.length}',
          );
          debugPrint(
            '📄 PDF: Content breakdown - Header: 1, Summary: 1, Water Quality: ${waterQualityData.length}, Leak sections: ~${leakData.isEmpty ? 0 : (leakData.length * 2 + 5)}, Manual sections: ~${manualActivitiesData.isEmpty ? 0 : (manualActivitiesData.length * 2 + 5)}',
          );

          debugPrint(
            '📄 PDF: Final content count after marker: ${content.length}',
          );

          return content;
        },
      ),
    );

    return await _savePdfFile(
      pdf,
      'smartpipe_${_getPeriodFileName(reportPeriod)}_$formattedDate.pdf',
    );
  }

  // Read file and convert to base64 string for emailing
  static Future<String> encodeFileToBase64(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  // Generate and save a water quality report PDF for all devices
  static Future<String> generateWaterQualityReport({
    required Map<String, Map<String, dynamic>> devicesData,
    required Map<String, String> deviceLabels,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);
    final formattedTime = DateFormat('HH:mm:ss').format(now);

    // Create PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        maxPages: 20, // Limit pages to prevent TooManyPagesException
        header:
            (context) => _buildHeader(
              title: 'Water Quality Report - All Devices',
              date: formattedDate,
              time: formattedTime,
            ),
        footer: (context) => _buildFooter(),
        build: (pw.Context context) {
          final List<pw.Widget> content = [
            _buildSectionHeader('WATER QUALITY REPORT', PdfColors.blue700),
            pw.SizedBox(height: 20),
          ];

          // Add each device's data
          devicesData.forEach((deviceId, data) {
            final deviceName = deviceLabels[deviceId] ?? deviceId;
            final double? ph = data['ph'];
            final String turbidityStatus = data['turbidityStatus'] ?? 'N/A';
            final List<Map<String, dynamic>> history = data['history'] ?? [];

            content.addAll([
              _buildDeviceInfo(deviceId: deviceId, deviceName: deviceName),
              pw.SizedBox(height: 15),
              _buildWaterQualityParameters(
                ph: ph,
                turbidityStatus: turbidityStatus,
              ),
              pw.SizedBox(height: 15),
              if (history.isNotEmpty) ...[
                _buildWaterQualityHistory(history: history),
                pw.SizedBox(height: 15),
              ],
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 20),
            ]);
          });

          return content;
        },
      ),
    );

    return await _savePdfFile(pdf, 'water_quality_report_$formattedDate.pdf');
  }

  // Generate and save a water quality report PDF with leak data and manual activities
  static Future<String> generateWaterQualityReportWithLeaks({
    required Map<String, Map<String, dynamic>> devicesData,
    required Map<String, String> deviceLabels,
    Map<String, List<Map<String, dynamic>>> leakData = const {},
    Map<String, List<Map<String, dynamic>>> manualActivitiesData = const {},
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);
    final formattedTime = DateFormat('HH:mm:ss').format(now);

    // Create PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        maxPages: 20, // Limit pages to prevent TooManyPagesException
        header:
            (context) => _buildHeader(
              title: 'Water Quality Report',
              date: formattedDate,
              time: formattedTime,
            ),
        footer: (context) => _buildFooter(),
        build: (pw.Context context) {
          final List<pw.Widget> content = [
            _buildSectionHeader('WATER QUALITY REPORT', PdfColors.blue700),
            pw.SizedBox(height: 20),
          ];

          // Add each device's data
          devicesData.forEach((deviceId, data) {
            final deviceName = deviceLabels[deviceId] ?? deviceId;
            final double? ph = data['ph'];
            final String turbidityStatus = data['turbidityStatus'] ?? 'N/A';
            final List<Map<String, dynamic>> history = data['history'] ?? [];

            content.addAll([
              _buildDeviceInfo(deviceId: deviceId, deviceName: deviceName),
              pw.SizedBox(height: 15),
              _buildWaterQualityParameters(
                ph: ph,
                turbidityStatus: turbidityStatus,
              ),
              pw.SizedBox(height: 15),
              if (history.isNotEmpty) ...[
                // Limit to most recent 3 entries to prevent TooManyPagesException
                _buildWaterQualityHistory(
                  history: history.take(3).toList(),
                  totalCount: history.length,
                ),
                pw.SizedBox(height: 15),
              ],
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 20),
            ]);
          });

          // Leak Detection Section (if leak data is provided)
          if (leakData.isNotEmpty) {
            content.addAll([
              _buildSectionHeader('LEAK DETECTION REPORT', PdfColors.red700),
              pw.SizedBox(height: 20),
            ]);

            // Add leak data for each device (limit to most recent 50)
            leakData.forEach((deviceId, leaks) {
              if (leaks.isNotEmpty) {
                final deviceName = deviceLabels[deviceId] ?? deviceId;
                // Limit to most recent 10 leaks to prevent TooManyPagesException
                final limitedLeaks = leaks.take(10).toList();
                content.addAll([
                  _buildLeakDetectionSection(
                    deviceName: deviceName,
                    leaks: limitedLeaks,
                    totalCount: leaks.length,
                  ),
                  pw.SizedBox(height: 15),
                ]);
              }
            });
          }

          // Manual Activities Section (if manual activities data is provided)
          if (manualActivitiesData.isNotEmpty) {
            content.addAll([
              _buildSectionHeader(
                'MANUAL ACTIVITIES REPORT',
                PdfColors.orange700,
              ),
              pw.SizedBox(height: 20),
            ]);

            // Add manual activities data for each device (limit to most recent 50)
            manualActivitiesData.forEach((deviceId, activities) {
              if (activities.isNotEmpty) {
                final deviceName = deviceLabels[deviceId] ?? deviceId;
                // Limit to most recent 30 activities to prevent TooManyPagesException
                final limitedActivities = activities.take(30).toList();
                content.addAll([
                  _buildManualActivitiesSection(
                    deviceName: deviceName,
                    activities: limitedActivities,
                    totalCount: activities.length,
                  ),
                  pw.SizedBox(height: 15),
                ]);
              }
            });
          }

          return content;
        },
      ),
    );

    return await _savePdfFile(
      pdf,
      'water_quality_report_with_leaks_$formattedDate.pdf',
    );
  }

  // Generate and save a water consumption report PDF for all periods
  static Future<String> generateWaterConsumptionReport({
    required Map<String, Map<String, double>> periodsData,
    required Map<String, String> deviceLabels,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);
    final formattedTime = DateFormat('HH:mm:ss').format(now);

    // Create PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        maxPages: 20, // Limit pages to prevent TooManyPagesException
        header:
            (context) => _buildHeader(
              title: 'Water Consumption Report - All Periods',
              date: formattedDate,
              time: formattedTime,
            ),
        footer: (context) => _buildFooter(),
        build: (pw.Context context) {
          final List<pw.Widget> content = [
            _buildSectionHeader('WATER CONSUMPTION REPORT', PdfColors.green700),
            pw.SizedBox(height: 20),
          ];

          // Add each period's data
          final periods = {
            'daily': 'Daily Report',
            'weekly': 'Weekly Report',
            'monthly': 'Monthly Report',
            'yearly': 'Yearly Report',
          };

          periodsData.forEach((periodKey, consumption) {
            if (consumption.isNotEmpty) {
              // Calculate total consumption for this period
              final totalConsumption = consumption.values.fold(
                0.0,
                (sum, value) => sum + value,
              );

              // Convert to liters
              final totalLiters = (totalConsumption * 5).toStringAsFixed(
                2,
              ); // 1 flowrate unit = 5 liters

              // Get period display name
              final periodName = periods[periodKey] ?? periodKey;

              content.addAll([
                _buildPeriodHeader(periodName),
                pw.SizedBox(height: 15),
                _buildTotalConsumption(totalLiters: totalLiters),
                pw.SizedBox(height: 15),
                _buildDeviceConsumptionTable(
                  consumption: consumption,
                  deviceLabels: deviceLabels,
                ),
                pw.Divider(color: PdfColors.grey300, thickness: 1),
                pw.SizedBox(height: 20),
              ]);
            }
          });

          return content;
        },
      ),
    );

    return await _savePdfFile(
      pdf,
      'water_consumption_report_all_periods_$formattedDate.pdf',
    );
  }

  // Save PDF file to device storage
  static Future<String> _savePdfFile(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Open the PDF file
  static Future<void> openPdfFile(String filePath) async {
    await OpenFile.open(filePath);
  }

  // Build header section
  static pw.Widget _buildHeader({
    required String title,
    required String date,
    required String time,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 2),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  'SmartPipe',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue700,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generated on: $date at $time',
            style: pw.TextStyle(
              fontSize: 12,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // Build section header
  static pw.Widget _buildSectionHeader(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color,
        border: pw.Border.all(color: color, width: 2),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 20,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // Build summary section
  static pw.Widget _buildSummarySection({
    required Map<String, Map<String, dynamic>> waterQualityData,
    required Map<String, Map<String, double>> waterConsumptionData,
    required Map<String, String> deviceLabels,
    required String periodName,
    Map<String, List<Map<String, dynamic>>> leakData = const {},
    Map<String, List<Map<String, dynamic>>> manualActivitiesData = const {},
  }) {
    final totalDevices = waterQualityData.length;
    final totalConsumption = waterConsumptionData.values.fold<double>(
      0.0,
      (sum, periodData) => sum + periodData.values.fold(0.0, (s, v) => s + v),
    );
    final totalLiters = (totalConsumption * 5).toStringAsFixed(2);

    // Calculate leak and manual switch statistics
    int totalLeaks = 0;
    int totalManualSwitches = 0;

    // Count leaks from leak data
    for (final deviceLeaks in leakData.values) {
      totalLeaks += deviceLeaks.length;
    }

    // Count manual switch events from manual activities data
    for (final deviceActivities in manualActivitiesData.values) {
      totalManualSwitches += deviceActivities.length;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'REPORT SUMMARY',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            children: [
              pw.Expanded(child: _buildSummaryItem('Period', periodName)),
              pw.Expanded(
                child: _buildSummaryItem(
                  'Total Devices',
                  totalDevices.toString(),
                ),
              ),
              pw.Expanded(
                child: _buildSummaryItem('Total Consumption', '$totalLiters L'),
              ),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildSummaryItem('Total Leaks', totalLeaks.toString()),
              ),
              pw.Expanded(
                child: _buildSummaryItem(
                  'Manual Switch Events',
                  totalManualSwitches.toString(),
                ),
              ),
              pw.Expanded(
                child: _buildSummaryItem(
                  'Total Events',
                  (totalLeaks + totalManualSwitches).toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build summary item
  static pw.Widget _buildSummaryItem(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
        ],
      ),
    );
  }

  // Build period header
  static pw.Widget _buildPeriodHeader(String periodName) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        periodName,
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.green700,
        ),
      ),
    );
  }

  // Build device information section
  static pw.Widget _buildDeviceInfo({
    required String deviceId,
    required String deviceName,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue300, width: 2),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Device Information',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Text(
                'Device Name:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 10),
              pw.Text(deviceName, style: pw.TextStyle()),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Text(
                'Device ID:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 10),
              pw.Text(deviceId, style: pw.TextStyle()),
            ],
          ),
        ],
      ),
    );
  }

  // Build water quality parameters section
  static pw.Widget _buildWaterQualityParameters({
    required double? ph,
    required String turbidityStatus,
  }) {
    final bool isPhGood = ph != null && ph >= 6.5 && ph <= 8.5;
    final bool isTurbidityGood = turbidityStatus == 'CLEAN';

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Water Quality Parameters',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Text(
                'pH Level:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                ph?.toStringAsFixed(2) ?? 'N/A',
                style: pw.TextStyle(
                  color: isPhGood ? PdfColors.green700 : PdfColors.red700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: isPhGood ? PdfColors.green100 : PdfColors.red100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  isPhGood ? 'Good' : 'Check',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: isPhGood ? PdfColors.green700 : PdfColors.red700,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Text(
                'Turbidity:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                turbidityStatus,
                style: pw.TextStyle(
                  color:
                      isTurbidityGood ? PdfColors.green700 : PdfColors.red700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color:
                      isTurbidityGood ? PdfColors.green100 : PdfColors.red100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  isTurbidityGood ? 'Good' : 'Check',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color:
                        isTurbidityGood ? PdfColors.green700 : PdfColors.red700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build water quality history section
  static pw.Widget _buildWaterQualityHistory({
    required List<Map<String, dynamic>> history,
    int? totalCount,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Water Quality History',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            totalCount != null && totalCount > history.length
                ? 'Recent readings (showing ${history.length} of $totalCount)'
                : 'Recent readings (${history.length} entries)',
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
            children: [
              // Table header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Date & Time',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'pH Level',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Turbidity',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              // Table rows with alternating colors
              ...history.asMap().entries.map((entry) {
                final index = entry.key;
                final data = entry.value;
                final isEven = index % 2 == 0;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isEven ? PdfColors.white : PdfColors.grey50,
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        data['time'] ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        data['ph']?.toString() ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        data['turbidity'] ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  // Build total consumption section
  static pw.Widget _buildTotalConsumption({required String totalLiters}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue300, width: 2),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'Total Water Consumption:',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(width: 15),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue700,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              '$totalLiters Liters',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build device consumption table
  static pw.Widget _buildDeviceConsumptionTable({
    required Map<String, double> consumption,
    required Map<String, String> deviceLabels,
  }) {
    // Sort devices by consumption (highest first)
    final sortedEntries =
        consumption.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Device Consumption Details',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
            children: [
              // Table header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Device',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Flow Units',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Liters',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              // Table rows with alternating colors
              ...sortedEntries.asMap().entries.map((entry) {
                final index = entry.key;
                final deviceEntry = entry.value;
                final isEven = index % 2 == 0;

                final deviceId = deviceEntry.key;
                final deviceName = deviceLabels[deviceId] ?? deviceId;
                final flowUnits = deviceEntry.value;
                final liters = flowUnits * 5; // 1 flowrate unit = 5 liters

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isEven ? PdfColors.white : PdfColors.grey50,
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        deviceName,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        flowUnits.toStringAsFixed(2),
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        liters.toStringAsFixed(2),
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  // Build leak detection section
  static pw.Widget _buildLeakDetectionSection({
    required String deviceName,
    required List<Map<String, dynamic>> leaks,
    int? totalCount,
  }) {
    // Count different types of events
    int leakCount = 0;
    int manualSwitchCount = 0;

    for (final leak in leaks) {
      final reason = leak['reason']?.toString().toLowerCase() ?? '';
      if (reason.contains('manual switch triggered')) {
        manualSwitchCount++;
      } else {
        leakCount++;
      }
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        border: pw.Border.all(color: PdfColors.red300, width: 2),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Leak Detection & Manual Switch Events - $deviceName',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700,
                  ),
                ),
              ),
              if (totalCount != null && totalCount > leaks.length)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'Showing ${leaks.length} of $totalCount',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.blue700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Total Leaks: $leakCount',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red600,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Manual Switch Events: $manualSwitchCount',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange600,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.red300, width: 1),
            children: [
              // Table header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.red200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Date & Time',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Event Type',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Flow Rate',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              // Table rows with alternating colors
              ...leaks.asMap().entries.map((entry) {
                final index = entry.key;
                final leak = entry.value;
                final isEven = index % 2 == 0;

                // Determine event type and color
                final reason = leak['reason']?.toString().toLowerCase() ?? '';
                final isManualSwitch = reason.contains(
                  'manual switch triggered',
                );
                final rowColor =
                    isManualSwitch
                        ? (isEven ? PdfColors.orange50 : PdfColors.orange100)
                        : (isEven ? PdfColors.white : PdfColors.red50);

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowColor),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '${leak['date']} ${leak['time']}',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        leak['reason'] ?? 'Unknown event',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        leak['flow_rate']?.toString() ?? 'Unknown',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  // Build manual activities section
  static pw.Widget _buildManualActivitiesSection({
    required String deviceName,
    required List<Map<String, dynamic>> activities,
    int? totalCount,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange50,
        border: pw.Border.all(color: PdfColors.orange300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Manual Activities - $deviceName',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange700,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange700,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Text(
                  totalCount != null && totalCount > activities.length
                      ? 'Showing ${activities.length} of $totalCount'
                      : '${activities.length} Events',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.orange300),
            columnWidths: {
              0: pw.FixedColumnWidth(120),
              1: pw.FixedColumnWidth(100),
              2: pw.FlexColumnWidth(),
              3: pw.FixedColumnWidth(80),
            },
            children: [
              // Table header
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.orange100),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Date & Time',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Event Type',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Description',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Flow Rate',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              // Table rows with alternating colors
              ...activities.asMap().entries.map((entry) {
                final index = entry.key;
                final activity = entry.value;
                final isEven = index % 2 == 0;
                final rowColor = isEven ? PdfColors.white : PdfColors.orange50;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowColor),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '${activity['date']} ${activity['time']}',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Manual Switch',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        activity['reason'] ?? 'Unknown event',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        activity['flow_rate'] ?? 'Unknown',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  // Build footer section
  static pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 20),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'SmartPipe Water Management System',
            style: pw.TextStyle(
              fontSize: 10,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            'SmartPipe Report',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // Get period display name
  static String _getPeriodDisplayName(ReportPeriod? reportPeriod) {
    switch (reportPeriod) {
      case ReportPeriod.today:
        return 'Today\'s Report';
      case ReportPeriod.weekly:
        return 'Weekly Report';
      case ReportPeriod.monthly:
        return 'Monthly Report';
      case ReportPeriod.summary:
        return 'Summary Report';
      default:
        return 'Comprehensive Report';
    }
  }

  // Get period file name
  static String _getPeriodFileName(ReportPeriod? reportPeriod) {
    switch (reportPeriod) {
      case ReportPeriod.today:
        return 'today_report';
      case ReportPeriod.weekly:
        return 'weekly_report';
      case ReportPeriod.monthly:
        return 'monthly_report';
      case ReportPeriod.summary:
        return 'summary_report';
      default:
        return 'comprehensive_report';
    }
  }
}

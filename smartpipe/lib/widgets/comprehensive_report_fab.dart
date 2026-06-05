import 'package:flutter/material.dart';
import '../services/comprehensive_report_service.dart';
import '../theme/app_theme.dart';

class ComprehensiveReportFab extends StatelessWidget {
  const ComprehensiveReportFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => ComprehensiveReportService.generateAndDownloadComprehensiveReport(context),
      backgroundColor: AppTheme.primaryColor,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.download_rounded),
      label: const Text(
        'Download Report',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      tooltip: 'Download Comprehensive Report (Water Quality + Consumption)',
      elevation: 8,
      heroTag: "comprehensive_report_fab", // Unique hero tag to avoid conflicts
    );
  }
}

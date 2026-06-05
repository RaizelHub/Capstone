import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/water_consumption_service.dart';
import '../../services/device_management_service.dart';

class WaterConsumptionReportScreen extends StatefulWidget {
  const WaterConsumptionReportScreen({super.key});

  @override
  State<WaterConsumptionReportScreen> createState() =>
      _WaterConsumptionReportScreenState();
}

class _WaterConsumptionReportScreenState
    extends State<WaterConsumptionReportScreen> {
  final WaterConsumptionService _consumptionService = WaterConsumptionService();
  final DeviceManagementService _deviceService = DeviceManagementService();
  late DatabaseReference _reportsRef;

  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _selectedPeriod = 'daily'; // daily, weekly, monthly, yearly

  // Period options
  final List<Map<String, dynamic>> _periodOptions = [
    {'value': 'daily', 'label': 'Day', 'icon': Icons.today},
    {'value': 'weekly', 'label': 'Week', 'icon': Icons.view_week},
    {'value': 'monthly', 'label': 'Month', 'icon': Icons.calendar_view_month},
    {'value': 'yearly', 'label': 'Year', 'icon': Icons.calendar_today},
  ];

  // Reset time information
  DateTime _nextResetTime = DateTime.now().add(const Duration(days: 1));
  DateTime? _lastResetTime;
  Timer? _resetCountdownTimer;

  @override
  void initState() {
    super.initState();
    // Initialize device service
    _deviceService.initialize();

    // Initialize reports reference based on selected period
    _updateReportsRef();
    _loadReports();
    _initializeResetTimes();
    _startResetCountdown();

    // Listen for changes in the consumption service
    _consumptionService.addListener(_onConsumptionServiceChanged);
  }

  // Update the reports reference based on the selected period
  void _updateReportsRef() {
    _reportsRef = FirebaseDatabase.instance.ref('reports/$_selectedPeriod');
  }

  @override
  void dispose() {
    _resetCountdownTimer?.cancel();
    _consumptionService.removeListener(_onConsumptionServiceChanged);
    super.dispose();
  }

  // Initialize reset times from the service
  Future<void> _initializeResetTimes() async {
    setState(() {
      _nextResetTime = _consumptionService.getNextResetTime();
    });

    _lastResetTime = await _consumptionService.getLastResetTime();
  }

  // Start a countdown timer to update the UI as we approach midnight
  void _startResetCountdown() {
    _resetCountdownTimer?.cancel();

    // Update every minute
    _resetCountdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          // Just trigger a rebuild to update the countdown display
        });

        // If we've passed midnight, update the next reset time
        final now = DateTime.now();
        if (now.day != _nextResetTime.day) {
          setState(() {
            _nextResetTime = _consumptionService.getNextResetTime();
          });
        }
      }
    });
  }

  // Called when the consumption service notifies of changes
  void _onConsumptionServiceChanged() {
    if (mounted) {
      _loadReports();
      _initializeResetTimes();
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await _reportsRef.get();
      final reports = <Map<String, dynamic>>[];

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        data.forEach((date, reportData) {
          final Map<String, dynamic> report = {
            'date': date.toString(),
            'timestamp': reportData['timestamp'] as int,
            'consumption': <String, double>{},
          };

          // Add period-specific fields if they exist
          if (reportData['start_date'] != null) {
            report['start_date'] = reportData['start_date'].toString();
          }
          if (reportData['end_date'] != null) {
            report['end_date'] = reportData['end_date'].toString();
          }
          if (reportData['month'] != null) {
            report['month'] = reportData['month'];
          }
          if (reportData['year'] != null) {
            report['year'] = reportData['year'];
          }
          if (reportData['report_type'] != null) {
            report['report_type'] = reportData['report_type'].toString();
          }

          final consumption =
              reportData['consumption'] as Map<dynamic, dynamic>;
          consumption.forEach((deviceId, value) {
            report['consumption'][deviceId.toString()] = double.parse(
              value.toString(),
            );
          });

          reports.add(report);
        });

        // Sort reports by date or timestamp (newest first)
        reports.sort((a, b) {
          // For yearly reports, sort by year
          if (_selectedPeriod == 'yearly' &&
              a.containsKey('year') &&
              b.containsKey('year')) {
            return (b['year'] as int).compareTo(a['year'] as int);
          }
          // For monthly reports, sort by year and month
          else if (_selectedPeriod == 'monthly' &&
              a.containsKey('year') &&
              b.containsKey('year') &&
              a.containsKey('month') &&
              b.containsKey('month')) {
            final yearComparison = (b['year'] as int).compareTo(
              a['year'] as int,
            );
            if (yearComparison != 0) return yearComparison;
            return (b['month'] as int).compareTo(a['month'] as int);
          }
          // Default to date string comparison
          return b['date'].toString().compareTo(a['date'].toString());
        });

        setState(() {
          _reports = reports;
          if (reports.isNotEmpty) {
            _selectedDate = reports.first['date'];
          }
        });
      }

      if (_reports.isEmpty) {
        final liveReport = _buildLiveReport();
        if (liveReport != null) {
          setState(() {
            _reports = [liveReport];
            _selectedDate = liveReport['date'];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading reports: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic>? _buildLiveReport() {
    final now = DateTime.now();
    final consumptionMap = _consumptionService.getCurrentConsumption(
      period: _selectedPeriod,
    );

    if (consumptionMap.isEmpty) {
      return null;
    }

    String dateKey;
    Map<String, dynamic> extraFields = {};

    switch (_selectedPeriod) {
      case 'weekly':
        final weekNumber = _getWeekOfYear(now);
        final weekId = '${now.year}-${now.month}-$weekNumber';
        final weekStart = DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(Duration(days: now.weekday - 1)));
        final weekEnd = DateFormat(
          'yyyy-MM-dd',
        ).format(now.add(Duration(days: DateTime.daysPerWeek - now.weekday)));
        dateKey = weekId;
        extraFields = {
          'start_date': weekStart,
          'end_date': weekEnd,
          'report_type': 'weekly_live',
        };
        break;
      case 'monthly':
        final monthId = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        dateKey = monthId;
        extraFields = {
          'month': now.month,
          'year': now.year,
          'report_type': 'monthly_live',
        };
        break;
      case 'yearly':
        dateKey = '${now.year}';
        extraFields = {'year': now.year, 'report_type': 'yearly_live'};
        break;
      case 'daily':
      default:
        dateKey = DateFormat('yyyy-MM-dd').format(now);
        extraFields = {'report_type': 'daily_live'};
        break;
    }

    return {
      'date': dateKey,
      'timestamp': now.millisecondsSinceEpoch,
      'consumption': consumptionMap,
      'is_live': true,
      ...extraFields,
    };
  }

  // Change the selected period and reload reports
  Future<void> _changePeriod(String period) async {
    if (period != _selectedPeriod) {
      setState(() {
        _selectedPeriod = period;
        _isLoading = true;
      });

      // Update the reports reference
      _updateReportsRef();

      // Load reports for the new period
      await _loadReports();
    }
  }

  Map<String, double>? _getSelectedReport() {
    try {
      // Find the selected report
      final report = _reports.firstWhere(
        (r) => r['date'] == _selectedDate,
        orElse: () => {'consumption': {}},
      );

      // Get the consumption data
      final dynamic consumptionData = report['consumption'];

      // Create a new Map<String, double> to return
      final Map<String, double> result = {};

      // Handle different types of maps
      if (consumptionData is Map) {
        // Convert each entry to the correct types
        consumptionData.forEach((key, value) {
          final deviceId = key.toString();
          final consumption = double.tryParse(value.toString()) ?? 0.0;
          result[deviceId] = consumption;
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error in _getSelectedReport: $e');
      return {};
    }
  }

  double _getTotalConsumption(Map<String, double>? report) {
    if (report == null) return 0;
    return report.values.fold(0, (sum, value) => sum + value);
  }

  @override
  Widget build(BuildContext context) {
    final selectedReport = _getSelectedReport();
    final totalConsumption = _getTotalConsumption(selectedReport);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Water Consumption Reports',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh Reports',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResetTimeInfo(),
                    const SizedBox(height: 16),
                    _buildPeriodSelector(),
                    const SizedBox(height: 16),
                    _buildDateSelector(),
                    const SizedBox(height: 24),
                    _buildTotalConsumptionCard(totalConsumption),
                    const SizedBox(height: 24),
                    _buildDeviceConsumptionList(selectedReport),
                  ],
                ),
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.water_drop_outlined,
            size: 80,
            color: AppTheme.primaryColor.withAlpha(100),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Reports Available',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Reports are automatically generated daily at 12:00 AM',
            style: TextStyle(color: AppTheme.secondaryTextColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryColor.withAlpha(50)),
            ),
            child: Column(
              children: [
                Icon(Icons.schedule, color: AppTheme.primaryColor, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Automatic Report Generation',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your first report will be available after 12:00 AM tomorrow',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Select ${_selectedPeriod.substring(0, 1).toUpperCase()}${_selectedPeriod.substring(1)} Report',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withAlpha(15),
                  AppTheme.secondaryColor.withAlpha(15),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryColor.withAlpha(50),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDate,
                isExpanded: true,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                items:
                    _reports.map((report) {
                      final date = report['date'] as String;
                      final formattedDate = _formatDateForPeriod(date);
                      final isToday = _isCurrentPeriod(date);

                      return DropdownMenuItem(
                        value: date,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    isToday
                                        ? AppTheme.primaryColor.withAlpha(20)
                                        : Colors.grey.withAlpha(20),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _getPeriodDisplayText(date),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isToday
                                          ? AppTheme.primaryColor
                                          : AppTheme.secondaryTextColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color:
                                          isToday
                                              ? AppTheme.primaryColor
                                              : AppTheme.primaryTextColor,
                                    ),
                                  ),
                                  if (isToday)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withAlpha(
                                          20,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Today',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedDate = value;
                    });
                  }
                },
                dropdownColor: Colors.white,
                elevation: 3,
                itemHeight: 60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build the period selector UI
  Widget _buildPeriodSelector() {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.date_range,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Select Report Period',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children:
                _periodOptions.map((option) {
                  final bool isSelected = option['value'] == _selectedPeriod;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _changePeriod(option['value']),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient:
                              isSelected
                                  ? LinearGradient(
                                    colors: [
                                      AppTheme.primaryColor,
                                      AppTheme.secondaryColor,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                  : null,
                          color: isSelected ? null : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow:
                              isSelected
                                  ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withAlpha(
                                        50,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                  : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              option['icon'],
                              color:
                                  isSelected
                                      ? Colors.white
                                      : AppTheme.secondaryTextColor,
                              size: 20,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              option['label'],
                              style: TextStyle(
                                color:
                                    isSelected
                                        ? Colors.white
                                        : AppTheme.primaryTextColor,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalConsumptionCard(double totalConsumption) {
    // Format date based on period type
    String formattedDate;
    String periodTitle;

    switch (_selectedPeriod) {
      case 'weekly':
        // For weekly reports, try to get start and end dates
        final report = _reports.firstWhere(
          (r) => r['date'] == _selectedDate,
          orElse: () => {},
        );

        if (report.containsKey('start_date') &&
            report.containsKey('end_date')) {
          final startDate = DateFormat(
            'yyyy-MM-dd',
          ).parse(report['start_date']);
          final endDate = DateFormat('yyyy-MM-dd').parse(report['end_date']);
          formattedDate =
              '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}';
        } else {
          formattedDate =
              'Week of ${DateFormat('MMMM d, yyyy').format(DateFormat('yyyy-MM-dd').parse(_selectedDate))}';
        }
        periodTitle = 'Weekly Water Consumption';
        break;

      case 'monthly':
        // For monthly reports
        final report = _reports.firstWhere(
          (r) => r['date'] == _selectedDate,
          orElse: () => {},
        );

        if (report.containsKey('month') && report.containsKey('year')) {
          final month = report['month'] as int;
          final year = report['year'] as int;
          formattedDate = DateFormat('MMMM yyyy').format(DateTime(year, month));
        } else {
          formattedDate = DateFormat(
            'MMMM yyyy',
          ).format(DateFormat('yyyy-MM-dd').parse(_selectedDate));
        }
        periodTitle = 'Monthly Water Consumption';
        break;

      case 'yearly':
        // For yearly reports
        final report = _reports.firstWhere(
          (r) => r['date'] == _selectedDate,
          orElse: () => {},
        );

        if (report.containsKey('year')) {
          final year = report['year'] as int;
          formattedDate = year.toString();
        } else {
          formattedDate = DateFormat(
            'yyyy',
          ).format(DateFormat('yyyy-MM-dd').parse(_selectedDate));
        }
        periodTitle = 'Yearly Water Consumption';
        break;

      case 'daily':
      default:
        formattedDate = DateFormat(
          'EEEE, MMMM d, yyyy',
        ).format(DateFormat('yyyy-MM-dd').parse(_selectedDate));
        periodTitle = 'Daily Water Consumption';
        break;
    }

    // Determine consumption level for visual indicators
    String consumptionLevel = 'Low';
    Color consumptionColor = AppTheme.successColor;
    IconData consumptionIcon = Icons.thumb_up;

    if (totalConsumption > 100) {
      consumptionLevel = 'High';
      consumptionColor = AppTheme.errorColor;
      consumptionIcon = Icons.warning_amber;
    } else if (totalConsumption > 50) {
      consumptionLevel = 'Medium';
      consumptionColor = AppTheme.warningColor;
      consumptionIcon = Icons.info;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, AppTheme.primaryColor.withAlpha(5)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.water_drop,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Consumption value with animation
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: totalConsumption),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Liters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Progress indicator
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value:
                          value / 200, // Assuming 200L is max for visualization
                      minHeight: 10,
                      backgroundColor: Colors.grey.withAlpha(30),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        consumptionColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // Consumption level indicator with detailed description
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: consumptionColor.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: consumptionColor.withAlpha(50),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(consumptionIcon, size: 24, color: consumptionColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$consumptionLevel Consumption',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: consumptionColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getConsumptionMessage(),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Detailed usage description
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dividerColor, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Usage Breakdown',
                            style: AppTheme.labelStyle.copyWith(
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildUsageDescription(totalConsumption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageDescription(double totalConsumption) {
    String description;
    List<String> tips = [];

    if (totalConsumption > 100) {
      description =
          'High water usage detected. This consumption level is above the recommended daily average of 50-100 liters per device.';
      tips = [
        '• Check for potential leaks in the system',
        '• Review valve operation schedules',
        '• Consider implementing water conservation measures',
        '• Monitor usage patterns for optimization opportunities',
      ];
    } else if (totalConsumption > 50) {
      description =
          'Moderate water usage within normal operating range. This level indicates regular system operation.';
      tips = [
        '• Usage is within acceptable limits',
        '• Continue monitoring for any unusual patterns',
        '• Consider scheduling regular maintenance checks',
        '• Review efficiency opportunities',
      ];
    } else if (totalConsumption > 0) {
      description =
          'Low water usage detected. This may indicate minimal system activity or efficient water management.';
      tips = [
        '• Verify all devices are functioning properly',
        '• Check if reduced usage is intentional',
        '• Ensure system is meeting operational requirements',
        '• Consider if additional capacity is needed',
      ];
    } else {
      description =
          'No water usage recorded for this period. This may indicate system downtime or data collection issues.';
      tips = [
        '• Verify system connectivity and operation',
        '• Check data collection sensors',
        '• Ensure devices are powered and functional',
        '• Review system maintenance logs',
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: AppTheme.bodyMediumStyle.copyWith(height: 1.5),
        ),
        const SizedBox(height: 12),
        Text(
          'Recommendations:',
          style: AppTheme.labelStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...tips.map(
          (tip) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              tip,
              style: AppTheme.captionStyle.copyWith(height: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceConsumptionList(Map<String, double>? report) {
    final formattedDate = DateFormat(
      'MMM d, yyyy',
    ).format(DateFormat('yyyy-MM-dd').parse(_selectedDate));

    if (report == null || report.isEmpty) {
      return Container(
        decoration: AppTheme.cardDecoration,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.water_drop_outlined,
              size: 48,
              color: Colors.grey.withAlpha(100),
            ),
            const SizedBox(height: 16),
            const Text(
              'No consumption data available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No water usage recorded for $formattedDate',
              style: TextStyle(fontSize: 14, color: Colors.grey.withAlpha(180)),
            ),
          ],
        ),
      );
    }

    // Sort devices by consumption (highest first)
    final sortedEntries =
        report.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Calculate total for percentage
    final totalConsumption = report.values.fold(
      0.0,
      (sum, value) => sum + value,
    );

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.device_hub,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Consumption by Device',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 10,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Devices list with animations
          ...sortedEntries.asMap().entries.map((mapEntry) {
            final index = mapEntry.key;
            final entry = mapEntry.value;
            final deviceId = entry.key;
            final consumption = entry.value;
            final deviceName =
                _consumptionService.deviceLabels[deviceId] ?? deviceId;
            final deviceColor = _getDeviceColor(deviceId);

            // Calculate percentage of total
            final percentage =
                totalConsumption > 0
                    ? (consumption / totalConsumption * 100)
                    : 0.0;

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 500 + (index * 100)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 20),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildDeviceConsumptionItem(
                        deviceId,
                        deviceName,
                        consumption,
                        deviceColor,
                        percentage,
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          const SizedBox(height: 20),

          // Summary and insights section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Consumption Insights',
                      style: AppTheme.labelStyle.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildConsumptionInsights(report, totalConsumption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDeviceUsageDescription(double consumption) {
    if (consumption > 50) {
      return 'High usage - Monitor for efficiency';
    } else if (consumption > 20) {
      return 'Normal usage - Operating efficiently';
    } else if (consumption > 0) {
      return 'Low usage - Check operation status';
    } else {
      return 'No usage - Verify device status';
    }
  }

  Widget _buildConsumptionInsights(
    Map<String, double> report,
    double totalConsumption,
  ) {
    final deviceCount = report.length;
    final averageConsumption =
        deviceCount > 0 ? totalConsumption / deviceCount : 0;
    final highUsageDevices =
        report.values.where((consumption) => consumption > 50).length;
    final lowUsageDevices =
        report.values.where((consumption) => consumption < 10).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Statistics row
        Row(
          children: [
            Expanded(
              child: _buildInsightItem(
                'Total Devices',
                deviceCount.toString(),
                Icons.devices,
                AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInsightItem(
                'Average Usage',
                '${averageConsumption.toStringAsFixed(1)}L',
                Icons.analytics,
                AppTheme.secondaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInsightItem(
                'High Usage',
                highUsageDevices.toString(),
                Icons.trending_up,
                AppTheme.warningColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInsightItem(
                'Low Usage',
                lowUsageDevices.toString(),
                Icons.trending_down,
                AppTheme.successColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Insights text
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.dividerColor.withAlpha(100),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analysis Summary',
                style: AppTheme.labelStyle.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getConsumptionAnalysis(
                  totalConsumption,
                  deviceCount,
                  highUsageDevices,
                  lowUsageDevices,
                ),
                style: AppTheme.captionStyle.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsightItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.captionStyle.copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getConsumptionAnalysis(
    double total,
    int deviceCount,
    int highUsage,
    int lowUsage,
  ) {
    if (deviceCount == 0) {
      return 'No devices reported consumption data for this period. Check device connectivity and operation status.';
    }

    String analysis = 'System is operating with $deviceCount active devices. ';

    if (highUsage > 0) {
      analysis +=
          '$highUsage device${highUsage > 1 ? 's show' : ' shows'} high usage patterns that may require attention. ';
    }

    if (lowUsage > 0) {
      analysis +=
          '$lowUsage device${lowUsage > 1 ? 's have' : ' has'} minimal usage, which could indicate efficient operation or potential issues. ';
    }

    final averagePerDevice = total / deviceCount;
    if (averagePerDevice > 50) {
      analysis +=
          'Overall consumption is above optimal levels - consider efficiency improvements.';
    } else if (averagePerDevice > 20) {
      analysis += 'Overall consumption is within normal operating parameters.';
    } else {
      analysis +=
          'Overall consumption is low - verify system is meeting operational requirements.';
    }

    return analysis;
  }

  Widget _buildDeviceConsumptionItem(
    String deviceId,
    String deviceName,
    double consumption,
    Color deviceColor,
    double percentage,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [deviceColor.withAlpha(10), Colors.white],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: deviceColor.withAlpha(50), width: 1),
        boxShadow: [
          BoxShadow(
            color: deviceColor.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Device icon with gradient
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [deviceColor, deviceColor.withAlpha(200)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: deviceColor.withAlpha(40),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.water_drop,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),

              // Device name and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.water_drop_outlined,
                          size: 12,
                          color: AppTheme.secondaryTextColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _getDeviceUsageDescription(consumption),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.secondaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Consumption value
              SizedBox(
                width: 85, // Fixed width to prevent overflow
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          consumption.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: deviceColor,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            'L',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: deviceColor.withAlpha(180),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: deviceColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: deviceColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  consumption / 100, // Assuming 100L is max for visualization
              minHeight: 6,
              backgroundColor: Colors.grey.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(deviceColor),
            ),
          ),
        ],
      ),
    );
  }

  // Build the reset time information card with improved UI
  Widget _buildResetTimeInfo() {
    // Calculate time until next reset
    final now = DateTime.now();
    final timeUntilReset = _nextResetTime.difference(now);

    // Format the time remaining
    final hours = timeUntilReset.inHours;
    final minutes = timeUntilReset.inMinutes % 60;

    // Format the last reset time if available
    String lastResetText = 'Not available';
    if (_lastResetTime != null) {
      lastResetText = DateFormat(
        'MMM d, yyyy - h:mm a',
      ).format(_lastResetTime!);
    }

    // Calculate progress for the circular indicator (24 hours in a day)
    final double progressValue = 1.0 - (timeUntilReset.inMinutes / (24 * 60));

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.7),
                      AppTheme.secondaryColor.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.update, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Text(
                  'Automatic Reset Schedule',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circular progress indicator for countdown
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Progress indicator
                    CircularProgressIndicator(
                      value: progressValue,
                      strokeWidth: 8,
                      backgroundColor: Colors.white,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        hours < 1
                            ? AppTheme.warningColor
                            : AppTheme.primaryColor,
                      ),
                    ),
                    // Time text
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${hours}h',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                hours < 1
                                    ? AppTheme.warningColor
                                    : AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          '${minutes}m',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                hours < 1
                                    ? AppTheme.warningColor
                                    : AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next Reset',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Today at 12:00 AM',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            hours < 1
                                ? AppTheme.warningColor.withValues(alpha: 0.1)
                                : AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              hours < 1
                                  ? AppTheme.warningColor.withValues(alpha: 0.3)
                                  : AppTheme.successColor.withValues(
                                    alpha: 0.3,
                                  ),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        hours < 1 ? 'Reset soon' : 'Scheduled',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              hours < 1
                                  ? AppTheme.warningColor
                                  : AppTheme.successColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.infoColor.withValues(alpha: 0.05),
                  AppTheme.primaryColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.infoColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, size: 18, color: AppTheme.infoColor),
                    const SizedBox(width: 8),
                    const Text(
                      'Last Reset',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  lastResetText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.infoColor,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Water consumption data is automatically reset every day at 12:00 AM. Reports are automatically generated and saved before each reset.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Get the appropriate consumption message based on the selected period
  String _getConsumptionMessage() {
    switch (_selectedPeriod) {
      case 'weekly':
        return 'This report shows water consumption for the selected week.';
      case 'monthly':
        return 'This report shows water consumption for the selected month.';
      case 'yearly':
        return 'This report shows water consumption for the entire year.';
      case 'daily':
      default:
        return 'This report shows water consumption for this specific day only.';
    }
  }

  Color _getDeviceColor(String deviceId) {
    switch (deviceId) {
      case 'device_01':
        return AppTheme.deviceColors['device_01']!;
      case 'sp25001':
        return AppTheme.deviceColors['sp25001'] ??
            AppTheme.deviceColors['device_02']!;
      case 'device_03':
        return AppTheme.deviceColors['device_03']!;
      default:
        return AppTheme.primaryColor;
    }
  }

  // Helper method to format date based on selected period
  String _formatDateForPeriod(String date) {
    try {
      switch (_selectedPeriod) {
        case 'day':
          final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
          return DateFormat('EEEE, MMMM d, yyyy').format(parsedDate);
        case 'week':
          // For weekly reports, date might be in format 'YYYY-WW' or 'YYYY-MM-DD'
          if (date.contains('-W')) {
            // Week format: 2024-W01
            final parts = date.split('-W');
            final year = int.parse(parts[0]);
            final week = int.parse(parts[1]);
            return 'Week $week, $year';
          } else {
            // Fallback to daily format
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return 'Week of ${DateFormat('MMM d, yyyy').format(parsedDate)}';
          }
        case 'month':
          // For monthly reports, date might be in format 'YYYY-MM' or 'YYYY-MM-DD'
          if (date.length == 7) {
            // Month format: 2024-01
            final parsedDate = DateFormat('yyyy-MM').parse(date);
            return DateFormat('MMMM yyyy').format(parsedDate);
          } else {
            // Fallback to daily format
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return DateFormat('MMMM yyyy').format(parsedDate);
          }
        case 'year':
          // For yearly reports, date might be in format 'YYYY' or 'YYYY-MM-DD'
          if (date.length == 4) {
            // Year format: 2024
            return 'Year $date';
          } else {
            // Fallback to daily format
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return DateFormat('yyyy').format(parsedDate);
          }
        default:
          final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
          return DateFormat('EEEE, MMMM d, yyyy').format(parsedDate);
      }
    } catch (e) {
      // If parsing fails, return the original date
      return date;
    }
  }

  // Helper method to check if date represents current period
  bool _isCurrentPeriod(String date) {
    try {
      final now = DateTime.now();

      switch (_selectedPeriod) {
        case 'day':
          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          return date == todayStr;
        case 'week':
          if (date.contains('-W')) {
            // Week format: 2024-W01
            final parts = date.split('-W');
            final year = int.parse(parts[0]);
            final week = int.parse(parts[1]);
            final currentWeek = _getWeekOfYear(now);
            return year == now.year && week == currentWeek;
          } else {
            // Check if date is in current week
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            final currentWeekStart = now.subtract(
              Duration(days: now.weekday - 1),
            );
            final currentWeekEnd = currentWeekStart.add(
              const Duration(days: 6),
            );
            return parsedDate.isAfter(
                  currentWeekStart.subtract(const Duration(days: 1)),
                ) &&
                parsedDate.isBefore(
                  currentWeekEnd.add(const Duration(days: 1)),
                );
          }
        case 'month':
          if (date.length == 7) {
            // Month format: 2024-01
            final currentMonthStr = DateFormat('yyyy-MM').format(now);
            return date == currentMonthStr;
          } else {
            // Check if date is in current month
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return parsedDate.year == now.year && parsedDate.month == now.month;
          }
        case 'year':
          if (date.length == 4) {
            // Year format: 2024
            return date == now.year.toString();
          } else {
            // Check if date is in current year
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return parsedDate.year == now.year;
          }
        default:
          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          return date == todayStr;
      }
    } catch (e) {
      return false;
    }
  }

  // Helper method to get week of year
  int _getWeekOfYear(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday - 1) / 7).ceil();
  }

  // Helper method to get display text for period icon
  String _getPeriodDisplayText(String date) {
    try {
      switch (_selectedPeriod) {
        case 'day':
          final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
          return parsedDate.day.toString();
        case 'week':
          if (date.contains('-W')) {
            final parts = date.split('-W');
            return 'W${parts[1]}';
          } else {
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            final week = _getWeekOfYear(parsedDate);
            return 'W$week';
          }
        case 'month':
          if (date.length == 7) {
            final parsedDate = DateFormat('yyyy-MM').parse(date);
            return DateFormat('MMM').format(parsedDate);
          } else {
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return DateFormat('MMM').format(parsedDate);
          }
        case 'year':
          if (date.length == 4) {
            return date;
          } else {
            final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
            return parsedDate.year.toString();
          }
        default:
          final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
          return parsedDate.day.toString();
      }
    } catch (e) {
      return '?';
    }
  }
}

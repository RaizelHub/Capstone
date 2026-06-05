import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_theme.dart';
import '../../services/device_management_service.dart';

class DashboardScreen extends StatefulWidget {
  final String deviceId;
  const DashboardScreen({super.key, this.deviceId = 'sp25001'});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Device management
  final DeviceManagementService _deviceService = DeviceManagementService();
  List<String> _deviceIds = [];
  Map<String, String> _deviceLabels = {};

  late final DatabaseReference _valveRef;
  late final DatabaseReference _qualityRef;

  String flowRate = 'Loading...';
  String waterQuality = 'Loading...';
  String valveStatus01 = 'Loading...';
  String valveStatus02 = 'Loading...';
  String valveStatus03 = 'Loading...';
  String currentTime = '';

  final Map<String, List<FlSpot>> _flowData = {};
  final Map<String, List<FlSpot>> _literData = {};
  final List<String> _xLabels = [];

  // Track the last reset date to handle midnight resets
  String _lastResetDate = '';

  Timer? _timer;
  Timer? _midnightCheckTimer;

  @override
  void initState() {
    super.initState();

    // Initialize device service and setup dashboard
    _initializeDeviceService();
  }

  // Check if we've passed midnight and need to reset
  void _checkForMidnightReset() {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    // If the date has changed since our last reset
    if (today != _lastResetDate) {
      // Reset the dashboard data
      _resetDashboardData();
      // Update the last reset date
      _lastResetDate = today;
    }
  }

  // Reset dashboard data at midnight
  void _resetDashboardData() {
    // Reload chart data
    _loadChartDataForAllDevices();
  }

  // Map to store valve status for all devices
  final Map<String, String> _valveStatusMap = {};

  void _listenToValveStatus(String deviceId) {
    _valveRef.child('$deviceId/relay').onValue.listen((event) {
      if (!mounted) return;
      final status = event.snapshot.value?.toString() ?? 'Unknown';
      setState(() {
        // Store status in the map for all devices
        _valveStatusMap[deviceId] = status;

        // Also update the legacy variables for backward compatibility
        if (deviceId == 'sp25001') {
          valveStatus01 = status;
          valveStatus02 = status;
        }
      });
    });
  }

  void _listenToWaterQuality() {
    _qualityRef.onValue.listen((event) {
      if (!mounted) return;
      final status = event.snapshot.value?.toString();
      if (status != null) {
        setState(() {
          waterQuality = status;
        });
      }
    });
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final formatter = DateFormat('EEEE, MMMM d, yyyy – hh:mm a');
    setState(() {
      currentTime = formatter.format(now);
    });
  }

  Future<void> _loadChartDataForAllDevices() async {
    _flowData.clear();
    _literData.clear();
    _xLabels.clear();

    try {
      // First, collect all data points and timestamps from all devices
      Map<String, List<Map<String, dynamic>>> allDevicesData = {};
      Set<int> allTimestamps = {};

      for (String deviceId in _deviceIds) {
        // Updated path to look for data in readings/deviceId/data
        final ref = FirebaseDatabase.instance.ref('readings/$deviceId/data');
        final snapshot = await ref.get();

        // If the device exists and has data
        if (snapshot.exists && snapshot.value is Map) {
          final dataMap = snapshot.value as Map;

          if (dataMap.isNotEmpty) {
            // Store the data points for this device
            List<Map<String, dynamic>> deviceDataPoints = [];

            for (final entry in dataMap.entries) {
              debugPrint('📊 Processing entry: ${entry.key} = ${entry.value}');
              if (entry.value is Map) {
                final dataPoint = Map<String, dynamic>.from(entry.value as Map);
                debugPrint('📊 Data point: $dataPoint');

                // Ensure each data point has a timestamp, falling back to key if needed
                int? timestampSeconds = _extractTimestampSeconds(
                  dataPoint['timestamp'],
                  entry.key.toString(),
                );

                if (timestampSeconds != null) {
                  dataPoint['timestamp'] = timestampSeconds;
                  deviceDataPoints.add(dataPoint);
                  allTimestamps.add(timestampSeconds);
                } else {
                  debugPrint(
                    '⚠️ Unable to determine timestamp for: $dataPoint',
                  );
                }
              } else {
                debugPrint('❌ Entry is not a Map: ${entry.value}');
              }
            }

            allDevicesData[deviceId] = deviceDataPoints;
          } else {
            debugPrint('⚠️ No data points found for $deviceId');
            allDevicesData[deviceId] = [];
          }
        } else {
          debugPrint('❌ No data found for $deviceId or invalid format');
          debugPrint('❌ Snapshot value: ${snapshot.value}');
          debugPrint('❌ Snapshot value type: ${snapshot.value.runtimeType}');
          allDevicesData[deviceId] = [];
        }
      }

      // Sort timestamps and take the most recent ones (up to 10)
      List<int> sortedTimestamps = allTimestamps.toList()..sort();
      if (sortedTimestamps.length > 10) {
        sortedTimestamps = sortedTimestamps.sublist(
          sortedTimestamps.length - 10,
        );
      }

      // Create x-axis labels from real timestamps
      if (sortedTimestamps.isNotEmpty) {
        for (final timestamp in sortedTimestamps) {
          try {
            final pointTime = DateTime.fromMillisecondsSinceEpoch(
              timestamp * 1000,
            );
            _xLabels.add(DateFormat.Hm().format(pointTime));
          } catch (e) {
            debugPrint(
              'Error converting timestamp to date: $timestamp, error: $e',
            );
            // Add a placeholder label if conversion fails
            _xLabels.add('--:--');
          }
        }
        debugPrint(
          'Created ${_xLabels.length} time labels from real timestamps',
        );
      } else {
        // If no timestamps available, use current time as reference
        final now = DateTime.now();
        for (int i = 0; i < 10; i++) {
          final pointTime = now.subtract(Duration(minutes: (9 - i) * 10));
          _xLabels.add(DateFormat.Hm().format(pointTime));
        }
        debugPrint('Created default time labels');
      }

      // Now process the data for each device using the common set of timestamps
      for (String deviceId in _deviceIds) {
        List<FlSpot> flowSpots = [];
        List<FlSpot> literSpots = [];
        double totalLiters = 0;

        final deviceDataPoints = allDevicesData[deviceId] ?? [];

        if (deviceDataPoints.isNotEmpty && sortedTimestamps.isNotEmpty) {
          // Create a map of timestamp -> data point for easier lookup
          Map<int, Map<String, dynamic>> timestampToDataPoint = {};
          for (final dataPoint in deviceDataPoints) {
            if (dataPoint['timestamp'] != null) {
              // Safely get the timestamp as an integer
              final timestamp = dataPoint['timestamp'];
              int timestampInt;

              if (timestamp is int) {
                timestampInt = timestamp;
              } else if (timestamp is double) {
                timestampInt = timestamp.toInt();
              } else {
                // Try parsing as a number if it's a string
                try {
                  timestampInt = int.parse(timestamp.toString());
                } catch (e) {
                  debugPrint(
                    'Invalid timestamp format in data point: $timestamp',
                  );
                  continue; // Skip this data point
                }
              }

              timestampToDataPoint[timestampInt] = dataPoint;
            }
          }

          // Process each timestamp in order
          for (int i = 0; i < sortedTimestamps.length; i++) {
            final timestamp = sortedTimestamps[i];

            // Check if we have data for this timestamp
            final dataPoint = timestampToDataPoint[timestamp];
            if (dataPoint != null) {

              // Get flow value (supports both flow and flowRate fields)
              final flow =
                  double.tryParse(
                    (dataPoint['flow'] ?? dataPoint['flowRate'] ?? 0)
                        .toString(),
                  ) ??
                  0.0;

              // Add to total liters (convert flow to liters)
              final liters = flow * 5.0; // 1 flow unit = 5 liters
              totalLiters += liters;

              // Add data points using the index of the timestamp as x-coordinate
              flowSpots.add(FlSpot(i.toDouble(), flow));
              literSpots.add(FlSpot(i.toDouble(), totalLiters));
            } else {
              // If no data for this timestamp, use a default value or the previous value
              final flow = flowSpots.isNotEmpty ? flowSpots.last.y : 0.0;
              final literValue =
                  literSpots.isNotEmpty ? literSpots.last.y : totalLiters;

              flowSpots.add(FlSpot(i.toDouble(), flow));
              literSpots.add(FlSpot(i.toDouble(), literValue));
            }
          }

          debugPrint(
            'Created ${flowSpots.length} data points for $deviceId using real timestamps',
          );
        }

        // Store the data for this device (may be empty if no readings)
        if (flowSpots.isNotEmpty || literSpots.isNotEmpty) {
          _flowData[deviceId] = flowSpots;
          _literData[deviceId] = literSpots;
        } else {
          _flowData[deviceId] = [];
          _literData[deviceId] = [];
        }
      }

      // Make sure we have enough labels for all data points
      while (_xLabels.length < 10) {
        _xLabels.add('--:--');
      }

      // Ensure all devices have the same number of data points for consistent charting
      int maxPoints = _xLabels.length;

      // Pad all devices to have the same number of data points
      for (String deviceId in _deviceIds) {
        final flowSpots = _flowData[deviceId];
        final literSpots = _literData[deviceId];
        if (flowSpots == null || flowSpots.isEmpty) {
          _flowData[deviceId] = [];
          _literData[deviceId] = [];
        } else if (flowSpots.length < maxPoints) {
          // Pad existing data to match the maximum length
          final List<FlSpot> currentFlowSpots = List.from(flowSpots);
          final List<FlSpot> currentLiterSpots = List.from(
            literSpots ?? [],
          );

          // Get the last values to use for padding
          final lastFlowValue =
              currentFlowSpots.isNotEmpty ? currentFlowSpots.last.y : 0.0;
          final lastLiterValue =
              currentLiterSpots.isNotEmpty ? currentLiterSpots.last.y : 0.0;

          // Add padding points
          for (int i = currentFlowSpots.length; i < maxPoints; i++) {
            currentFlowSpots.add(FlSpot(i.toDouble(), lastFlowValue));
            currentLiterSpots.add(FlSpot(i.toDouble(), lastLiterValue));
          }

          _flowData[deviceId] = currentFlowSpots;
          _literData[deviceId] = currentLiterSpots;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading chart data: $e');
      // Generate mock data as fallback
      _generateMockChartData();
    }
  }

  void _generateMockChartData() {
    _flowData.clear();
    _literData.clear();
    _xLabels.clear();

    // Skip generating placeholder data; leave datasets empty to show "No data available"
    if (mounted) {
      setState(() {});
    }
  }

  int? _extractTimestampSeconds(dynamic rawTimestamp, String key) {
    if (rawTimestamp != null) {
      if (rawTimestamp is int) {
        return rawTimestamp;
      } else if (rawTimestamp is double) {
        return rawTimestamp.toInt();
      } else {
        final parsed = int.tryParse(rawTimestamp.toString());
        if (parsed != null) {
          return parsed;
        }
      }
    }

    final numericKey = int.tryParse(key);
    if (numericKey != null) {
      return numericKey;
    }

    try {
      final dateTime = DateTime.parse(key).toUtc();
      return (dateTime.millisecondsSinceEpoch / 1000).round();
    } catch (_) {
      return null;
    }
  }

  LineChartData _buildLineChart(
    Map<String, List<FlSpot>> dataMap,
    Map<String, Color> colorMap,
    Map<String, String> labelMap,
  ) {
    // Find the maximum Y value for better scaling
    double maxY = 0;
    for (final spots in dataMap.values) {
      for (final spot in spots) {
        if (spot.y > maxY) {
          maxY = spot.y;
        }
      }
    }

    // Round up to the next multiple of 5 for a cleaner scale
    maxY = (maxY / 5).ceil() * 5.0;
    if (maxY < 5) maxY = 5; // Minimum scale

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: maxY / 5, // 5 horizontal grid lines
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.grey.withAlpha(30), strokeWidth: 1);
        },
        getDrawingVerticalLine: (value) {
          return FlLine(color: Colors.grey.withAlpha(30), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              int index = value.toInt();
              // Only show every other label if we have more than 5 to avoid crowding
              if (_xLabels.length > 5 &&
                  index % 2 != 0 &&
                  index != _xLabels.length - 1) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  index < _xLabels.length ? _xLabels[index] : '',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
            interval: 1,
            reservedSize: 30,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              // Only show whole numbers
              if (value == value.roundToDouble()) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withAlpha(50), width: 1),
          left: BorderSide(color: Colors.grey.withAlpha(50), width: 1),
          right: BorderSide(color: Colors.transparent),
          top: BorderSide(color: Colors.transparent),
        ),
      ),
      minY: 0,
      maxY: maxY,
      lineBarsData:
          dataMap.entries.map((entry) {
            return LineChartBarData(
              spots: entry.value,
              isCurved: true,
              curveSmoothness: 0.3,
              color: colorMap[entry.key],
              barWidth:
                  2.5, // Slightly thinner lines for better visibility when multiple lines
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show:
                    false, // Don't show area below to avoid overlapping colors
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter:
                    (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 3,
                      color: colorMap[entry.key] ?? AppTheme.primaryColor,
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    ),
              ),
            );
          }).toList(),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.white,
          tooltipRoundedRadius: 8,
          tooltipBorder: BorderSide(color: Colors.grey.withAlpha(50), width: 1),
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final deviceId = dataMap.entries.elementAt(barSpot.barIndex).key;
              final deviceLabel = labelMap[deviceId] ?? deviceId;

              return LineTooltipItem(
                '$deviceLabel: ${barSpot.y.toStringAsFixed(1)}',
                TextStyle(
                  color: colorMap[deviceId] ?? AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Cancel all timers to prevent memory leaks
    _timer?.cancel();
    _midnightCheckTimer?.cancel();
    _deviceService.removeListener(_onDevicesChanged);
    super.dispose();
  }

  void _onDevicesChanged() {
    if (!mounted) return;
    setState(() {
      _deviceIds = _deviceService.deviceIds;
      _deviceLabels = _deviceService.deviceLabels;

      // Re-initialize listeners for all devices
      for (final deviceId in _deviceIds) {
        _listenToValveStatus(deviceId);
      }

      // Reload chart data
      _loadChartDataForAllDevices();
    });
  }

  Future<void> _initializeDeviceService() async {
    // Initialize device service
    await _deviceService.initialize();

    // Update device information
    if (mounted) {
      setState(() {
        _deviceIds = _deviceService.deviceIds;
        _deviceLabels = _deviceService.deviceLabels;

        // If no devices available, use default
        if (_deviceIds.isEmpty) {
          _deviceIds = ['sp25001'];
        }
      });
    }

    // Initialize Firebase references before attaching listeners that depend on them
    _valveRef = FirebaseDatabase.instance.ref('control');
    _qualityRef = FirebaseDatabase.instance.ref(
      'quality/${widget.deviceId}/status',
    );

    // Listen for device changes (after references are ready)
    _deviceService.addListener(_onDevicesChanged);

    // Initialize last reset date to today
    _lastResetDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Set up listeners for all devices
    for (final deviceId in _deviceIds) {
      _listenToValveStatus(deviceId);
    }

    _listenToWaterQuality();
    _updateTime();

    _loadChartDataForAllDevices();

    // Set up periodic updates
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadChartDataForAllDevices();
      }
    });

    // Set up midnight check for daily reset
    _midnightCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _checkForMidnightReset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Create dynamic color map for all devices
    final Map<String, Color> colorMap = {};
    final Map<String, String> labelMap = {};

    // Populate maps for all devices
    for (int i = 0; i < _deviceIds.length; i++) {
      final deviceId = _deviceIds[i];
      // Use the getDeviceColor method to ensure we have a color for each device
      colorMap[deviceId] = AppTheme.getDeviceColor(deviceId);

      // Get device label from service or use a friendly default
      final deviceName = _deviceLabels[deviceId] ?? 'Device ${i + 1}';
      // Create a short label (first 3 characters or first word)
      final shortLabel =
          deviceName.contains(' ')
              ? deviceName.split(' ')[0]
              : (deviceName.length > 3
                  ? deviceName.substring(0, 3).toUpperCase()
                  : deviceName);

      labelMap[deviceId] = shortLabel;
    }

    // Ensure we have the default devices for backward compatibility
    if (!colorMap.containsKey('sp25001')) {
      colorMap['sp25001'] = AppTheme.deviceColors['sp25001'] ?? 
          AppTheme.getDeviceColor('sp25001');
      labelMap['sp25001'] = 'COT';
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryColor,
          onRefresh: () async {
            _updateTime();
            _loadChartDataForAllDevices();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildDashboardCards(),
                const SizedBox(height: 32),
                _buildChartSection('Flow Rate', _flowData, colorMap, labelMap),
                const SizedBox(height: 32),
                _buildChartSection(
                  'Total Liters',
                  _literData,
                  colorMap,
                  labelMap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection(
    String title,
    Map<String, List<FlSpot>> data,
    Map<String, Color> colorMap,
    Map<String, String> labelMap,
  ) {
    // Check if we have any data to display
    bool hasData =
        data.isNotEmpty && data.values.any((spots) => spots.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.subheadingStyle),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child:
                hasData
                    ? LineChart(_buildLineChart(data, colorMap, labelMap))
                    : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 48,
                            color: Colors.grey.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No data available',
                            style: TextStyle(
                              color: Colors.grey.withAlpha(180),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              _loadChartDataForAllDevices();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                            ),
                            child: const Text('Refresh Data'),
                          ),
                        ],
                      ),
                    ),
          ),
          const SizedBox(height: 16),
          if (hasData)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children:
                  labelMap.entries
                      .where(
                        (entry) {
                          final spots = data[entry.key];
                          return spots != null && spots.isNotEmpty;
                        },
                      )
                      .map(
                        (entry) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: colorMap[entry.key],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              entry.value,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.primaryColor.withAlpha(15),
          AppTheme.secondaryColor.withAlpha(5),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryColor.withAlpha(10),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Animated icon container
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.secondaryColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withAlpha(50),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.dashboard_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animated welcome text
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(20 * (1 - value), 0),
                          child: const Text(
                            '👋 Welcome Back!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  // Animated subtitle
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(20 * (1 - value), 0),
                          child: Text(
                            'SmartPipe - Dashboard',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Animated time container
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.infoColor.withAlpha(20),
                        AppTheme.primaryColor.withAlpha(20),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.infoColor.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.infoColor.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: AppTheme.infoColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          currentTime,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.primaryTextColor,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: GestureDetector(
                          onTap: _updateTime,
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );

  Widget _buildDashboardCards() {
    // Create a combined valve status map with both the dynamic map and legacy variables
    final Map<String, String> valveStatusMap = Map.from(_valveStatusMap);

    // Add legacy status values for backward compatibility
    if (!valveStatusMap.containsKey('sp25001')) {
      valveStatusMap['sp25001'] = valveStatus01;
    }

    // Calculate grid columns based on screen width for better responsiveness
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2; // Default for smaller screens

    // Adjust columns based on screen width
    if (screenWidth > 600) {
      crossAxisCount = 4; // More columns for tablets/larger screens
    } else if (screenWidth > 400) {
      crossAxisCount = 3; // Medium screens
    } else {
      crossAxisCount = 2; // Smaller screens
    }

    // Ensure we don't have more columns than devices
    if (_deviceIds.isNotEmpty) {
      crossAxisCount = math.min(crossAxisCount, _deviceIds.length);
    }

    // Show a message when there are no devices
    if (_deviceIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: 48,
              color: Colors.grey.withAlpha(100),
            ),
            const SizedBox(height: 16),
            const Text(
              'No devices available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add devices to see them here',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 6, // Reduced spacing
        mainAxisSpacing: 6, // Reduced spacing
        childAspectRatio: 1.0, // Square aspect ratio to prevent overflow
      ),
      // Add padding around the grid
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: _deviceIds.length,
      itemBuilder: (context, index) {
        final deviceId = _deviceIds[index];
        final deviceName =
            _deviceLabels[deviceId] ?? 'Smart Device ${index + 1}';
        final valveStatus = valveStatusMap[deviceId] ?? 'Unknown';
        final color = AppTheme.getDeviceColor(deviceId);

        return _buildCard('$deviceName Valve', valveStatus, Icons.power, color);
      },
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    final bool isOn = value == 'ON';
    // Get screen width to make card responsive
    final screenWidth = MediaQuery.of(context).size.width;
    // Calculate card size based on screen width and number of columns
    final isSmallScreen = screenWidth < 360;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  isOn ? color.withAlpha(10) : Colors.grey.withAlpha(5),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color:
                      isOn ? color.withAlpha(20) : Colors.black.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: isOn ? color.withAlpha(50) : Colors.grey.withAlpha(30),
                width: 1,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal:
                  isSmallScreen ? 2 : 4, // Adjust padding based on screen size
              vertical: isSmallScreen ? 4 : 6,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // Use minimum space needed
              children: [
                // Status indicator with animation
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background circle
                        Container(
                          width: isSmallScreen ? 32 : 36, // Responsive size
                          height: isSmallScreen ? 32 : 36,
                          decoration: BoxDecoration(
                            color:
                                isOn
                                    ? color.withAlpha(15)
                                    : Colors.grey.withAlpha(15),
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Animated circle
                        if (isOn)
                          Container(
                            width:
                                (isSmallScreen ? 32 : 36) *
                                value, // Responsive size
                            height: (isSmallScreen ? 32 : 36) * value,
                            decoration: BoxDecoration(
                              color: color.withAlpha(5),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withAlpha(30),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(6), // Smaller padding
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors:
                                  isOn
                                      ? [color, color.withAlpha(200)]
                                      : [
                                        Colors.grey.withAlpha(150),
                                        Colors.grey.withAlpha(100),
                                      ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow:
                                isOn
                                    ? [
                                      BoxShadow(
                                        color: color.withAlpha(50),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                    : [],
                          ),
                          child: Icon(
                            isOn ? Icons.power : Icons.power_off_rounded,
                            size:
                                isSmallScreen ? 10 : 12, // Responsive icon size
                            color: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4), // Minimal spacing
                // Title with better typography
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 9 : 10, // Responsive font size
                      color: AppTheme.primaryTextColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2), // Minimal spacing
                // Status badge with animation
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (context, animValue, child) {
                    return Transform.scale(
                      scale: animValue,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              isSmallScreen ? 4 : 6, // Responsive padding
                          vertical: 1, // Minimal vertical padding
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                isOn
                                    ? [color, color.withAlpha(200)]
                                    : [
                                      Colors.grey.withAlpha(150),
                                      Colors.grey.withAlpha(100),
                                    ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(
                            8,
                          ), // Smaller radius
                          boxShadow:
                              isOn
                                  ? [
                                    BoxShadow(
                                      color: color.withAlpha(40),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                  : [],
                        ),
                        child: Text(
                          value,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize:
                                isSmallScreen ? 7 : 8, // Responsive font size
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

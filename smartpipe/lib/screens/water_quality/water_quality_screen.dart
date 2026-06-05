import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import '../../theme/app_theme.dart';
import '../../services/device_management_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/comprehensive_report_fab.dart';

class WaterQualityScreen extends StatefulWidget {
  final String initialDeviceId;
  const WaterQualityScreen({super.key, this.initialDeviceId = 'sp25001'});

  @override
  State<WaterQualityScreen> createState() => _WaterQualityScreenState();
}

class _WaterQualityScreenState extends State<WaterQualityScreen> {
  late String _selectedDeviceId;
  final DeviceManagementService _deviceService = DeviceManagementService();
  Map<String, String> deviceLabels = {};

  double? _ph;
  double? _turbidity;
  String _turbidityStatus = '';
  String _status = 'Loading...';
  String _turbidityMessage = '';
  DateTime? _lastTurbidityUpdate;
  Timer? _turbidityTimer;

  List<FlSpot> phHistory = [];
  List<String> historyLabels = [];

  // Stream subscriptions for proper cleanup
  StreamSubscription<DatabaseEvent>? _dataListener;
  StreamSubscription<DatabaseEvent>? _dataUpdateListener;
  StreamSubscription<DatabaseEvent>? _dataValueListener;
  StreamSubscription<DatabaseEvent>? _historyListener;

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.initialDeviceId;

    // Initialize device service and load data
    _initializeAndLoadData();

    // Listen for device changes
    _deviceService.addListener(_onDevicesChanged);

    // Start turbidity update timer
    _startTurbidityTimer();
  }

  @override
  void dispose() {
    _deviceService.removeListener(_onDevicesChanged);
    _turbidityTimer?.cancel();
    _dataListener?.cancel();
    _dataUpdateListener?.cancel();
    _dataValueListener?.cancel();
    _historyListener?.cancel();
    super.dispose();
  }

  void _startTurbidityTimer() {
    // Cancel existing timer if any
    _turbidityTimer?.cancel();

    // Start new timer that runs every 50 seconds
    _turbidityTimer = Timer.periodic(const Duration(seconds: 50), (timer) {
      _checkTurbidityTimeout();
    });
  }

  void _checkTurbidityTimeout() {
    if (!mounted) return;

    final now = DateTime.now();
    final lastUpdate = _lastTurbidityUpdate;

    // If no update in the last 50 seconds or never updated
    if (lastUpdate == null || now.difference(lastUpdate).inSeconds >= 50) {
      setState(() {
        _turbidity = 0.0;
        _turbidityStatus = 'NO WATER';
        _turbidityMessage = 'Water tank is no water or system is not on';

        // Update overall status
        _status =
            (_ph != null && _ph! >= 6.5 && _ph! <= 8.5) ? 'Good' : 'No Water';
      });
    }
  }

  void _onDevicesChanged() {
    setState(() {
      deviceLabels = _deviceService.deviceLabels;

      // Ensure selected device exists in available devices
      if (deviceLabels.isNotEmpty &&
          !deviceLabels.containsKey(_selectedDeviceId)) {
        // If current device is not available, select the first available device
        _selectedDeviceId = deviceLabels.keys.first;
        debugPrint('Selected device changed to: $_selectedDeviceId');
      }
    });
  }

  Future<void> _initializeAndLoadData() async {
    // Initialize device service
    await _deviceService.initialize();

    // Update device labels
    setState(() {
      deviceLabels = _deviceService.deviceLabels;

      // Ensure selected device exists in available devices
      if (deviceLabels.isNotEmpty &&
          !deviceLabels.containsKey(_selectedDeviceId)) {
        // If current device is not available, select the first available device
        _selectedDeviceId = deviceLabels.keys.first;
        debugPrint('Selected device changed to: $_selectedDeviceId');
      }
    });

    // Use a small delay to ensure we don't interfere with other screens' initialization
    // This prevents race conditions when multiple screens try to access Firebase
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      _listenToData();
      _fetchHistory();
    }
  }

  void _listenToData() {
    // Cancel existing listeners if any
    _dataListener?.cancel();
    _dataUpdateListener?.cancel();
    _dataValueListener?.cancel();

    // Updated path to look for data in readings/deviceId/data
    final ref = FirebaseDatabase.instance.ref(
      'readings/$_selectedDeviceId/data',
    );

    debugPrint(
      '🔍 Setting up listener for water quality data at: readings/$_selectedDeviceId/data',
    );

    // First, let's check if the path exists and get the latest data
    ref
        .once()
        .then((snapshot) {
          debugPrint('📊 Initial data check for $_selectedDeviceId:');
          debugPrint('   - Path exists: ${snapshot.snapshot.exists}');
          debugPrint(
            '   - Has children: ${snapshot.snapshot.children.isNotEmpty}',
          );
          if (snapshot.snapshot.exists) {
            debugPrint('   - Data: ${snapshot.snapshot.value}');

            // Check for existing data with pH/turbidity
            final data = snapshot.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              debugPrint('   - All data keys: ${data.keys.toList()}');

              // Find the most recent data point with pH or turbidity
              Map<String, dynamic>? latestWaterQualityData;
              int? latestTimestamp = 0;

              for (final entry in data.entries) {
                final key = entry.key.toString();
                final value = entry.value;

                // Skip direct fields that are not data points (flowRate, lastReading, name, etc.)
                if (key == 'flowRate' ||
                    key == 'lastReading' ||
                    key == 'name' ||
                    key == 'building' ||
                    key == 'target_number' ||
                    key == 'registeredAt') {
                  debugPrint('   - Skipping direct field: $key');
                  continue;
                }

                // Only process map entries (these are the actual data points)
                if (value is Map) {
                  final dataPoint = Map<String, dynamic>.from(value);
                  debugPrint('   - Checking data point: $key');
                  debugPrint(
                    '   - Data point keys: ${dataPoint.keys.toList()}',
                  );

                  if (dataPoint.containsKey('ph') ||
                      dataPoint.containsKey('turbidity')) {
                    debugPrint('   - ✅ Found water quality data in: $key');

                    // Parse timestamp to find the latest
                    final timestamp = dataPoint['timestamp'];
                    int? timestampValue;

                    try {
                      if (timestamp is int) {
                        timestampValue = timestamp;
                      } else if (timestamp is double) {
                        timestampValue = timestamp.toInt();
                      } else if (timestamp is String) {
                        if (timestamp.contains('-')) {
                          final dateTime = DateTime.parse(timestamp);
                          timestampValue =
                              dateTime.millisecondsSinceEpoch ~/ 1000;
                        } else {
                          timestampValue = int.parse(timestamp);
                        }
                      }
                      // If no timestamp in data, try to extract from key (e.g., point_1234567890)
                      if (timestampValue == null && key.startsWith('point_')) {
                        final keyTimestamp = key.replaceFirst('point_', '');
                        timestampValue = int.tryParse(keyTimestamp);
                      }

                      if (timestampValue != null &&
                          timestampValue > latestTimestamp!) {
                        latestTimestamp = timestampValue;
                        latestWaterQualityData = dataPoint;
                        debugPrint(
                          '   - ✅ Updated latest data (timestamp: $timestampValue)',
                        );
                      }
                    } catch (e) {
                      debugPrint(
                        'Error parsing timestamp for water quality: $e',
                      );
                    }
                  } else {
                    debugPrint('   - ⚠️ No ph/turbidity in data point: $key');
                  }
                } else {
                  debugPrint(
                    '   - ⚠️ Entry is not a Map: $key (type: ${value.runtimeType})',
                  );
                }
              }

              if (latestWaterQualityData != null) {
                debugPrint(
                  '📊 Found existing water quality data: $latestWaterQualityData',
                );
                _processWaterQualityData(latestWaterQualityData);
              }
            }
          }
        })
        .catchError((error) {
          debugPrint('❌ Error checking initial data: $error');
        });

    // Primary listener: onValue catches ALL changes (new data and updates)
    // This is the most reliable way to catch real-time updates
    _dataValueListener = ref
        .limitToLast(1)
        .onValue
        .listen(
          (event) {
            if (event.snapshot.exists && mounted) {
              final data = event.snapshot.value;
              debugPrint(
                '📨 Water quality onValue received (all changes): ${event.snapshot.key}',
              );
              debugPrint('📨 Raw onValue data: $data');
              debugPrint('📨 Data type: ${data.runtimeType}');

              Map<String, dynamic>? latestData;

              if (data is Map) {
                final dataMap = Map<String, dynamic>.from(data);
                debugPrint('📨 Data map keys: ${dataMap.keys.toList()}');

                // Filter out direct fields and find data points with ph/turbidity
                Map<String, dynamic>? candidateData;
                int? candidateTimestamp;

                for (final entry in dataMap.entries) {
                  final key = entry.key.toString();
                  final value = entry.value;

                  // Skip direct fields
                  if (key == 'flowRate' ||
                      key == 'lastReading' ||
                      key == 'name' ||
                      key == 'building' ||
                      key == 'target_number' ||
                      key == 'registeredAt') {
                    continue;
                  }

                  // Check if this is a data point with water quality data
                  if (value is Map) {
                    final dataPoint = Map<String, dynamic>.from(value);
                    if (dataPoint.containsKey('ph') ||
                        dataPoint.containsKey('turbidity')) {
                      // Try to get timestamp
                      int? timestampValue;
                      final timestamp = dataPoint['timestamp'];

                      if (timestamp is int) {
                        timestampValue = timestamp;
                      } else if (timestamp is double) {
                        timestampValue = timestamp.toInt();
                      } else if (timestamp is String) {
                        if (timestamp.contains('-')) {
                          final dateTime = DateTime.parse(timestamp);
                          timestampValue =
                              dateTime.millisecondsSinceEpoch ~/ 1000;
                        } else {
                          timestampValue = int.tryParse(timestamp);
                        }
                      }
                      // If no timestamp in data, try to extract from key
                      if (timestampValue == null && key.startsWith('point_')) {
                        final keyTimestamp = key.replaceFirst('point_', '');
                        timestampValue = int.tryParse(keyTimestamp);
                      }

                      if (timestampValue != null &&
                          (candidateTimestamp == null ||
                              timestampValue > candidateTimestamp)) {
                        candidateTimestamp = timestampValue;
                        candidateData = dataPoint;
                        debugPrint(
                          '📨 Found candidate data point: $key (timestamp: $timestampValue)',
                        );
                      } else if (candidateData == null) {
                        // If no timestamp, use first found
                        candidateData = dataPoint;
                        debugPrint(
                          '📨 Found candidate data point (no timestamp): $key',
                        );
                      }
                    }
                  }
                }

                if (candidateData != null) {
                  latestData = candidateData;
                  debugPrint(
                    '📨 Using latest data point with water quality fields',
                  );
                } else {
                  debugPrint('⚠️ No data points with ph/turbidity found');
                }
              } else {
                debugPrint('❌ Data is not a Map: ${data.runtimeType}');
              }

              if (latestData != null) {
                debugPrint(
                  '📊 Latest water quality data from onValue: $latestData',
                );
                debugPrint('📊 Has pH: ${latestData.containsKey('ph')}');
                debugPrint(
                  '📊 Has turbidity: ${latestData.containsKey('turbidity')}',
                );
                debugPrint('📊 pH value: ${latestData['ph']}');
                debugPrint('📊 Turbidity value: ${latestData['turbidity']}');

                // Only process if this data has pH or turbidity
                if (latestData.containsKey('ph') ||
                    latestData.containsKey('turbidity')) {
                  _processWaterQualityData(latestData);
                } else {
                  debugPrint(
                    '⚠️ Latest entry does not contain pH or turbidity',
                  );
                }
              } else {
                debugPrint('❌ Could not extract latest data from onValue');
              }
            }
          },
          onError: (error) {
            debugPrint('❌ Error in water quality onValue listener: $error');
          },
        );

    // Also listen for new data being added (backup listener)
    _dataListener = ref
        .limitToLast(1)
        .onChildAdded
        .listen(
          (event) {
            if (!mounted) return;

            debugPrint(
              '📨 Water quality received NEW data: ${event.snapshot.key}',
            );
            debugPrint('📨 Raw value: ${event.snapshot.value}');

            // Check if the value is a Map
            if (event.snapshot.value is! Map) {
              debugPrint('❌ Unexpected data format: ${event.snapshot.value}');
              return;
            }

            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            debugPrint('📊 Water quality data from onChildAdded: $data');

            // Only process if this data has pH or turbidity
            if (data.containsKey('ph') || data.containsKey('turbidity')) {
              _processWaterQualityData(data);
            } else {
              debugPrint('📊 Skipping data point - no pH or turbidity data');
            }
          },
          onError: (error) {
            debugPrint(
              '❌ Error in water quality onChildAdded listener: $error',
            );
          },
        );

    // Also listen for changes to existing data (updates) - backup listener
    _dataUpdateListener = ref.onChildChanged.listen(
      (event) {
        if (!mounted) return;

        debugPrint('📨 Water quality data UPDATED: ${event.snapshot.key}');
        debugPrint('📨 Raw value: ${event.snapshot.value}');

        // Check if the value is a Map
        if (event.snapshot.value is! Map) {
          debugPrint('❌ Unexpected data format: ${event.snapshot.value}');
          return;
        }

        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        debugPrint('📊 Updated water quality data from onChildChanged: $data');

        // Only process if this data has pH or turbidity
        if (data.containsKey('ph') || data.containsKey('turbidity')) {
          _processWaterQualityData(data);
        } else {
          debugPrint(
            '📊 Skipping updated data point - no pH or turbidity data',
          );
        }
      },
      onError: (error) {
        debugPrint('❌ Error in water quality onChildChanged listener: $error');
      },
    );
  }

  void _processWaterQualityData(Map<String, dynamic> data) {
    if (!mounted) {
      debugPrint('⚠️ Widget not mounted, skipping data processing');
      return;
    }

    debugPrint('🔄 Processing water quality data: $data');
    debugPrint('🔄 Data keys: ${data.keys.join(', ')}');

    setState(() {
      // Only parse pH if it exists in the data
      if (data['ph'] != null) {
        final phString = data['ph'].toString();
        _ph = double.tryParse(phString);
        debugPrint('🔬 Parsed pH value: $_ph (from: $phString)');
      } else {
        _ph = null;
        debugPrint('🔬 No pH value in data');
      }

      // Handle turbidity - only set status if turbidity data exists
      if (data['turbidity'] != null) {
        final turbValue = data['turbidity'].toString();
        debugPrint(
          '🌊 Turbidity raw value: $turbValue (type: ${data['turbidity'].runtimeType})',
        );

        if (turbValue == 'CLEAN' || turbValue == 'DIRTY') {
          _turbidityStatus = turbValue;
          _turbidity = null; // No numeric value
          _turbidityMessage = ''; // Clear any timeout message
          debugPrint('🌊 Set turbidity status to: $_turbidityStatus');
        } else {
          // For backward compatibility, if it's still a number
          _turbidity = double.tryParse(turbValue);
          _turbidityStatus =
              (_turbidity != null && _turbidity! <= 5) ? 'CLEAN' : 'DIRTY';
          _turbidityMessage = ''; // Clear any timeout message
          debugPrint(
            '🌊 Parsed numeric turbidity: $_turbidity, status: $_turbidityStatus',
          );
        }
      } else {
        // No turbidity data available
        _turbidityStatus = '';
        _turbidity = null;
        _turbidityMessage = '';
        debugPrint('🌊 No turbidity value in data');
      }

      // Update last turbidity update time
      _lastTurbidityUpdate = DateTime.now();

      debugPrint('🌊 Final turbidity status: $_turbidityStatus');
      debugPrint('🔬 Final pH value: $_ph');

      _status =
          _ph == null && _turbidityStatus.isEmpty
              ? 'No Data'
              : (_ph != null &&
                  _ph! >= 6.5 &&
                  _ph! <= 8.5 &&
                  _turbidityStatus == 'CLEAN')
              ? 'Good'
              : (_turbidityStatus == 'NO WATER' ? 'No Water' : 'Check');
      debugPrint('✅ Water quality status updated to: $_status');
      debugPrint('✅ State updated - pH: $_ph, Turbidity: $_turbidityStatus');
    });
  }

  void _fetchHistory() {
    // Cancel existing history listener if any
    _historyListener?.cancel();

    // Updated path to look for data in readings/deviceId/data
    final ref = FirebaseDatabase.instance.ref(
      'readings/$_selectedDeviceId/data',
    );

    debugPrint(
      'Fetching water quality history from: readings/$_selectedDeviceId/data',
    );

    _historyListener = ref.limitToLast(8).onValue.listen((event) {
      debugPrint('Received water quality history data');

      final data = event.snapshot.value as Map<dynamic, dynamic>?;

      if (data != null) {
        debugPrint('History data keys: ${data.keys.join(', ')}');

        // Sort keys to ensure chronological order
        final sortedKeys = data.keys.toList()..sort();
        List<FlSpot> tempPh = [];
        List<String> labels = [];

        for (int i = 0; i < sortedKeys.length; i++) {
          final entry = data[sortedKeys[i]];

          if (entry is! Map) {
            debugPrint('Skipping invalid entry: $entry');
            continue;
          }

          // Try to get pH value, only add to history if it exists
          final phValue =
              entry['ph'] != null
                  ? double.tryParse(entry['ph'].toString())
                  : null;
          if (phValue != null) {
            tempPh.add(FlSpot(i.toDouble(), phValue));
            debugPrint('Added pH value: $phValue at index $i');
          } else {
            debugPrint('No pH value found at index $i');
          }

          // Try to get timestamp for the label
          final timestamp = entry['timestamp'];
          if (timestamp != null) {
            try {
              int timestampValue;
              if (timestamp is int) {
                timestampValue = timestamp;
              } else if (timestamp is double) {
                timestampValue = timestamp.toInt();
              } else if (timestamp is String) {
                // Try to parse string timestamp
                if (timestamp.contains('-')) {
                  // Handle date string format like "2025-08-04 22:08:24"
                  final dateTime = DateTime.parse(timestamp);
                  timestampValue = dateTime.millisecondsSinceEpoch ~/ 1000;
                } else {
                  // Try to parse as numeric string
                  timestampValue = int.parse(timestamp);
                }
              } else {
                timestampValue = int.parse(timestamp.toString());
              }

              final timeLabel = DateFormat.Hm().format(
                DateTime.fromMillisecondsSinceEpoch(timestampValue * 1000),
              );
              labels.add(timeLabel);
              debugPrint(
                'Added time label: $timeLabel from timestamp: $timestamp',
              );
            } catch (e) {
              debugPrint('Error parsing timestamp: $timestamp, error: $e');
              labels.add('--:--');
            }
          } else {
            labels.add('--:--');
            debugPrint('Added default time label: --:--');
          }
        }

        setState(() {
          phHistory = tempPh;
          historyLabels = labels;
          debugPrint('Updated history with ${tempPh.length} data points');
        });
      } else {
        debugPrint('No history data found');
      }
    });
  }

  void _onDeviceChanged(String? newDevice) {
    if (newDevice != null && newDevice != _selectedDeviceId) {
      debugPrint('Changing device from $_selectedDeviceId to $newDevice');

      // Cancel existing listeners before switching devices
      _dataListener?.cancel();
      _dataUpdateListener?.cancel();
      _dataValueListener?.cancel();
      _historyListener?.cancel();

      setState(() {
        _selectedDeviceId = newDevice;
        _ph = null;
        _turbidity = null;
        _turbidityStatus = '';
        _turbidityMessage = '';
        _status = 'Loading...';
        _lastTurbidityUpdate = null;
        phHistory.clear();
        historyLabels.clear();
      });

      // Restart turbidity timer for new device
      _startTurbidityTimer();

      // Use a small delay to ensure we don't interfere with other operations
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _selectedDeviceId == newDevice) {
          debugPrint('Setting up listeners for new device: $newDevice');
          _listenToData();
          _fetchHistory();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      floatingActionButton: const ComprehensiveReportFab(),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        title: const Text(
          'Water Quality Monitor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withAlpha(60), width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value:
                    deviceLabels.isNotEmpty &&
                            deviceLabels.containsKey(_selectedDeviceId)
                        ? _selectedDeviceId
                        : null,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                dropdownColor: Colors.white,
                elevation: 8,
                isDense: true,
                isExpanded: false,
                borderRadius: BorderRadius.circular(16),
                menuMaxHeight: 300,
                items:
                    deviceLabels.isNotEmpty
                        ? deviceLabels.entries.map((e) {
                          final deviceColor = _getDeviceColor(e.key);
                          return DropdownMenuItem<String>(
                            value: e.key,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 180),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: deviceColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: deviceColor.withAlpha(100),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.primaryTextColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList()
                        : [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Loading devices...'),
                          ),
                        ],
                onChanged: deviceLabels.isNotEmpty ? _onDeviceChanged : null,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                selectedItemBuilder: (BuildContext context) {
                  return deviceLabels.entries.map<Widget>((e) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
          ),

          // Download report button
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download Water Quality Report',
            onPressed: () => _downloadWaterQualityReport(),
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh data',
            onPressed: () async {
              setState(() {
                _ph = null;
                _turbidity = null;
                _turbidityStatus = '';
                _turbidityMessage = '';
                _status = 'Loading...';
                _lastTurbidityUpdate = null;
                phHistory.clear();
                historyLabels.clear();
              });

              // Restart turbidity timer
              _startTurbidityTimer();

              await Future.delayed(const Duration(milliseconds: 300));
              _listenToData();
              _fetchHistory();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () async {
          setState(() {
            _ph = null;
            _turbidity = null;
            _turbidityStatus = '';
            _turbidityMessage = '';
            _status = 'Loading...';
            _lastTurbidityUpdate = null;
            phHistory.clear();
            historyLabels.clear();
          });

          // Restart turbidity timer
          _startTurbidityTimer();

          await Future.delayed(const Duration(milliseconds: 300));
          _listenToData();
          _fetchHistory();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              _buildQualityStatus(),
              const SizedBox(height: 24),
              _buildParametersCard(),
              const SizedBox(height: 24),
              _buildHistoryChart(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityStatus() {
    final bool isGood = _status == 'Good';
    final bool isNoWater = _status == 'No Water';
    final statusColor =
        isGood
            ? AppTheme.successColor
            : (isNoWater ? Colors.orange : AppTheme.errorColor);
    final deviceIndex = _deviceService.deviceIds.indexOf(_selectedDeviceId) + 1;
    final deviceName =
        deviceLabels[_selectedDeviceId] ?? 'Smart Device $deviceIndex';
    final deviceColor = _getDeviceColor(_selectedDeviceId);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, deviceColor.withAlpha(10)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header with device info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [deviceColor, deviceColor.withAlpha(200)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: deviceColor.withAlpha(50),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Water Quality Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deviceName,
                        style: TextStyle(
                          fontSize: 14,
                          color: deviceColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGood
                            ? Icons.check_circle
                            : (isNoWater
                                ? Icons.warning_amber
                                : Icons.warning_rounded),
                        color: statusColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Status indicator
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          statusColor.withAlpha(40),
                          statusColor.withAlpha(15),
                        ],
                        radius: 0.8,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: statusColor.withAlpha(100),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withAlpha(30),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isGood
                                ? Icons.check_circle
                                : (isNoWater
                                    ? Icons.warning_amber
                                    : Icons.warning_rounded),
                            color: statusColor,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _status,
                            style: TextStyle(
                              fontSize: 24,
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Status description
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withAlpha(30), width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    isGood
                        ? Icons.info_outline
                        : (isNoWater
                            ? Icons.warning_amber
                            : Icons.priority_high_rounded),
                    color: statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isGood
                          ? 'Water quality is within acceptable parameters. The pH level and turbidity are in the normal range.'
                          : isNoWater
                          ? 'Water tank is no water or system is not on. Please check the water supply and system status.'
                          : 'Water quality needs attention. Please check the parameters below for details.',
                      style: TextStyle(
                        color: AppTheme.primaryTextColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParametersCard() {
    final deviceColor = _getDeviceColor(_selectedDeviceId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withAlpha(15),
                  AppTheme.secondaryColor.withAlpha(5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.analytics_rounded,
                    size: 20,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Water Parameters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),

          // Parameters
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildParameterCard(
                  'pH Level',
                  _ph?.toStringAsFixed(2) ?? '--',
                  _ph != null && _ph! >= 6.5 && _ph! <= 8.5,
                  'Ideal range: 6.5 - 8.5',
                  Icons.science_rounded,
                  deviceColor,
                ),
                const SizedBox(height: 16),
                _buildParameterCard(
                  'Turbidity',
                  _turbidityStatus.isNotEmpty ? _turbidityStatus : '--',
                  _turbidityStatus == 'CLEAN',
                  _turbidityMessage.isNotEmpty
                      ? _turbidityMessage
                      : (_turbidityStatus.isNotEmpty
                          ? 'Ideal: CLEAN water'
                          : 'No data available'),
                  Icons.opacity_rounded,
                  deviceColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterCard(
    String title,
    String value,
    bool isGood,
    String description,
    IconData icon,
    Color deviceColor,
  ) {
    final statusColor = isGood ? AppTheme.successColor : AppTheme.errorColor;
    final bool isTurbidity = title == 'Turbidity';
    final bool isNoWater = value == 'NO WATER';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withAlpha(10), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(50), width: 1),
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: deviceColor.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: deviceColor, size: 24),
          ),
          const SizedBox(width: 16),

          // Parameter info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),

          // Value display
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              isTurbidity
                  ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isNoWater
                              ? Colors.orange.withAlpha(25)
                              : (isGood
                                  ? Colors.green.withAlpha(25)
                                  : Colors.red.withAlpha(25)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isNoWater
                                ? Colors.orange.withAlpha(75)
                                : (isGood
                                    ? Colors.green.withAlpha(75)
                                    : Colors.red.withAlpha(75)),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      isNoWater ? '0' : value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            isNoWater
                                ? Colors.orange
                                : (isGood ? Colors.green : Colors.red),
                      ),
                    ),
                  )
                  : Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isNoWater
                        ? Icons.warning_amber
                        : (isGood ? Icons.check_circle : Icons.warning),
                    color: isNoWater ? Colors.orange : statusColor,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isNoWater ? 'No Water' : (isGood ? 'Normal' : 'Check'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isNoWater ? Colors.orange : statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryChart() {
    final deviceColor = _getDeviceColor(_selectedDeviceId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [deviceColor.withAlpha(15), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: deviceColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.timeline_rounded,
                        size: 20,
                        color: deviceColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'pH Level History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),

                // Refresh button
                GestureDetector(
                  onTap: _fetchHistory,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chart
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 260,
                  padding: const EdgeInsets.only(
                    right: 16,
                    top: 16,
                    bottom: 12,
                  ),
                  child:
                      phHistory.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: deviceColor,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading historical data...',
                                  style: TextStyle(
                                    color: AppTheme.secondaryTextColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: true,
                                horizontalInterval: 1,
                                verticalInterval: 1,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: Colors.grey.withAlpha(30),
                                    strokeWidth: 1,
                                  );
                                },
                                getDrawingVerticalLine: (value) {
                                  return FlLine(
                                    color: Colors.grey.withAlpha(30),
                                    strokeWidth: 1,
                                  );
                                },
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    getTitlesWidget:
                                        (value, _) => Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                          ),
                                          child: Text(
                                            value.toInt() < historyLabels.length
                                                ? historyLabels[value.toInt()]
                                                : '',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  AppTheme.secondaryTextColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                    reservedSize: 30,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  axisNameWidget: Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Text(
                                      'pH Value',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        value.toStringAsFixed(1),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.secondaryTextColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.withAlpha(50),
                                    width: 1,
                                  ),
                                  left: BorderSide(
                                    color: Colors.grey.withAlpha(50),
                                    width: 1,
                                  ),
                                  right: const BorderSide(
                                    color: Colors.transparent,
                                  ),
                                  top: const BorderSide(
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: phHistory,
                                  isCurved: true,
                                  curveSmoothness: 0.3,
                                  barWidth: 3,
                                  isStrokeCapRound: true,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) =>
                                            FlDotCirclePainter(
                                              radius: 4,
                                              color: deviceColor,
                                              strokeWidth: 1,
                                              strokeColor: Colors.white,
                                            ),
                                  ),
                                  color: deviceColor,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: deviceColor.withAlpha(40),
                                  ),
                                ),
                                // Add reference lines for ideal pH range (6.5 - 8.5)
                                LineChartBarData(
                                  spots: const [FlSpot(0, 6.5), FlSpot(7, 6.5)],
                                  isCurved: false,
                                  barWidth: 1,
                                  color: AppTheme.infoColor.withAlpha(150),
                                  dotData: FlDotData(show: false),
                                  dashArray: [5, 5],
                                ),
                                LineChartBarData(
                                  spots: const [FlSpot(0, 8.5), FlSpot(7, 8.5)],
                                  isCurved: false,
                                  barWidth: 1,
                                  color: AppTheme.infoColor.withAlpha(150),
                                  dotData: FlDotData(show: false),
                                  dashArray: [5, 5],
                                ),
                              ],
                              lineTouchData: LineTouchData(
                                enabled: true,
                                touchTooltipData: LineTouchTooltipData(
                                  tooltipBgColor: Colors.white,
                                  tooltipRoundedRadius: 8,
                                  tooltipBorder: BorderSide(
                                    color: Colors.grey.withAlpha(50),
                                    width: 1,
                                  ),
                                  getTooltipItems: (
                                    List<LineBarSpot> touchedBarSpots,
                                  ) {
                                    return touchedBarSpots.map((barSpot) {
                                      if (barSpot.barIndex > 0) {
                                        return null; // Skip reference lines
                                      }

                                      final index = barSpot.spotIndex;
                                      final time =
                                          index < historyLabels.length
                                              ? historyLabels[index]
                                              : '';

                                      return LineTooltipItem(
                                        'pH: ${barSpot.y.toStringAsFixed(2)}\nTime: $time',
                                        TextStyle(
                                          color: deviceColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                            ),
                          ),
                ),

                // Legend
                if (phHistory.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.infoColor.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.infoColor.withAlpha(30),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: deviceColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'pH Level',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.infoColor.withAlpha(150),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ideal Range (6.5 - 8.5)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The chart shows pH level readings over time. Ideal pH levels for water should be between 6.5 and 8.5.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryTextColor,
                            height: 1.4,
                          ),
                        ),
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

  Color _getDeviceColor(String deviceId) {
    // Use the getDeviceColor method from AppTheme to handle any device ID
    return AppTheme.getDeviceColor(deviceId);
  }

  Future<void> _downloadWaterQualityReport() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Collect water quality data for the selected device
      final Map<String, Map<String, dynamic>> devicesData = {};

      // Get current water quality data
      final List<Map<String, dynamic>> history = [];

      // Fetch history data
      final dataRef = FirebaseDatabase.instance.ref(
        'readings/$_selectedDeviceId/data',
      );
      final snapshot = await dataRef.limitToLast(10).get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          final sortedKeys = data.keys.toList()..sort();

          for (final key in sortedKeys) {
            final entry = data[key];
            if (entry is Map) {
              final entryMap = Map<String, dynamic>.from(entry);
              if (entryMap.containsKey('ph') ||
                  entryMap.containsKey('turbidity')) {
                final timestamp =
                    entryMap['recordedAt'] ??
                    entryMap['timestamp'] ??
                    key.toString();

                String formattedTime = _formatTimestamp(timestamp.toString());

                history.add({
                  'time': formattedTime,
                  'ph': entryMap['ph']?.toString() ?? 'N/A',
                  'turbidity': entryMap['turbidity']?.toString() ?? 'N/A',
                });
              }
            }
          }
        }
      }

      devicesData[_selectedDeviceId] = {
        'ph': _ph,
        'turbidityStatus':
            _turbidityStatus.isNotEmpty ? _turbidityStatus : 'N/A',
        'history': history.reversed.toList(), // Latest first
      };

      // Fetch leak alerts for the selected device
      final Map<String, List<Map<String, dynamic>>> leakData = {};
      try {
        final leakRef = FirebaseDatabase.instance.ref(
          'readings/$_selectedDeviceId/leak_alerts',
        );
        final leakSnapshot = await leakRef.limitToLast(50).get();

        if (leakSnapshot.exists) {
          final leakMap = leakSnapshot.value as Map<dynamic, dynamic>?;
          if (leakMap != null) {
            final List<Map<String, dynamic>> leaks = [];

            leakMap.forEach((key, value) {
              if (value is Map) {
                final leak = Map<String, dynamic>.from(value);
                final timestamp = leak['timestamp'];
                DateTime? leakDate;

                if (timestamp != null) {
                  if (timestamp is int) {
                    leakDate = DateTime.fromMillisecondsSinceEpoch(
                      timestamp > 9999999999 ? timestamp : timestamp * 1000,
                    );
                  } else if (timestamp is String) {
                    try {
                      leakDate = DateTime.parse(timestamp);
                    } catch (_) {}
                  }
                }

                if (leakDate == null) {
                  leakDate = DateTime.now();
                }

                final formattedDate = DateFormat('yyyy-MM-dd').format(leakDate);
                final formattedTime = DateFormat('HH:mm:ss').format(leakDate);
                final flowRate = leak['flowRate'] ?? leak['flow'] ?? 0.0;
                final reason =
                    leak['message'] ?? leak['reason'] ?? 'Leak detected';

                leaks.add({
                  'timestamp': leakDate.millisecondsSinceEpoch,
                  'reason': reason,
                  'flow': flowRate is num ? flowRate.toDouble() : 0.0,
                  'time': formattedTime,
                  'date': formattedDate,
                  'flow_rate':
                      '${(flowRate is num ? flowRate.toDouble() : 0.0).toStringAsFixed(2)} L/min',
                });
              }
            });

            // Sort by timestamp (newest first)
            leaks.sort(
              (a, b) =>
                  (b['timestamp'] as int).compareTo(a['timestamp'] as int),
            );

            if (leaks.isNotEmpty) {
              leakData[_selectedDeviceId] = leaks;
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching leak data: $e');
      }

      // Fetch manual activities for the selected device
      final Map<String, List<Map<String, dynamic>>> manualActivitiesData = {};
      try {
        final manualRef = FirebaseDatabase.instance.ref(
          'readings/$_selectedDeviceId/manual-activities',
        );
        final manualSnapshot = await manualRef.limitToLast(50).get();

        if (manualSnapshot.exists) {
          final manualMap = manualSnapshot.value as Map<dynamic, dynamic>?;
          if (manualMap != null) {
            final List<Map<String, dynamic>> activities = [];

            manualMap.forEach((key, value) {
              if (value is Map) {
                final activity = Map<String, dynamic>.from(value);
                final timestamp = activity['timestamp'];
                DateTime? activityDate;

                if (timestamp != null) {
                  if (timestamp is int) {
                    activityDate = DateTime.fromMillisecondsSinceEpoch(
                      timestamp > 9999999999 ? timestamp : timestamp * 1000,
                    );
                  } else if (timestamp is String) {
                    try {
                      activityDate = DateTime.parse(timestamp);
                    } catch (_) {}
                  }
                }

                if (activityDate == null) {
                  activityDate = DateTime.now();
                }

                final formattedDate = DateFormat(
                  'yyyy-MM-dd',
                ).format(activityDate);
                final formattedTime = DateFormat(
                  'HH:mm:ss',
                ).format(activityDate);
                final flowRate = activity['flow'] ?? 0.0;
                final reason =
                    activity['reason'] ??
                    activity['message'] ??
                    'Manual activity detected';

                activities.add({
                  'timestamp': activityDate.millisecondsSinceEpoch,
                  'reason': reason,
                  'flow': flowRate is num ? flowRate.toDouble() : 0.0,
                  'time': formattedTime,
                  'date': formattedDate,
                  'flow_rate':
                      '${(flowRate is num ? flowRate.toDouble() : 0.0).toStringAsFixed(2)} L/min',
                });
              }
            });

            // Sort by timestamp (newest first)
            activities.sort(
              (a, b) =>
                  (b['timestamp'] as int).compareTo(a['timestamp'] as int),
            );

            if (activities.isNotEmpty) {
              manualActivitiesData[_selectedDeviceId] = activities;
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching manual activities: $e');
      }

      // Generate PDF report
      final pdfPath = await PdfService.generateWaterQualityReportWithLeaks(
        devicesData: devicesData,
        deviceLabels: deviceLabels,
        leakData: leakData,
        manualActivitiesData: manualActivitiesData,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Open the PDF file
      await PdfService.openPdfFile(pdfPath);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Water Quality Report saved to: $pdfPath'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      debugPrint('Error generating water quality report: $e');
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is int) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(
          timestamp > 9999999999 ? timestamp : timestamp * 1000,
        );
        return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
      } else if (timestamp is String) {
        try {
          final dateTime = DateTime.parse(timestamp);
          return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
        } catch (_) {
          return timestamp.toString();
        }
      }
      return timestamp.toString();
    } catch (e) {
      return timestamp.toString();
    }
  }
}

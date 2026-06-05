import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/device_management_service.dart';
import '../../services/database_email_service.dart';

class WaterLeakageScreen extends StatefulWidget {
  const WaterLeakageScreen({super.key});

  @override
  State<WaterLeakageScreen> createState() => _WaterLeakageScreenState();
}

class _WaterLeakageScreenState extends State<WaterLeakageScreen> {
  final DeviceManagementService _deviceService = DeviceManagementService();
  List<String> deviceIds = [];
  String selectedDevice = 'sp25001';
  Map<String, String> deviceLabels = {};

  // Device grouping and filtering
  String _filterQuery = '';
  String _selectedGroup = 'All Devices';
  List<String> _filteredDeviceIds = [];
  Map<String, List<String>> _deviceGroups = {'All Devices': []};

  final Map<String, DatabaseReference> _flowRefs = {};
  final Map<String, DatabaseReference> _valveRefs = {};
  final Map<String, DatabaseReference> _notifRefs = {};
  final Map<String, DatabaseReference> _leakAlertRefs = {};
  final Map<String, DatabaseReference> _manualAlertRefs = {};
  static const Duration _alertRetentionWindow = Duration(minutes: 2);
  final Map<String, double> _flowRates = {};
  final Map<String, bool> _valveStates = {};
  final Map<String, String> _leakStatuses = {};
  final Map<String, String> _timeStamps = {};
  final Map<String, bool> _hasShownLeakSnackbar = {};

  // Track valve state changes for improved leak detection
  final Map<String, DateTime> _lastValveStateChange = {};
  final Map<String, bool> _previousValveState = {};
  final Map<String, Set<String>> _processedLeakAlertKeys = {};
  final Map<String, Set<String>> _processedManualAlertKeys = {};
  final Map<String, DateTime?> _latestAlertTimestamp = {};

  // Leak history for each device
  final Map<String, List<Map<String, dynamic>>> _leakHistory = {};

  // Leakage detection toggle
  final Map<String, bool> _leakDetectionEnabled = {};

  // History of flow rates for each device
  final Map<String, List<double>> _flowHistory = {};
  final Map<String, List<String>> _timeHistory = {};
  // Email recipients for leak alerts
  List<String> _emailRecipients = [];

  @override
  void initState() {
    super.initState();
    _initializeDeviceService();
    _loadLeakEmailRecipients();
  }

  @override
  void dispose() {
    _deviceService.removeListener(_onDevicesChanged);
    super.dispose();
  }

  Future<void> _loadLeakEmailRecipients() async {
    try {
      final ref = FirebaseDatabase.instance.ref('email_settings/recipients');
      final snap = await ref.get();

      final recipients = <String>[];
      if (snap.exists) {
        final val = snap.value;
        if (val is List) {
          for (final item in val) {
            if (item is String && item.trim().isNotEmpty)
              recipients.add(item.trim());
          }
        } else if (val is Map) {
          final map = Map<dynamic, dynamic>.from(val);
          for (final v in map.values) {
            if (v is String && v.trim().isNotEmpty) recipients.add(v.trim());
          }
        }
      }

      if (mounted) {
        setState(() {
          _emailRecipients = recipients.toSet().toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading email recipients: $e');
    }
  }

  Future<void> _queueLeakEmails(
    String deviceId,
    String reason,
    double flow,
  ) async {
    if (_emailRecipients.isEmpty) return;
    try {
      final deviceIndex = deviceIds.indexOf(deviceId) + 1;
      final deviceName = deviceLabels[deviceId] ?? 'Smart Device $deviceIndex';
      final flowRate = '${flow.toStringAsFixed(2)} L/min';
      final message = reason;

      for (final to in _emailRecipients) {
        await DatabaseEmailService.sendWaterLeakNotification(
          to: to,
          deviceName: deviceName,
          message: message,
          flowRate: flowRate,
          systemName: 'SmartPipe Water Management System',
          subject: 'Water Leak Alert - $deviceName',
        );
      }
    } catch (e) {
      debugPrint('Error queuing leak emails: $e');
    }
  }

  void _onDevicesChanged() {
    setState(() {
      deviceIds = _deviceService.deviceIds;
      deviceLabels = _deviceService.deviceLabels;

      // Update filtered devices and groups
      _updateDeviceGroups();
      _filterDevices();

      // Re-initialize data for new devices
      _initializeData();
    });
  }

  // Group devices by location/building
  void _updateDeviceGroups() {
    // Reset groups
    _deviceGroups = {'All Devices': deviceIds};

    // Group by building/location (extract from device label if possible)
    final buildingGroups = <String, List<String>>{};

    for (int i = 0; i < deviceIds.length; i++) {
      final deviceId = deviceIds[i];
      final label = deviceLabels[deviceId] ?? 'Smart Device ${i + 1}';

      // Try to extract building/location from label (assuming format like "Building Name - Device Name")
      String building = 'Other';
      if (label.contains(' - ')) {
        building = label.split(' - ')[0].trim();
      }

      buildingGroups[building] = [
        ...(buildingGroups[building] ?? []),
        deviceId,
      ];
    }

    // Add building groups
    _deviceGroups.addAll(buildingGroups);

    // If current selected group no longer exists, reset to All Devices
    if (!_deviceGroups.containsKey(_selectedGroup)) {
      _selectedGroup = 'All Devices';
    }
  }

  // Filter devices based on search query and selected group
  void _filterDevices() {
    final query = _filterQuery.toLowerCase();

    // Start with devices from selected group
    final devicesInGroup = _deviceGroups[_selectedGroup] ?? deviceIds;

    // Apply search filter if query is not empty
    if (query.isEmpty) {
      _filteredDeviceIds = List.from(devicesInGroup);
    } else {
      _filteredDeviceIds =
          devicesInGroup.where((deviceId) {
            final deviceIndex = deviceIds.indexOf(deviceId) + 1;
            final label =
                deviceLabels[deviceId]?.toLowerCase() ??
                'smart device $deviceIndex';
            return label.contains(query);
          }).toList();
    }
  }

  Future<void> _initializeDeviceService() async {
    // Initialize device service
    await _deviceService.initialize();

    // Update device information
    setState(() {
      deviceIds = _deviceService.deviceIds;
      deviceLabels = _deviceService.deviceLabels;

      // If no devices available, use default
      if (deviceIds.isEmpty) {
        deviceIds = ['sp25001'];
      }

      // If selected device is not in the list, use the first one
      if (!deviceIds.contains(selectedDevice) && deviceIds.isNotEmpty) {
        selectedDevice = deviceIds[0];
      }

      // Initialize device groups and filtering
      _updateDeviceGroups();
      _filterDevices();
    });

    // Listen for device changes
    _deviceService.addListener(_onDevicesChanged);

    // Continue with initialization
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Load saved leak detection settings
    final prefs = await SharedPreferences.getInstance();

    // First, set up all references and data structures
    for (final deviceId in deviceIds) {
      _hasShownLeakSnackbar[deviceId] = false;

      // Load saved leak detection setting or use default (true)
      _leakDetectionEnabled[deviceId] =
          prefs.getBool('leak_detection_$deviceId') ?? true;

      // Initialize history arrays
      _flowHistory[deviceId] = [];
      _timeHistory[deviceId] = [];
      _leakHistory[deviceId] = [];
      _processedLeakAlertKeys[deviceId] = <String>{};
      _processedManualAlertKeys[deviceId] = <String>{};
      _latestAlertTimestamp[deviceId] = null;
      _leakStatuses[deviceId] ??= '✅ Normal Operation';

      // Initialize valve state tracking
      _lastValveStateChange[deviceId] = DateTime.now();
      _previousValveState[deviceId] = false;

      // Set up database references
      _flowRefs[deviceId] = FirebaseDatabase.instance.ref('readings/$deviceId');
      _valveRefs[deviceId] = FirebaseDatabase.instance.ref(
        'control/$deviceId/relay',
      );
      _notifRefs[deviceId] = FirebaseDatabase.instance.ref('notifications');
      _leakAlertRefs[deviceId] = _flowRefs[deviceId]!.child('leak_alerts');
      _manualAlertRefs[deviceId] = _flowRefs[deviceId]!.child('manual_alerts');
    }

    // Then, fetch the current valve states without modifying them
    for (final deviceId in deviceIds) {
      try {
        final snapshot = await _valveRefs[deviceId]!.get();
        if (snapshot.exists) {
          final status = snapshot.value?.toString().toUpperCase() ?? 'OFF';
          _valveStates[deviceId] = status == 'ON';
        } else {
          _valveStates[deviceId] = false; // Default to OFF if no data
        }
      } catch (e) {
        debugPrint('Error fetching valve state for $deviceId: $e');
        _valveStates[deviceId] = false; // Default to OFF on error
      }
    }

    // Now that we have the current states, set up listeners
    for (final deviceId in deviceIds) {
      _listenToValveStatus(deviceId);
      _listenToLatestFlow(deviceId);
      _listenToLeakAlerts(deviceId);
      _listenToManualAlerts(deviceId);
    }

    // Force a rebuild with the loaded settings
    if (mounted) {
      setState(() {});
    }
  }

  void _listenToValveStatus(String deviceId) {
    _valveRefs[deviceId]!.onValue.listen((event) {
      // Only update the local state without modifying the actual valve state
      final status = event.snapshot.value?.toString().toUpperCase() ?? 'OFF';
      final newValveState = status == 'ON';
      final oldValveState = _valveStates[deviceId] ?? false;

      debugPrint(
        'Valve status update for $deviceId: $status (newValveState: $newValveState, oldValveState: $oldValveState)',
      );

      // Check if this is a new value before updating state to prevent unnecessary rebuilds
      if (oldValveState != newValveState) {
        // Store previous state before updating
        _previousValveState[deviceId] = oldValveState;

        // Record the time of valve state change
        _lastValveStateChange[deviceId] = DateTime.now();

        // Log the valve state change
        debugPrint(
          'Valve state changed for $deviceId: ${oldValveState ? 'ON' : 'OFF'} -> ${newValveState ? 'ON' : 'OFF'}',
        );

        // Auto-disable leak detection when valve is ON, re-enable when valve is OFF
        if (newValveState) {
          // Valve turned ON - disable leak detection but don't override status yet
          _leakDetectionEnabled[deviceId] = false;
          // Reset manual switch notification when valve turns ON
          _hasShownLeakSnackbar[deviceId] = false;
          debugPrint('Auto-disabled leak detection for $deviceId (valve ON)');
        } else {
          // Valve turned OFF - re-enable leak detection
          _leakDetectionEnabled[deviceId] = true;
          _leakStatuses[deviceId] = '✅ Leak Detection Active (Valve OFF)';
          // Reset manual switch notification when valve turns OFF
          _hasShownLeakSnackbar[deviceId] = false;
          debugPrint('Auto-enabled leak detection for $deviceId (valve OFF)');
        }

        setState(() {
          _valveStates[deviceId] = newValveState;
        });
      }
    });
  }

  void _listenToLatestFlow(String deviceId) {
    // Updated path to look for data in readings/deviceId/data
    // This will listen for new children added to the data node
    debugPrint(
      '🔍 Setting up flow listener for $deviceId at: readings/$deviceId/data',
    );

    // First, let's check if the path exists and get the latest flow data
    _flowRefs[deviceId]!
        .child('data')
        .once()
        .then((snapshot) {
          debugPrint('📊 Initial flow data check for $deviceId:');
          debugPrint('   - Path exists: ${snapshot.snapshot.exists}');
          debugPrint(
            '   - Has children: ${snapshot.snapshot.children.isNotEmpty}',
          );
          if (snapshot.snapshot.exists) {
            debugPrint('   - Data: ${snapshot.snapshot.value}');

            // Check for existing flow data
            final data = snapshot.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              debugPrint('   - All data keys: ${data.keys.toList()}');

              // Find the most recent data point with flowRate
              Map<String, dynamic>? latestFlowData;
              int? latestTimestamp = 0;

              for (final entry in data.entries) {
                final key = entry.key.toString();
                final value = entry.value;

                // Skip direct fields that are not data points
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
                  dataPoint['_key'] = key;
                  debugPrint('   - Checking data point: $key');
                  debugPrint(
                    '   - Data point keys: ${dataPoint.keys.toList()}',
                  );

                  // Check for flowRate (new field name) or flow (backward compatibility)
                  if (dataPoint.containsKey('flowRate') ||
                      dataPoint.containsKey('flow')) {
                    debugPrint('   - ✅ Found flow data in: $key');

                    // Parse timestamp to find the latest
                    int? timestampValue;

                    // Try to parse timestamp from the key (ISO 8601 format like 2025-11-12T12:04:40Z)
                    try {
                      if (key.contains('T') && key.contains('Z')) {
                        // ISO 8601 format timestamp in key
                        final dateTime = DateTime.parse(key);
                        timestampValue =
                            dateTime.millisecondsSinceEpoch ~/ 1000;
                        debugPrint(
                          '   - Parsed timestamp from key: $timestampValue',
                        );
                      } else if (key.startsWith('point_')) {
                        // Legacy point_timestamp format
                        final keyTimestamp = key.replaceFirst('point_', '');
                        timestampValue = int.tryParse(keyTimestamp);
                        debugPrint(
                          '   - Parsed timestamp from point_ key: $timestampValue',
                        );
                      }
                    } catch (e) {
                      debugPrint('   - Error parsing timestamp from key: $e');
                    }

                    // Also try to get timestamp from data point
                    final timestamp = dataPoint['timestamp'];
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
                          timestampValue = int.tryParse(timestamp);
                        }
                      }
                    } catch (e) {
                      debugPrint('Error parsing timestamp from data: $e');
                    }

                    if (timestampValue != null &&
                        timestampValue > latestTimestamp!) {
                      latestTimestamp = timestampValue;
                      latestFlowData = dataPoint;
                      debugPrint(
                        '   - ✅ Updated latest flow data (timestamp: $timestampValue)',
                      );
                    } else if (latestFlowData == null) {
                      // If no timestamp, use first found
                      latestFlowData = dataPoint;
                      debugPrint(
                        '   - ✅ Using first flow data point (no timestamp)',
                      );
                    }
                  } else {
                    debugPrint('   - ⚠️ No flow/flowRate in data point: $key');
                  }
                } else {
                  debugPrint(
                    '   - ⚠️ Entry is not a Map: $key (type: ${value.runtimeType})',
                  );
                }
              }

              if (latestFlowData != null) {
                debugPrint('📊 Found existing flow data: $latestFlowData');
                _processFlowData(deviceId, latestFlowData);
              }
            }
          }
        })
        .catchError((error) {
          debugPrint('❌ Error checking initial flow data: $error');
        });

    // Listen for new data being added
    _flowRefs[deviceId]!
        .child('data')
        .limitToLast(1)
        .onChildAdded
        .listen(
          (event) {
            // Debug the received data
            debugPrint(
              '📨 Water leakage received NEW data for $deviceId: ${event.snapshot.key}',
            );
            debugPrint('📨 Raw value: ${event.snapshot.value}');
            debugPrint('📨 Value type: ${event.snapshot.value.runtimeType}');

            // The data is directly in the value, not nested
            final entry = event.snapshot.value;

            // Check if entry is a Map and has flowRate or flow field
            if (entry is Map) {
              final dataMap = Map<String, dynamic>.from(entry);
              dataMap['_key'] = event.snapshot.key?.toString();
              // Check for flowRate (new field name) or flow (backward compatibility)
              if (dataMap.containsKey('flowRate') ||
                  dataMap.containsKey('flow')) {
                _processFlowData(deviceId, dataMap);
              } else {
                debugPrint('📊 Skipping data point - no flowRate/flow data');
                debugPrint('📊 Available keys: ${dataMap.keys.join(', ')}');
              }
            } else {
              debugPrint('📊 Skipping data point - not a Map');
            }
          },
          onError: (error) {
            debugPrint('❌ Error in flow onChildAdded listener: $error');
          },
        );

    // Also listen for changes to existing data (updates) using onValue
    _flowRefs[deviceId]!
        .child('data')
        .limitToLast(1)
        .onValue
        .listen(
          (event) {
            if (event.snapshot.exists && mounted) {
              final data = event.snapshot.value;
              debugPrint(
                '📨 Water leakage onValue received (all changes) for $deviceId',
              );
              debugPrint('📨 Raw onValue data: $data');
              debugPrint('📨 Data type: ${data.runtimeType}');

              if (data is Map) {
                final dataMap = Map<String, dynamic>.from(data);
                debugPrint('📨 Data map keys: ${dataMap.keys.toList()}');

                // Filter out direct fields and find data points with flowRate/flow
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

                  // Check if this is a data point with flow data
                  if (value is Map) {
                    final dataPoint = Map<String, dynamic>.from(value);
                    if (dataPoint.containsKey('flowRate') ||
                        dataPoint.containsKey('flow')) {
                      // Try to get timestamp
                      int? timestampValue;

                      // Try to parse timestamp from the key (ISO 8601 format)
                      try {
                        if (key.contains('T') && key.contains('Z')) {
                          final dateTime = DateTime.parse(key);
                          timestampValue =
                              dateTime.millisecondsSinceEpoch ~/ 1000;
                        } else if (key.startsWith('point_')) {
                          final keyTimestamp = key.replaceFirst('point_', '');
                          timestampValue = int.tryParse(keyTimestamp);
                        }
                      } catch (e) {
                        debugPrint('Error parsing timestamp from key: $e');
                      }

                      final timestamp = dataPoint['timestamp'];
                      if (timestampValue == null && timestamp != null) {
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
                              timestampValue = int.tryParse(timestamp);
                            }
                          }
                        } catch (e) {
                          debugPrint('Error parsing timestamp from data: $e');
                        }
                      }

                      if (timestampValue != null &&
                          (candidateTimestamp == null ||
                              timestampValue > candidateTimestamp)) {
                        candidateTimestamp = timestampValue;
                        candidateData = dataPoint;
                        debugPrint(
                          '📨 Found candidate flow data: $key (timestamp: $timestampValue)',
                        );
                      } else if (candidateData == null) {
                        candidateData = dataPoint;
                        debugPrint(
                          '📨 Found candidate flow data (no timestamp): $key',
                        );
                      }
                    }
                  }
                }

                if (candidateData != null) {
                  debugPrint('📨 Using latest flow data point');
                  _processFlowData(deviceId, candidateData);
                } else {
                  debugPrint('⚠️ No data points with flowRate/flow found');
                }
              }
            }
          },
          onError: (error) {
            debugPrint('❌ Error in flow onValue listener: $error');
          },
        );
  }

  void _listenToLeakAlerts(String deviceId) {
    final ref = _leakAlertRefs[deviceId];
    if (ref == null) return;

    ref
        .limitToLast(50)
        .onChildAdded
        .listen(
          (event) {
            final value = event.snapshot.value;
            if (value is! Map) {
              debugPrint(
                '⚠️ Leak alert entry is not a map for $deviceId: ${event.snapshot.value}',
              );
              return;
            }

            final alertData = Map<String, dynamic>.from(value);
            final status = (alertData['status'] ?? '').toString().toLowerCase();
            if (status == 'sent' ||
                status == 'processed' ||
                status == 'dismissed') {
              return;
            }
            final dedupeKey = _buildAlertKey(
              deviceId,
              event.snapshot.key,
              alertData,
            );
            if (_markAlertProcessed(
              _processedLeakAlertKeys,
              deviceId,
              dedupeKey,
            )) {
              return;
            }

            _handleAlertFromFirebase(
              deviceId: deviceId,
              alertData: alertData,
              rawKey: event.snapshot.key,
              alertType: 'leak',
            );
          },
          onError: (error) {
            debugPrint('❌ Error in leak alert listener for $deviceId: $error');
          },
        );
  }

  void _listenToManualAlerts(String deviceId) {
    final ref = _manualAlertRefs[deviceId];
    if (ref == null) return;

    ref
        .limitToLast(50)
        .onChildAdded
        .listen(
          (event) {
            final value = event.snapshot.value;
            if (value is! Map) {
              debugPrint(
                '⚠️ Manual alert entry is not a map for $deviceId: ${event.snapshot.value}',
              );
              return;
            }

            final alertData = Map<String, dynamic>.from(value);
            final status = (alertData['status'] ?? '').toString().toLowerCase();
            if (status == 'processed' ||
                status == 'dismissed' ||
                status == 'sent') {
              return;
            }
            final dedupeKey = _buildAlertKey(
              deviceId,
              event.snapshot.key,
              alertData,
            );
            if (_markAlertProcessed(
              _processedManualAlertKeys,
              deviceId,
              dedupeKey,
            )) {
              return;
            }

            _handleAlertFromFirebase(
              deviceId: deviceId,
              alertData: alertData,
              rawKey: event.snapshot.key,
              alertType: 'manual',
            );
          },
          onError: (error) {
            debugPrint(
              '❌ Error in manual alert listener for $deviceId: $error',
            );
          },
        );
  }

  String _buildAlertKey(
    String deviceId,
    String? rawKey,
    Map<String, dynamic> data,
  ) {
    final baseKey =
        rawKey ??
        data['id']?.toString() ??
        data['timestamp']?.toString() ??
        data['createdAt']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return '$deviceId::$baseKey';
  }

  bool _markAlertProcessed(
    Map<String, Set<String>> processedMap,
    String deviceId,
    String dedupeKey,
  ) {
    processedMap[deviceId] ??= <String>{};
    if (processedMap[deviceId]!.contains(dedupeKey)) {
      return true;
    }
    processedMap[deviceId]!.add(dedupeKey);
    return false;
  }

  void _handleAlertFromFirebase({
    required String deviceId,
    required Map<String, dynamic> alertData,
    required String alertType,
    String? rawKey,
  }) {
    final bool isManualAlert = alertType == 'manual';
    final dynamic flowField = alertData['flowRate'] ?? alertData['flow'];
    final double flow = _parseAlertFlow(flowField);
    final DateTime alertTime = _extractAlertTimestamp(
      alertData['timestamp'],
      rawKey,
    );
    final String formattedTime = DateFormat('hh:mm a').format(alertTime);
    final String formattedDate = DateFormat('yyyy-MM-dd').format(alertTime);

    String message =
        (alertData['message'] ??
                alertData['status'] ??
                alertData['reason'] ??
                (isManualAlert
                    ? '⚠️ Manual switch triggered or no water'
                    : '🚨 Leak Detected'))
            .toString();

    if (isManualAlert && !message.toLowerCase().contains('manual')) {
      message = '⚠️ Manual switch triggered - $message';
    } else if (!isManualAlert &&
        !message.contains('Leak') &&
        !message.contains('⚠️') &&
        !message.contains('🚨')) {
      message = '🚨 Leak Detected - $message';
    }

    _latestAlertTimestamp[deviceId] = alertTime;

    void updateState() {
      final history = _leakHistory[deviceId]!;
      history.add({
        'timestamp': alertTime.millisecondsSinceEpoch,
        'reason': message,
        'flow': flow,
        'time': formattedTime,
        'date': formattedDate,
        'valve_state':
            alertData['valve_state'] ?? _valveStates[deviceId] ?? false,
        'type': alertType,
        'source': 'firebase',
      });
      if (history.length > 50) {
        history.removeAt(0);
      }
      _flowRates[deviceId] = flow;
      _timeStamps[deviceId] = formattedTime;
      _leakStatuses[deviceId] = message;
    }

    if (mounted) {
      setState(updateState);
    } else {
      updateState();
    }

    _hasShownLeakSnackbar[deviceId] = false;

    final sanitizedReason =
        message.replaceAll('🚨', '').replaceAll('⚠️', '').trim();
    final reasonForNotifications =
        sanitizedReason.isNotEmpty ? sanitizedReason : message;

    if (!isManualAlert && _emailRecipients.isNotEmpty) {
      _queueLeakEmails(deviceId, reasonForNotifications, flow);
    }

    _sendLeakNotification(
      deviceId,
      reasonForNotifications,
      flow,
      alertTime: alertTime,
    );
    _markAlertRecordAsProcessed(deviceId, alertType, rawKey);

    final bool shouldShowSnackbar =
        isManualAlert || (_leakDetectionEnabled[deviceId] ?? true);
    if (shouldShowSnackbar) {
      _showLeakSnackbar(deviceId);
    }
  }

  double _parseAlertFlow(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  DateTime _extractAlertTimestamp(dynamic timestampField, String? rawKey) {
    DateTime? fromField;

    if (timestampField is int) {
      fromField = _fromEpoch(timestampField);
    } else if (timestampField is double) {
      fromField = _fromEpoch(timestampField.toInt());
    } else if (timestampField is String) {
      if (timestampField.contains('-')) {
        fromField = DateTime.tryParse(timestampField);
      } else {
        final numeric = int.tryParse(timestampField);
        if (numeric != null) {
          fromField = _fromEpoch(numeric);
        }
      }
    }

    if (fromField == null && rawKey != null) {
      if (rawKey.contains('T') && rawKey.contains('Z')) {
        fromField = DateTime.tryParse(rawKey);
      } else {
        final sanitized =
            rawKey.startsWith('point_')
                ? rawKey.replaceFirst('point_', '')
                : rawKey;
        final numeric = int.tryParse(sanitized);
        if (numeric != null) {
          fromField = _fromEpoch(numeric);
        }
      }
    }

    return (fromField ?? DateTime.now()).toLocal();
  }

  DateTime _fromEpoch(int secondsOrMillis) {
    if (secondsOrMillis > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(secondsOrMillis);
    }
    return DateTime.fromMillisecondsSinceEpoch(secondsOrMillis * 1000);
  }

  DateTime? _parseTimestamp(dynamic rawTimestamp, {String? fallbackKey}) {
    if (rawTimestamp != null) {
      if (rawTimestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(rawTimestamp * 1000);
      } else if (rawTimestamp is double) {
        return DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt() * 1000);
      } else {
        final numeric = int.tryParse(rawTimestamp.toString());
        if (numeric != null) {
          return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
        }
        try {
          return DateTime.parse(rawTimestamp.toString());
        } catch (_) {}
      }
    }

    if (fallbackKey != null) {
      final numeric = int.tryParse(fallbackKey);
      if (numeric != null) {
        return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      }
      try {
        return DateTime.parse(fallbackKey);
      } catch (_) {}
    }
    return null;
  }

  void _processFlowData(String deviceId, Map<String, dynamic> data) {
    final flowValue = data['flowRate'] ?? data['flow'];
    final flow = double.tryParse(flowValue?.toString() ?? '0') ?? 0.0;
    final now = DateTime.now();
    final DateTime? parsedTimestamp = _parseTimestamp(
      data['timestamp'],
      fallbackKey: data['_key']?.toString(),
    );
    final usedTime = parsedTimestamp ?? now;
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(usedTime);

    debugPrint(
      '🌊 Processing flow data for $deviceId: flowRate=$flowValue, parsed=$flow',
    );

    // Store flow history (keep last 10 readings)
    if (_flowHistory[deviceId]!.length >= 10) {
      _flowHistory[deviceId]!.removeAt(0);
      _timeHistory[deviceId]!.removeAt(0);
    }
    _flowHistory[deviceId]!.add(flow);
    _timeHistory[deviceId]!.add(formattedTime);

    // Log flow after valve change for debugging
    final lastValveChange = _lastValveStateChange[deviceId] ?? now;
    final timeSinceValveChange = now.difference(lastValveChange);
    if (timeSinceValveChange.inSeconds < 60) {
      debugPrint(
        'Flow after valve change for $deviceId: $flow L/min (${timeSinceValveChange.inSeconds}s after change)',
      );
    }

    final hasRecentAlert = _hasRecentAlert(deviceId);
    final detectionEnabled = _leakDetectionEnabled[deviceId] ?? true;
    final defaultStatus =
        detectionEnabled ? '✅ Normal Operation' : '⚠️ Leak Detection Disabled';

    if (mounted) {
      setState(() {
        _flowRates[deviceId] = flow;
        _timeStamps[deviceId] = formattedTime;
        if (!hasRecentAlert) {
          _leakStatuses[deviceId] = defaultStatus;
        }
      });
    } else {
      _flowRates[deviceId] = flow;
      _timeStamps[deviceId] = formattedTime;
      if (!hasRecentAlert) {
        _leakStatuses[deviceId] = defaultStatus;
      }
    }
  }

  bool _hasRecentAlert(String deviceId) {
    final lastAlert = _latestAlertTimestamp[deviceId];
    if (lastAlert == null) return false;
    return DateTime.now().difference(lastAlert) < _alertRetentionWindow;
  }

  Future<void> _sendLeakNotification(
    String deviceId,
    String reason,
    double flow, {
    DateTime? alertTime,
  }) async {
    final deviceIndex = deviceIds.indexOf(deviceId) + 1;
    final deviceName = deviceLabels[deviceId] ?? 'Smart Device $deviceIndex';
    final timestamp = (alertTime ?? DateTime.now()).millisecondsSinceEpoch;

    // Determine notification type and title based on reason
    final isManualSwitch = reason.toLowerCase().contains(
      'manual switch triggered',
    );
    final title =
        isManualSwitch ? 'Manual Switch Alert' : 'Water Leak Detected';
    final type = isManualSwitch ? 'manual_switch' : 'leak';

    await _notifRefs[deviceId]!.push().set({
      'title': title,
      'message':
          '$title in $deviceName: $reason (Flow: ${flow.toStringAsFixed(2)} L/min)',
      'timestamp': timestamp,
      'read': false,
      'type': type,
      'device_id': deviceId,
      'device_name': deviceName,
      'flow_rate': flow,
    });
  }

  void _markAlertRecordAsProcessed(
    String deviceId,
    String alertType,
    String? rawKey,
  ) {
    if (rawKey == null || rawKey.isEmpty) return;

    final DatabaseReference? baseRef =
        alertType == 'manual'
            ? _manualAlertRefs[deviceId]
            : _leakAlertRefs[deviceId];
    if (baseRef == null) return;

    baseRef
        .child(rawKey)
        .update({
          'status': alertType == 'manual' ? 'processed' : 'sent',
          'processedAt': DateTime.now().toIso8601String(),
          'processedBy': 'smartpipe-app',
        })
        .catchError((error) {
          debugPrint(
            '❌ Failed to update ${alertType} alert ${deviceId}/$rawKey: $error',
          );
        });
  }

  void _showLeakSnackbar(String deviceId) {
    if (mounted) {
      final status = _leakStatuses[deviceId] ?? '';
      final isWarning = status.contains('Possible');
      final isManualSwitch = status.contains('Manual switch triggered');
      final flow = _flowRates[deviceId]?.toStringAsFixed(2) ?? '0.0';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isManualSwitch
                    ? '⚠️ Manual Switch Alert (${deviceLabels[deviceId] ?? 'Smart Device'})'
                    : isWarning
                    ? '⚠️ Possible Leak Alert (${deviceLabels[deviceId] ?? 'Smart Device'})'
                    : '🚨 Leak Alert (${deviceLabels[deviceId] ?? 'Smart Device'})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status
                    .replaceAll('🚨 Leak Detected! ', '')
                    .replaceAll('⚠️ Possible Leak! ', '')
                    .replaceAll(
                      '⚠️ Manual switch triggered or no water',
                      'Manual switch triggered or no water',
                    ),
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'Current flow: $flow L/min',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          backgroundColor:
              isManualSwitch
                  ? Colors.orange
                  : (isWarning ? AppTheme.warningColor : AppTheme.errorColor),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () {
              setState(() {
                selectedDevice = deviceId;
              });
            },
          ),
        ),
      );
    }
  }

  // Get summary statistics for all devices
  Map<String, int> _getLeakSummary() {
    int totalDevices = deviceIds.length;
    int leakingDevices = 0;
    int warningDevices = 0;
    int normalDevices = 0;
    int disabledDevices = 0;

    for (final deviceId in deviceIds) {
      final status = _leakStatuses[deviceId] ?? '';
      final isEnabled = _leakDetectionEnabled[deviceId] ?? true;

      if (!isEnabled) {
        disabledDevices++;
      } else if (status.contains('Leak Detected')) {
        leakingDevices++;
      } else if (status.contains('Possible Leak')) {
        warningDevices++;
      } else if (status.contains('Normal')) {
        normalDevices++;
      }
    }

    return {
      'total': totalDevices,
      'leaking': leakingDevices,
      'warning': warningDevices,
      'normal': normalDevices,
      'disabled': disabledDevices,
    };
  }

  // Search for devices
  void _searchDevices(String query) {
    setState(() {
      _filterQuery = query;
      _filterDevices();
    });
  }

  // Change device group
  void _changeDeviceGroup(String group) {
    setState(() {
      _selectedGroup = group;
      _filterDevices();
    });
  }

  // Change sort option
  // Build a summary card for the dashboard
  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(50), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flowRates[selectedDevice]?.toStringAsFixed(2) ?? '--';
    final status = _leakStatuses[selectedDevice] ?? 'Checking...';
    final time = _timeStamps[selectedDevice] ?? '--:--';
    final isLoading = flow == '--';
    final deviceColor = _getDeviceColor(selectedDevice);

    // Get summary statistics
    final summary = _getLeakSummary();

    // Determine status color
    Color statusColor;
    if (status.contains('✅')) {
      statusColor = AppTheme.successColor;
    } else if (status.contains('⚠️')) {
      statusColor = AppTheme.warningColor;
    } else {
      statusColor = AppTheme.errorColor;
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Water Leakage Detection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh data',
            onPressed: () {
              _initializeData();
            },
          ),
          // Manage email recipients
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Manage email recipients',
            onPressed: _openRecipientsManager,
          ),
          // Clear notifications button
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear notification states',
            onPressed: () {
              for (final deviceId in deviceIds) {
                _hasShownLeakSnackbar[deviceId] = false;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Notification states cleared for all devices'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary dashboard
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor.withAlpha(30), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System Overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildSummaryCard(
                        'Total Devices',
                        summary['total'].toString(),
                        Icons.devices,
                        AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Leaking',
                        summary['leaking'].toString(),
                        Icons.water_damage,
                        AppTheme.errorColor,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Warnings',
                        summary['warning'].toString(),
                        Icons.warning_amber,
                        AppTheme.warningColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildSummaryCard(
                        'Normal',
                        summary['normal'].toString(),
                        Icons.check_circle,
                        AppTheme.successColor,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Disabled',
                        summary['disabled'].toString(),
                        Icons.do_not_disturb,
                        Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Search and filter
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search devices...',
                        prefixIcon: const Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: _searchDevices,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.filter_list),
                    tooltip: 'Filter by group',
                    onSelected: _changeDeviceGroup,
                    itemBuilder:
                        (context) => [
                          ..._deviceGroups.keys.map(
                            (group) => PopupMenuItem(
                              value: group,
                              child: Row(
                                children: [
                                  Icon(
                                    group == _selectedGroup
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color:
                                        group == _selectedGroup
                                            ? AppTheme.primaryColor
                                            : Colors.grey,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(group),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${_deviceGroups[group]?.length ?? 0})',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Device selector
            Container(
              decoration: AppTheme.cardDecoration,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Device', style: AppTheme.subheadingStyle),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryColor.withAlpha(50),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedDevice,
                        isExpanded: true,
                        icon: Icon(
                          Icons.arrow_drop_down_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        items:
                            _filteredDeviceIds
                                .map(
                                  (device) => DropdownMenuItem(
                                    value: device,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _getDeviceColor(device),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          deviceLabels[device] ?? device,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedDevice = value!;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main status card
            Container(
              decoration: AppTheme.cardDecoration,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: deviceColor.withAlpha(20),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        deviceLabels[selectedDevice]!,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: deviceColor,
                        ),
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        isLoading
                            ? Center(
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Loading flow data...'),
                                ],
                              ),
                            )
                            : Column(
                              children: [
                                // Flow rate display
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.infoColor.withAlpha(20),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.water_drop_rounded,
                                        size: 40,
                                        color: AppTheme.infoColor,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current Flow Rate',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.secondaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              flow,
                                              style: const TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const Text(
                                              ' L/min',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // Status display
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: statusColor.withAlpha(50),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        status.contains('✅')
                                            ? Icons.check_circle_outline_rounded
                                            : status.contains('⚠️')
                                            ? Icons.warning_amber_rounded
                                            : Icons.error_outline_rounded,
                                        color: statusColor,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        status,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Last updated: $time',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Valve status
                                _buildValveStatus(selectedDevice),
                              ],
                            ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Flow history
            if (_flowHistory.containsKey(selectedDevice) &&
                _flowHistory[selectedDevice]!.isNotEmpty)
              _buildFlowHistoryCard(selectedDevice),

            // Leak history
            if (_leakHistory.containsKey(selectedDevice) &&
                _leakHistory[selectedDevice]!.isNotEmpty)
              _buildLeakHistoryCard(selectedDevice),
          ],
        ),
      ),
    );
  }

  Widget _buildValveStatus(String deviceId) {
    final isOpen = _valveStates[deviceId] ?? false;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isOpen ? AppTheme.successColor : AppTheme.errorColor)
                .withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isOpen ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Valve Status: ${isOpen ? 'Open' : 'Closed'}',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
          ),
        ),
      ],
    );
  }

  Widget _buildFlowHistoryCard(String deviceId) {
    final history = _flowHistory[deviceId]!;
    final times = _timeHistory[deviceId]!;

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Flow History', style: AppTheme.subheadingStyle),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.separated(
              itemCount: history.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reversedIndex = history.length - 1 - index;
                final flow = history[reversedIndex];
                final time = times[reversedIndex];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: flow > 0 ? AppTheme.infoColor : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${flow.toStringAsFixed(2)} L/min',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeakHistoryCard(String deviceId) {
    final history = _leakHistory[deviceId]!;

    // Filter out manual switch events and sort by timestamp (newest first)
    final leakEvents =
        history.where((event) {
          final reason = event['reason'] as String;
          return !reason.toLowerCase().contains('manual switch triggered');
        }).toList();

    leakEvents.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Leak Detection History',
                style: AppTheme.subheadingStyle,
              ),
              if (leakEvents.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _leakHistory[deviceId]!.clear();
                    });
                  },
                  child: const Text('Clear History'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          leakEvents.isEmpty
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No leak events detected',
                    style: TextStyle(color: AppTheme.secondaryTextColor),
                  ),
                ),
              )
              : SizedBox(
                height: 250,
                child: ListView.separated(
                  itemCount: leakEvents.length,
                  separatorBuilder:
                      (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final leak = leakEvents[index];
                    final reason = leak['reason'] as String;
                    final flow = leak['flow'] as double;
                    final time = leak['time'] as String;
                    final date = leak['date'] as String;
                    final valveState = leak['valve_state'] as bool;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor.withAlpha(20),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.water_damage,
                                  color: AppTheme.errorColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reason,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Flow: ${flow.toStringAsFixed(2)} L/min | Valve: ${valveState ? 'Open' : 'Closed'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              '$date at $time',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        ],
      ),
    );
  }

  Color _getDeviceColor(String deviceId) {
    return AppTheme.getDeviceColor(deviceId);
  }

  Future<void> _openRecipientsManager() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => _EmailRecipientsDialog(
            initialRecipients: List<String>.from(_emailRecipients),
            onRecipientsChanged: (newRecipients) {
              if (mounted) {
                setState(() {
                  _emailRecipients = newRecipients;
                });
              }
            },
            onSave: _saveRecipientsToFirebase,
            isValidEmail: _isValidEmail,
          ),
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Future<void> _saveRecipientsToFirebase() async {
    try {
      final ref = FirebaseDatabase.instance.ref('email_settings/recipients');
      final unique = _emailRecipients.toSet().toList();
      await ref.set(unique);
    } catch (e) {
      debugPrint('Error saving recipients: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save recipients: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _EmailRecipientsDialog extends StatefulWidget {
  final List<String> initialRecipients;
  final Function(List<String>) onRecipientsChanged;
  final Future<void> Function() onSave;
  final bool Function(String) isValidEmail;

  const _EmailRecipientsDialog({
    required this.initialRecipients,
    required this.onRecipientsChanged,
    required this.onSave,
    required this.isValidEmail,
  });

  @override
  State<_EmailRecipientsDialog> createState() => _EmailRecipientsDialogState();
}

class _EmailRecipientsDialogState extends State<_EmailRecipientsDialog> {
  late TextEditingController _addEmailController;
  late List<String> _recipients;

  @override
  void initState() {
    super.initState();
    _addEmailController = TextEditingController();
    _recipients = List<String>.from(widget.initialRecipients);
  }

  @override
  void dispose() {
    _addEmailController.dispose();
    super.dispose();
  }

  Future<void> _addEmail() async {
    final email = _addEmailController.text.trim();
    if (email.isEmpty) return;

    if (!widget.isValidEmail(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid email'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!_recipients.contains(email)) {
      setState(() {
        _recipients.add(email);
      });
      widget.onRecipientsChanged(_recipients);
      await widget.onSave();
      _addEmailController.clear();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email already exists'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _removeEmail(int index) async {
    setState(() {
      _recipients.removeAt(index);
    });
    widget.onRecipientsChanged(_recipients);
    await widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Email Recipients'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _addEmailController,
                decoration: const InputDecoration(
                  labelText: 'Add email',
                  hintText: 'name@example.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _addEmail(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addEmail,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_recipients.length} configured'),
                ],
              ),
              const SizedBox(height: 12),
              if (_recipients.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    'No recipients yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _recipients.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final email = _recipients[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        leading: const Icon(Icons.email_outlined, size: 20),
                        title: Text(
                          email,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () => _removeEmail(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}

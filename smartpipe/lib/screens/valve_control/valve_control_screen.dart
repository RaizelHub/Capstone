import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/device_management_service.dart';
import '../../services/emergency_auth_service.dart';

class ValveControlScreen extends StatefulWidget {
  const ValveControlScreen({super.key});

  @override
  State<ValveControlScreen> createState() => _ValveControlScreenState();
}

class _ValveControlScreenState extends State<ValveControlScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final DeviceManagementService _deviceService = DeviceManagementService();
  final EmergencyAuthService _emergencyAuth = EmergencyAuthService();

  List<String> _deviceIds = [];
  final Map<String, bool> _valveStates = {};
  final Map<String, bool> _emergencyOverrideStates = {};
  Map<String, String> _deviceLabels = {};

  // Device grouping and filtering
  String _filterQuery = '';
  String _selectedGroup = 'All Devices';
  List<String> _filteredDeviceIds = [];
  Map<String, List<String>> _deviceGroups = {'All Devices': []};

  // Valve operation history
  final Map<String, List<Map<String, dynamic>>> _valveHistory = {};

  // Scheduled operations
  final List<Map<String, dynamic>> _scheduledOperations = [];

  // Flow monitoring for valve control alerts
  final Map<String, double> _flowRates = {};
  final Map<String, String> _flowAlerts = {};
  final Map<String, DateTime> _lastValveStateChange = {};

  // Loading states for valve operations
  final Map<String, bool> _valveLoadingStates = {};

  @override
  void initState() {
    super.initState();
    _loadDevicesAndInitializeValveStates();

    // Listen for device changes
    _deviceService.addListener(_onDevicesChanged);
  }

  @override
  void dispose() {
    _deviceService.removeListener(_onDevicesChanged);
    super.dispose();
  }

  void _onDevicesChanged() {
    setState(() {
      _updateDeviceInfo();
      _updateDeviceGroups();
      _filterDevices();
    });
  }

  void _updateDeviceInfo() {
    _deviceIds = _deviceService.deviceIds;
    _deviceLabels = _deviceService.deviceLabels;

    // Initialize loading states for new devices
    for (final deviceId in _deviceIds) {
      if (!_valveLoadingStates.containsKey(deviceId)) {
        _valveLoadingStates[deviceId] = false;
      }
    }
  }

  // Group devices by location/building
  void _updateDeviceGroups() {
    // Reset groups
    _deviceGroups = {'All Devices': _deviceIds};

    // Group by building/location (extract from device label if possible)
    final buildingGroups = <String, List<String>>{};

    for (final deviceId in _deviceIds) {
      final label = _deviceLabels[deviceId] ?? deviceId;

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
    final devicesInGroup = _deviceGroups[_selectedGroup] ?? _deviceIds;

    // Apply search filter if query is not empty
    if (query.isEmpty) {
      _filteredDeviceIds = List.from(devicesInGroup);
    } else {
      _filteredDeviceIds =
          devicesInGroup.where((deviceId) {
            final label =
                _deviceLabels[deviceId]?.toLowerCase() ??
                deviceId.toLowerCase();
            return label.contains(query) ||
                deviceId.toLowerCase().contains(query);
          }).toList();
    }
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

  // Record valve operation in history
  void _recordValveOperation(String deviceId, bool newState) {
    final now = DateTime.now();
    final formattedTime = DateFormat('hh:mm a').format(now);
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);

    // Initialize history list if needed
    _valveHistory[deviceId] ??= [];

    // Add operation to history
    _valveHistory[deviceId]!.add({
      'timestamp': now.millisecondsSinceEpoch,
      'state': newState ? 'ON' : 'OFF',
      'time': formattedTime,
      'date': formattedDate,
    });

    // Keep history limited to last 20 events
    if (_valveHistory[deviceId]!.length > 20) {
      _valveHistory[deviceId]!.removeAt(0);
    }
  }

  Future<void> _loadDevicesAndInitializeValveStates() async {
    // Wait for device service to be initialized
    await _deviceService.initialize();

    // Get device information
    setState(() {
      _updateDeviceInfo();
      _updateDeviceGroups();
      _filterDevices();
    });

    // Initialize valve states and history for all devices
    for (String deviceId in _deviceIds) {
      // Initialize valve history
      _valveHistory[deviceId] = [];

      // Initialize loading state
      _valveLoadingStates[deviceId] = false;

      // Get current valve state
      final snapshot = await _dbRef.child('control/$deviceId/relay').get();
      final status = snapshot.exists ? snapshot.value.toString() : 'OFF';

      if (mounted) {
        setState(() {
          _valveStates[deviceId] = status == 'ON';
        });
      }

      // Set up listener for this device's relay state
      _setupDeviceRelayListener(deviceId);

      // Set up flow monitoring for valve control alerts
      _setupFlowMonitoring(deviceId);
    }
  }

  // Listen for changes to a device's relay state
  void _setupDeviceRelayListener(String deviceId) {
    _dbRef.child('control/$deviceId/relay').onValue.listen((event) {
      if (event.snapshot.exists) {
        final status = event.snapshot.value.toString();

        // Handle normal ON/OFF states and emergency override
        if (mounted) {
          setState(() {
            if (status == 'EMERGENCY_OFF') {
              _valveStates[deviceId] = false;
              _emergencyOverrideStates[deviceId] = true;
            } else if (status == 'ON' || status == 'OFF') {
              _valveStates[deviceId] = status == 'ON';
              _emergencyOverrideStates[deviceId] = false;
            }
          });
        }
      }
    });

    // Also listen for emergency override status changes
    _dbRef.child('control/$deviceId/emergency_override').onValue.listen((
      event,
    ) {
      if (mounted) {
        setState(() {
          _emergencyOverrideStates[deviceId] = event.snapshot.value == true;
        });
      }
    });
  }

  // Set up flow monitoring for valve control alerts
  void _setupFlowMonitoring(String deviceId) {
    // Listen to flow data for this device
    _dbRef.child('readings/$deviceId/data').limitToLast(1).onChildAdded.listen((
      event,
    ) {
      if (event.snapshot.value is Map) {
        final data = event.snapshot.value as Map;
        // Check for flowRate (new field name) first, then fall back to flow (backward compatibility)
        final flowValue = data['flowRate'] ?? data['flow'];
        final flow = double.tryParse(flowValue?.toString() ?? '0') ?? 0.0;

        // Update flow rate
        _flowRates[deviceId] = flow;

        // Check for valve control alerts
        _checkValveControlAlert(deviceId, flow);
      }
    });

    // Track valve state changes for timing
    _dbRef.child('control/$deviceId/relay').onValue.listen((event) {
      if (event.snapshot.exists) {
        final status = event.snapshot.value.toString();
        final isValveOpen = status == 'ON';
        final wasValveOpen = _valveStates[deviceId] ?? false;

        // Record valve state change time
        if (isValveOpen != wasValveOpen) {
          _lastValveStateChange[deviceId] = DateTime.now();
        }
      }
    });
  }

  // Check for valve control specific alerts
  void _checkValveControlAlert(String deviceId, double flow) {
    final isValveOpen = _valveStates[deviceId] ?? false;
    final lastChange = _lastValveStateChange[deviceId];
    final previousAlert = _flowAlerts[deviceId] ?? '';

    String alert = '';

    if (isValveOpen && flow < 0.01 && lastChange != null) {
      final timeSinceChange = DateTime.now().difference(lastChange);

      // Alert if valve is ON but no flow for more than 30 seconds
      if (timeSinceChange.inSeconds > 30) {
        alert = '⚠️ Manual switch triggered or no water';

        // Send notification if this is a new alert
        if (previousAlert != alert) {
          _sendValveControlNotification(deviceId, alert);
        }
      }
    }

    if (mounted) {
      setState(() {
        _flowAlerts[deviceId] = alert;
      });
    }
  }

  // Show dialog for inactive devices
  void _showInactiveDeviceDialog(String deviceId) {
    final deviceName = _deviceLabels[deviceId] ?? deviceId;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.warningColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text('Device Inactive'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cannot control valve for $deviceName',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This device is currently inactive and cannot be controlled. Please contact an administrator to activate the device.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Send notification for valve control alerts
  Future<void> _sendValveControlNotification(
    String deviceId,
    String alert,
  ) async {
    final deviceName = _deviceLabels[deviceId] ?? deviceId;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await _dbRef.child('notifications').push().set({
      'title': 'Valve Control Alert',
      'message': '$deviceName: $alert - Check manual switch or water supply',
      'timestamp': timestamp,
      'read': false,
      'type': 'valve_control',
      'device_id': deviceId,
      'device_name': deviceName,
      'alert_type': 'no_flow_valve_on',
    });
  }

  Future<void> _toggleValve(String deviceId) async {
    // Check if device is active
    if (!_deviceService.isDeviceActive(deviceId)) {
      _showInactiveDeviceDialog(deviceId);
      return;
    }

    // Check if device is in emergency override
    if (_emergencyOverrideStates[deviceId] == true) {
      _showEmergencyOverrideDialog(deviceId);
      return;
    }

    // Set loading state
    setState(() {
      _valveLoadingStates[deviceId] = true;
    });

    try {
      final newState = !_valveStates[deviceId]!;
      setState(() {
        _valveStates[deviceId] = newState;
      });

      final stateText = newState ? 'ON' : 'OFF';
      await _dbRef.child('control/$deviceId/relay').set(stateText);

      final friendlyName = _deviceLabels[deviceId] ?? deviceId;
      final time = DateFormat('hh:mm a').format(DateTime.now());

      // Record operation in history
      _recordValveOperation(deviceId, newState);

      await _sendNotification(
        'Valve Changed: $friendlyName',
        '$friendlyName turned $stateText at $time',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$friendlyName turned $stateText'),
            backgroundColor:
                newState ? AppTheme.successColor : AppTheme.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Add 5-second delay for loading state
      await Future.delayed(const Duration(seconds: 5));
    } catch (e) {
      // Revert state on error
      setState(() {
        _valveStates[deviceId] = !_valveStates[deviceId]!;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle valve: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // Clear loading state
      if (mounted) {
        setState(() {
          _valveLoadingStates[deviceId] = false;
        });
      }
    }
  }

  // Schedule a valve operation for the future (hours only)
  Future<void> _scheduleValveOperation(
    String deviceId,
    bool targetState,
    DateTime scheduledTime,
  ) async {
    final friendlyName = _deviceLabels[deviceId] ?? deviceId;
    final formattedTime = DateFormat('hh:mm a').format(scheduledTime);
    final isToday = scheduledTime.day == DateTime.now().day;
    final dayLabel = isToday ? 'Today' : 'Tomorrow';

    // Add to scheduled operations
    final operation = {
      'deviceId': deviceId,
      'deviceName': friendlyName,
      'targetState': targetState,
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'formattedTime': formattedTime,
      'dayLabel': dayLabel,
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    setState(() {
      _scheduledOperations.add(operation);
    });

    // Calculate delay until scheduled time
    final now = DateTime.now();
    final delay = scheduledTime.difference(now);

    if (delay.isNegative) {
      // Time is in the past, execute immediately
      await _executeScheduledOperation(operation);
    } else {
      // Schedule for future execution
      Future.delayed(delay, () async {
        await _executeScheduledOperation(operation);
      });
    }

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scheduled $friendlyName to turn ${targetState ? 'ON' : 'OFF'} at $formattedTime $dayLabel',
          ),
          backgroundColor: AppTheme.infoColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Execute a scheduled operation
  Future<void> _executeScheduledOperation(
    Map<String, dynamic> operation,
  ) async {
    final deviceId = operation['deviceId'] as String;
    final targetState = operation['targetState'] as bool;
    final deviceName = operation['deviceName'] as String;

    // Check if device still exists
    if (!_deviceIds.contains(deviceId)) {
      // Remove from scheduled operations
      if (mounted) {
        setState(() {
          _scheduledOperations.removeWhere((op) => op['id'] == operation['id']);
        });
      }
      return;
    }

    // Check if device is active
    if (!_deviceService.isDeviceActive(deviceId)) {
      // Remove from scheduled operations and show notification
      if (mounted) {
        setState(() {
          _scheduledOperations.removeWhere((op) => op['id'] == operation['id']);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scheduled operation cancelled: $deviceName is inactive',
            ),
            backgroundColor: AppTheme.warningColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Set loading state
    if (mounted) {
      setState(() {
        _valveLoadingStates[deviceId] = true;
      });
    }

    try {
      // Set valve state
      final stateText = targetState ? 'ON' : 'OFF';
      await _dbRef.child('control/$deviceId/relay').set(stateText);

      // Update local state
      if (mounted) {
        setState(() {
          _valveStates[deviceId] = targetState;
          // Remove from scheduled operations
          _scheduledOperations.removeWhere((op) => op['id'] == operation['id']);
        });
      }

      // Record operation in history
      _recordValveOperation(deviceId, targetState);

      // Send notification
      final time = DateFormat('hh:mm a').format(DateTime.now());
      await _sendNotification(
        'Scheduled Valve Operation',
        '$deviceName turned $stateText at $time (scheduled)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to execute scheduled operation: ${e.toString()}',
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // Clear loading state
      if (mounted) {
        setState(() {
          _valveLoadingStates[deviceId] = false;
        });
      }
    }
  }

  // Show valve operation history for a device
  void _showValveHistory(String deviceId) {
    final history = _valveHistory[deviceId] ?? [];
    final deviceName = _deviceLabels[deviceId] ?? deviceId;

    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No operation history for $deviceName'),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    // Sort by timestamp (newest first)
    history.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Operation History: $deviceName'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final operation = history[index];
                  final state = operation['state'] as String;
                  final time = operation['time'] as String;
                  final date = operation['date'] as String;

                  return ListTile(
                    leading: Icon(
                      state == 'ON' ? Icons.check_circle : Icons.cancel,
                      color:
                          state == 'ON'
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                    ),
                    title: Text('Turned $state'),
                    subtitle: Text('$date at $time'),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
    );
  }

  Future<void> _sendNotification(String title, String subtitle) async {
    final DatabaseReference notifRef = _dbRef.child('notifications');
    await notifRef.push().set({'title': title, 'subtitle': subtitle});
  }

  // Show emergency override dialog when device is in emergency state
  void _showEmergencyOverrideDialog(String deviceId) {
    final deviceName = _deviceLabels[deviceId] ?? deviceId;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text(
                'EMERGENCY OVERRIDE ACTIVE',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device: $deviceName',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'This valve is currently under emergency override and cannot be operated normally.',
              ),
              SizedBox(height: 16),
              Text(
                'Available actions:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('• Clear emergency override (requires authorization)'),
              Text('• View emergency override details'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('CLOSE'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEmergencyOverrideDetails(deviceId);
              },
              child: Text('VIEW DETAILS'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearEmergencyOverride(deviceId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('CLEAR OVERRIDE'),
            ),
          ],
        );
      },
    );
  }

  // Show emergency override details
  Future<void> _showEmergencyOverrideDetails(String deviceId) async {
    final details = await _deviceService.getEmergencyOverrideDetails(deviceId);
    final deviceName = _deviceLabels[deviceId] ?? deviceId;

    if (!mounted) return;

    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No emergency override details found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Emergency Override Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device: $deviceName',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('Reason: ${details['reason'] ?? 'Not specified'}'),
              SizedBox(height: 8),
              Text('Authorized by: ${details['authorized_by'] ?? 'Unknown'}'),
              SizedBox(height: 8),
              Text('Activated at: ${details['timestamp'] ?? 'Unknown'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  // Clear emergency override with authorization
  Future<void> _clearEmergencyOverride(String deviceId) async {
    final authorizedPerson = await _emergencyAuth.showEmergencyAuthDialog(
      context,
    );

    if (!mounted) return;

    if (authorizedPerson != null) {
      final success = await _deviceService.clearEmergencyOverride(
        deviceId,
        authorizedPerson,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency override cleared successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear emergency override'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Activate emergency override
  Future<void> _activateEmergencyOverride(String deviceId) async {
    final deviceName = _deviceLabels[deviceId] ?? deviceId;
    String? reason;

    // First, get the reason for emergency override
    final reasonResult = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Emergency Override Reason'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please specify the reason for emergency override of $deviceName:',
              ),
              SizedBox(height: 16),
              TextField(
                onChanged: (value) => reason = value,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Water leak detected, Safety concern, etc.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(reason),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('CONTINUE'),
            ),
          ],
        );
      },
    );

    if (reasonResult != null && reasonResult.isNotEmpty) {
      if (!mounted) return;

      // Then get authorization
      final authorizedPerson = await _emergencyAuth.showEmergencyAuthDialog(
        context,
      );

      if (authorizedPerson != null) {
        // Set loading state
        setState(() {
          _valveLoadingStates[deviceId] = true;
        });

        try {
          final success = await _deviceService.emergencyOverrideValve(
            deviceId,
            reasonResult,
            authorizedPerson,
          );

          if (!mounted) return;

          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Emergency override activated for $deviceName'),
                backgroundColor: Colors.red,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to activate emergency override'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error activating emergency override: ${e.toString()}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        } finally {
          // Clear loading state
          if (mounted) {
            setState(() {
              _valveLoadingStates[deviceId] = false;
            });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Valve Control',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        actions: [
          // Schedule button
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Scheduled operations',
            onPressed: () {
              _showScheduledOperations();
            },
          ),
          // Filter button
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter devices',
            onPressed: () {
              _showFilterDialog();
            },
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh valve status',
            onPressed: _loadDevicesAndInitializeValveStates,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _loadDevicesAndInitializeValveStates,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8),
                  ],
                ),
                margin: const EdgeInsets.only(bottom: 20),
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

              // Group indicator
              if (_selectedGroup != 'All Devices')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primaryColor.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Filtered: $_selectedGroup',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedGroup = 'All Devices';
                            _filterDevices();
                          });
                        },
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

              _buildControlPanel(),
              const SizedBox(height: 24),
              Expanded(
                child:
                    _filteredDeviceIds.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.devices_rounded,
                                size: 64,
                                color: Colors.grey.withAlpha(100),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No devices found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try changing your search or filter',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        )
                        : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _filteredDeviceIds.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final deviceId = _filteredDeviceIds[index];
                            return _buildValveControlCard(deviceId);
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show filter dialog
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Filter Devices'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView(
                children: [
                  const Text(
                    'Select Group:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._deviceGroups.keys.map(
                    (group) => ListTile(
                      title: Text(group),
                      trailing: Text(
                        '(${_deviceGroups[group]?.length ?? 0})',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      selected: group == _selectedGroup,
                      selectedTileColor: AppTheme.primaryColor.withAlpha(20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _changeDeviceGroup(group);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
            ],
          ),
    );
  }

  // Show scheduled operations dialog
  void _showScheduledOperations() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Scheduled Operations'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child:
                  _scheduledOperations.isEmpty
                      ? const Center(child: Text('No scheduled operations'))
                      : ListView.separated(
                        itemCount: _scheduledOperations.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final operation = _scheduledOperations[index];
                          final deviceName = operation['deviceName'] as String;
                          final targetState = operation['targetState'] as bool;
                          final formattedTime =
                              operation['formattedTime'] as String;
                          final dayLabel =
                              operation['dayLabel'] as String? ?? 'Today';

                          return ListTile(
                            leading: Icon(
                              targetState ? Icons.check_circle : Icons.cancel,
                              color:
                                  targetState
                                      ? AppTheme.successColor
                                      : AppTheme.errorColor,
                            ),
                            title: Text(
                              '$deviceName: Turn ${targetState ? 'ON' : 'OFF'}',
                            ),
                            subtitle: Text(
                              'Scheduled for $formattedTime $dayLabel',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() {
                                  _scheduledOperations.removeAt(index);
                                });
                                Navigator.pop(context);
                                _showScheduledOperations();
                              },
                            ),
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showScheduleOperationDialog();
                },
                child: const Text('ADD NEW'),
              ),
            ],
          ),
    );
  }

  // Show dialog to schedule a new operation (hours only)
  void _showScheduleOperationDialog() {
    String selectedDeviceId =
        _filteredDeviceIds.isNotEmpty
            ? _filteredDeviceIds[0]
            : (_deviceIds.isNotEmpty ? _deviceIds[0] : '');
    bool targetState = true;
    // Default to next hour
    final now = DateTime.now();
    DateTime scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour + 1,
      0,
    );

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Schedule Valve Operation'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Device selector
                      const Text('Select Device:'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedDeviceId,
                            items:
                                (_filteredDeviceIds.isNotEmpty
                                        ? _filteredDeviceIds
                                        : _deviceIds)
                                    .map(
                                      (deviceId) => DropdownMenuItem(
                                        value: deviceId,
                                        child: Text(
                                          _deviceLabels[deviceId] ?? deviceId,
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  selectedDeviceId = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Target state
                      const Text('Target State:'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('ON'),
                              value: true,
                              groupValue: targetState,
                              onChanged: (value) {
                                setState(() {
                                  targetState = value!;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('OFF'),
                              value: false,
                              groupValue: targetState,
                              onChanged: (value) {
                                setState(() {
                                  targetState = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Time picker (hours only)
                      const Text('Schedule Time (Today/Tomorrow):'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.dividerColor,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('hh:mm a').format(scheduledTime),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    scheduledTime.day == DateTime.now().day
                                        ? 'Today'
                                        : 'Tomorrow',
                                    style: AppTheme.captionStyle,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _selectHoursOnly(scheduledTime).then((
                                  newDateTime,
                                ) {
                                  if (newDateTime != null && mounted) {
                                    setState(() {
                                      scheduledTime = newDateTime;
                                    });
                                  }
                                });
                              },
                              child: const Text('CHANGE'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _scheduleValveOperation(
                          selectedDeviceId,
                          targetState,
                          scheduledTime,
                        );
                      },
                      child: const Text('SCHEDULE'),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor.withAlpha(15), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.settings_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'System Controls',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        subtitle: const Text(
          'Control system settings',
          style: TextStyle(fontSize: 12, color: AppTheme.secondaryTextColor),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                // Schedule operations button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showScheduleOperationDialog,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Schedule Operation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Show device count
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Text(
              'Currently managing ${_filteredDeviceIds.isEmpty ? _deviceIds.length : _filteredDeviceIds.length} device(s) in $_selectedGroup',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryTextColor,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValveControlCard(String deviceId) {
    final isOpen = _valveStates[deviceId] ?? false;
    final isEmergencyOverride = _emergencyOverrideStates[deviceId] ?? false;
    final deviceIndex = _deviceIds.indexOf(deviceId) + 1;
    final friendlyName = _deviceLabels[deviceId] ?? 'Smart Device $deviceIndex';
    final deviceColor = _getDeviceColor(deviceId);
    final bool isDeviceActive = _deviceService.isDeviceActive(deviceId);
    final bool canTriggerEmergencyOverride =
        isDeviceActive && isOpen && !isEmergencyOverride;
    final String emergencyTooltip =
        !isDeviceActive
            ? 'Emergency override disabled: device inactive'
            : !isOpen
                ? 'Emergency override disabled: valve is closed'
                : isEmergencyOverride
                    ? 'Emergency override already active'
                    : 'Activate emergency override';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              isEmergencyOverride
                  ? Colors.red.withAlpha(100)
                  : deviceColor.withAlpha(50),
          width: isEmergencyOverride ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header with device name
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: deviceColor.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.water, color: deviceColor, size: 20),
            ),
            title: Text(
              friendlyName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              'Smart Water Control Device',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryTextColor,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Device status indicator
                Container(
                  constraints: const BoxConstraints(maxWidth: 60),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _deviceService.isDeviceActive(deviceId)
                            ? AppTheme.successColor.withAlpha(30)
                            : Colors.grey.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _deviceService.isDeviceActive(deviceId)
                        ? 'ACTIVE'
                        : 'INACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color:
                          _deviceService.isDeviceActive(deviceId)
                              ? AppTheme.successColor
                              : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                // Valve status indicator
                Container(
                  constraints: const BoxConstraints(maxWidth: 60),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isEmergencyOverride
                            ? Colors.red.withAlpha(30)
                            : isOpen
                            ? AppTheme.successColor.withAlpha(30)
                            : AppTheme.errorColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isEmergencyOverride
                        ? 'EMRG'
                        : isOpen
                        ? 'OPEN'
                        : 'CLOSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color:
                          isEmergencyOverride
                              ? Colors.red
                              : isOpen
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Flow indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: isOpen ? 1.0 : 0.0,
                backgroundColor: Colors.grey.withAlpha(30),
                color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
                minHeight: 8,
              ),
            ),
          ),

          // Status and control row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isOpen
                            ? AppTheme.successColor
                            : AppTheme.errorColor)
                        .withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOpen ? Icons.power_rounded : Icons.power_off_rounded,
                    size: 20,
                    color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                ),
                const SizedBox(width: 12),
                // Status text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Valve Status',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                      Text(
                        isEmergencyOverride
                            ? 'Emergency Override'
                            : isOpen
                            ? 'Water Flowing'
                            : 'No Flow',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color:
                              isEmergencyOverride
                                  ? Colors.red
                                  : isOpen
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                        ),
                      ),
                      // Add flow alert if present
                      if (_flowAlerts[deviceId]?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.warningColor.withAlpha(50),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 12,
                                color: AppTheme.warningColor,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _flowAlerts[deviceId]!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.warningColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Control button
                Flexible(
                  child: ElevatedButton.icon(
                    onPressed:
                        _valveLoadingStates[deviceId] == true ||
                                !_deviceService.isDeviceActive(deviceId)
                            ? null
                            : () => _toggleValve(deviceId),
                    icon:
                        _valveLoadingStates[deviceId] == true
                            ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : !_deviceService.isDeviceActive(deviceId)
                            ? Icon(Icons.block_rounded, size: 16)
                            : Icon(
                              isOpen
                                  ? Icons.close_rounded
                                  : Icons.check_rounded,
                              size: 16,
                            ),
                    label: Text(
                      _valveLoadingStates[deviceId] == true
                          ? 'Turning...'
                          : !_deviceService.isDeviceActive(deviceId)
                          ? 'Inactive'
                          : (isOpen ? 'Close' : 'Open'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          !_deviceService.isDeviceActive(deviceId)
                              ? Colors.grey
                              : isOpen
                              ? AppTheme.errorColor
                              : AppTheme.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: Row(
              children: [
                // Emergency override button
                Expanded(
                  flex: 2,
                  child: Tooltip(
                    message: emergencyTooltip,
                    child: TextButton.icon(
                      onPressed:
                          canTriggerEmergencyOverride
                              ? () => _activateEmergencyOverride(deviceId)
                              : null,
                      icon: const Icon(Icons.emergency, size: 16),
                      label: const Text('Emergency'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        disabledForegroundColor: Colors.grey.withAlpha(160),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // History button
                Expanded(
                  flex: 2,
                  child: TextButton.icon(
                    onPressed: () => _showValveHistory(deviceId),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('History'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.secondaryTextColor,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Schedule button
                Expanded(
                  flex: 2,
                  child: TextButton.icon(
                    onPressed: () {
                      _showScheduleOperationDialog();
                    },
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('Schedule'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
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
    return AppTheme.getDeviceColor(deviceId);
  }

  // Helper method to select hours only (no date/month selection)
  Future<DateTime?> _selectHoursOnly(DateTime initialDate) async {
    // Only show time picker for hours selection
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      helpText: 'Select time for today',
    );

    if (time == null || !mounted) return null;

    // Combine with today's date only
    final now = DateTime.now();
    final selectedDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If the selected time is in the past, schedule for tomorrow
    if (selectedDateTime.isBefore(now)) {
      return selectedDateTime.add(const Duration(days: 1));
    }

    return selectedDateTime;
  }
}

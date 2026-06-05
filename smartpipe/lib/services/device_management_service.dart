import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Service to manage devices in the SmartPipe app
class DeviceManagementService {
  // Singleton instance
  static final DeviceManagementService _instance =
      DeviceManagementService._internal();
  factory DeviceManagementService() => _instance;
  DeviceManagementService._internal();

  // Firebase reference
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Device data
  final Map<String, DeviceInfo> _devices = {};
  final List<String> _deviceIds = [];

  // Device status tracking
  final Map<String, bool> _deviceStatuses =
      {}; // true = active, false = inactive

  // Stream controllers for device updates
  final List<Function()> _listeners = [];

  // Initialization status
  bool _isInitialized = false;

  /// Initialize the service and start listening for device updates
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadDevices();
    await _loadDeviceStatuses();
    _setupDeviceListener();
    _setupDeviceStatusListener();

    _isInitialized = true;
  }

  /// Load all devices from Firebase
  Future<void> _loadDevices() async {
    try {
      // Get devices from readings section
      final readingsSnapshot = await _dbRef.child('readings').get();
      if (readingsSnapshot.exists) {
        final readingsData = readingsSnapshot.value as Map<dynamic, dynamic>;

        // Process each device
        readingsData.forEach((key, value) {
          final deviceId = key.toString();
          final deviceData = value as Map<dynamic, dynamic>;

          // Extract device info
          final name = deviceData['name']?.toString() ?? deviceId;
          final building =
              deviceData['building']?.toString() ?? 'Unknown Building';
          final targetNumber =
              deviceData['target_number']?.toString() ?? "+639999999999";

          // Add to devices map
          _devices[deviceId] = DeviceInfo(
            id: deviceId,
            name: name,
            building: building,
            targetNumber: targetNumber,
          );

          // Add to device IDs list if not already present
          if (!_deviceIds.contains(deviceId)) {
            _deviceIds.add(deviceId);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }
  }

  /// Load device statuses from Firebase
  Future<void> _loadDeviceStatuses() async {
    try {
      // Get device statuses from control section
      final controlSnapshot = await _dbRef.child('control').get();
      if (controlSnapshot.exists) {
        final controlData = controlSnapshot.value as Map<dynamic, dynamic>;

        controlData.forEach((key, value) {
          final deviceId = key.toString();
          final deviceData = value as Map<dynamic, dynamic>;

          // Check status field from control section
          // status can be "active" or "inactive" (string)
          // Default to active if status is not set or empty
          final status = deviceData['status']?.toString().toLowerCase();
          _deviceStatuses[deviceId] =
              status == null || status.isEmpty ? true : status == 'active';
        });
      }
    } catch (e) {
      debugPrint('Error loading device statuses: $e');
    }
  }

  /// Set up listener for device status changes
  void _setupDeviceStatusListener() {
    // Listen for new devices added to control section
    _dbRef.child('control').onChildAdded.listen((event) {
      final deviceId = event.snapshot.key;
      if (deviceId == null) return;

      final deviceData = event.snapshot.value as Map<dynamic, dynamic>?;
      if (deviceData == null) return;

      // Update device status from control section
      // Default to active if status is not set
      final status = deviceData['status']?.toString().toLowerCase();
      _deviceStatuses[deviceId] =
          status == null || status.isEmpty ? true : status == 'active';

      _notifyListeners();
    });

    // Listen for changes in device status in control section
    _dbRef.child('control').onChildChanged.listen((event) {
      final deviceId = event.snapshot.key;
      if (deviceId == null) return;

      final deviceData = event.snapshot.value as Map<dynamic, dynamic>?;
      if (deviceData == null) return;

      // Update device status from control section
      final status = deviceData['status']?.toString().toLowerCase();
      _deviceStatuses[deviceId] =
          status == null || status.isEmpty ? true : status == 'active';

      _notifyListeners();
    });

    // Also listen for changes in the status field specifically
    _dbRef.child('control').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final deviceId = key.toString();
          final deviceData = value as Map<dynamic, dynamic>;
          final status = deviceData['status']?.toString().toLowerCase();
          // Default to active if status is not set
          _deviceStatuses[deviceId] =
              status == null || status.isEmpty ? true : status == 'active';
        });
        _notifyListeners();
      }
    });
  }

  /// Set up listener for device changes
  void _setupDeviceListener() {
    // Listen for changes in the readings section
    _dbRef.child('readings').onChildAdded.listen((event) {
      final deviceId = event.snapshot.key;
      if (deviceId == null) return;

      // Get device data
      final deviceData = event.snapshot.value as Map<dynamic, dynamic>?;
      if (deviceData == null) return;

      // Extract device info
      final name = deviceData['name']?.toString() ?? deviceId;
      final building = deviceData['building']?.toString() ?? 'Unknown Building';
      final targetNumber =
          deviceData['target_number']?.toString() ?? "+639999999999";

      // Add to devices map
      _devices[deviceId] = DeviceInfo(
        id: deviceId,
        name: name,
        building: building,
        targetNumber: targetNumber,
      );

      // Add to device IDs list if not already present
      if (!_deviceIds.contains(deviceId)) {
        _deviceIds.add(deviceId);
        _notifyListeners();
      }
    });

    // Listen for changes in device data
    _dbRef.child('readings').onChildChanged.listen((event) {
      final deviceId = event.snapshot.key;
      if (deviceId == null) return;

      // Get device data
      final deviceData = event.snapshot.value as Map<dynamic, dynamic>?;
      if (deviceData == null) return;

      // Extract device info
      final name = deviceData['name']?.toString() ?? deviceId;
      final building = deviceData['building']?.toString() ?? 'Unknown Building';
      final targetNumber =
          deviceData['target_number']?.toString() ?? "+639999999999";

      // Update device info
      _devices[deviceId] = DeviceInfo(
        id: deviceId,
        name: name,
        building: building,
        targetNumber: targetNumber,
      );

      _notifyListeners();
    });

    // Listen for device removal
    _dbRef.child('readings').onChildRemoved.listen((event) {
      final deviceId = event.snapshot.key;
      if (deviceId == null) return;

      // Remove from devices map
      _devices.remove(deviceId);

      // Remove from device IDs list
      _deviceIds.remove(deviceId);

      _notifyListeners();
    });
  }

  /// Get a list of all device IDs
  List<String> get deviceIds => List.unmodifiable(_deviceIds);

  /// Get a map of device IDs to device labels
  Map<String, String> get deviceLabels {
    final Map<String, String> labels = {};
    _devices.forEach((id, info) {
      labels[id] = info.name;
    });
    return labels;
  }

  /// Get a friendly device name with fallback
  String getFriendlyDeviceName(String deviceId) {
    final deviceInfo = _devices[deviceId];
    if (deviceInfo != null &&
        deviceInfo.name.isNotEmpty &&
        deviceInfo.name != deviceId) {
      return deviceInfo.name;
    }

    // Generate a friendly fallback name
    final deviceIndex = _deviceIds.indexOf(deviceId);
    if (deviceIndex >= 0) {
      return 'Smart Device ${deviceIndex + 1}';
    }

    // Last resort fallback
    return 'Smart Device';
  }

  /// Get a map of device IDs to building names
  Map<String, String> get deviceBuildings {
    final Map<String, String> buildings = {};
    _devices.forEach((id, info) {
      buildings[id] = info.building;
    });
    return buildings;
  }

  /// Get information about a specific device
  DeviceInfo? getDeviceInfo(String deviceId) {
    return _devices[deviceId];
  }

  /// Check if a device is active
  bool isDeviceActive(String deviceId) {
    // If device status is not loaded yet, default to active for new devices
    if (!_deviceStatuses.containsKey(deviceId)) {
      // Default to active for new devices that haven't been loaded yet
      // This allows new devices to be controlled immediately
      return true;
    }
    // Return the stored status, defaulting to active if null
    return _deviceStatuses[deviceId] ?? true;
  }

  /// Check if a device is active (async version that checks Firebase if needed)
  Future<bool> isDeviceActiveAsync(String deviceId) async {
    // If we have the status cached, return it
    if (_deviceStatuses.containsKey(deviceId)) {
      return _deviceStatuses[deviceId] ?? true;
    }

    // Otherwise, check Firebase directly
    try {
      final snapshot = await _dbRef.child('control/$deviceId/status').get();
      if (snapshot.exists) {
        final status = snapshot.value?.toString().toLowerCase();
        final isActive = status == null || status.isEmpty || status == 'active';
        _deviceStatuses[deviceId] = isActive;
        return isActive;
      }
      // If status doesn't exist, default to active
      _deviceStatuses[deviceId] = true;
      return true;
    } catch (e) {
      debugPrint('Error checking device status: $e');
      // Default to active on error
      return true;
    }
  }

  /// Get all device statuses
  Map<String, bool> get deviceStatuses => Map.unmodifiable(_deviceStatuses);

  /// Update device status (active/inactive)
  Future<bool> updateDeviceStatus(String deviceId, bool isActive) async {
    try {
      await _dbRef.child('readings/$deviceId').update({
        'isActive': isActive,
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Update local status
      _deviceStatuses[deviceId] = isActive;

      // Send notification about status change
      await _dbRef.child('notifications').push().set({
        'title': 'Device Status Changed',
        'message':
            '${_devices[deviceId]?.name ?? deviceId} is now ${isActive ? 'ACTIVE' : 'INACTIVE'}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'read': false,
        'type': 'device_status',
        'device_id': deviceId,
        'priority': isActive ? 'normal' : 'high',
      });

      _notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating device status: $e');
      return false;
    }
  }

  /// Register a new device with proper data structure
  Future<bool> registerDevice(
    String deviceId,
    String deviceName,
    String buildingName,
    String targetNumber,
  ) async {
    try {
      final now = DateTime.now();
      final timestamp =
          now.millisecondsSinceEpoch ~/ 1000; // Unix timestamp in seconds

      // Register device in readings with the updated structure
      await _dbRef.child('readings/$deviceId').set({
        'name': deviceName,
        'building': buildingName,
        'target_number': targetNumber,
        'registeredAt': now.toIso8601String(),
        'flowRate': 0,
        'lastReading': now.toIso8601String(),
        'isActive': true, // New devices start as active
      });

      // Add initial data points in the data node
      final dataRef = _dbRef.child('readings/$deviceId/data');

      // Generate unique keys for each data point
      final point1Ref = dataRef.push();
      final point2Ref = dataRef.push();
      final point3Ref = dataRef.push();

      // Set data for each point (water quality data will be added when sensors provide readings)
      await point1Ref.set({
        'flow': 0,
        'timestamp': timestamp - 600, // 10 minutes ago
      });

      await point2Ref.set({
        'flow': 0,
        'timestamp': timestamp - 300, // 5 minutes ago
      });

      await point3Ref.set({
        'flow': 0,
        'timestamp': timestamp, // now
      });

      // Register device in control
      await _dbRef.child('control/$deviceId').set({
        'name': deviceName,
        'building': buildingName,
        'target_number': targetNumber,
        'registeredAt': now.toIso8601String(),
        'relay': 'OFF',
        'valve': 'closed',
        'isActive': true, // New devices start as active
        'lastUpdated': now.toIso8601String(),
      });

      // Update local status
      _deviceStatuses[deviceId] = true;

      return true;
    } catch (e) {
      debugPrint('Error registering device: $e');
      return false;
    }
  }

  /// Add a listener for device updates
  void addListener(Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners of a change
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Emergency override a valve (force close for safety)
  Future<bool> emergencyOverrideValve(
    String deviceId,
    String reason,
    String authorizedBy,
  ) async {
    try {
      final now = DateTime.now();

      // Set valve to emergency override state
      await _dbRef.child('control/$deviceId').update({
        'relay': 'EMERGENCY_OFF',
        'emergency_override': true,
        'emergency_reason': reason,
        'emergency_authorized_by': authorizedBy,
        'emergency_timestamp': now.toIso8601String(),
        'lastUpdated': now.toIso8601String(),
      });

      // Log the emergency action
      await _dbRef.child('emergency_logs').push().set({
        'device_id': deviceId,
        'action': 'emergency_override',
        'reason': reason,
        'authorized_by': authorizedBy,
        'timestamp': now.toIso8601String(),
        'unix_timestamp': now.millisecondsSinceEpoch,
      });

      // Send emergency notification
      await _dbRef.child('notifications').push().set({
        'title': 'EMERGENCY OVERRIDE ACTIVATED',
        'message':
            'Emergency override activated for ${_devices[deviceId]?.name ?? deviceId}. Reason: $reason',
        'timestamp': now.millisecondsSinceEpoch,
        'read': false,
        'type': 'emergency',
        'device_id': deviceId,
        'priority': 'critical',
      });

      return true;
    } catch (e) {
      debugPrint('Error during emergency override: $e');
      return false;
    }
  }

  /// Clear emergency override (requires authorization)
  Future<bool> clearEmergencyOverride(
    String deviceId,
    String authorizedBy,
  ) async {
    try {
      final now = DateTime.now();

      // Clear emergency override state
      await _dbRef.child('control/$deviceId').update({
        'relay': 'OFF',
        'emergency_override': false,
        'emergency_cleared_by': authorizedBy,
        'emergency_cleared_timestamp': now.toIso8601String(),
        'lastUpdated': now.toIso8601String(),
      });

      // Log the clearance action
      await _dbRef.child('emergency_logs').push().set({
        'device_id': deviceId,
        'action': 'emergency_override_cleared',
        'authorized_by': authorizedBy,
        'timestamp': now.toIso8601String(),
        'unix_timestamp': now.millisecondsSinceEpoch,
      });

      // Send clearance notification
      await _dbRef.child('notifications').push().set({
        'title': 'Emergency Override Cleared',
        'message':
            'Emergency override cleared for ${_devices[deviceId]?.name ?? deviceId} by $authorizedBy',
        'timestamp': now.millisecondsSinceEpoch,
        'read': false,
        'type': 'emergency_cleared',
        'device_id': deviceId,
        'priority': 'high',
      });

      return true;
    } catch (e) {
      debugPrint('Error clearing emergency override: $e');
      return false;
    }
  }

  /// Check if a device is in emergency override state
  Future<bool> isInEmergencyOverride(String deviceId) async {
    try {
      final snapshot =
          await _dbRef.child('control/$deviceId/emergency_override').get();
      return snapshot.exists && snapshot.value == true;
    } catch (e) {
      debugPrint('Error checking emergency override status: $e');
      return false;
    }
  }

  /// Get emergency override details for a device
  Future<Map<String, dynamic>?> getEmergencyOverrideDetails(
    String deviceId,
  ) async {
    try {
      final snapshot = await _dbRef.child('control/$deviceId').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        if (data['emergency_override'] == true) {
          return {
            'reason': data['emergency_reason'],
            'authorized_by': data['emergency_authorized_by'],
            'timestamp': data['emergency_timestamp'],
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting emergency override details: $e');
      return null;
    }
  }

  /// Dispose the service
  void dispose() {
    _listeners.clear();
  }
}

/// Class to hold device information
class DeviceInfo {
  final String id;
  final String name;
  final String building;
  final String targetNumber;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.building,
    this.targetNumber = "+639999999999",
  });
}

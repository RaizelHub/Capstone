import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../theme/app_theme.dart';
import '../../services/device_management_service.dart';

class ManualActivitiesScreen extends StatefulWidget {
  const ManualActivitiesScreen({super.key});

  @override
  State<ManualActivitiesScreen> createState() => _ManualActivitiesScreenState();
}

class _ManualActivitiesScreenState extends State<ManualActivitiesScreen> {
  final DeviceManagementService _deviceService = DeviceManagementService();
  List<String> deviceIds = [];
  String selectedDevice = '';
  final Map<String, List<Map<String, dynamic>>> _manualActivities = {};
  final Map<String, DatabaseReference> _manualActivitiesRefs = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeManualActivities();
  }

  Future<void> _initializeManualActivities() async {
    // Initialize device service and load devices
    await _deviceService.initialize();

    setState(() {
      deviceIds = _deviceService.deviceIds;
      if (deviceIds.isNotEmpty) {
        selectedDevice = deviceIds.first;
      }
    });

    for (final deviceId in deviceIds) {
      _manualActivities[deviceId] = [];
      _manualActivitiesRefs[deviceId] = FirebaseDatabase.instance
          .ref()
          .child('readings')
          .child(deviceId)
          .child('manual-activities');
    }
    _loadManualActivities();
  }

  Future<void> _loadManualActivities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      for (final deviceId in deviceIds) {
        _listenToManualActivities(deviceId);
      }
    } catch (e) {
      debugPrint('Error loading manual activities: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _listenToManualActivities(String deviceId) {
    debugPrint('🔍 Setting up manual activities listener for $deviceId');

    _manualActivitiesRefs[deviceId]!
        .once()
        .then((snapshot) {
          debugPrint('📊 Initial manual activities check for $deviceId:');
          debugPrint('   - Path exists: ${snapshot.snapshot.exists}');
          debugPrint(
            '   - Has children: ${snapshot.snapshot.children.isNotEmpty}',
          );

          if (snapshot.snapshot.exists) {
            final data = snapshot.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              final activities = <Map<String, dynamic>>[];
              for (final entry in data.entries) {
                if (entry.value is Map) {
                  final activity = Map<String, dynamic>.from(
                    entry.value as Map,
                  );
                  activity['key'] = entry.key;
                  activities.add(activity);
                }
              }

              // Sort by timestamp (newest first)
              activities.sort((a, b) {
                final timestampA = a['timestamp'] ?? 0;
                final timestampB = b['timestamp'] ?? 0;
                return timestampB.compareTo(timestampA);
              });

              setState(() {
                _manualActivities[deviceId] = activities;
              });

              debugPrint(
                '📊 Loaded ${activities.length} manual activities for $deviceId',
              );
            }
          }
        })
        .catchError((error) {
          debugPrint('❌ Error checking initial manual activities: $error');
        });

    // Listen for new manual activities
    _manualActivitiesRefs[deviceId]!.onChildAdded.listen(
      (event) {
        debugPrint(
          '📨 New manual activity received for $deviceId: ${event.snapshot.key}',
        );
        final activity = Map<String, dynamic>.from(event.snapshot.value as Map);
        activity['key'] = event.snapshot.key;

        if (mounted) {
          setState(() {
            _manualActivities[deviceId]!.insert(0, activity);
          });
        }
      },
      onError: (error) {
        debugPrint('❌ Error in manual activities listener: $error');
      },
    );
  }

  Future<void> _clearManualActivities(String deviceId) async {
    try {
      await _manualActivitiesRefs[deviceId]!.remove();
      setState(() {
        _manualActivities[deviceId]!.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Manual activities cleared for ${_deviceService.deviceLabels[deviceId] ?? deviceId}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error clearing manual activities: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing manual activities: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Manual Activities'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device selector
                    Container(
                      decoration: AppTheme.cardDecoration,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.devices,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Select Device:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedDevice,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items:
                                  deviceIds
                                      .map(
                                        (deviceId) => DropdownMenuItem(
                                          value: deviceId,
                                          child: Text(
                                            _deviceService
                                                    .deviceLabels[deviceId] ??
                                                deviceId,
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Manual activities history
                    _buildManualActivitiesCard(),
                  ],
                ),
              ),
    );
  }

  Widget _buildManualActivitiesCard() {
    final activities = _manualActivities[selectedDevice] ?? [];

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Manual Activities History - ${_deviceService.deviceLabels[selectedDevice] ?? selectedDevice}',
                style: AppTheme.subheadingStyle,
              ),
              if (activities.isNotEmpty)
                TextButton(
                  onPressed: () => _clearManualActivities(selectedDevice),
                  child: const Text('Clear History'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          activities.isEmpty
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No manual activities recorded',
                    style: TextStyle(color: AppTheme.secondaryTextColor),
                  ),
                ),
              )
              : SizedBox(
                height: 400,
                child: ListView.separated(
                  itemCount: activities.length,
                  separatorBuilder:
                      (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final activity = activities[index];
                    final reason = activity['reason'] as String? ?? 'Unknown';
                    final flow = (activity['flow'] as num?)?.toDouble() ?? 0.0;
                    final time = activity['time'] as String? ?? '--:--';
                    final date = activity['date'] as String? ?? '--';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: 14,
                                      color: AppTheme.secondaryTextColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$time • $date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Icon(
                                      Icons.water_drop,
                                      size: 14,
                                      color: AppTheme.secondaryTextColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${flow.toStringAsFixed(2)} L/min',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryTextColor,
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
                  },
                ),
              ),
        ],
      ),
    );
  }
}

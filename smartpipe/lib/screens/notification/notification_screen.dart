import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final DatabaseReference _notifRef = FirebaseDatabase.instance.ref(
    'notifications',
  );

  // Updated notification model to include timestamp and type
  List<Map<String, dynamic>> notifications = [];
  Map<String, List<Map<String, dynamic>>> groupedNotifications = {};

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() {
    _notifRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final List<Map<String, dynamic>> loaded = [];
        data.forEach((key, value) {
          final map = value as Map;
          // Extract timestamp or use current time as fallback
          int timestamp = 0;
          if (map['timestamp'] != null) {
            timestamp =
                map['timestamp'] is int
                    ? map['timestamp']
                    : int.tryParse(map['timestamp'].toString()) ??
                        DateTime.now().millisecondsSinceEpoch;
          } else {
            timestamp = DateTime.now().millisecondsSinceEpoch;
          }

          loaded.add({
            'id': key,
            'title': map['title'] ?? 'No Title',
            'subtitle': map['subtitle'] ?? map['message'] ?? 'No Details',
            'timestamp': timestamp,
            'type': map['type'] ?? 'general',
            'read': map['read'] ?? false,
          });
        });

        // Sort by timestamp (newest first)
        loaded.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        // Group notifications by date
        final grouped = _groupNotifications(loaded);

        setState(() {
          notifications = loaded;
          groupedNotifications = grouped;
        });
      }
    });
  }

  // Group notifications by type instead of date for better organization
  Map<String, List<Map<String, dynamic>>> _groupNotifications(
    List<Map<String, dynamic>> notifs,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {
      'Emergency': [],
      'Leak Alerts': [],
      'Valve Operations': [],
      'System Reports': [],
      'Water Quality': [],
      'General': [],
    };

    for (final notification in notifs) {
      final type = notification['type']?.toString().toLowerCase() ?? 'general';

      switch (type) {
        case 'emergency':
        case 'emergency_cleared':
          grouped['Emergency']!.add(notification);
          break;
        case 'leak':
          grouped['Leak Alerts']!.add(notification);
          break;
        case 'valve':
          grouped['Valve Operations']!.add(notification);
          break;
        case 'report':
        case 'system':
          grouped['System Reports']!.add(notification);
          break;
        case 'quality':
          grouped['Water Quality']!.add(notification);
          break;
        default:
          grouped['General']!.add(notification);
          break;
      }
    }

    // Sort notifications within each group by timestamp (newest first)
    grouped.forEach((key, value) {
      value.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    });

    // Remove empty groups
    grouped.removeWhere((key, value) => value.isEmpty);

    return grouped;
  }

  // Get appropriate icon for notification type
  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'report':
        return Icons.assessment;
      case 'valve':
        return Icons.power;
      case 'leak':
        return Icons.water_damage;
      case 'quality':
        return Icons.water_drop;
      case 'system':
        return Icons.settings;
      default:
        return Icons.notifications;
    }
  }

  // Get color for notification type
  Color _getNotificationColor(String type) {
    switch (type.toLowerCase()) {
      case 'report':
        return AppTheme.infoColor;
      case 'valve':
        return AppTheme.primaryColor;
      case 'leak':
        return AppTheme.errorColor;
      case 'quality':
        return AppTheme.warningColor;
      case 'system':
        return AppTheme.secondaryColor;
      default:
        return AppTheme.accentColor;
    }
  }

  // Format timestamp to readable date/time
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final notificationDate = DateTime(date.year, date.month, date.day);

    if (notificationDate.isAtSameMomentAs(today)) {
      return 'Today at ${DateFormat('h:mm a').format(date)}';
    } else if (notificationDate.isAtSameMomentAs(yesterday)) {
      return 'Yesterday at ${DateFormat('h:mm a').format(date)}';
    } else {
      return DateFormat('MMM d, y • h:mm a').format(date);
    }
  }

  // Get section color based on notification type
  Color _getSectionColor(String sectionTitle) {
    switch (sectionTitle) {
      case 'Emergency':
        return AppTheme.errorColor;
      case 'Leak Alerts':
        return AppTheme.warningColor;
      case 'Valve Operations':
        return AppTheme.primaryColor;
      case 'System Reports':
        return AppTheme.successColor;
      case 'Water Quality':
        return AppTheme.secondaryColor;
      case 'General':
      default:
        return AppTheme.secondaryTextColor;
    }
  }

  // Get section icon based on notification type
  IconData _getSectionIcon(String sectionTitle) {
    switch (sectionTitle) {
      case 'Emergency':
        return Icons.emergency;
      case 'Leak Alerts':
        return Icons.water_damage;
      case 'Valve Operations':
        return Icons.power_settings_new;
      case 'System Reports':
        return Icons.assessment;
      case 'Water Quality':
        return Icons.water_drop;
      case 'General':
      default:
        return Icons.notifications;
    }
  }

  // Mark a notification as read
  Future<void> _markAsRead(String notificationId) async {
    await _notifRef.child(notificationId).update({'read': true});
  }

  // Mark all notifications as read
  Future<void> _markAllAsRead() async {
    for (final notification in notifications) {
      if (notification['read'] == false) {
        await _notifRef.child(notification['id']).update({'read': true});
      }
    }
  }

  // Clear all notifications
  Future<void> _clearAllNotifications() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear All Notifications'),
            content: const Text(
              'Are you sure you want to delete all notifications? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('CLEAR ALL'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _notifRef.remove();
      setState(() {
        notifications.clear();
        groupedNotifications.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Count unread notifications
    final unreadCount = notifications.where((n) => n['read'] == false).length;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Text("Notifications"),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unreadCount',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.mark_email_read),
              tooltip: 'Mark all as read',
              onPressed: () {
                _markAllAsRead();
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all notifications',
            onPressed: () {
              _clearAllNotifications();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _loadNotifications();
            },
          ),
        ],
      ),
      body:
          notifications.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You\'ll see notifications about your system here',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: () async {
                  _loadNotifications();
                },
                color: AppTheme.primaryColor,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: groupedNotifications.length,
                  itemBuilder: (context, sectionIndex) {
                    final sectionTitle = groupedNotifications.keys.elementAt(
                      sectionIndex,
                    );
                    final sectionNotifications =
                        groupedNotifications[sectionTitle]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Enhanced section header with icon and count
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getSectionColor(sectionTitle).withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getSectionColor(
                                sectionTitle,
                              ).withAlpha(50),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getSectionIcon(sectionTitle),
                                color: _getSectionColor(sectionTitle),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                sectionTitle,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _getSectionColor(sectionTitle),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getSectionColor(sectionTitle),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${sectionNotifications.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ListView.separated(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: sectionNotifications.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final notification = sectionNotifications[index];
                            final notificationType =
                                notification['type'] as String;
                            final notificationColor = _getNotificationColor(
                              notificationType,
                            );
                            final notificationIcon = _getNotificationIcon(
                              notificationType,
                            );
                            final timestamp = notification['timestamp'] as int;
                            final formattedTime = _formatTimestamp(timestamp);

                            final bool isRead = notification['read'] as bool;
                            final String notificationId =
                                notification['id'] as String;

                            return Container(
                              decoration: BoxDecoration(
                                color: isRead ? Colors.white : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(
                                      13,
                                    ), // ~0.05 opacity
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border:
                                    isRead
                                        ? null
                                        : Border.all(
                                          color: notificationColor.withAlpha(
                                            100,
                                          ),
                                          width: 1.5,
                                        ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () async {
                                    // Mark as read when tapped
                                    if (!isRead) {
                                      await _markAsRead(notificationId);
                                    }
                                  },
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: notificationColor
                                                    .withAlpha(25),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                notificationIcon,
                                                size: 24,
                                                color: notificationColor,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    notification['title']!,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          isRead
                                                              ? FontWeight
                                                                  .normal
                                                              : FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    notification['subtitle']!,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color:
                                                          AppTheme
                                                              .secondaryTextColor,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    formattedTime,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[500],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Unread indicator
                                      if (!isRead)
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: notificationColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),

                                      // Delete button
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: Colors.grey[400],
                                          ),
                                          onPressed: () async {
                                            await _notifRef
                                                .child(notificationId)
                                                .remove();
                                            _loadNotifications();
                                          },
                                          tooltip: 'Delete notification',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
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
                      ],
                    );
                  },
                ),
              ),
    );
  }
}

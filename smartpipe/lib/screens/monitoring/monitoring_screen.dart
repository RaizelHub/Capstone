import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../water_quality/water_quality_screen.dart';
import '../water_leakage/water_leakage_screen.dart';
import '../manual_activities/manual_activities_screen.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Custom tab bar with better styling
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: AppTheme.secondaryTextColor,
              indicatorColor: AppTheme.primaryColor,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 16,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.water_drop), text: 'Water Quality'),
                Tab(icon: Icon(Icons.water_damage), text: 'Leak Detection'),
                Tab(icon: Icon(Icons.engineering), text: 'Manual Activities'),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                WaterQualityScreen(),
                WaterLeakageScreen(),
                ManualActivitiesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

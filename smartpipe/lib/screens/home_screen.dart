import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dashboard/dashboard_screen.dart';
import 'valve_control/valve_control_screen.dart';
import 'monitoring/monitoring_screen.dart';
import 'reports/reports_screen.dart';
import '../services/water_consumption_service.dart';
import '../services/device_management_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final WaterConsumptionService _consumptionService = WaterConsumptionService();
  final DeviceManagementService _deviceService = DeviceManagementService();

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ValveControlScreen(),
    const MonitoringScreen(), // Combined water quality and leakage
    const ReportsScreen(), // Combined consumption and notifications
  ];

  final List<String> _titles = ['Dashboard', 'Control', 'Monitor', 'Reports'];

  @override
  void initState() {
    super.initState();
    // Initialize services
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize the water consumption service
    await _consumptionService.initialize();

    // Initialize the device management service
    await _deviceService.initialize();
  }

  @override
  void dispose() {
    _consumptionService.dispose();
    _deviceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.secondaryTextColor,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.power_settings_new),
            label: 'Control',
            
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart),
            label: 'Monitor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}

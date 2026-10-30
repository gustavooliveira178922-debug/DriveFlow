import 'package:flutter/material.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/auth/login_screen.dart';
import 'theme.dart';

class DriveFlowApp extends StatefulWidget {
  const DriveFlowApp({super.key});

  @override
  State<DriveFlowApp> createState() => _DriveFlowAppState();
}

class _DriveFlowAppState extends State<DriveFlowApp> {
  bool _connected = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DriveFlow',
        debugShowCheckedModeBanner: false,
        theme: DriveFlowTheme.dark,
        home: _connected
            ? DashboardScreen(onDisconnect: () => setState(() => _connected = false))
            : LoginScreen(onConnected: () => setState(() => _connected = true)),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_demo_mode.dart';
import '../providers/app_provider.dart';
import '../screens/calibration_wizard_screen.dart';
import '../screens/home_screen.dart';
import '../screens/standby_screen.dart';

/// 根据演示模式与校准状态路由首页
class DemoModeRouter extends StatefulWidget {
  const DemoModeRouter({super.key});

  @override
  State<DemoModeRouter> createState() => _DemoModeRouterState();
}

class _DemoModeRouterState extends State<DemoModeRouter> {
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _waitForSettings());
  }

  Future<void> _waitForSettings() async {
    await context.read<AppProvider>().waitForSettingsLoaded();
    if (mounted) {
      setState(() => _settingsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (!provider.calibrationCompleted) {
          return const CalibrationWizardScreen();
        }

        if (provider.demoModeEnabled && provider.demoMode == DemoMode.standby) {
          return const StandbyScreen();
        }
        return const HomeScreen();
      },
    );
  }
}

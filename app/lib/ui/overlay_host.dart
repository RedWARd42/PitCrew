// Single wiring point for the overlay engine (runs inside the accessibility service's FlutterEngine).
import 'package:flutter/widgets.dart';
import '../core/bridge.dart';
import '../core/controller.dart';
import '../overlay/overlay.dart';

Widget buildOverlayApp() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SwarmController(bridge: MethodChannelBridge());
  controller.start();
  return SwarmOverlay(state: controller);
}

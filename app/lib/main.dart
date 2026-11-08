import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/overlay_host.dart';

void main() => runApp(const SwarmApp());

/// Entrypoint of the transparent overlay engine (runs inside the accessibility service).
@pragma('vm:entry-point')
void overlayMain() => runApp(buildOverlayApp());

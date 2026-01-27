import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

void main() {
  usePathUrlStrategy(); // Use HTML5 path-based routing instead of hash
  runApp(const RepubAdminApp());
}

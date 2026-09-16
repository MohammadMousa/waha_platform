import 'package:flutter/material.dart';

/// Lets background listeners (e.g. GeideaUsbActivityLogger) show a SnackBar
/// from outside any particular screen's own BuildContext — passed to
/// MaterialApp.scaffoldMessengerKey in main.dart.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

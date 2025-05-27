import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:provider/provider.dart';

import 'package:flutter_hbb/desktop/pages/remote_terminal_tab_page.dart';

class DesktopRemoteTerminalScreen extends StatelessWidget {
  final Map<String, dynamic> params;

  const DesktopRemoteTerminalScreen({Key? key, required this.params})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.ffiModel),
      ],
      child: Scaffold(
        backgroundColor: isLinux ? Colors.transparent : null,
        body: RemoteTerminalTabPage(
          params: params,
        ),
      ),
    );
  }
}

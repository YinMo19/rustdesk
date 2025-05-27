import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:get/get.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class RemoteTerminalPage extends StatefulWidget {
  const RemoteTerminalPage({
    Key? key,
    required this.id,
    required this.password,
    required this.tabController,
    required this.isSharedPassword,
    this.forceRelay,
    this.connToken,
  }) : super(key: key);
  final String id;
  final String? password;
  final DesktopTabController tabController;
  final bool? forceRelay;
  final bool? isSharedPassword;
  final String? connToken;

  @override
  State<RemoteTerminalPage> createState() => _RemoteTerminalPageState();
}

class _RemoteTerminalPageState extends State<RemoteTerminalPage>
    with AutomaticKeepAliveClientMixin {
  late Terminal terminal;
  late TerminalController terminalController;
  late Pty? pty;
  late FFI _ffi;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    terminalController = TerminalController();
    _ffi = FFI(null);
    _ffi.start(widget.id,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay,
        connToken: widget.connToken);
    Get.put<FFI>(_ffi, tag: 'terminal_${widget.id}');

    // 初始化终端连接
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController.onSelected?.call(widget.id);
      _startRemoteTerminal();
    });
  }

  void _startRemoteTerminal() {
    // TODO: 实现与远程终端的连接
    // 这里应该调用 Rust 后端建立终端会话
    // 暂时使用本地终端作为示例
    if (Platform.isWindows) {
      pty = Pty.start('cmd.exe',
          columns: terminal.viewWidth, rows: terminal.viewHeight);
    } else {
      pty = Pty.start(Platform.environment['SHELL'] ?? 'bash',
          columns: terminal.viewWidth, rows: terminal.viewHeight);
    }

    pty!.output
        .cast<List<int>>()
        .transform(Utf8Decoder())
        .listen(terminal.write);

    pty!.exitCode.then((code) {
      terminal.write('\n进程退出，代码: $code');
    });

    terminal.onOutput = (data) {
      pty!.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty!.resize(h, w);
    };
  }

  @override
  void dispose() {
    pty?.kill();
    _ffi.close();
    _ffi.dialogManager.dismissAll();
    Get.delete<FFI>(tag: 'terminal_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          border: Border.all(
            width: 20,
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
        child: TerminalView(
          terminal,
          controller: terminalController,
          autofocus: true,
          backgroundOpacity: 0.7,
          onSecondaryTapDown: (details, offset) async {
            final selection = terminalController.selection;
            if (selection != null) {
              final text = terminal.buffer.getText(selection);
              terminalController.clearSelection();
              await Clipboard.setData(ClipboardData(text: text));
            } else {
              final data = await Clipboard.getData('text/plain');
              final text = data?.text;
              if (text != null) {
                terminal.paste(text);
              }
            }
          },
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

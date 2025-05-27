import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter_pty/flutter_pty.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../models/model.dart';
import 'dart:convert';
import 'dart:io';

class TerminalPage extends StatefulWidget {
  TerminalPage({
    Key? key,
    required this.id,
    this.password,
    this.isSharedPassword,
  }) : super(key: key);

  final String id;
  final String? password;
  final bool? isSharedPassword;

  @override
  State<TerminalPage> createState() => _TerminalPageState(id);
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _showBar = !isWebDesktop;
  Orientation? _currentOrientation;

  final _blockableOverlayState = BlockableOverlayState();
  final FocusNode _focusNode = FocusNode();

  late Terminal terminal;
  late TerminalController terminalController;
  late FFI _ffi;

  _TerminalPageState(String id) {
    initSharedStates(id);
    _ffi = FFI(null);
    _ffi.start(widget.id,
        password: widget.password, isSharedPassword: widget.isSharedPassword);
    Get.put<FFI>(_ffi, tag: 'terminal_${widget.id}');
  }

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    terminalController = TerminalController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });

    if (!isWeb) {
      WakelockPlus.enable();
    }

    _focusNode.requestFocus();
    _blockableOverlayState.applyFfi(_ffi);

    WidgetsBinding.instance.addObserver(this);
    _startRemoteTerminal();
  }

  void _startRemoteTerminal() {
    // TODO: 实现与Rust后端的终端连接
    // 这里应该调用FFI方法与Rust后端建立终端会话

    // 临时使用本地终端作为示例
    final shell = Platform.isWindows ? 'cmd.exe' : 'bash';
    final pty = Pty.start(
      shell,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    await _ffi.close();
    _timer?.cancel();
    _ffi.dialogManager.dismissAll();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    if (!isWeb) {
      await WakelockPlus.disable();
    }
    removeSharedStates(widget.id);
  }

  Widget emptyOverlay(Color bgColor) => BlockableOverlay(
        state: _blockableOverlayState,
        underlying: Container(
          color: bgColor,
        ),
      );

  Widget _bottomWidget() => (_showBar
      ? BottomAppBar(
          elevation: 10,
          color: MyTheme.accent,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      // closeConnection(sessionId, _ffi.dialogManager);
                    },
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.settings),
                    onPressed: showTerminalOptions,
                  ),
                ],
              ),
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.expand_more),
                onPressed: () {
                  setState(() => _showBar = !_showBar);
                },
              ),
            ],
          ),
        )
      : Offstage());

  void showTerminalOptions() {
    // TODO: 添加终端设置选项
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // closeConnection(sessionId, _ffi.dialogManager);
        return false;
      },
      child: Scaffold(
        floatingActionButton: !_showBar
            ? FloatingActionButton(
                mini: true,
                child: const Icon(Icons.expand_less, color: Colors.white),
                backgroundColor: MyTheme.accent,
                onPressed: () {
                  setState(() => _showBar = !_showBar);
                },
              )
            : null,
        bottomNavigationBar: Obx(() => Stack(
              alignment: Alignment.bottomCenter,
              children: [
                _bottomWidget(),
              ],
            )),
        body: Obx(
          () => Overlay(
            initialEntries: [
              OverlayEntry(builder: (context) {
                return Container(
                  color: kColorCanvas,
                  child: SafeArea(
                    child: OrientationBuilder(builder: (ctx, orientation) {
                      if (_currentOrientation != orientation) {
                        Timer(const Duration(milliseconds: 200), () {
                          _currentOrientation = orientation;
                        });
                      }
                      return Container(
                        color: MyTheme.canvasColor,
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
                              await Clipboard.setData(
                                  ClipboardData(text: text));
                            } else {
                              final data =
                                  await Clipboard.getData('text/plain');
                              final text = data?.text;
                              if (text != null) {
                                terminal.paste(text);
                              }
                            }
                          },
                        ),
                      );
                    }),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

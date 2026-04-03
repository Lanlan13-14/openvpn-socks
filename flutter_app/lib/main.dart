import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:process_run/process_run.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OVPN SOCKS5',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _ovpnPath;
  bool _running = false;
  String _status = '未连接';
  Process? _xrayProcess;

  Timer? _statusTimer;

  @override
  void dispose() {
    _statusTimer?.cancel();
    _stopXray();
    super.dispose();
  }

  Future<void> _pickOvpn() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ovpn'],
    );
    if (result != null) {
      setState(() {
        _ovpnPath = result.files.single.path;
      });
    }
  }

  String _getXrayPath() {
    if (Platform.isWindows) return path.join('xray', 'windows', 'xray.exe');
    if (Platform.isLinux) return path.join('xray', 'linux', 'xray');
    if (Platform.isMacOS) return path.join('xray', 'macos', 'xray');
    if (Platform.isAndroid) return path.join('xray', 'android', 'xray');
    throw UnsupportedError('Unsupported platform');
  }

  Future<void> _startXray() async {
    if (_ovpnPath == null) return;
    setState(() {
      _status = '启动中...';
      _running = true;
    });

    final xrayPath = _getXrayPath();

    // 启动 Xray
    _xrayProcess = await runExecutableArguments(
      xrayPath,
      ['-config', 'xray.json'],
      mode: RunMode.detached,
    );

    // 每秒检查 tun0 状态
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      bool exists = false;
      if (Platform.isLinux || Platform.isAndroid || Platform.isMacOS) {
        var result = await run('ip', ['a']);
        exists = result.stdout.toString().contains('tun0');
      }
      setState(() {
        _status = exists ? '已连接 (tun0)' : '未连接';
      });
    });
  }

  Future<void> _stopXray() async {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (_xrayProcess != null) {
      _xrayProcess!.kill();
      _xrayProcess = null;
    }
    setState(() {
      _running = false;
      _status = '未连接';
    });
  }

  void _toggle() {
    if (_running) {
      _stopXray();
    } else {
      _startXray();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OVPN SOCKS5 前置'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('选择 OVPN 配置文件'),
              onPressed: _pickOvpn,
            ),
            const SizedBox(height: 8),
            Text(
              _ovpnPath ?? '未选择文件',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _ovpnPath == null ? null : _toggle,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(32),
              ),
              child: Icon(
                _running ? Icons.stop : Icons.play_arrow,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '状态: $_status',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
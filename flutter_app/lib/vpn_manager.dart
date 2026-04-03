import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;

class VpnManager {
  Process? _vpnProcess;
  Process? _xrayProcess;
  Timer? _statusTimer;

  final StreamController<bool> _tunController = StreamController.broadcast();
  Stream<bool> get tunStatusStream => _tunController.stream;

  final String _tunInterface = 'tun0';

  /// 启动 VPN + Xray
  Future<void> start({required String ovpnPath}) async {
    final xrayPath = _getXrayPath();

    // 启动 OpenVPN（不修改默认路由）
    _vpnProcess = await Process.start(
      'openvpn',
      ['--config', ovpnPath, '--route-nopull'],
    );
    _vpnProcess!.stdout.transform(SystemEncoding().decoder).listen((e) => print('[OpenVPN] $e'));
    _vpnProcess!.stderr.transform(SystemEncoding().decoder).listen((e) => print('[OpenVPN-ERR] $e'));

    await Future.delayed(Duration(seconds: 3)); // 等待 tun0 生成

    // 写入 Xray 临时配置文件
    final configFile = File('${Directory.systemTemp.path}/xray_config.json');
    await configFile.writeAsString('''
{
  "log": {},
  "inbounds":[{"port":1080,"listen":"0.0.0.0","protocol":"socks","settings":{"udp":true}}],
  "outbounds":[{"protocol":"freedom"}]
}
''');

    // 启动 Xray
    _xrayProcess = await Process.start(xrayPath, ['-config', configFile.path]);
    _xrayProcess!.stdout.transform(SystemEncoding().decoder).listen((e) => print('[Xray] $e'));
    _xrayProcess!.stderr.transform(SystemEncoding().decoder).listen((e) => print('[Xray-ERR] $e'));

    // tun0 状态检测
    _statusTimer = Timer.periodic(Duration(seconds: 1), (_) => _checkTun());
  }

  /// 停止 VPN + Xray
  Future<void> stop() async {
    _vpnProcess?.kill(ProcessSignal.sigterm);
    _xrayProcess?.kill(ProcessSignal.sigterm);
    _statusTimer?.cancel();
    _tunController.add(false);
  }

  void _checkTun() async {
    try {
      bool isTunUp = false;
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('ip', ['a']);
        isTunUp = result.stdout.toString().contains(_tunInterface);
      } else if (Platform.isWindows) {
        final result = await Process.run('netsh', ['interface', 'show', 'interface']);
        isTunUp = result.stdout.toString().toLowerCase().contains(_tunInterface);
      }
      _tunController.add(isTunUp);
    } catch (_) {
      _tunController.add(false);
    }
  }

  String _getXrayPath() {
    if (Platform.isWindows) return path.join('xray', 'windows', 'xray.exe');
    if (Platform.isMacOS) return path.join('xray', 'macos', 'xray');
    if (Platform.isLinux) return path.join('xray', 'linux', 'xray');
    if (Platform.isAndroid) return path.join('xray', 'android', 'xray');
    throw UnsupportedError('Unsupported platform');
  }
}
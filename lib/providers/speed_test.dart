import 'dart:async';
import 'dart:io';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SpeedTestStatus {
  idle,
  testing,
  completed,
  error,
}

const speedTestTiersMB = [50, 250, 500, 1000];

class SpeedTestState {
  final SpeedTestStatus status;
  final double currentSpeed; // bytes per second
  final double peakSpeed; // bytes per second
  final double avgSpeed; // bytes per second
  final int totalBytes; // bytes downloaded
  final int targetBytes; // target bytes (e.g. 50MB, 250MB, 500MB, 1000MB)
  final int selectedTargetMB; // 50, 250, 500, 1000
  final int? pingMs; // handshake latency
  final double progress; // 0.0 ~ 1.0
  final List<double> history; // recent speed samples (bytes/s)
  final String? nodeName;
  final String? errorMessage;
  final Duration elapsed;

  const SpeedTestState({
    this.status = SpeedTestStatus.idle,
    this.currentSpeed = 0,
    this.peakSpeed = 0,
    this.avgSpeed = 0,
    this.totalBytes = 0,
    this.targetBytes = 50 * 1024 * 1024,
    this.selectedTargetMB = 50,
    this.pingMs,
    this.progress = 0,
    this.history = const [],
    this.nodeName,
    this.errorMessage,
    this.elapsed = Duration.zero,
  });

  SpeedTestState copyWith({
    SpeedTestStatus? status,
    double? currentSpeed,
    double? peakSpeed,
    double? avgSpeed,
    int? totalBytes,
    int? targetBytes,
    int? selectedTargetMB,
    int? pingMs,
    double? progress,
    List<double>? history,
    String? nodeName,
    String? errorMessage,
    Duration? elapsed,
  }) {
    return SpeedTestState(
      status: status ?? this.status,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      peakSpeed: peakSpeed ?? this.peakSpeed,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      totalBytes: totalBytes ?? this.totalBytes,
      targetBytes: targetBytes ?? this.targetBytes,
      selectedTargetMB: selectedTargetMB ?? this.selectedTargetMB,
      pingMs: pingMs ?? this.pingMs,
      progress: progress ?? this.progress,
      history: history ?? this.history,
      nodeName: nodeName ?? this.nodeName,
      errorMessage: errorMessage ?? this.errorMessage,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

final speedTestProvider =
    NotifierProvider<SpeedTestNotifier, SpeedTestState>(SpeedTestNotifier.new);

class SpeedTestNotifier extends Notifier<SpeedTestState> {
  HttpClient? _client;
  bool _isCancelled = false;

  @override
  SpeedTestState build() => const SpeedTestState();

  void setTargetMB(int mb) {
    if (state.status == SpeedTestStatus.testing) return;
    state = state.copyWith(
      selectedTargetMB: mb,
      targetBytes: mb * 1024 * 1024,
    );
  }

  Future<void> startTest() async {
    if (state.status == SpeedTestStatus.testing) return;
    _isCancelled = false;

    // Check if proxy core is started
    final isStart = ref.read(isStartProvider);
    if (!isStart) {
      state = state.copyWith(
        status: SpeedTestStatus.error,
        errorMessage: '请先启动代理连接',
      );
      return;
    }

    final mixedPort =
        ref.read(patchClashConfigProvider.select((s) => s.mixedPort));

    // Try to get current node name from visible groups
    String? currentNode;
    try {
      final groups = ref.read(visibleGroupsStateProvider).value;
      if (groups.isNotEmpty) {
        final activeGroup = groups.first;
        currentNode =
            ref.read(selectedProxyNameProvider(activeGroup.name)) ??
            activeGroup.name;
      }
    } catch (_) {}

    final targetMB = state.selectedTargetMB;
    final targetBytes = targetMB * 1024 * 1024;
    final testUrl = 'https://speed.cloudflare.com/__down?bytes=$targetBytes';

    state = SpeedTestState(
      status: SpeedTestStatus.testing,
      targetBytes: targetBytes,
      selectedTargetMB: targetMB,
      nodeName: currentNode ?? '当前代理节点',
      history: const [],
    );

    final client = HttpClient();
    _client = client;
    client.badCertificateCallback = (cert, host, port) => true;
    client.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
    client.connectionTimeout = const Duration(seconds: 8);

    final stopwatch = Stopwatch()..start();

    try {
      final pingStart = stopwatch.elapsedMilliseconds;
      final request = await client.getUrl(Uri.parse(testUrl));
      request.headers.set('User-Agent', 'ClashforWindows/0.20.39');
      final response = await request.close();
      final pingMs = stopwatch.elapsedMilliseconds - pingStart;

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      var totalDownloaded = 0;
      var sampleBytes = 0;
      var sampleStart = stopwatch.elapsedMilliseconds;
      var peakSpeed = 0.0;
      final history = <double>[];

      await for (final chunk in response) {
        if (_isCancelled) break;
        totalDownloaded += chunk.length;
        sampleBytes += chunk.length;
        final now = stopwatch.elapsedMilliseconds;
        final sampleDuration = now - sampleStart;

        if (sampleDuration >= 180) {
          final curSpeed = sampleBytes / (sampleDuration / 1000.0);
          if (curSpeed > peakSpeed) peakSpeed = curSpeed;
          history.add(curSpeed);
          if (history.length > 25) history.removeAt(0);

          final totalElapsedSec = (now - pingStart) / 1000.0;
          final avgSpeed =
              totalElapsedSec > 0 ? (totalDownloaded / totalElapsedSec) : 0.0;

          state = SpeedTestState(
            status: SpeedTestStatus.testing,
            currentSpeed: curSpeed,
            peakSpeed: peakSpeed,
            avgSpeed: avgSpeed,
            totalBytes: totalDownloaded,
            targetBytes: targetBytes,
            selectedTargetMB: targetMB,
            pingMs: pingMs,
            progress: (totalDownloaded / targetBytes).clamp(0.0, 1.0),
            history: List.unmodifiable(history),
            nodeName: currentNode ?? '当前代理节点',
            elapsed: Duration(milliseconds: now - pingStart),
          );

          sampleBytes = 0;
          sampleStart = now;
        }

        if (totalDownloaded >= targetBytes) break;
        // Cap test time according to payload: 50MB -> 12s, 250MB -> 25s, 500MB -> 45s, 1000MB -> 80s
        final maxTimeoutMs = (targetMB * 80).clamp(12000, 80000);
        if (stopwatch.elapsedMilliseconds >= maxTimeoutMs) break;
      }

      final totalElapsedSec =
          (stopwatch.elapsedMilliseconds - pingStart) / 1000.0;
      final finalAvgSpeed =
          totalElapsedSec > 0 ? (totalDownloaded / totalElapsedSec) : 0.0;

      state = SpeedTestState(
        status: SpeedTestStatus.completed,
        currentSpeed: 0,
        peakSpeed: peakSpeed,
        avgSpeed: finalAvgSpeed,
        totalBytes: totalDownloaded,
        targetBytes: targetBytes,
        selectedTargetMB: targetMB,
        pingMs: pingMs,
        progress: 1.0,
        history: List.unmodifiable(history),
        nodeName: currentNode ?? '当前代理节点',
        elapsed:
            Duration(milliseconds: stopwatch.elapsedMilliseconds - pingStart),
      );
    } catch (e) {
      if (!_isCancelled) {
        state = SpeedTestState(
          status: SpeedTestStatus.error,
          targetBytes: targetBytes,
          selectedTargetMB: targetMB,
          errorMessage: '测速异常: ${e.toString().split('\n').first}',
          nodeName: currentNode ?? '当前代理节点',
        );
      }
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  void stopTest() {
    _isCancelled = true;
    _client?.close(force: true);
    _client = null;
    if (state.status == SpeedTestStatus.testing) {
      state = state.copyWith(
        status: SpeedTestStatus.completed,
        currentSpeed: 0,
      );
    }
  }

  void reset() {
    stopTest();
    state = SpeedTestState(selectedTargetMB: state.selectedTargetMB);
  }
}

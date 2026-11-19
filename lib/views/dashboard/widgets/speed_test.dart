import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class SpeedTestCard extends ConsumerWidget {
  const SpeedTestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = DashboardDensityScope.of(context);
    final scale = DashboardDensityScope.scaleOf(context);
    final compact = density.isCompact;
    final padding = dashboardCardPadding(density);
    final state = ref.watch(speedTestProvider);
    final notifier = ref.read(speedTestProvider.notifier);
    final colorScheme = context.colorScheme;

    final isTesting = state.status == SpeedTestStatus.testing;
    final isCompleted = state.status == SpeedTestStatus.completed;
    final isError = state.status == SpeedTestStatus.error;

    // Active speed to display
    final num activeBytesPerSec = isTesting
        ? state.currentSpeed
        : (isCompleted ? state.peakSpeed : 0);
    final speedTraffic = activeBytesPerSec.traffic;
    final mbps = (activeBytesPerSec * 8 / 1000000).toStringAsFixed(1);

    return DashboardCard(
      semanticLabel: '代理测速',
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: '代理测速',
            leading: [
              if (state.nodeName != null && state.nodeName!.isNotEmpty)
                DashboardChip(
                  label: state.nodeName!,
                  tone: isTesting
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                ),
            ],
            trailing: [
              if (isTesting)
                DashboardBlock(
                  radius: DashboardCorner.tab,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  onTap: notifier.stopTest,
                  child: Row(
                    spacing: 4,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '停止',
                        style: DashboardText.label(context).copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                DashboardBlock(
                  radius: DashboardCorner.tab,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  onTap: notifier.startTest,
                  child: Row(
                    spacing: 4,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(
                        isCompleted ? AppGlyphs.refresh : AppGlyphs.bolt,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      Text(
                        isCompleted ? '重新测速' : '开始测速',
                        style: DashboardText.label(context).copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),

          // Main speed readout & metrics
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Big Speed Display
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            speedTraffic.value,
                            style: TextStyle(
                              fontSize: compact ? 28 * scale : 36 * scale,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${speedTraffic.unit}/s',
                            style: TextStyle(
                              fontSize: compact ? 12 * scale : 14 * scale,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isTesting
                            ? '实时: $mbps Mbps'
                            : (isCompleted ? '峰值: $mbps Mbps' : '真实下行带宽测试'),
                        style: DashboardText.label(context).copyWith(
                          fontSize: 11 * scale,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),

                // Metrics Badges Column
                Expanded(
                  flex: 4,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      _MetricBadge(
                        label: '延迟',
                        value: state.pingMs != null ? '${state.pingMs} ms' : '--',
                        color: state.pingMs != null && state.pingMs! < 100
                            ? const Color(0xFF4CAF50)
                            : colorScheme.onSurfaceVariant,
                      ),
                      _MetricBadge(
                        label: '峰值',
                        value: state.peakSpeed > 0
                            ? '${state.peakSpeed.traffic.value} ${state.peakSpeed.traffic.unit}/s'
                            : '--',
                        color: colorScheme.primary,
                      ),
                      _MetricBadge(
                        label: '平均',
                        value: state.avgSpeed > 0
                            ? '${state.avgSpeed.traffic.value} ${state.avgSpeed.traffic.unit}/s'
                            : '--',
                      ),
                      _MetricBadge(
                        label: '流量',
                        value: state.totalBytes > 0
                            ? '${state.totalBytes.traffic.value} MB'
                            : '0 MB',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Progress or Status Bar
          SizedBox(
            height: 18 * scale,
            child: isTesting
                ? Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: state.progress > 0 ? state.progress : null,
                            minHeight: 4,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(state.progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 10 * scale,
                          color: colorScheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : (isCompleted
                    ? Row(
                        children: [
                          GlyphIcon(
                            AppGlyphs.checkCircle,
                            size: 14 * scale,
                            color: const Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _speedRatingText(state.peakSpeed),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11 * scale,
                                color: const Color(0xFF4CAF50),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    : (isError
                        ? Text(
                            state.errorMessage ?? '测速失败',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11 * scale,
                              color: colorScheme.error,
                            ),
                          )
                        : Text(
                            '通过当前代理节点下载测速块，测试真实下行速度',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11 * scale,
                              color: colorScheme.outline,
                            ),
                          ))),
          ),
        ],
      ),
    );
  }

  static String _speedRatingText(double peakSpeedBytes) {
    if (peakSpeedBytes >= 25 * 1024 * 1024) {
      return '极速带宽 🚀 (流畅 4K/8K 视频与大文件下载)';
    } else if (peakSpeedBytes >= 10 * 1024 * 1024) {
      return '高速带宽 ⚡ (秒开 1080P/2K 流媒体)';
    } else if (peakSpeedBytes >= 2 * 1024 * 1024) {
      return '良好带宽 🌐 (满足日常流畅浏览与社交)';
    } else {
      return '普通带宽 🐢 (响应偏慢，适合基础网页)';
    }
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.outline,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color ?? colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

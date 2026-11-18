import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/config/dns.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _minRecommendedDelayTimeout = 3000;

enum EnvironmentCheckSeverity { ok, warning, error }

enum EnvironmentCheckAction {
  none,
  prepareVpn,
  openVpnSettings,
  openNetworkSettings,
  openDateTimeSettings,
  requestBatteryOptimization,
  openNotificationSettings,
  openBatterySaverSettings,
  openDataSaverSettings,
  enableVpnMode,
  openNetworkConfig,
  openProfiles,
  openDnsConfig,
  openAccessControl,
  openGeneralConfig,
}

@immutable
class EnvironmentCheckItem {
  const EnvironmentCheckItem({
    required this.title,
    required this.description,
    required this.severity,
    this.action = EnvironmentCheckAction.none,
  });

  final String title;
  final String description;
  final EnvironmentCheckSeverity severity;
  final EnvironmentCheckAction action;
}

@immutable
class EnvironmentCheckReport {
  const EnvironmentCheckReport({
    required this.systemItems,
    required this.appItems,
  });

  final List<EnvironmentCheckItem> systemItems;
  final List<EnvironmentCheckItem> appItems;

  Iterable<EnvironmentCheckItem> get allItems => [...systemItems, ...appItems];

  int get errorCount => allItems
      .where((item) => item.severity == EnvironmentCheckSeverity.error)
      .length;

  int get warningCount => allItems
      .where((item) => item.severity == EnvironmentCheckSeverity.warning)
      .length;

  int get okCount => allItems
      .where((item) => item.severity == EnvironmentCheckSeverity.ok)
      .length;
}

String _transportLabel(AppLocalizations l, String transport) =>
    switch (transport) {
      'wifi' => l.envCheckTransportWifi,
      'cellular' => l.envCheckTransportCellular,
      'ethernet' => l.envCheckTransportEthernet,
      _ => l.envCheckTransportOther,
    };

EnvironmentCheckReport evaluateAndroidEnvironment({
  required AppLocalizations localizations,
  required AndroidEnvironmentInfo? info,
  required bool? batteryOptimizationIgnored,
  required VpnProps vpnProps,
  required PatchClashConfig clashConfig,
  required int delayTestTimeout,
  required Profile? currentProfile,
  required CoreStatus coreStatus,
  required bool isFlClashRunning,
}) {
  final systemItems = <EnvironmentCheckItem>[];
  if (info != null) {
    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.envCheckVpnPermission,
        description: info.vpnPermissionGranted
            ? localizations.envCheckVpnPermissionOk
            : localizations.envCheckVpnPermissionMissing,
        severity: info.vpnPermissionGranted
            ? EnvironmentCheckSeverity.ok
            : EnvironmentCheckSeverity.error,
        action: info.vpnPermissionGranted
            ? EnvironmentCheckAction.none
            : EnvironmentCheckAction.prepareVpn,
      ),
    );

    final hasOtherVpn = info.vpnActive && !(isFlClashRunning && vpnProps.enable);
    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.envCheckVpnConflict,
        description: hasOtherVpn
            ? localizations.envCheckVpnConflictDetected
            : localizations.envCheckVpnConflictOk,
        severity: hasOtherVpn
            ? EnvironmentCheckSeverity.error
            : EnvironmentCheckSeverity.ok,
        action: hasOtherVpn
            ? EnvironmentCheckAction.openVpnSettings
            : EnvironmentCheckAction.none,
      ),
    );

    if (!info.hasNetwork) {
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckNetworkDns,
          description: localizations.envCheckNetworkOffline,
          severity: EnvironmentCheckSeverity.error,
          action: EnvironmentCheckAction.openNetworkSettings,
        ),
      );
    } else if (info.systemDnsServers.isEmpty) {
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckNetworkDns,
          description: localizations.envCheckNetworkNoDns,
          severity: EnvironmentCheckSeverity.warning,
          action: EnvironmentCheckAction.openNetworkSettings,
        ),
      );
    } else {
      final dnsPreview = info.systemDnsServers.take(2).join(', ');
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckNetworkDns,
          description: localizations.envCheckNetworkOk(
            _transportLabel(localizations, info.networkTransport),
            dnsPreview,
          ),
          severity: EnvironmentCheckSeverity.ok,
          action: EnvironmentCheckAction.openNetworkSettings,
        ),
      );
    }

    final strictPrivateDns = info.privateDnsMode == 'hostname';
    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.envCheckPrivateDns,
        description: strictPrivateDns
            ? localizations.envCheckPrivateDnsStrict(
                info.privateDnsSpecifier ?? 'DoT',
              )
            : localizations.envCheckPrivateDnsOk,
        severity: strictPrivateDns
            ? EnvironmentCheckSeverity.warning
            : EnvironmentCheckSeverity.ok,
        action: EnvironmentCheckAction.openNetworkSettings,
      ),
    );

    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.envCheckAutoTime,
        description: info.autoTimeEnabled
            ? localizations.envCheckAutoTimeOk
            : localizations.envCheckAutoTimeOff,
        severity: info.autoTimeEnabled
            ? EnvironmentCheckSeverity.ok
            : EnvironmentCheckSeverity.warning,
        action: info.autoTimeEnabled
            ? EnvironmentCheckAction.none
            : EnvironmentCheckAction.openDateTimeSettings,
      ),
    );

    final batteryOk = batteryOptimizationIgnored == true;
    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.ignoreBatteryOptimization,
        description: batteryOk
            ? localizations.envCheckBatteryOk
            : localizations.envCheckBatteryRestricted,
        severity: batteryOk
            ? EnvironmentCheckSeverity.ok
            : EnvironmentCheckSeverity.warning,
        action: batteryOk
            ? EnvironmentCheckAction.none
            : EnvironmentCheckAction.requestBatteryOptimization,
      ),
    );

    systemItems.add(
      EnvironmentCheckItem(
        title: localizations.envCheckNotification,
        description: info.notificationPermissionGranted
            ? localizations.envCheckNotificationOk
            : localizations.envCheckNotificationOff,
        severity: info.notificationPermissionGranted
            ? EnvironmentCheckSeverity.ok
            : EnvironmentCheckSeverity.warning,
        action: info.notificationPermissionGranted
            ? EnvironmentCheckAction.none
            : EnvironmentCheckAction.openNotificationSettings,
      ),
    );

    if (info.backgroundDataRestricted) {
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckPowerDataSaver,
          description: localizations.envCheckDataSaverOn,
          severity: EnvironmentCheckSeverity.warning,
          action: EnvironmentCheckAction.openDataSaverSettings,
        ),
      );
    } else if (info.powerSaveMode) {
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckPowerDataSaver,
          description: localizations.envCheckPowerSaverOn,
          severity: EnvironmentCheckSeverity.warning,
          action: EnvironmentCheckAction.openBatterySaverSettings,
        ),
      );
    } else {
      systemItems.add(
        EnvironmentCheckItem(
          title: localizations.envCheckPowerDataSaver,
          description: localizations.envCheckPowerDataSaverOk,
          severity: EnvironmentCheckSeverity.ok,
        ),
      );
    }
  }

  final dnsOverrideDisabled =
      clashConfig.dnsOverrideKeys.contains(DnsOverrideKey.enable) &&
      !clashConfig.dns.enable;
  final dnsOverrideEmptyNameserver =
      clashConfig.dnsOverrideKeys.contains(DnsOverrideKey.nameserver) &&
      clashConfig.dns.nameserver.isEmpty;
  final ipv6Enabled =
      vpnProps.ipv6 ||
      (clashConfig.generalOverrideKeys.contains(GeneralOverrideKey.ipv6) &&
          clashConfig.ipv6) ||
      (clashConfig.dnsOverrideKeys.contains(DnsOverrideKey.ipv6) &&
          clashConfig.dns.ipv6);
  final accessControl = vpnProps.accessControlProps;
  final emptyWhitelist =
      accessControl.enable &&
      accessControl.mode == AccessControlMode.acceptSelected &&
      accessControl.acceptList.isEmpty;
  final lowTimeout = delayTestTimeout < _minRecommendedDelayTimeout;

  final appItems = <EnvironmentCheckItem>[
    EnvironmentCheckItem(
      title: localizations.envCheckVpnMode,
      description: vpnProps.enable
          ? localizations.envCheckVpnModeOk
          : localizations.envCheckVpnModeOff,
      severity: vpnProps.enable
          ? EnvironmentCheckSeverity.ok
          : EnvironmentCheckSeverity.error,
      action: vpnProps.enable
          ? EnvironmentCheckAction.openNetworkConfig
          : EnvironmentCheckAction.enableVpnMode,
    ),
    if (currentProfile == null)
      EnvironmentCheckItem(
        title: localizations.envCheckProfileCore,
        description: localizations.envCheckProfileMissing,
        severity: EnvironmentCheckSeverity.error,
        action: EnvironmentCheckAction.openProfiles,
      )
    else if (coreStatus != CoreStatus.connected)
      EnvironmentCheckItem(
        title: localizations.envCheckProfileCore,
        description: localizations.envCheckCoreDisconnected(
          currentProfile.realLabel,
        ),
        severity: EnvironmentCheckSeverity.warning,
      )
    else
      EnvironmentCheckItem(
        title: localizations.envCheckProfileCore,
        description: localizations.envCheckProfileCoreOk(
          currentProfile.realLabel,
        ),
        severity: EnvironmentCheckSeverity.ok,
      ),
    EnvironmentCheckItem(
      title: localizations.envCheckDnsConfig,
      description: dnsOverrideDisabled
          ? localizations.envCheckDnsDisabled
          : dnsOverrideEmptyNameserver
          ? localizations.envCheckDnsNoNameserver
          : localizations.envCheckDnsOk,
      severity: dnsOverrideDisabled || dnsOverrideEmptyNameserver
          ? EnvironmentCheckSeverity.error
          : EnvironmentCheckSeverity.ok,
      action: EnvironmentCheckAction.openDnsConfig,
    ),
    EnvironmentCheckItem(
      title: localizations.envCheckIpv6,
      description: ipv6Enabled
          ? localizations.envCheckIpv6Enabled
          : localizations.envCheckIpv6Ok,
      severity: ipv6Enabled
          ? EnvironmentCheckSeverity.warning
          : EnvironmentCheckSeverity.ok,
      action: EnvironmentCheckAction.openNetworkConfig,
    ),
    EnvironmentCheckItem(
      title: localizations.accessControl,
      description: emptyWhitelist
          ? localizations.envCheckAccessControlEmptyWhitelist
          : accessControl.enable
          ? localizations.envCheckAccessControlActive(
              accessControl.currentList.length,
            )
          : localizations.envCheckAccessControlOk,
      severity: emptyWhitelist
          ? EnvironmentCheckSeverity.warning
          : EnvironmentCheckSeverity.ok,
      action: EnvironmentCheckAction.openAccessControl,
    ),
    EnvironmentCheckItem(
      title: localizations.delayTestTimeout,
      description: lowTimeout
          ? localizations.envCheckDelayTimeoutLow(delayTestTimeout)
          : localizations.envCheckDelayTimeoutOk(delayTestTimeout),
      severity: lowTimeout
          ? EnvironmentCheckSeverity.warning
          : EnvironmentCheckSeverity.ok,
      action: EnvironmentCheckAction.openGeneralConfig,
    ),
  ];

  return EnvironmentCheckReport(systemItems: systemItems, appItems: appItems);
}

class EnvironmentCheckView extends ConsumerStatefulWidget {
  const EnvironmentCheckView({
    super.key,
    this.environmentLoader,
    this.onPrepareVpn,
    this.onOpenSettings,
  });

  final Future<AndroidEnvironmentInfo?> Function()? environmentLoader;
  final Future<bool> Function()? onPrepareVpn;
  final Future<bool> Function(AndroidSettingsTarget target)? onOpenSettings;

  @override
  ConsumerState<EnvironmentCheckView> createState() =>
      _EnvironmentCheckViewState();
}

class _EnvironmentCheckViewState extends ConsumerState<EnvironmentCheckView> {
  late final AppLifecycleListener _lifecycle;
  AndroidEnvironmentInfo? _info;
  var _loading = true;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    unawaited(_refresh(initial: true));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    if (!initial && mounted) {
      setState(() {});
    }
    try {
      final loader = widget.environmentLoader ?? app?.getEnvironmentInfo;
      final result = loader == null ? null : await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _info = result;
        _loading = false;
      });
    } finally {
      _refreshing = false;
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSettings(AndroidSettingsTarget target) async {
    final handler = widget.onOpenSettings ?? app?.openSystemSettings;
    if (handler == null) {
      return;
    }
    await handler(target);
  }

  Future<void> _handleAction(EnvironmentCheckAction action) async {
    switch (action) {
      case EnvironmentCheckAction.none:
        return;
      case EnvironmentCheckAction.prepareVpn:
        final prepare = widget.onPrepareVpn ?? app?.prepareVpn;
        if (prepare != null) {
          await prepare();
          await _refresh();
        }
      case EnvironmentCheckAction.openVpnSettings:
        await _openSettings(AndroidSettingsTarget.vpn);
      case EnvironmentCheckAction.openNetworkSettings:
        await _openSettings(AndroidSettingsTarget.network);
      case EnvironmentCheckAction.openDateTimeSettings:
        await _openSettings(AndroidSettingsTarget.dateTime);
      case EnvironmentCheckAction.requestBatteryOptimization:
        await ref.read(batteryOptimizationIgnoredProvider.notifier).request();
        await _refresh();
      case EnvironmentCheckAction.openNotificationSettings:
        await _openSettings(AndroidSettingsTarget.notification);
      case EnvironmentCheckAction.openBatterySaverSettings:
        await _openSettings(AndroidSettingsTarget.batterySaver);
      case EnvironmentCheckAction.openDataSaverSettings:
        await _openSettings(AndroidSettingsTarget.dataSaver);
      case EnvironmentCheckAction.enableVpnMode:
        ref
            .read(vpnSettingProvider.notifier)
            .update((state) => state.copyWith(enable: true));
      case EnvironmentCheckAction.openProfiles:
        ref.read(currentPageLabelProvider.notifier).toProfiles();
        if (mounted) {
          await Navigator.of(context).maybePop();
        }
      case EnvironmentCheckAction.openNetworkConfig ||
          EnvironmentCheckAction.openDnsConfig ||
          EnvironmentCheckAction.openAccessControl ||
          EnvironmentCheckAction.openGeneralConfig:
        return;
    }
  }

  Widget? _pageFor(
    BuildContext context,
    EnvironmentCheckAction action,
  ) => switch (action) {
    EnvironmentCheckAction.openNetworkConfig => BaseScaffold(
      title: context.appLocalizations.network,
      body: const NetworkListView(),
    ),
    EnvironmentCheckAction.openDnsConfig => const DnsView(),
    EnvironmentCheckAction.openAccessControl => const AccessView(),
    EnvironmentCheckAction.openGeneralConfig => const GeneralView(),
    _ => null,
  };

  Widget _buildCheckRow(BuildContext context, EnvironmentCheckItem item) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final (glyph, color, chipColor, chipForeground, statusLabel) =
        switch (item.severity) {
          EnvironmentCheckSeverity.ok => (
            AppGlyphs.checkCircle,
            colorScheme.success,
            colorScheme.successContainer,
            colorScheme.onSuccessContainer,
            appLocalizations.envCheckStatusOk,
          ),
          EnvironmentCheckSeverity.warning => (
            AppGlyphs.warning,
            colorScheme.warning,
            colorScheme.warningContainer,
            colorScheme.onWarningContainer,
            appLocalizations.envCheckStatusWarning,
          ),
          EnvironmentCheckSeverity.error => (
            AppGlyphs.error,
            colorScheme.error,
            colorScheme.errorContainer,
            colorScheme.onErrorContainer,
            appLocalizations.error,
          ),
        };

    final chip = TonalChip(
      label: statusLabel,
      color: chipColor,
      foregroundColor: chipForeground,
    );
    final trailing = item.action == EnvironmentCheckAction.none
        ? chip
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              chip,
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          );
    final leading = GlyphIcon(glyph, color: color);
    final page = _pageFor(context, item.action);
    if (page != null) {
      return ListItem.open(
        leading: leading,
        title: Text(item.title),
        subtitle: Text(item.description),
        trailing: trailing,
        widget: page,
      );
    }
    return ListItem(
      leading: leading,
      title: Text(item.title),
      subtitle: Text(item.description),
      trailing: trailing,
      onTap: item.action == EnvironmentCheckAction.none
          ? null
          : () => unawaited(_handleAction(item.action)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final vpnProps = ref.watch(vpnSettingProvider);
    final clashConfig = ref.watch(patchClashConfigProvider);
    final delayTestTimeout = ref.watch(
      appSettingProvider.select((state) => state.delayTestTimeout),
    );
    final currentProfile = ref.watch(currentProfileProvider);
    final coreStatus = ref.watch(coreStatusProvider);
    final isFlClashRunning = ref.watch(
      runTimeProvider.select((state) => state != null),
    );
    final batteryIgnored = ref.watch(batteryOptimizationIgnoredProvider).value;

    final report = evaluateAndroidEnvironment(
      localizations: appLocalizations,
      info: _info,
      batteryOptimizationIgnored: batteryIgnored,
      vpnProps: vpnProps,
      clashConfig: clashConfig,
      delayTestTimeout: delayTestTimeout,
      currentProfile: currentProfile,
      coreStatus: coreStatus,
      isFlClashRunning: isFlClashRunning,
    );

    return Scaffold(
      title: appLocalizations.environmentCheck,
      isLoading: _refreshing,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: appLocalizations.envCheckRecheck,
          isLoading: _refreshing,
          onPressed: _refresh,
        ),
      ],
      body: NullStatusSwitcher(
        isLoading: _loading,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
            top: context.contentTopPadding,
            bottom: 24 + context.bottomInset,
          ),
          children: [
            _EnvironmentSummaryCard(
              report: report,
              info: _info,
              refreshing: _refreshing,
              onRefresh: _refresh,
            ),
            if (report.systemItems.isNotEmpty)
              generateSection(
                title: appLocalizations.envCheckSectionSystem,
                items: [
                  for (final item in report.systemItems)
                    _buildCheckRow(context, item),
                ],
              )
            else
              generateSection(
                title: appLocalizations.envCheckSectionSystem,
                items: [
                  ListItem(
                    leading: GlyphIcon(
                      AppGlyphs.info,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(appLocalizations.envCheckUnavailable),
                    onTap: _refresh,
                  ),
                ],
              ),
            generateSection(
              title: appLocalizations.envCheckSectionApp,
              items: [
                for (final item in report.appItems)
                  _buildCheckRow(context, item),
              ],
              footer: appLocalizations.envCheckFooter,
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentSummaryCard extends StatelessWidget {
  const _EnvironmentSummaryCard({
    required this.report,
    required this.info,
    required this.refreshing,
    required this.onRefresh,
  });

  final EnvironmentCheckReport report;
  final AndroidEnvironmentInfo? info;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final errors = report.errorCount;
    final warnings = report.warningCount;
    final (glyph, color, headline) = errors > 0
        ? (
            AppGlyphs.error,
            colorScheme.error,
            appLocalizations.envCheckSummaryErrors(errors),
          )
        : warnings > 0
        ? (
            AppGlyphs.warning,
            colorScheme.warning,
            appLocalizations.envCheckSummaryWarnings(warnings),
          )
        : (
            AppGlyphs.checkCircle,
            colorScheme.success,
            appLocalizations.envCheckSummaryAllGood,
          );

    final deviceParts = [
      if (info case final env? when env.androidVersion.isNotEmpty)
        'Android ${env.androidVersion} (API ${env.sdkInt})',
      if (info case final env? when env.manufacturer.isNotEmpty)
        env.manufacturer,
    ];

    final cardLevel = context.raisedSurfaceLevel;
    return SurfaceScope(
      level: cardLevel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: cardLevel.colorOf(colorScheme),
          shape: AppShape.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              GlyphIcon(glyph, size: 28, color: color),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      headline,
                      style: AppTextStyle.headline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    if (deviceParts.isNotEmpty)
                      Text(
                        deviceParts.join(' · '),
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                label: appLocalizations.envCheckRecheck,
                onPressed: refreshing ? null : onRefresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/environment_check.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

AndroidEnvironmentInfo _healthyInfo({
  bool vpnPermissionGranted = true,
  bool vpnActive = false,
  bool hasNetwork = true,
  String networkTransport = 'wifi',
  List<String> systemDnsServers = const ['223.5.5.5'],
  String privateDnsMode = 'opportunistic',
  String? privateDnsSpecifier,
  bool autoTimeEnabled = true,
  bool notificationPermissionGranted = true,
  bool powerSaveMode = false,
  bool backgroundDataRestricted = false,
}) {
  return AndroidEnvironmentInfo(
    vpnPermissionGranted: vpnPermissionGranted,
    vpnActive: vpnActive,
    hasNetwork: hasNetwork,
    networkTransport: networkTransport,
    systemDnsServers: systemDnsServers,
    privateDnsMode: privateDnsMode,
    privateDnsSpecifier: privateDnsSpecifier,
    autoTimeEnabled: autoTimeEnabled,
    notificationPermissionGranted: notificationPermissionGranted,
    powerSaveMode: powerSaveMode,
    backgroundDataRestricted: backgroundDataRestricted,
    androidVersion: '15',
    sdkInt: 35,
    manufacturer: 'Google',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  late Profile sampleProfile;

  setUpAll(() async {
    l10n = await AppLocalizations.load(const Locale('en'));
    sampleProfile = const Profile(
      id: 1,
      label: 'TestSub',
      url: '',
      autoUpdateDuration: Duration(hours: 24),
    );
  });

  group('evaluateAndroidEnvironment', () {
    test('reports all OK for a healthy Android environment', () {
      final report = evaluateAndroidEnvironment(
        localizations: l10n,
        info: _healthyInfo(),
        batteryOptimizationIgnored: true,
        vpnProps: const VpnProps(enable: true),
        clashConfig: const PatchClashConfig(),
        delayTestTimeout: 5000,
        currentProfile: sampleProfile,
        coreStatus: CoreStatus.connected,
        isFlClashRunning: false,
      );

      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
      expect(report.systemItems, hasLength(8));
      expect(report.appItems, hasLength(6));
    });

    test('flags critical system and proxy issues', () {
      final report = evaluateAndroidEnvironment(
        localizations: l10n,
        info: _healthyInfo(
          vpnPermissionGranted: false,
          vpnActive: true,
          hasNetwork: false,
          systemDnsServers: const [],
          privateDnsMode: 'hostname',
          privateDnsSpecifier: 'dns.google',
          autoTimeEnabled: false,
          notificationPermissionGranted: false,
          backgroundDataRestricted: true,
        ),
        batteryOptimizationIgnored: false,
        vpnProps: const VpnProps(
          enable: false,
          ipv6: true,
          accessControlProps: AccessControlProps(
            enable: true,
            mode: AccessControlMode.acceptSelected,
          ),
        ),
        clashConfig: const PatchClashConfig(
          dns: Dns(enable: false),
          dnsOverrideKeys: {DnsOverrideKey.enable},
        ),
        delayTestTimeout: 1500,
        currentProfile: null,
        coreStatus: CoreStatus.disconnected,
        isFlClashRunning: false,
      );

      expect(report.errorCount, 6);
      expect(report.warningCount, 8);
      expect(report.okCount, 0);
    });

    test('does not flag FlClash own VPN as a conflict while running', () {
      final report = evaluateAndroidEnvironment(
        localizations: l10n,
        info: _healthyInfo(vpnActive: true),
        batteryOptimizationIgnored: true,
        vpnProps: const VpnProps(enable: true),
        clashConfig: const PatchClashConfig(),
        delayTestTimeout: 5000,
        currentProfile: sampleProfile,
        coreStatus: CoreStatus.connected,
        isFlClashRunning: true,
      );

      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
    });
  });

  group('EnvironmentCheckView', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          batteryOptimizationIgnoredProvider.overrideWith(
            _FakeBatteryOptimizationIgnored.new,
          ),
        ],
      );
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(420, 900);
    });

    tearDown(() => container.dispose());

    testWidgets('renders checks and handles direct fixes', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      container.listen(vpnSettingProvider, (_, _) {});
      container.read(vpnSettingProvider.notifier).value = const VpnProps(
        enable: false,
      );
      var prepared = false;
      AndroidSettingsTarget? openedTarget;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: EnvironmentCheckView(
              environmentLoader: () async => _healthyInfo(
                vpnPermissionGranted: false,
                privateDnsMode: 'hostname',
                privateDnsSpecifier: 'dns.example',
              ),
              onPrepareVpn: () async {
                prepared = true;
                return true;
              },
              onOpenSettings: (target) async {
                openedTarget = target;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapCentered(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        }
        await Scrollable.ensureVisible(
          tester.element(finder),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      expect(find.text(l10n.envCheckCleanRestartTitle), findsOneWidget);
      expect(find.text(l10n.envCheckVpnPermission), findsOneWidget);

      await tapCentered(find.text(l10n.envCheckVpnPermission));
      expect(prepared, isTrue);

      await tapCentered(find.text(l10n.envCheckPrivateDns));
      expect(openedTarget, AndroidSettingsTarget.network);

      await tapCentered(find.text(l10n.envCheckVpnMode));
      expect(container.read(vpnSettingProvider).enable, isTrue);
    });

    testWidgets('shows step-by-step progress for clean restart recovery', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final executed = <RecoveryStepId>[];
      final gate = Completer<void>();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: EnvironmentCheckView(
              environmentLoader: () async => _healthyInfo(),
              onRunRecoveryStep: (step) async {
                executed.add(step);
                if (step == RecoveryStepId.flushDns) {
                  await gate.future;
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.envCheckCleanRestartTitle));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.envCheckRecoveryRunning), findsOneWidget);
      expect(find.text(l10n.envCheckRecoveryStepProgress(1, 4)), findsOneWidget);
      expect(executed, [
        RecoveryStepId.closeConnections,
        RecoveryStepId.flushDns,
      ]);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(l10n.envCheckRecoveryDone), findsOneWidget);
      expect(find.text(l10n.envCheckRecoveryStepProgress(4, 4)), findsOneWidget);
      expect(executed, recoveryStepsFor(RecoveryMode.cleanRestartService));
    });

    testWidgets('surfaces failing step during core reinitialization', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final executed = <RecoveryStepId>[];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: EnvironmentCheckView(
              environmentLoader: () async => _healthyInfo(),
              onRunRecoveryStep: (step) async {
                executed.add(step);
                if (step == RecoveryStepId.restartCore) {
                  throw StateError('core init failed');
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.envCheckReinitCoreTitle));
      await tester.pumpAndSettle();

      expect(find.text(l10n.envCheckRecoveryFailed), findsOneWidget);
      expect(find.text(l10n.envCheckRecoveryStepProgress(2, 4)), findsOneWidget);
      expect(find.textContaining('core init failed'), findsOneWidget);
      expect(executed, [
        RecoveryStepId.clearState,
        RecoveryStepId.initGeo,
        RecoveryStepId.restartCore,
      ]);
    });
  });
}

class _FakeBatteryOptimizationIgnored extends BatteryOptimizationIgnored {
  @override
  Stream<bool> build() => Stream.value(true);
}

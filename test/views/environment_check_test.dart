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

      expect(find.text(l10n.envCheckVpnPermission), findsOneWidget);
      expect(find.text(l10n.envCheckPrivateDns), findsOneWidget);

      await tester.tap(find.text(l10n.envCheckVpnPermission));
      await tester.pumpAndSettle();
      expect(prepared, isTrue);

      await tester.tap(find.text(l10n.envCheckPrivateDns));
      await tester.pumpAndSettle();
      expect(openedTarget, AndroidSettingsTarget.network);

      await tester.scrollUntilVisible(find.text(l10n.envCheckVpnMode), 200);
      await tester.tap(find.text(l10n.envCheckVpnMode));
      await tester.pumpAndSettle();
      expect(container.read(vpnSettingProvider).enable, isTrue);
    });
  });
}

class _FakeBatteryOptimizationIgnored extends BatteryOptimizationIgnored {
  @override
  Stream<bool> build() => Stream.value(true);
}

import 'package:core/utils/config/env_loader.dart';
import 'package:core/utils/platform_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:tmail_ui_user/main.dart' show TMailApp;
import 'package:tmail_ui_user/main/main_entry.dart' show runTmailPreload;

import '../models/test_tags.dart';
import '../utils/backend_reset_client.dart';
import 'base_scenario.dart';
import 'base_test_scenario.dart';
import 'test_app_bootstrap.dart';
import '../factories/robot_factory.dart';
import '../factories/robot_factory_provider.dart';

class TestBase {
  static final TestBase _instance = TestBase._internal();
  factory TestBase() => _instance;

  TestBase._internal();

  void runPatrolTest({
    required String description,
    required BaseScenario Function(PatrolIntegrationTester $, RobotFactory robots) scenarioBuilder,
    List<TestTags> tags = const [TestTags.ios],
    bool seedTestCredentials = true,
  }) {
    patrolSetUp(_setup);

    patrolTearDown(_tearDown);

    patrolTest(
      description,
      config: const PatrolTesterConfig(
        settlePolicy: SettlePolicy.trySettle,
        existsTimeout: Duration(seconds: 30),
        visibleTimeout: Duration(seconds: 30),
        settleTimeout: Duration(seconds: 30),
        printLogs: true,
      ),
      tags: tags.map((t) => t.name).toList(),
      platformAutomatorConfig: PlatformAutomatorConfig.fromOptions(
        findTimeout: const Duration(seconds: 30),
      ),
      framePolicy: LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive,
      ($) async {
        await setupTest(seedTestCredentials: seedTestCredentials);
        await scenarioBuilder($, createRobotFactory($)).execute();
      },
    );
  }

  Future<void> setupTest({bool seedTestCredentials = true}) async {
    await EnvLoader.loadEnvFile();
    await bootstrapTestApp(
      preload: runTmailPreload,
      seedCredentials: BaseTestScenario.seedTestCredentials,
      mount: () => runApp(const TMailApp()),
      enableCredentialSeeding: seedTestCredentials,
    );

    final originalOnError = FlutterError.onError!;
    FlutterError.onError = (FlutterErrorDetails details) {
      originalOnError(details);
    };
  }

  Future<void> _setup() async {
    PlatformInfo.isIntegrationTesting = true;
  }

  Future<void> _tearDown() async {
    PlatformInfo.isIntegrationTesting = false;
    await BackendResetClient.reset();
  }
}

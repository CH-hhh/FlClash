import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final delayTestConcurrencyProvider =
    NotifierProvider<DelayTestConcurrency, int>(DelayTestConcurrency.new);

class DelayTestConcurrency extends Notifier<int> {
  @override
  int build() {
    return preferences.delayTestConcurrencySync;
  }

  void update(int value) {
    state = value;
    unawaited(preferences.setDelayTestConcurrency(value));
  }
}

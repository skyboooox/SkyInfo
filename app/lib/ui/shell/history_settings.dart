part of 'home.dart';

extension _HistorySettings on _HomeState {
  Future<void> localHistorySettings() =>
      showLocalHistoryPreferences(context, c);
}

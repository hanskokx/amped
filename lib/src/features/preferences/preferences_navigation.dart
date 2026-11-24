import "package:flutter/foundation.dart";

import "preferences_page.dart";

/// Where the Preferences dialog is in its page tree.
///
/// This lives outside the widget tree: DevTools' select-widget mode inserts a
/// widget inspector around the app, remounting every widget and discarding
/// local state. Keeping the current page here means it survives that.
class PreferencesNavigation extends ChangeNotifier {
  PreferencesNavigation([this._page = PreferencesPage.skinsInstalled]) {
    _visited.add(_page);
  }

  PreferencesPage _page;
  final Set<PreferencesPage> _visited = {};

  /// The page currently shown.
  PreferencesPage get page => _page;

  /// Whether [page] has been opened since this navigation was created.
  bool hasVisited(PreferencesPage page) => _visited.contains(page);

  /// Shows [page], remembering it for later rebuilds and dialog openings.
  void select(PreferencesPage page) {
    _visited.add(page);
    if (page == _page) return;
    _page = page;
    notifyListeners();
  }
}

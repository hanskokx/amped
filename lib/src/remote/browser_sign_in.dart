import "package:amped_media_source/amped_media_source.dart";
import "package:url_launcher/url_launcher.dart";

export "package:amped_media_source/amped_media_source.dart"
    show
        BrowserOpener,
        BrowserSignInException,
        OAuthTokens,
        PkceSignIn,
        pollSignIn;

/// The system's default browser.
Future<void> openInSystemBrowser(Uri url) async {
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    throw const BrowserSignInException("Could not open the browser.");
  }
}

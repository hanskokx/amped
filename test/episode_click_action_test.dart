import "package:amped/src/app/episode_click_action.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("the saved name picks the action, anything else does nothing", () {
    expect(EpisodeClickAction.fromName("play"), EpisodeClickAction.play);
    expect(EpisodeClickAction.fromName("enqueue"), EpisodeClickAction.enqueue);
    expect(EpisodeClickAction.fromName("nothing"), EpisodeClickAction.nothing);
    expect(EpisodeClickAction.fromName(null), EpisodeClickAction.nothing);
    expect(EpisodeClickAction.fromName("bogus"), EpisodeClickAction.nothing);
  });
}

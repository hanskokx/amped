/// The cursor slots a classic skin can override, in the order and with the
/// file names of `Skin_LoadCursors` (Skins.cpp). A skin that has no file for a
/// slot leaves that slot on the OS cursor.
enum SkinCursor {
  // Main window.
  volBal("volbal.cur"),
  posbar("posbar.cur"),
  winBut("winbut.cur"),
  min("min.cur"),
  close("close.cur"),
  mainMenu("mainmenu.cur"),
  titleBar("titlebar.cur"),
  songName("songname.cur"),
  normal("normal.cur"),

  // Main window, windowshade mode.
  wsWinBut("winbut.cur"),
  wsMin("min.cur"),
  wsPosbar("wsposbar.cur"),
  wsClose("close.cur"),
  wsMainMenu("mmenu.cur"),
  wsNormal("wsnormal.cur"),

  // Playlist editor.
  plWinBut("pwinbut.cur"),
  plClose("pclose.cur"),
  plTitleBar("ptbar.cur"),
  plVScroll("pvscroll.cur"),
  plSize("psize.cur"),
  plNormal("pnormal.cur"),

  // Playlist editor, windowshade mode.
  plWsWinBut("pwinbut.cur"),
  plWsClose("pclose.cur"),
  plWsSize("pwssize.cur"),
  plWsNormal("pwsnorm.cur"),

  // Equalizer.
  eqSlider("eqslid.cur"),
  eqClose("eqclose.cur"),
  eqTitleBar("eqtitle.cur"),
  eqNormal("eqnormal.cur");

  const SkinCursor(this.fileName);

  /// The lower-cased file name the skin may provide.
  final String fileName;
}

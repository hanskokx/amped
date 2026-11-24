// Progressive enhancement for the download button: reads /release.json and
// offers the installers that fit the visitor's operating system. Without it
// (no JavaScript, release.json not published yet) the plain link to the
// GitHub releases page in the markup stays.
(async () => {
  const root = document.getElementById('download');
  if (!root) return;

  let release;
  try {
    const res = await fetch('/release.json', { cache: 'no-cache' });
    release = await res.json();
  } catch (_) {
    return;
  }
  const assets = Array.isArray(release.assets) ? release.assets : [];
  if (!assets.length) return;

  const uaData = navigator.userAgentData;
  const ua = navigator.userAgent;
  const platform = (uaData && uaData.platform) || navigator.platform || '';
  let os = 'other';
  if (/win/i.test(platform) || /Windows/.test(ua)) os = 'windows';
  else if (/mac/i.test(platform) || /Macintosh/.test(ua)) os = 'macos';
  else if (/linux|x11/i.test(platform) || /Linux|X11/.test(ua)) os = 'linux';
  if (/Android|iPhone|iPad/.test(ua)) os = 'other';

  let arm = /arm|aarch64/i.test(ua);
  if (uaData && uaData.getHighEntropyValues) {
    try {
      const h = await uaData.getHighEntropyValues(['architecture']);
      arm = h.architecture === 'arm';
    } catch (_) {}
  }

  const find = (re) => assets.find((a) => re.test(a.name));
  const options = {
    windows: [
      [arm ? 'Windows (ARM64)' : 'Windows (64-bit)', find(arm ? /windows-arm64/ : /windows-x64/)],
    ],
    // Browsers cannot tell Apple silicon from Intel, so macOS gets the
    // universal disk image, with the Apple silicon one as the alternative.
    macos: [
      ['macOS', find(/macos-universal/)],
      ['macOS (Apple silicon only)', find(/macos-arm64/)],
    ],
    linux: [
      ['Linux (AppImage)', find(/\.AppImage$/)],
      ['Linux (Flatpak)', find(/\.flatpak$/)],
      ['Linux (.deb)', find(/\.deb$/)],
      ['Linux (.rpm)', find(/\.rpm$/)],
    ],
  }[os];

  const shown = (options || []).filter(([, a]) => a);
  const [first, ...rest] = shown;

  const frag = document.createDocumentFragment();
  const link = (text, href, cls) => {
    const a = document.createElement('a');
    a.href = href;
    a.textContent = text;
    if (cls) a.className = cls;
    return a;
  };

  if (first) {
    frag.append(link(`Download for ${first[0]}`, first[1].url, 'button'));
    const meta = document.createElement('p');
    meta.className = 'meta';
    meta.textContent = `Amped ${release.version}`;
    rest.forEach(([label, a]) => {
      meta.append(' · ', link(label, a.url));
    });
    frag.append(meta);
  }

  // Everything else, for other platforms.
  const all = document.createElement('details');
  const summary = document.createElement('summary');
  summary.textContent = 'Other downloads';
  const list = document.createElement('ul');
  assets.forEach((a) => {
    const li = document.createElement('li');
    li.append(link(a.name, a.url));
    list.append(li);
  });
  const notes = release.notes
    ? link('Release notes', release.notes)
    : null;
  all.append(summary, list);
  if (notes) all.append(notes);
  frag.append(all);

  root.replaceChildren(frag);
})();

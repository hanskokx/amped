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

  // What each file runs on, read from its name. The package formats spell the
  // architectures their own ways.
  const systemOf = ({ name }) => {
    if (/macos|\.dmg$/i.test(name)) return 'macos';
    if (/windows|\.exe$/i.test(name)) return 'windows';
    if (/\.(AppImage|flatpak|deb|rpm)$/i.test(name)) return 'linux';
    return null;
  };
  const archOf = ({ name }) => {
    if (/universal/i.test(name)) return 'Universal';
    if (/arm64|aarch64/i.test(name)) return 'ARM64';
    if (/x64|x86_64|amd64/i.test(name)) return 'x64';
    return null;
  };

  // The list's order: by system, then architecture with x86 first (a
  // universal build includes it), then package format. Anything not
  // recognized goes last.
  const rank = (order, value) => {
    const i = order.indexOf(value);
    return i < 0 ? order.length : i;
  };
  const sortKey = (a) => [
    rank(['macos', 'windows', 'linux'], systemOf(a)),
    rank(['Universal', 'x64', 'ARM64'], archOf(a)),
    rank(['appimage', 'flatpak', 'deb', 'rpm'], a.name.split('.').pop().toLowerCase()),
  ];
  const sorted = [...assets].sort((a, b) => {
    const x = sortKey(a);
    const y = sortKey(b);
    return x[0] - y[0] || x[1] - y[1] || x[2] - y[2] || a.name.localeCompare(b.name);
  });

  // Small drawings of each system's logo, 24 by 24, as [shape, attributes].
  const logos = {
    macos: [
      'macOS',
      [
        ['path', { d: 'M12 7.2c1-.1 2.2-1 3.8-.9 1.6.1 2.9.8 3.7 2-3.2 2-2.7 6.4.6 7.7-.7 1.9-2.6 5.2-4.6 5.2-1.3 0-1.9-.8-3.5-.8s-2.3.8-3.5.8C6.100 21.200 3.200 16.600 3.200 13c0-4 2.600-6.700 5.200-6.700 1.600 0 2.7.9 3.6.9z' }],
        ['path', { d: 'M11.8 5.9c-.1-2.5 2-4.7 4.3-4.9.3 2.6-2.1 4.9-4.3 4.9z' }],
      ],
    ],
    windows: [
      'Windows',
      [['path', { d: 'M3 3h8.5v8.5H3zM12.5 3H21v8.5h-8.5zM3 12.5h8.5V21H3zM12.5 12.5H21V21h-8.5z' }]],
    ],
    // The penguin: body, belly, eyes, beak and feet.
    linux: [
      'Linux',
      [
        ['path', { d: 'M12 1.5c-3 0-4.3 2.3-4.3 5 0 2.3-.3 3.6-1.8 5.8C4.4 14.5 4 16.2 4 17.5c0 2.5 3.5 4 8 4s8-1.5 8-4c0-1.3-.4-3-1.9-5.2-1.5-2.2-1.8-3.5-1.8-5.8 0-2.7-1.3-5-4.3-5z' }],
        ['ellipse', { cx: 12, cy: 15.5, rx: 4.3, ry: 5.2, fill: '#fff' }],
        ['circle', { cx: 10.3, cy: 6, r: 1.2, fill: '#fff' }],
        ['circle', { cx: 13.7, cy: 6, r: 1.2, fill: '#fff' }],
        ['circle', { cx: 10.5, cy: 6.2, r: 0.6, fill: '#000' }],
        ['circle', { cx: 13.5, cy: 6.2, r: 0.6, fill: '#000' }],
        ['path', { d: 'M12 7.2l2.6 1.6L12 10.8 9.4 8.8z', fill: '#ffb23e' }],
        ['path', { d: 'M3.2 19.5l3.6-2.6 3.4 4.2c-.6 1.6-2.2 1.6-3.6 1.1-1.6-.6-3.7-1-3.4-2.7zM20.8 19.5l-3.6-2.6-3.4 4.2c.6 1.6 2.2 1.6 3.6 1.1 1.6-.6 3.7-1 3.4-2.7z', fill: '#ffb23e' }],
      ],
    ],
  };
  const logo = (system) => {
    const make = (tag, attributes) => {
      const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
      Object.entries(attributes).forEach(([k, v]) => node.setAttribute(k, v));
      return node;
    };
    const [label, shapes] = logos[system];
    const svg = make('svg', {
      viewBox: '0 0 24 24',
      fill: 'currentColor',
      class: `logo ${system}`,
      role: 'img',
      'aria-label': label,
    });
    const title = make('title', {});
    title.textContent = label;
    svg.append(title, ...shapes.map(([tag, attributes]) => make(tag, attributes)));
    return svg;
  };

  const find = (re) => assets.find((a) => re.test(a.name));
  // The Linux package of one kind that matches the visitor's processor.
  const linux = (re) =>
    assets.find(
      (a) => re.test(a.name) && archOf(a) === (arm ? 'ARM64' : 'x64'),
    );
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
      ['Linux (AppImage)', linux(/\.AppImage$/)],
      ['Linux (Flatpak)', linux(/\.flatpak$/)],
      ['Linux (.deb)', linux(/\.deb$/)],
      ['Linux (.rpm)', linux(/\.rpm$/)],
    ],
  }[os];

  const shown = (options || []).filter(([, a]) => a);
  const [first, ...rest] = shown;

  const frag = document.createDocumentFragment();
  const link = (text, href, cls) => {
    const a = document.createElement('a');
    a.href = href;
    a.textContent = text;
    // They all go to GitHub, which opens in a new tab.
    a.target = '_blank';
    a.rel = 'noopener';
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
  let previous;
  sorted.forEach((a) => {
    const li = document.createElement('li');
    const system = systemOf(a);
    if (previous !== undefined && system !== previous) {
      li.className = 'next-system';
    }
    previous = system;
    // Empty cells keep the columns lined up when a name says nothing.
    const arch = document.createElement('span');
    const architecture = archOf(a);
    if (architecture) {
      arch.className = 'badge';
      arch.textContent = architecture;
    }
    li.append(
      system ? logo(system) : document.createElement('span'),
      arch,
      link(a.name, a.url),
    );
    list.append(li);
  });
  const notes = release.notes
    ? link('Release notes', release.notes)
    : null;
  all.append(summary, list);
  if (notes) all.append(notes);
  frag.append(all);

  root.replaceChildren(frag);

  // macOS and Windows warn about unsigned apps, so downloading for either also
  // shows how to get past that. The download itself carries on.
  root.addEventListener('click', (event) => {
    const a = event.target.closest('a');
    if (!a) return;
    const system = systemOf({ name: a.href });
    const help = system && document.getElementById(`help-${system}`);
    if (help && !help.open) help.showModal();
  });

  // A click outside a dialog closes it.
  document.querySelectorAll('.install-help').forEach((help) => {
    help.addEventListener('click', (event) => {
      if (event.target === help) help.close();
    });
  });
})();

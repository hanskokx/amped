// Brings the classic skin on the homepage to life: a picture of it with a
// transparent canvas over it, on which a pretend song plays, drawn with the
// skin's own digit, font and seek bar bitmaps. Without JavaScript the plain
// picture stays. Also runs the page's scroll and pointer effects.
(() => {
  const root = document.documentElement;
  const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // The same made-up songs the skin renderer puts in its pictures.
  const tracks = [
    ['Neon Harbor - Midnight Static', 222],
    ['The Paper Satellites - Glass Orchard', 245],
    ['Velvet Arcade - Lo-Fi Sunrise', 178],
    ['Marlow and the Echoes - Paper Planes', 211],
    ['Juniper Static - Golden Hour', 257],
    ['Cassette Dreams - Slow Motion', 189],
    ['Orbit Garden - Night Bloom', 302],
  ];
  const trackSeconds = 14; // How long each one "plays" before the next.

  const clock = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

  const song = (t) => {
    const index = Math.floor(t / trackSeconds) % tracks.length;
    const [title, length] = tracks[index];
    // Starts part of the way in, so the seek bar has somewhere to be.
    const position = Math.floor(37 + (t % trackSeconds));
    return { index, title, length, position };
  };

  // A spectrum that moves like music: a beat in the low bands, slower swells
  // above it, and bars that fall rather than vanish.
  const spectrum = (count) => {
    const levels = new Array(count).fill(0);
    const peaks = new Array(count).fill(0);
    let last = 0;
    return (t) => {
      const dt = Math.min(0.1, Math.max(0, t - last));
      last = t;
      const beat = Math.pow(1 - ((t * 2.05) % 1), 3);
      for (let i = 0; i < count; i++) {
        const x = i / count;
        const swell = 0.5 + 0.5 * Math.sin(t * (2.3 + x * 5) + i * 1.7);
        const flutter = 0.5 + 0.5 * Math.sin(t * (11 + (i % 5) * 2.9) + i * 4.2);
        const target = Math.min(
          1,
          (1 - x) * beat * 0.75 + swell * 0.4 + flutter * 0.28 * (1 - x * 0.5),
        );
        levels[i] = Math.max(target, levels[i] - dt * 2.2);
        peaks[i] = Math.max(levels[i], peaks[i] - dt * 0.55);
      }
      return { levels, peaks };
    };
  };

  const load = (src) =>
    new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = reject;
      image.src = src;
    });

  // --- The classic skin ----------------------------------------------------

  // viscolor.txt, from the top of the analyzer to the bottom.
  const visColors = [
    '#ef3110', '#ce2910', '#d65a00', '#d66600', '#d67300', '#c67b08',
    '#dea518', '#d6b521', '#bdde29', '#94de21', '#29ce10', '#32be10',
    '#39b510', '#319c08', '#299400', '#188408',
  ];

  // Where each character is in text.bmp: 5x6 cells.
  const fontRows = [
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ"@',
    '0123456789….:()-\'!_+\\/[]^&%,=$#',
  ];

  const classic = async () => {
    const [numbers, text, posbar, playpaus] = await Promise.all(
      ['numbers', 'text', 'posbar', 'playpaus'].map((n) =>
        load(`images/skins/${n}.png`),
      ),
    );
    const bars = spectrum(19);

    const write = (ctx, string, x, y) => {
      for (const c of string.toUpperCase()) {
        let row = 0;
        let column = fontRows[0].indexOf(c);
        if (column < 0) {
          row = 1;
          column = fontRows[1].indexOf(c);
        }
        if (column < 0) {
          row = 0;
          column = 30; // A space.
        }
        ctx.drawImage(text, column * 5, row * 6, 5, 6, x, y, 5, 6);
        x += 5;
      }
    };

    return (ctx, t) => {
      const now = song(t);

      // The play indicator, over the picture's "stopped" one.
      ctx.fillStyle = '#000';
      ctx.fillRect(26, 28, 9, 9);
      ctx.drawImage(playpaus, 0, 0, 9, 9, 26, 28, 9, 9);

      // The time.
      const minutes = Math.floor(now.position / 60);
      const seconds = now.position % 60;
      [[48, 0], [60, minutes], [78, Math.floor(seconds / 10)], [90, seconds % 10]]
        .forEach(([x, digit]) => {
          ctx.drawImage(numbers, digit * 9, 0, 9, 13, x, 26, 9, 13);
        });

      // The analyzer: 19 bars of 3 pixels, 16 rows high.
      const { levels, peaks } = bars(t);
      for (let i = 0; i < 19; i++) {
        const height = Math.round(levels[i] * 16);
        for (let row = 16 - height; row < 16; row++) {
          ctx.fillStyle = visColors[row];
          ctx.fillRect(24 + i * 4, 43 + row, 3, 1);
        }
        const peak = Math.round(peaks[i] * 15);
        ctx.fillStyle = '#969696';
        ctx.fillRect(24 + i * 4, 58 - peak, 3, 1);
      }

      // The title, scrolling five characters a second.
      const line = `${now.index + 1}. ${now.title} (${clock(now.length)})  ***  `;
      const from = Math.floor((t % trackSeconds) * 5) % line.length;
      write(ctx, (line + line).slice(from, from + 30), 112, 27);
      write(ctx, '320', 111, 43);
      write(ctx, '44', 156, 43);

      // The seek bar.
      ctx.drawImage(posbar, 0, 0, 248, 10, 16, 72, 248, 10);
      const along = Math.round((now.position / now.length) * (248 - 29));
      ctx.drawImage(posbar, 248, 0, 29, 10, 16 + along, 72, 29, 10);

      // The playlist, 232 pixels down, in pledit.txt's colors.
      ctx.font = '9px Arial, Helvetica, sans-serif';
      ctx.textBaseline = 'middle';
      tracks.forEach(([title, length], i) => {
        const y = 254 + i * 13;
        const current = i === now.index;
        ctx.fillStyle = current ? '#0000c6' : '#000';
        ctx.fillRect(12, y, 243, 13);
        ctx.fillStyle = current ? '#fff' : '#0f0';
        ctx.textAlign = 'left';
        ctx.fillText(`${i + 1}. ${title}`, 14, y + 7);
        ctx.textAlign = 'right';
        ctx.fillText(clock(length), 253, y + 7);
      });
      write(ctx, `${clock(now.position)}/26:44`, 133, 436);
    };
  };

  // --- Running them --------------------------------------------------------

  const players = { classic };

  document.querySelectorAll('canvas[data-player]').forEach(async (canvas) => {
    let draw;
    try {
      draw = await players[canvas.dataset.player]();
    } catch (_) {
      return; // The picture underneath stays.
    }
    const ctx = canvas.getContext('2d');
    const scale = canvas.width / Number(canvas.dataset.skinWidth);
    const render = (t) => {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      ctx.imageSmoothingEnabled = false;
      draw(ctx, t);
    };

    if (still) {
      render(1.3);
      return;
    }

    // Only draws while it can be seen, about 30 times a second.
    let visible = false;
    let running = false;
    let last = 0;
    const frame = (ms) => {
      if (!visible) {
        running = false;
        return;
      }
      if (ms - last >= 32) {
        last = ms;
        render(ms / 1000);
      }
      requestAnimationFrame(frame);
    };
    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible && !running) {
        running = true;
        requestAnimationFrame(frame);
      }
    }).observe(canvas);
  });

  if (still) return;

  // Sections slide in as they are reached. The class that hides them is only
  // added here, so nothing stays hidden without JavaScript.
  root.classList.add('animate');
  const reveal = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('seen');
        reveal.unobserve(entry.target);
      });
    },
    { threshold: 0.12 },
  );
  document.querySelectorAll('.reveal').forEach((el) => reveal.observe(el));

  // The players lean toward the pointer.
  document.querySelectorAll('[data-tilt]').forEach((stage) => {
    stage.addEventListener('pointermove', (e) => {
      const box = stage.getBoundingClientRect();
      const x = (e.clientX - box.left) / box.width - 0.5;
      const y = (e.clientY - box.top) / box.height - 0.5;
      stage.style.setProperty('--tilt-x', `${(-y * 7).toFixed(2)}deg`);
      stage.style.setProperty('--tilt-y', `${(x * 9).toFixed(2)}deg`);
    });
    stage.addEventListener('pointerleave', () => {
      stage.style.removeProperty('--tilt-x');
      stage.style.removeProperty('--tilt-y');
    });
  });
})();

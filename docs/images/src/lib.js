// Shared code of the README images: TOML highlighting, the tiling tree, the desktop mock and the animations.
//
// An animation page calls Anim({...}). Opened in a browser it plays; scripts/make-docs-images.sh opens it with
// ?meta (the size and the delays of the frames, as JSON) and with ?sprite=N (16 frames in a grid, starting at
// the frame 16 * N), and gif.swift cuts those grids into a GIF.

const ACCENT = '#ff9f0a';
const INACTIVE = 'rgba(142,142,147,.45)';
const FLOATING = '#bf5af2';

// ---------- TOML ----------

function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

/** Highlights TOML. A line that starts with '>' is marked as the one that matters */
function toml(text) {
  return text.split('\n').map(line => {
    const hl = line.startsWith('>');
    if (hl) line = line.slice(1);
    let html;
    const m = line.match(/^(\s*)([\w.\-"]+)(\s*=\s*)(.*?)(\s*#.*)?$/);
    if (/^\s*#/.test(line)) html = `<span class="c">${esc(line)}</span>`;
    else if (/^\s*\[/.test(line)) html = `<span class="t">${esc(line)}</span>`;
    else if (m) {
      const v = /^['"\[{]/.test(m[4]) ? `<span class="s">${esc(m[4])}</span>` : `<span class="n">${esc(m[4])}</span>`;
      html = `${m[1]}<span class="k">${esc(m[2])}</span>${m[3]}${v}${m[5] ? `<span class="c">${esc(m[5])}</span>` : ''}`;
    } else html = esc(line);
    return hl ? `<span class="hl">${html}</span>` : html;
  }).join('\n');
}
function fillToml() {
  document.querySelectorAll('.toml').forEach(el => { el.innerHTML = toml(el.textContent.replace(/^\n/, '').replace(/\n\s*$/, '')); });
}

// ---------- The tiling tree ----------
// The same rules as Sources/AppBundle/tree/dwindle.swift. A window is { id, w }, a container is { o: 'h'|'v', kids, w },
// and w is the weight of the node in its container.

const T = {
  win: (id, w = 1) => ({ id, w }),
  box: (o, kids, w = 1) => ({ o, kids, w }),
  clone: n => JSON.parse(JSON.stringify(n)),

  /**
   * The rectangles of the windows: { id: { x, y, w, h } }. The inner gap is taken from both neighbors, like the layout does.
   * `gaps` is a number, or { h, v } for gaps.inner.horizontal and gaps.inner.vertical
   */
  layout(root, rect, gaps = 0, out = {}) {
    if (!root.kids) { out[root.id] = rect; return out; }
    const total = root.kids.reduce((s, k) => s + k.w, 0);
    const h = root.o === 'h';
    const gap = typeof gaps === 'number' ? gaps : h ? gaps.h : gaps.v;
    let pos = h ? rect.x : rect.y;
    root.kids.forEach((k, i) => {
      const size = (h ? rect.w : rect.h) * k.w / total;
      const a = pos + (i > 0 ? gap / 2 : 0);
      const b = pos + size - (i < root.kids.length - 1 ? gap / 2 : 0);
      pos += size;
      T.layout(k, h ? { x: a, y: rect.y, w: b - a, h: rect.h } : { x: rect.x, y: a, w: rect.w, h: b - a }, gaps, out);
    });
    return out;
  },

  find(root, id, parent = null, index = 0) {
    if (root.id === id) return { node: root, parent, index };
    for (const [i, k] of (root.kids || []).entries()) {
      const found = T.find(k, id, root, i);
      if (found) return found;
    }
    return null;
  },

  /** new-window-placement = 'dwindle': the new window splits the target, which keeps `ratio` of its place */
  split(root, targetId, newId, rects, ratio = 0.5) {
    const r = rects[targetId];
    const axis = r.w > r.h ? 'h' : 'v';
    const { node, parent, index } = T.find(root, targetId);
    const fresh = T.win(newId);
    if (parent === root && root.kids.length === 1 && root.o !== axis) root.o = axis; // Case b
    if (parent.o === axis) { // Case a: a sibling
      const w = node.w;
      node.w = w * ratio;
      fresh.w = w * (1 - ratio);
      parent.kids.splice(index + 1, 0, fresh);
    } else { // Case c: a new container takes the place of the target
      const box = T.box(axis, [node, fresh], node.w);
      node.w = ratio;
      fresh.w = 1 - ratio;
      parent.kids[index] = box;
    }
  },

  /** The window leaves the tree. Its space goes to the previous sibling (to the next one, for a first child) */
  remove(root, id) {
    const { node, parent, index } = T.find(root, id);
    if (parent.kids.length >= 3) parent.kids[index > 0 ? index - 1 : 1].w += node.w;
    parent.kids.splice(index, 1);
    T.flatten(root, root);
  },

  /** A container with a single child is replaced by its child */
  flatten(root, node) {
    if (!node.kids) return;
    node.kids = node.kids.map(k => (k.kids && k.kids.length === 1 ? { ...k.kids[0], w: k.w } : k));
    node.kids.forEach(k => T.flatten(root, k));
  },
};

// ---------- The desktop mock ----------

const APP_NAMES = { ghostty: 'Ghostty', zed: 'Zed', safari: 'Safari', mail: 'Mail', messages: 'Messages', music: 'Music', notes: 'Notes',
  finder: 'Finder', terminal: 'Terminal', calendar: 'Calendar', preview: 'Preview' };

/**
 * A screen of W x H points, drawn at `scale`, at (x, y) of `parent`.
 * wins: [{ id, x, y, w, h, o?, app?, num?, text?, focus?, color?, floating?, noBorder? }], back to front, in points.
 * opt: { bar (height of the menu bar), chips: { n, foc, occ: [..] }, bw, radius, cursor: { x, y }, glow }
 */
function drawScreen(parent, x, y, scale, W, H, wins, opt = {}) {
  const bar = opt.bar ?? 24;
  const bw = opt.bw ?? 4;
  const radius = opt.radius ?? 16;
  const el = document.createElement('div');
  el.className = 'screen';
  el.style.cssText = `left:${x}px;top:${y}px;width:${W * scale}px;height:${H * scale}px;border-radius:${Math.max(6, 18 * scale)}px`;
  let html = `<div class="pt" style="width:${W}px;height:${H}px;transform:scale(${scale})">`;
  if (bar) {
    html += `<div class="bar" style="height:${bar}px">`;
    if (opt.chips) {
      html += '<span class="chips">';
      for (let i = 1; i <= opt.chips.n; i++) {
        const cls = i === opt.chips.foc ? 'foc' : opt.chips.occ.includes(i) ? 'occ' : 'empty';
        html += `<span class="chip ${cls}">${i}</span>`;
      }
      html += '</span>';
    }
    html += '</div>';
  }
  for (const w of wins) {
    const o = w.o ?? 1;
    if (o <= 0.01) continue;
    const color = w.color ?? (w.focus ? (w.floating ? FLOATING : ACCENT) : INACTIVE);
    const m = Math.min(w.w, w.h);
    const icon = Math.max(18, Math.min(72, m * 0.34));
    const font = Math.max(13, Math.min(34, m * 0.16));
    let mid = '';
    if (w.app) mid += `<img src="icons/${w.app}.png" width="${icon}" height="${icon}">`;
    if (w.num !== undefined) mid += `<span class="num" style="font-size:${font * 1.5}px">${w.num}</span>`;
    else if (w.app && w.w > 170 && w.h > 150) mid += `<span style="font-size:${font}px">${APP_NAMES[w.app] || w.app}</span>`;
    if (w.text) mid += `<span class="dim" style="font-size:${font * 0.8}px">${w.text}</span>`;
    const shadow = w.floating ? 'box-shadow:0 18px 50px rgba(0,0,0,.55);' : '';
    const glow = w.glow && w.focus ? `box-shadow:0 0 ${w.glow}px ${color};` : '';
    html += `<div class="w ${w.focus ? 'focus' : ''}" style="left:${w.x}px;top:${w.y}px;width:${w.w}px;height:${w.h}px;opacity:${o};border-radius:${radius}px;${shadow}">`;
    if (!w.noBorder && bw > 0) html += `<div class="ring" style="inset:${-bw}px;border:${bw}px solid ${color};border-radius:${radius + bw}px;${glow}"></div>`;
    if (w.w > 90 && w.h > 60 && !opt.noLights) html += '<div class="lights"><i></i><i></i><i></i></div>';
    html += `<div class="mid" style="border-radius:${radius}px">${mid}</div></div>`;
  }
  if (opt.cursor) {
    html += `<div class="cursor" style="left:${opt.cursor.x}px;top:${opt.cursor.y}px"><svg width="${26 / scale / 2.2}" height="${38 / scale / 2.2}" viewBox="0 0 13 19">` +
      '<path d="M1 1v15l4-3.6 2.6 5.8 2.3-1-2.6-5.7H12z" fill="#fff" stroke="#000" stroke-width="1" stroke-linejoin="round"/></svg></div>';
  }
  html += (opt.extra || '') + '</div>';
  el.innerHTML = html;
  parent.appendChild(el);
  return el;
}

/** The tiling area of a screen: what is left after the menu bar and the outer gaps */
function tilingArea(W, H, bar, outer) {
  return { x: outer, y: bar + outer, w: W - 2 * outer, h: H - bar - 2 * outer };
}

/** [{ id, ...rect, ...props[id] }] for the windows of a tree */
function tiled(root, area, gap, props = {}) {
  const rects = T.layout(root, area, gap);
  return Object.keys(rects).map(id => ({ id, ...rects[id], ...(props[id] || {}) }));
}

// ---------- Animations ----------

const PER_SPRITE = 16;
const ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const lerp = (a, b, t) => a + (b - a) * t;

/** The windows between two lists of windows. A window that is only in one of them fades in or out, in its place */
function tweenWins(a, b, t) {
  const out = [];
  const inA = Object.fromEntries(a.map(w => [w.id, w]));
  const inB = Object.fromEntries(b.map(w => [w.id, w]));
  for (const w of a) if (!inB[w.id]) out.push({ ...w, o: (w.o ?? 1) * (1 - t) });
  for (const w of b) {
    const from = inA[w.id];
    if (!from) { out.push({ ...w, o: (w.o ?? 1) * t }); continue; }
    out.push({ ...w, x: lerp(from.x, w.x, t), y: lerp(from.y, w.y, t), w: lerp(from.w, w.w, t), h: lerp(from.h, w.h, t), o: lerp(from.o ?? 1, w.o ?? 1, t) });
  }
  return out;
}

/**
 * def: { W, H, keys: [{ ...state, hold (ms), cut? }], steps (frames between two keys), tween(a, b, t) -> state, draw(el, state) }
 * A key with `cut` is shown without a transition from the previous one. The animation loops, with a transition
 * from the last key to the first one unless the first one has `cut`
 */
function Anim(def) {
  const steps = def.steps ?? 5;
  const frames = [];
  def.keys.forEach((key, i) => {
    const prev = def.keys[(i + def.keys.length - 1) % def.keys.length];
    if (!key.cut) for (let s = 1; s <= steps; s++) frames.push({ state: def.tween(prev, key, ease(s / (steps + 1))), delay: 40 });
    frames.push({ state: key, delay: key.hold ?? 1200 });
  });
  // The loop starts on the first key, not on the transition towards it
  while (frames[0].state !== def.keys[0]) frames.push(frames.shift());

  const make = frame => {
    const el = document.createElement('div');
    el.className = 'frame';
    el.style.cssText = `width:${def.W}px;height:${def.H}px`;
    def.draw(el, frame.state);
    return el;
  };
  const query = location.search;
  document.body.style.margin = '0';
  if (query.includes('meta')) {
    document.body.innerHTML = `<pre id="meta">@@${JSON.stringify({ w: def.W, h: def.H, cols: 8, per: PER_SPRITE, delays: frames.map(f => f.delay) })}@@</pre>`;
  } else if (query.includes('sprite')) {
    const first = PER_SPRITE * Number(query.split('sprite=')[1]);
    const grid = document.createElement('div');
    grid.id = 'sprite';
    grid.style.gridTemplateColumns = `repeat(8, ${def.W}px)`;
    frames.slice(first, first + PER_SPRITE).forEach(f => grid.appendChild(make(f)));
    document.body.appendChild(grid);
  } else {
    let i = 0;
    const show = () => {
      document.body.replaceChildren(make(frames[i]));
      setTimeout(show, frames[i].delay);
      i = (i + 1) % frames.length;
    };
    show();
  }
}

/** The usual frame: a title with the key, the 'illustration' mark and a caption under the picture */
function chrome(el, title, caption, captionTop) {
  el.insertAdjacentHTML('beforeend', `<div class="title">${title}</div><div class="illu">Illustration</div>` +
    (caption ? `<div class="caption" style="top:${captionTop}px">${caption}</div>` : ''));
}

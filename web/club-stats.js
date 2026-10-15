'use strict';

// Club statistics: how far each club goes and whether the player is getting better, over every finished round. Built to
// be easy to change or remove: it lives in this file alone, only reads the rounds, and keeps its own setting (the
// start date) under its own storage key. Removing it = deleting this file and its <script> line in index.html.
//
// It registers itself in window.strokeCounterFeatures before the app's script runs; index.html reads that list
// for extra screens (views), buttons (actions), a row on the home screen (home) and files to check for updates
// (file). From index.html it uses, at call time and read only: db.rounds, isFinished, shotDistance, CLUBS,
// PENALTY, esc, render and the view variable.
//
// What counts (the same rules as the mockup the screen was designed from):
// - Full swings only: no putts, penalty strokes, chips, pitches or bunker shots; no shot followed by a penalty
//   (its distance is to the drop), none with poor GPS, no automatic stroke not yet confirmed.
// - A club's normal length is the median of its shots in the period shown. A shot over twice that is a GPS
//   glitch and left out.
// - A mishit is a shot shorter than 3/4 of its club's normal length. A shot followed by a putt went onto the green:
//   the hole set its length, so it is never a mishit and counts for neither length nor consistency.
(function () {
  const KEY = 'golf-strokes.club-stats.v1';
  const MIN_SHOTS = 5;    // a club with fewer shots is shown faded, and left out of the cards
  const SOLID = 0.75;     // shorter than this share of the club's normal length is a mishit
  const WINDOW = 15;      // shots behind each point of a club's band
  const WEEKS_UP_TO = 70; // days: periods are weeks up to this span, months beyond it

  /* ---------- Numbers (pure: rounds in, numbers out) ---------- */

  function quant(values, q) {
    const s = [...values].sort((a, b) => a - b);
    if (!s.length) return NaN;
    const i = (s.length - 1) * q, lo = Math.floor(i), hi = Math.ceil(i);
    return s[lo] + (s[hi] - s[lo]) * (i - lo);
  }
  const median = values => quant(values, 0.5);

  // Every full swing with a measured distance in the finished rounds, in playing order.
  function collectShots(rounds, clubs) {
    const shots = [];
    rounds.filter(isFinished).forEach(round => {
      Object.keys(round.holes || {}).forEach(h => {
        const list = round.holes[h] || [];
        list.forEach((s, i) => {
          if (!clubs.includes(s.club) || s.club === 'Putter' || s.chip || s.pitch || s.bunker || s.auto) return;
          const next = list[i + 1];
          if (next && next.club === PENALTY) return;
          const d = shotDistance(list, i);
          if (!d || d.approx) return;
          shots.push({ t: s.t || round.createdAt, round: round.id, club: s.club, m: d.m, onGreen: !!next && next.club === 'Putter' });
        });
      });
    });
    return shots.sort((a, b) => a.t - b.t);
  }

  // Monday of the week, or the first of the month, as a time.
  function periodOf(t, months) {
    const d = new Date(t);
    d.setHours(0, 0, 0, 0);
    if (months) d.setDate(1); else d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return +d;
  }

  // Everything the screen shows, for the shots from `from` (a time, or null for all).
  function analyse(rounds, { from = null, clubs = CLUBS } = {}) {
    let shots = collectShots(rounds, clubs).filter(s => from === null || s.t >= from);
    const lengths = c => shots.filter(s => s.club === c && !s.onGreen).map(s => s.m);
    const normal = {};
    for (const c of clubs) { const m = lengths(c); if (m.length) normal[c] = median(m); }
    shots = shots.filter(s => normal[s.club] != null && s.m <= 2 * normal[s.club]);
    for (const c in normal) normal[c] = median(lengths(c));
    shots.forEach(s => { s.solid = s.onGreen || s.m >= SOLID * normal[s.club]; s.forLength = s.solid && !s.onGreen; });

    const count = c => shots.filter(s => s.club === c).length;
    const counted = shots.filter(s => count(s.club) >= MIN_SHOTS);

    // Week by week (month by month over a longer span), every club together: the share of solid shots, how far
    // solid shots land from their club's normal length and how long they go, both as shares of it, so a 6i and a
    // PW can be put together.
    const months = shots.length > 1 && shots[shots.length - 1].t - shots[0].t > WEEKS_UP_TO * 86400000;
    const periods = [...new Set(counted.map(s => periodOf(s.t, months)))].sort((a, b) => a - b).map(p => {
      const ps = counted.filter(s => periodOf(s.t, months) === p);
      const good = ps.filter(s => s.forLength);
      return {
        start: p, n: ps.length,
        solid: ps.filter(s => s.solid).length / ps.length,
        spread: median(good.map(s => Math.abs(s.m - normal[s.club]) / normal[s.club])),
        length: median(good.map(s => s.m / normal[s.club]))
      };
    }).filter(p => !isNaN(p.spread));

    // The bag in club order: normal length and where half the shots land.
    const bag = clubs.filter(c => normal[c] != null).map(c => {
      const m = lengths(c).filter(v => v <= 2 * normal[c]);
      return { club: c, n: count(c), p25: quant(m, 0.25), med: median(m), p75: quant(m, 0.75) };
    });

    return { shots, normal, months, periods, bag, clubs: bag.filter(b => b.n >= MIN_SHOTS).sort((a, b) => b.n - a.n).map(b => b.club) };
  }

  // A club's shots then and now: its first and last thirds.
  function clubThenNow(list) {
    const third = Math.max(3, Math.floor(list.length / 3));
    const early = list.slice(0, third), late = list.slice(-third);
    const missRate = a => a.filter(s => !s.solid).length / a.length;
    const spreadOf = a => { const m = a.filter(s => s.forLength).map(s => s.m); return (quant(m, 0.75) - quant(m, 0.25)) / 2; };
    const medOf = a => median(a.filter(s => s.forLength).map(s => s.m));
    return {
      early: { med: medOf(early), spread: spreadOf(early), miss: missRate(early) },
      late: { med: medOf(late), spread: spreadOf(late), miss: missRate(late) }
    };
  }

  /* ---------- Setting: the start date ---------- */

  function loadSettings() {
    try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (err) { return {}; }
  }
  function saveSettings(settings) {
    try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch (err) { /* private mode: just not kept */ }
  }
  let settings = loadSettings();
  const fromTime = () => {
    if (!settings.from) return null;
    const [y, m, d] = settings.from.split('-').map(Number);
    return +new Date(y, m - 1, d);
  };

  /* ---------- Drawing ---------- */

  const dayFmt = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short' });
  const monthFmt = new Intl.DateTimeFormat('en-GB', { month: 'short' });
  const fmtDay = t => dayFmt.format(t);
  const attrs = a => Object.entries(a).map(([k, v]) => `${k}="${esc(String(v))}"`).join(' ');
  const svgEl = (tag, a, text) => text == null ? `<${tag} ${attrs(a)}/>` : `<${tag} ${attrs(a)}>${esc(String(text))}</${tag}>`;

  // One bar per period, the latest in the accent, its value on top and its start below.
  function bars(values, better, fmt) {
    const W = 320, H = 74, top = 16, base = 56, gap = 10;
    const max = Math.max(...values.map(v => v.y)), min = Math.min(...values.map(v => v.y));
    const lo = better === 'down' ? 0 : Math.max(0, min - (max - min) * 1.2);
    const lower = Math.min(lo, min);
    const bw = Math.min(56, (W - gap * (values.length - 1)) / values.length);
    const x0 = (W - (bw * values.length + gap * (values.length - 1))) / 2;
    const body = values.map((v, i) => {
      const h = Math.max(3, (v.y - lower) / (max - lower || 1) * (base - top));
      const x = x0 + i * (bw + gap), last = i === values.length - 1;
      return svgEl('rect', { x, y: base - h, width: bw, height: h, rx: 5, fill: last ? 'var(--fairway)' : 'var(--cs-band)' }) +
        svgEl('text', { x: x + bw / 2, y: base - h - 4, 'text-anchor': 'middle', 'font-size': 11, 'font-weight': 700, fill: last ? 'var(--fairway)' : 'var(--mute)' }, fmt(v.y)) +
        svgEl('text', { x: x + bw / 2, y: H - 3, 'text-anchor': 'middle', 'font-size': 11, fill: 'var(--mute)' }, v.label);
    }).join('');
    return `<svg viewBox="0 0 ${W} ${H}" aria-hidden="true">${body}</svg>`;
  }

  function card({ label, value, good, line, chart }) {
    return `
        <div class="cs-card">
          <div class="cs-label">${esc(label)}</div>
          <div class="cs-value${good ? ' good' : ''}">${esc(value)}</div>
          <div class="cs-line">${esc(line)}</div>
          ${chart}
        </div>`;
  }

  // The cards answer "am I getting better?" for the whole bag, so they speak in shares, never in one club's meters;
  // meters are per club, under Club by club. Each compares the latest period with the first.
  function cardsHtml(a) {
    const ps = a.periods;
    if (!ps.length) return '';
    const label = p => a.months ? monthFmt.format(p.start) : fmtDay(p.start);
    const first = ps[0], last = ps[ps.length - 1], one = ps.length === 1;
    const since = a.months ? 'your first month' : 'your first week';
    let html = '';
    {
      const x = Math.round(first.solid * 10), y = Math.round(last.solid * 10);
      html += card({ label: 'Solid shots', value: `${y} of 10`, good: !one && y > x,
        line: `Across all your clubs. ${one ? 'Keep playing to see a trend.' : y > x ? `Up from ${x} of 10 in ${since}: fewer mishits.` : y < x ? `${x} of 10 in ${since}.` : `Same as ${since}.`}`,
        chart: bars(ps.map(p => ({ y: p.solid * 10, label: label(p) })), 'up', v => String(Math.round(v))) });
    }
    {
      const x = Math.round(first.spread * 100), y = Math.round(last.spread * 100);
      const better = !one && y < x * 0.9, worse = !one && y > x * 1.1;
      html += card({ label: 'Consistency', value: better ? 'Better' : worse ? 'Varies more' : 'Steady', good: better,
        line: `Across all your clubs, good shots land within about ${y} % of their normal length${better || worse ? ` (${x} % in ${since})` : ''}. Shorter bars are better.`,
        chart: bars(ps.map(p => ({ y: p.spread * 100, label: label(p) })), 'down', v => Math.round(v) + ' %') });
    }
    {
      const d = Math.round((last.length / first.length - 1) * 100);
      const signed = v => (v > 0 ? '+' : v < 0 ? '−' : '±') + Math.abs(v) + ' %';
      html += card({ label: 'Distance', value: signed(d), good: d >= 2,
        line: one ? 'Across all your clubs. Keep playing to see a trend.'
          : `Across all your clubs, good shots go ${d === 0 ? 'as far as' : `${Math.abs(d)} % ${d > 0 ? 'further than' : 'shorter than'}`} in ${since}.`,
        chart: bars(ps.map(p => ({ y: (p.length / first.length - 1) * 100, label: label(p) })), 'up', v => signed(Math.round(v))) });
    }
    return html;
  }

  // Every club's normal length on one scale: a dot for it, a bar where half the shots land.
  function bagHtml(a) {
    const stats = a.bag;
    const row = 30, left = 58, right = 44, top = 22, W = 340, H = top + stats.length * row + 6;
    const maxM = Math.max(50, Math.ceil(Math.max(...stats.map(s => s.p75)) / 50) * 50);
    const x = m => left + m / maxM * (W - left - right);
    let body = '';
    for (let g = 0; g <= maxM; g += 50) {
      body += svgEl('line', { x1: x(g), x2: x(g), y1: top - 4, y2: H - 4, stroke: 'var(--line)', 'stroke-width': 1 }) +
        svgEl('text', { x: x(g), y: 12, 'text-anchor': 'middle', 'font-size': 11, fill: 'var(--mute)' }, g + (g === maxM ? ' m' : ''));
    }
    stats.forEach((s, i) => {
      const y = top + i * row + row / 2;
      body += `<g opacity="${s.n < MIN_SHOTS ? 0.4 : 1}">` +
        svgEl('text', { x: 0, y: y + 5, 'font-size': 15, 'font-weight': 700, fill: 'var(--ink)' }, s.club) +
        svgEl('rect', { x: x(s.p25), y: y - 6, width: Math.max(4, x(s.p75) - x(s.p25)), height: 12, rx: 6, fill: 'var(--cs-band)' }) +
        svgEl('circle', { cx: x(s.med), cy: y, r: 7, fill: 'var(--fairway)', stroke: 'var(--white)', 'stroke-width': 2 }) +
        svgEl('text', { x: W, y: y + 5, 'text-anchor': 'end', 'font-size': 14, 'font-weight': 700, fill: 'var(--ink)' }, Math.round(s.med)) +
        '</g>';
    });
    // A club going shorter than the next, shorter club in the bag: the headline, as it is the thing to look at.
    const i = stats.findIndex((s, k) => k < stats.length - 1 && s.n >= MIN_SHOTS && stats[k + 1].n >= MIN_SHOTS && s.med < stats[k + 1].med);
    const title = i >= 0 ? `Your ${stats[i].club} goes shorter than your ${stats[i + 1].club}` : 'How far each club goes';
    return `
        <div class="cs-panel">
          <h3>${esc(title)}</h3>
          <p class="cs-note">The dot is your normal length, the bar where half your shots land.</p>
          <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Normal length per club">${body}</svg>
        </div>`;
  }

  // One club over time: a column per round, a dot per shot, the band and line of the last WINDOW shots.
  function clubChart(list) {
    const W = 340, H = 220, left = 34, right = 10, top = 12, bottom = 26;
    const rounds = [...new Set(list.map(s => s.round))];
    const col = (W - left - right) / rounds.length;
    const x = s => {
      const inRound = list.filter(w => w.round === s.round), k = inRound.indexOf(s);
      return left + col * (rounds.indexOf(s.round) + 0.5) + (inRound.length > 1 ? (k / (inRound.length - 1) - 0.5) * col * 0.6 : 0);
    };
    const maxM = Math.max(25, Math.ceil(Math.max(...list.map(s => s.m)) / 25) * 25);
    const y = m => top + (1 - m / maxM) * (H - top - bottom);
    const step = maxM > 150 ? 50 : 25;
    let body = '';
    for (let g = 0; g <= maxM; g += step) {
      body += svgEl('line', { x1: left, x2: W - right, y1: y(g), y2: y(g), stroke: 'var(--line)', 'stroke-width': 1 }) +
        svgEl('text', { x: left - 6, y: y(g) + 4, 'text-anchor': 'end', 'font-size': 11, fill: 'var(--mute)' }, g);
    }
    const pts = rounds.map((id, r) => {
      const lastIdx = list.map(s => s.round).lastIndexOf(id);
      const win = list.slice(Math.max(0, lastIdx - WINDOW + 1), lastIdx + 1).filter(w => w.forLength).map(w => w.m);
      return win.length >= 6 ? { x: left + col * (r + 0.5), p25: quant(win, 0.25), med: median(win), p75: quant(win, 0.75) } : null;
    }).filter(Boolean);
    if (pts.length > 1) {
      const band = pts.map(p => `${p.x},${y(p.p75)}`).concat(pts.slice().reverse().map(p => `${p.x},${y(p.p25)}`));
      body += svgEl('polygon', { points: band.join(' '), fill: 'var(--cs-band)', opacity: 0.8 });
    }
    list.forEach(s => {
      body += svgEl('circle', s.onGreen
        ? { cx: x(s), cy: y(s.m), r: 3, fill: 'var(--white)', stroke: 'var(--fairway)', 'stroke-width': 1.5 }
        : s.solid
          ? { cx: x(s), cy: y(s.m), r: 3, fill: 'var(--fairway)', opacity: 0.45 }
          : { cx: x(s), cy: y(s.m), r: 3, fill: 'var(--white)', stroke: 'var(--cs-miss)', 'stroke-width': 1.5 });
    });
    if (pts.length > 1) {
      body += svgEl('polyline', { points: pts.map(p => `${p.x},${y(p.med)}`).join(' '), fill: 'none', stroke: 'var(--fairway)', 'stroke-width': 3, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' });
      const e = pts[pts.length - 1];
      body += svgEl('circle', { cx: e.x, cy: y(e.med), r: 5, fill: 'var(--fairway)', stroke: 'var(--white)', 'stroke-width': 2 });
    }
    body += svgEl('text', { x: left + col * 0.5, y: H - 6, 'text-anchor': rounds.length > 1 ? 'start' : 'middle', 'font-size': 11, fill: 'var(--mute)' }, fmtDay(list[0].t));
    if (rounds.length > 1) {
      body += svgEl('text', { x: (left + W - right) / 2, y: H - 6, 'text-anchor': 'middle', 'font-size': 11, fill: 'var(--mute)' }, `${rounds.length} rounds`) +
        svgEl('text', { x: left + col * (rounds.length - 0.5), y: H - 6, 'text-anchor': 'end', 'font-size': 11, fill: 'var(--mute)' }, fmtDay(list[list.length - 1].t));
    }
    return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Shots over time">${body}</svg>`;
  }

  let currentClub = null;

  function clubHtml(a) {
    if (!a.clubs.length) return '';
    if (!a.clubs.includes(currentClub)) currentClub = a.clubs[0];
    const list = a.shots.filter(s => s.club === currentClub);
    const { early, late } = clubThenNow(list);
    const parts = [];
    if (late.spread < early.spread * 0.85) parts.push('more consistent'); else if (late.spread > early.spread * 1.15) parts.push('less consistent');
    if (late.miss < early.miss - 0.1) parts.push('with fewer mishits'); else if (late.miss > early.miss + 0.1) parts.push('with more mishits');
    const title = parts.length ? `Your ${currentClub} is getting ${parts.join(', ')}` : `Your ${currentClub} is holding steady`;
    const fact = (label, then, now, fmt) => `<div class="cs-fact"><b>${esc(fmt(now))}</b><span>${esc(label)}<br>was ${esc(fmt(then))}</span></div>`;
    const m = v => isNaN(v) ? '–' : Math.round(v) + ' m';
    const chips = a.clubs.map(c => {
      const n = a.shots.filter(s => s.club === c).length;
      return `<button class="cs-chip" data-action="club-stats-club" data-club="${esc(c)}" aria-pressed="${c === currentClub}">${esc(c)} <span>${n}</span></button>`;
    }).join('');
    return `
        <h2 class="cs-head">Club by club</h2>
        <div class="cs-chips" role="group" aria-label="Club">${chips}</div>
        <div class="cs-panel">
          <h3>${esc(title)}</h3>
          <p class="cs-note">The band narrowing means your shots land closer together. Grey rings are mishits, green rings went onto the green.</p>
          ${clubChart(list)}
          <div class="cs-facts">
            ${fact('normal length', early.med, late.med, m)}
            ${fact('half land within', early.spread, late.spread, v => isNaN(v) ? '–' : '±' + Math.round(v) + ' m')}
            ${fact('mishits', early.miss, late.miss, v => Math.round(v * 10) + ' of 10')}
          </div>
        </div>`;
  }

  // A date as the date field writes it (yyyy-mm-dd), in local time.
  const isoDay = t => { const d = new Date(t); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

  // The field starts on the chosen date, else on the first shot, so the picker opens where the shots begin.
  function fromHtml(first) {
    const on = !!settings.from;
    return `
        <div class="cs-from" role="group" aria-label="Shots shown">
          <button class="cs-chip" data-action="club-stats-all" aria-pressed="${!on}">All</button>
          <label class="cs-chip cs-since" aria-pressed="${on}">
            <span>${on ? 'Since ' + esc(fmtDay(fromTime())) : 'Since a date'}</span>
            <input type="date" id="club-stats-from" value="${esc(settings.from || (first ? isoDay(first) : ''))}" max="${esc(isoDay(Date.now()))}" aria-label="Show shots since">
          </label>
        </div>`;
  }

  function renderScreen() {
    const a = analyse(db.rounds, { from: fromTime() });
    let main;
    if (!a.shots.length) {
      main = `<p class="empty">${settings.from ? 'No shots with a distance since that date yet.' : 'No shots with a distance yet.'} A distance is measured when a stroke and the next one, or its landing spot, both have a GPS position. Finished rounds count.</p>`;
    } else {
      main = `
        <p class="cs-sub">${a.shots.length} shots from ${esc(fmtDay(a.shots[0].t))} to ${esc(fmtDay(a.shots[a.shots.length - 1].t))}</p>
        ${a.periods.length ? `<h2 class="cs-head">Are you getting better?</h2><div class="cs-cards">${cardsHtml(a)}</div>` : ''}
        <h2 class="cs-head">Your bag</h2>
        ${bagHtml(a)}
        ${clubHtml(a)}
        <p class="cs-foot">Full swings only, total distance including roll. Putts, penalty strokes, chips, pitches and bunker
          shots are left out, as are shots followed by a penalty, shots with poor GPS and automatic strokes not yet confirmed.
          A mishit is a shot shorter than ¾ of the club's normal length. A shot onto the green is never a mishit, and is
          left out of length and consistency, since the hole set how far it went. Mark half swings as Pitch to leave them out.</p>`;
    }
    return `
    <div class="screen">
      <header class="top">
        <button class="ghost" data-action="club-stats-back">‹ Back</button>
        <h2>Club statistics</h2>
        <span style="width:64px"></span>
      </header>
      <main class="scroll cs">
        ${fromHtml(collectShots(db.rounds, CLUBS)[0]?.t)}
        ${main}
      </main>
    </div>`;
  }

  // The row under the home screen's stats: the latest share of solid shots, when there is one.
  function homeRow() {
    let hint = '';
    try {
      const ps = analyse(db.rounds, { from: fromTime() }).periods;
      if (ps.length) hint = ` · ${Math.round(ps[ps.length - 1].solid * 10)} of 10 solid shots`;
    } catch (err) { /* a problem here must never break the home screen */ }
    return `<button class="cs-home" data-action="club-stats"><span><b>Club statistics</b>${esc(hint)}</span><span aria-hidden="true">›</span></button>`;
  }

  const css = `
    .cs { --cs-band: #B9CFAE; --cs-miss: #A7AFA3; }
    .cs-home { display: flex; justify-content: space-between; align-items: center; width: 100%; margin: -6px 0 14px;
               padding: 12px 16px; background: var(--white); border: 1px solid var(--line); border-radius: 14px;
               color: var(--ink); font-size: 15px; text-align: left; }
    .cs-home b { color: var(--fairway); }
    .cs-home span:last-child { color: var(--fairway); font-size: 20px; font-weight: 700; }
    .cs-head { font-size: 12px; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; color: var(--mute); margin: 22px 0 8px; }
    .cs-sub { color: var(--mute); font-size: 14px; margin: 10px 0 0; }
    .cs-cards { display: grid; gap: 10px; }
    .cs-card { background: var(--white); border: 1px solid var(--line); border-radius: 16px; padding: 14px 16px;
               display: grid; grid-template-columns: 1fr auto; gap: 2px 12px; align-items: center; }
    .cs-label { font-weight: 700; }
    .cs-value { font-size: 22px; font-weight: 800; text-align: right; color: var(--mute); font-variant-numeric: tabular-nums; }
    .cs-value.good { color: var(--under); }
    .cs-line { color: var(--mute); font-size: 14px; grid-column: 1 / -1; }
    .cs-card svg { grid-column: 1 / -1; width: 100%; height: auto; margin-top: 6px; }
    .cs-panel { background: var(--white); border: 1px solid var(--line); border-radius: 16px; padding: 14px 12px 10px; }
    .cs-panel h3 { margin: 0 4px 2px; font-size: 18px; font-weight: 800; text-wrap: balance; }
    .cs-note { margin: 0 4px 8px; color: var(--mute); font-size: 14px; }
    .cs-panel svg { width: 100%; height: auto; display: block; }
    .cs svg text { font-family: inherit; }
    .cs-chips, .cs-from { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 10px; }
    .cs-from { margin: 4px 0 0; }
    .cs-chip { position: relative; border: 1px solid var(--line); background: var(--white); color: var(--ink); border-radius: 999px;
               padding: 7px 14px; font: inherit; font-size: 15px; font-weight: 700; min-height: 36px; display: inline-flex; align-items: center; }
    .cs-chip span { color: var(--mute); font-weight: 500; font-size: 13px; margin-left: 4px; }
    .cs-chip[aria-pressed="true"] { background: var(--fairway); border-color: var(--fairway); color: var(--white); }
    .cs-chip[aria-pressed="true"] span { color: var(--cs-band); }
    .cs-since span { margin-left: 0; color: inherit; font-size: 15px; font-weight: 700; }
    .cs-since input { position: absolute; inset: 0; opacity: 0; width: 100%; height: 100%; }
    .cs-facts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin: 8px 4px 4px; }
    .cs-fact b { display: block; font-size: 20px; font-variant-numeric: tabular-nums; }
    .cs-fact span { color: var(--mute); font-size: 12px; }
    .cs-foot { color: var(--mute); font-size: 13px; margin: 18px 4px 0; }`;
  const style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  // The start date is a date field inside the "Since" chip; it changes, it does not click. Redrawing the screen
  // replaces the field, which closes its picker, so while the field has focus (its picker open) a change only
  // waits and is applied when the picker closes. iOS sends a change as soon as the picker opens on an empty field,
  // which closed it at once before.
  let pendingFrom = false;
  function applyFrom(input) {
    pendingFrom = false;
    const from = input.value || null;
    if (from === (settings.from || null)) return;
    settings = { ...settings, from };
    saveSettings(settings);
    render();
  }
  document.addEventListener('change', event => {
    if (event.target.id !== 'club-stats-from') return;
    if (document.activeElement === event.target) pendingFrom = true; else applyFrom(event.target);
  });
  document.addEventListener('blur', event => {
    if (event.target.id === 'club-stats-from' && pendingFrom) applyFrom(event.target);
  }, true);

  (window.strokeCounterFeatures = window.strokeCounterFeatures || []).push({
    file: 'club-stats.js',
    views: { 'club-stats': renderScreen },
    home: homeRow,
    actions: {
      'club-stats': () => { view = 'club-stats'; render(); },
      'club-stats-back': () => { view = 'list'; render(); },
      'club-stats-club': el => { currentClub = el.dataset.club; render(); },
      'club-stats-all': () => { settings = { ...settings, from: null }; saveSettings(settings); render(); }
    }
  });

  // For the tests.
  window.ClubStats = { collectShots, analyse, clubThenNow, SOLID, MIN_SHOTS };
})();

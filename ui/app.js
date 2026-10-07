/* Perch notch UI. Swift owns the state machine and calls window.perch.apply(snapshot);
   this file only draws and reports user actions back through the "perch" message handler. */
(function () {
  var NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.perch);
  var CARD_W = 360;
  var COLORS = { attention: '#FB923C', done: '#4ADE80', idle: '#71717A' };
  var DOME = { d: 'M2 19V12a10 10 0 0 1 20 0v7a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', et: '44%' };

  /* ---- shadcn recipes ---- */
  var ICON = {
    enter: '<polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    win: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/>',
    file: '<path d="M10 12.5 8 15l2 2.5"/><path d="m14 12.5 2 2.5-2 2.5"/><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    term: '<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/>'
  };
  function svg(n, c) { return '<svg class="' + (c || 'size-3.5') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICON[n] + '</svg>'; }
  var BTN = 'inline-flex items-center justify-center gap-1 whitespace-nowrap rounded-md text-xs font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/50 h-6 px-2 cursor-pointer';
  function Button(v, label, extra, cls) {
    var c = { default: 'bg-primary text-primary-foreground hover:bg-primary/90', ghost: 'text-muted-foreground hover:bg-accent hover:text-accent-foreground' }[v];
    return '<button class="' + BTN + ' ' + c + ' ' + (cls || '') + '">' + label + (extra || '') + '</button>';
  }
  function Kbd(t, onPrimary) { return '<kbd class="pointer-events-none inline-flex h-4 min-w-4 items-center justify-center rounded-sm px-1 font-sans text-[10.5px] font-medium select-none ' + (onPrimary ? 'bg-primary-foreground/15 text-primary-foreground' : 'bg-muted text-muted-foreground') + '">' + t + '</kbd>'; }
  function Badge(inner, cls) { return '<span class="inline-flex w-fit items-center gap-1.5 whitespace-nowrap rounded-md bg-white/[0.07] px-1.5 py-px text-xs font-medium text-foreground/80 ' + (cls || '') + '">' + inner + '</span>'; }
  function Dot(c) { return '<i class="block size-1.5 rounded-full" style="background:' + c + '"></i>'; }
  var icons = {};
  function App(k, c) {
    if (icons[k]) return '<img class="' + (c || 'size-5') + ' flex-none rounded-[5px]" src="' + icons[k] + '" alt="">';
    var g = {
      xcode: ['#1C7CF4', '<path d="M7 17l6.2-6.2" stroke="#fff" stroke-width="2" stroke-linecap="round"/><rect x="11" y="5.2" width="7.4" height="4" rx="1" transform="rotate(45 14.7 7.2)" fill="#fff"/>'],
      claude: ['#D97757', '<g stroke="#fff" stroke-width="1.7" stroke-linecap="round"><path d="M12 5.5v13"/><path d="M5.5 12h13"/><path d="M7.4 7.4l9.2 9.2"/><path d="M16.6 7.4l-9.2 9.2"/></g>'],
      numbers: ['#2FB457', '<g fill="#fff"><rect x="6" y="12" width="3" height="6" rx=".8"/><rect x="10.5" y="8" width="3" height="10" rx=".8"/><rect x="15" y="5" width="3" height="13" rx=".8"/></g>']
    }[k] || ['#52525B', ''];
    return '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="' + g[0] + '"/>' + g[1] + '</svg>';
  }
  /* the agent's real app icon, with a small state dot on its corner */
  function StatusIcon(st) {
    var color = COLORS[st.kind] || COLORS.idle;
    if (!icons[st.app]) return Dot(color);
    return '<span class="relative flex size-3.5 flex-none"><img class="size-3.5 rounded-[4px]" src="' + icons[st.app] + '" alt=""><i class="absolute -bottom-[2px] -right-[2px] block size-1.5 rounded-full ring-[1.5px] ring-black" style="background:' + color + '"></i></span>';
  }
  function header(inner, right, i) { return '<div class="rv flex h-10 items-center gap-2 pl-[44px] pr-4" style="--i:' + (i || 0) + '"><div class="min-w-0 flex-1">' + inner + '</div>' + (right || '') + '</div>'; }

  /* ---- markup (built once) ---- */
  var scene = document.getElementById('scene');
  scene.innerHTML =
    '<div class="cr" data-m="sleep"><i class="f"><svg viewBox="0 0 24 24"><path d="' + DOME.d + '"/></svg></i><i class="ey l"></i><i class="ey r"></i></div>' +
    '<div class="n perch" data-s="idle"><i class="ear l"></i><i class="ear r"></i><div class="clip">' +
    '<div class="pane p-open">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      '<div class="rv flex h-10 items-center gap-2 pl-[44px] pr-4" style="--i:0"><div class="min-w-0 flex-1"><div dir="auto" class="o-n truncate text-sm font-medium leading-4"></div><div class="o-a mt-0.5 text-xs leading-4 tabular-nums text-muted-foreground"></div></div><span class="o-bw">' + Badge('<span class="o-b font-mono text-[11px]"></span>') + '</span></div>' +
      '<p dir="auto" class="o-h rv mt-1 px-4 text-[13.5px] font-semibold leading-[18px] tracking-[-0.02em] text-balance" style="--i:1"></p>' +
      '<p dir="auto" class="o-c rv mt-0.5 px-4 text-sm leading-[16px] text-pretty text-muted-foreground" style="--i:2"></p>' +
      '<p class="rv mt-2 flex items-baseline gap-2 px-4 text-sm" style="--i:3"><span class="text-muted-foreground">Next</span><span dir="auto" class="o-x min-w-0 truncate font-medium"></span></p>' +
      '<div class="rv mt-1 flex h-9 items-center gap-1 px-2.5" style="--i:4"><span class="o-st pl-1.5"></span><span class="flex-1"></span>' + Button('ghost', 'Not now', '', 'x-esc') + Button('default', 'Pick up', Kbd(svg('enter', 'size-2'), 1), 'x-go pr-0.5') + '</div>' +
      '<div id="b"></div></div></div>' +
    '<div class="pane p-switch">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="text-sm font-medium leading-4">Parked projects</div><div class="mt-0.5 text-xs leading-4 text-muted-foreground s-count"></div>') +
      '<div class="rv px-1.5 pb-1 s-l" style="--i:1"></div>' +
      '<div class="rv flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground" style="--i:3"><span class="flex items-center gap-1.5">' + Kbd('↑↓') + 'Choose</span><span class="flex items-center gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Open</span><span class="flex items-center gap-1.5">' + Kbd('esc') + 'Close</span></div>' +
    '</div></div>' +
    '<div class="pane p-restore"><div class="inner pt-8">' +
      header('<div class="r-n text-sm font-medium leading-4"></div><div class="mt-0.5 text-xs leading-4 text-muted-foreground">Picking up where you left off</div>') +
      '<div class="rv px-4 pb-4 pt-0.5 r-l" style="--i:1"></div>' +
    '</div></div>' +
    '</div></div>';

  function q(c) { return scene.querySelector(c); }
  var n = q('.n'), cr = q('.cr');
  q('.x-go').onclick = function () { post({ type: 'confirm' }); };
  q('.x-esc').onclick = function () { post({ type: 'snooze' }); };
  scene.querySelectorAll('.x-close').forEach(function (b) { b.onclick = function () { post({ type: 'dismiss' }); }; });

  /* ---- render ---- */
  var last = { phase: null, token: null };
  var snap = null;

  function fill(p) {
    q('.o-n').textContent = p.name;
    q('.o-a').textContent = 'Left ' + p.at + ' · ' + p.away + ' ago';
    q('.o-bw').style.display = p.branch ? '' : 'none';
    q('.o-b').textContent = p.branch || '';
    q('.o-h').textContent = p.headline;
    q('.o-c').textContent = p.context;
    q('.o-x').textContent = p.next;
    q('.o-st').innerHTML = Badge(StatusIcon(p.status) + p.status.text);
  }
  function list(s) {
    q('.s-count').textContent = s.projects.length + ' projects';
    q('.s-l').innerHTML = s.projects.map(function (p, k) {
      return '<div class="row flex h-9 cursor-default items-center gap-2 rounded-md px-1.5 text-sm transition-colors ' + (k === s.selected ? 'bg-accent' : '') + '" data-i="' + k + '">' +
        App(p.app) +
        '<span class="min-w-0 flex-1 truncate"><span class="font-medium">' + p.name + '</span><span dir="auto" class="ml-2 text-muted-foreground">' + p.topic + '</span></span>' +
        (p.attention ? Dot(COLORS.attention) : '') +
        '<span class="text-xs tabular-nums text-muted-foreground">' + p.away + ' ago</span></div>';
    }).join('');
    scene.querySelectorAll('.row').forEach(function (r) { r.onclick = function () { post({ type: 'choose', index: +r.dataset.i }); }; });
  }
  function rest(p) {
    q('.r-n').textContent = p.name;
    q('.r-l').innerHTML = '<div class="rest-i flex flex-col gap-0.5">' + p.steps.map(function (x, k) {
      return '<div class="flex h-7 items-center gap-2 text-sm" style="--k:' + k + '"><span class="text-muted-foreground">' + svg(x.icon, 'size-3.5') + '</span><span class="flex-1 truncate">' + x.text + '</span><span class="ck text-emerald-400">' + svg('check', 'size-3') + '</span></div>';
    }).join('') + '</div>';
  }
  function bar(on) {
    var b = q('#b'); b.style.transition = 'none'; b.style.width = on ? '100%' : '0';
    if (on) { void b.offsetWidth; b.style.transition = 'width 9s linear'; b.style.width = '0'; }
  }
  function layout(st, s) {
    var scr = s.screen, idleW = scr.hasNotch ? scr.notchW : 0, idleH = scr.hasNotch ? scr.notchH : 32;
    var w = st === 'idle' ? idleW : CARD_W, h = idleH;
    if (st !== 'idle') { var pane = q('.p-' + st); h = pane.querySelector('.inner').offsetHeight; }
    n.style.width = w + 'px'; n.style.marginLeft = (-w / 2) + 'px'; n.style.height = h + 'px';
    n.style.opacity = (st === 'idle' && !scr.hasNotch) ? 0 : 1;
    n.dataset.s = st;
    if (st === 'idle') {
      var d = 18; cr.style.width = cr.style.height = d + 'px';
      cr.style.transform = 'translate(' + (scr.hasNotch ? (-scr.notchW / 2 - d + 6) : -d / 2) + 'px,' + (scr.hasNotch ? (idleH - d) / 2 : 6) + 'px)';
    } else {
      cr.style.width = cr.style.height = '20px';
      cr.style.transform = 'translate(' + (-CARD_W / 2 + 16) + 'px,' + (32 + (40 - 20) / 2) + 'px)';
    }
    cr.dataset.m = st === 'idle' ? 'sleep' : (st === 'restore' ? 'happy' : 'awake');
    post({ type: 'size', width: w, height: h });
  }
  function apply(s) {
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore' }[s.phase];
    var p = s.projects[s.selected];
    if (p) { fill(p); if (st === 'switch') list(s); if (st === 'restore') rest(p); }
    layout(st, s);
    if (s.phase === 'open' && s.autoCollapse) { if (last.token !== s.timerToken || last.phase !== 'open' || !last.running) bar(true); last.running = true; }
    else { if (last.running) bar(false); last.running = false; }
    last.phase = s.phase; last.token = s.timerToken;
  }
  window.perch = { apply: apply };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  function dev(m) {
    if (!snap || m.type === 'size' || m.type === 'log') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'confirm') s.phase = 'restoring';
    if (m.type === 'dismiss' || m.type === 'snooze') s.phase = 'idle';
    if (m.type === 'choose') { s.selected = m.index; s.phase = 'restoring'; }
    s.timerToken++; apply(s);
  }
  if (!NATIVE) {
    var P = [
      { id: 'onboarding', name: 'Onboarding flow', branch: 'main', away: '2h 14m', at: '11:32 AM', headline: 'You were fixing the permissions screen.', context: 'You swapped the sheet for a popover because it clipped on small windows.', next: 'Add the tooltip to the Accessibility row', topic: 'Permissions screen', app: 'xcode', attention: true, status: { kind: 'attention', text: 'Codex needs you' }, steps: [{ icon: 'win', text: 'Put 3 windows back' }, { icon: 'file', text: 'Opened PermissionsView.swift' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'website', name: 'Website', branch: 'feature/hero', away: '20h', at: 'Yesterday 5:05 PM', headline: 'You were tightening the hero spacing.', context: 'You dropped the full-bleed video because it slowed the page down.', next: 'Check the hero at phone width', topic: 'Hero spacing', app: 'claude', attention: false, status: { kind: 'done', text: 'Build passing' }, steps: [{ icon: 'win', text: 'Put 2 windows back' }, { icon: 'term', text: 'Started the dev server on :3000' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'finance', name: 'Finance', branch: '', away: '3d', at: 'Mon 3:40 PM', headline: 'You were reconciling September invoices.', context: 'You are matching by vendor and amount, not by date.', next: 'Two invoices are still unmatched', topic: 'September invoices', app: 'numbers', attention: false, status: { kind: 'idle', text: 'No agents running' }, steps: [{ icon: 'win', text: 'Put 2 windows back' }, { icon: 'file', text: 'Opened Invoices, September' }, { icon: 'file', text: 'Scrolled to row 41' }] }
    ];
    var hash = (location.hash || '#open').slice(1);
    var phase = { idle: 'idle', open: 'open', switcher: 'switcher', restoring: 'restoring' }[hash] || 'open';
    var sel = +(new URLSearchParams(location.search).get('i') || 0);
    document.body.style.background = '#16201e';
    apply({ phase: phase, selected: sel, autoCollapse: false, timerToken: 0, screen: { hasNotch: true, notchW: 185, notchH: 32 }, projects: P });
  }
})();

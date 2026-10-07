/* Perch notch UI. Swift owns the state machine and calls window.perch.apply(snapshot);
   this file only draws and reports user actions back through the "perch" message handler. */
(function () {
  var NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.perch);
  var CARD_W = 400;
  var COLORS = { attention: '#FB923C', done: '#4ADE80', idle: '#71717A' };
  var DOME = { d: 'M2 19V12a10 10 0 0 1 20 0v7a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', et: '44%' };

  /* ---- shadcn recipes ---- */
  var ICON = {
    enter: '<polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    list: '<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>',
    load: '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
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
  function header(inner, right, i) { return '<div class="rv flex h-9 items-center gap-2 pl-4 pr-4" style="--i:' + (i || 0) + '"><div class="min-w-0 flex-1">' + inner + '</div>' + (right || '') + '</div>'; }

  /* ---- markup (built once) ---- */
  var scene = document.getElementById('scene');
  scene.innerHTML =
    '<div class="cr" data-m="sleep"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><path d="' + DOME.d + '"/></svg></i><i class="ey l"></i><i class="ey r"></i></div><i class="dot"></i></div>' +
    '<div class="n perch" data-s="idle"><i class="ear l"></i><i class="ear r"></i><div class="clip"><i class="glow"></i>' +
    '<div class="pane p-open">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '<svg class="pointer-events-none absolute -inset-[3px] size-6" viewBox="0 0 24 24" style="transform:rotate(-90deg)" aria-hidden="true"><circle id="ring" cx="12" cy="12" r="10" fill="none" stroke="rgba(250,250,250,.42)" stroke-width="1.3" stroke-linecap="round" stroke-dasharray="62.83" stroke-dashoffset="62.83"/></svg></button>' +
    '<div class="inner pt-8">' +
      '<div class="rv flex items-center justify-between gap-2 px-4 pt-0.5" style="--i:0"><span class="o-away text-xs tabular-nums text-muted-foreground"></span><span class="o-st"></span></div>' +
      '<p dir="auto" class="o-h rv mt-2 px-4 text-[13.5px] font-semibold leading-[18px] tracking-[-0.02em]" style="--i:1"></p>' +
      '<p dir="auto" class="o-c rv mt-1 px-4 text-[13px] leading-[18px] text-muted-foreground line-clamp-3" style="--i:2"></p>' +
      '<p class="rv mt-3 flex items-baseline gap-2 px-4 text-[13px] leading-[18px]" style="--i:3"><span class="text-muted-foreground">Next</span><span dir="auto" class="o-x min-w-0 flex-1 text-foreground/80"></span></p>' +
      '<div class="rv mt-2 h-9 px-2.5" style="--i:4"><div class="f-main flex h-9 items-center gap-1">' + Button('ghost', 'Other projects', Kbd('Tab'), 'x-list') + '<span class="flex-1"></span>' + Button('ghost', 'Reply', Kbd('R'), 'x-rep hidden') + Button('ghost', 'Not now', Kbd('N'), 'x-esc') + Button('default', 'Pick up', Kbd(svg('enter', 'size-2'), 1), 'x-go pr-0.5') + '</div>' +
      '<div class="f-rep hidden h-9 items-center gap-1.5"><input class="r-in h-6 min-w-0 flex-1 rounded-md bg-white/[0.07] px-2 text-[13px] text-foreground outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring/50" placeholder="Reply to Claude\u2026" spellcheck="false" autocomplete="off" aria-label="Reply">' + Button('default', 'Send', Kbd(svg('enter', 'size-2'), 1), 'x-send pr-0.5') + '</div>' +
      '<div class="f-snz hidden h-9 items-center gap-1"><span class="pl-1.5 text-[13px] text-muted-foreground">Remind me in</span><span class="flex-1"></span>' + Button('ghost', '30 min', Kbd('1'), 'x-s1') + Button('ghost', '2 hours', Kbd('2'), 'x-s2') + Button('ghost', 'Tomorrow', Kbd('3'), 'x-s3') + '</div></div>' +
    '</div></div>' +
    '<div class="pane p-switch">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="text-sm font-medium leading-4">Jump back in</div>') +
      '<div class="rv px-1.5 pb-1 s-l" style="--i:1"></div>' +
      '<div class="rv flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground" style="--i:3"><span class="flex items-center gap-1.5">' + Kbd('\u2191\u2193') + 'Choose</span><span class="flex items-center gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Open</span><button class="x-back flex cursor-pointer items-center gap-1.5 rounded-md px-1 text-muted-foreground transition-colors hover:text-foreground">' + Kbd('Tab') + 'Back</button><span class="flex items-center gap-1.5">' + Kbd('esc') + 'Close</span></div>' +
    '</div></div>' +
    '<div class="pane p-setup">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="text-sm font-medium leading-4">Better summaries</div><div class="mt-0.5 text-xs leading-4 text-muted-foreground">Written on your Mac. Nothing leaves it.</div>') +
      '<div class="rv flex flex-col gap-0.5 px-4 pb-1 pt-0.5 su-rows" style="--i:1"></div>' +
      '<div class="rv flex h-9 items-center gap-1 px-2.5" style="--i:2"><span class="su-note min-w-0 flex-1 pl-1.5 text-xs text-muted-foreground"></span><span class="su-btns flex items-center gap-1"></span></div>' +
    '</div></div>' +
    '<div class="pane p-restore"><div class="inner pt-8">' +
      header('<div class="r-n text-sm font-medium leading-4"></div><div class="mt-0.5 text-xs leading-4 text-muted-foreground">Picking up where you left off</div>') +
      '<div class="rv px-4 pb-4 pt-0.5 r-l" style="--i:1"></div>' +
    '</div></div>' +
    '</div></div>';

  function q(c) { return scene.querySelector(c); }
  var n = q('.n'), cr = q('.cr');
  q('.x-go').onclick = function () { post({ type: 'confirm' }); };
  /* "Not now" asks when to come back: 30 min, 2 hours or tomorrow morning. */
  var fMain = q('.f-main'), fSnz = q('.f-snz');
  function snoozeMenu(open, quiet) {
    fMain.style.display = open ? 'none' : ''; fSnz.style.display = open ? 'flex' : 'none';
    if (!quiet) post({ type: 'snoozeMenu', open: open });
  }
  /* "Reply": answer a question Claude asked without opening the session first. The reply is pasted into the session. */
  var fRep = q('.f-rep'), rIn = q('.r-in'), bRep = q('.x-rep');
  function replyMenu(open, quiet) {
    fMain.style.display = open ? 'none' : ''; fRep.style.display = open ? 'flex' : 'none';
    if (open) setTimeout(function () { rIn.focus(); }, 30); else { rIn.value = ''; rIn.blur(); }
    if (!quiet) post({ type: 'replyMenu', open: open });
  }
  function sendReply() { var t = rIn.value.trim(); if (!t) return; replyMenu(false, true); post({ type: 'reply', text: t }); }
  bRep.onclick = function () { replyMenu(true); };
  q('.x-send').onclick = sendReply;
  rIn.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); sendReply(); } else if (e.key === 'Escape') { e.preventDefault(); replyMenu(false); } e.stopPropagation(); });
  q('.x-esc').onclick = function () { snoozeMenu(true); };
  [['.x-s1', '30m'], ['.x-s2', '2h'], ['.x-s3', 'tomorrow']].forEach(function (b) { q(b[0]).onclick = function () { snoozeMenu(false, true); post({ type: 'snooze', when: b[1] }); }; });
  scene.querySelectorAll('.x-back').forEach(function (b) { b.onclick = function () { post({ type: 'back' }); }; });
  scene.querySelectorAll('.x-list').forEach(function (b) { b.onclick = function () { post({ type: 'switcher' }); }; });
  scene.querySelectorAll('.x-close').forEach(function (b) { b.onclick = function () { post({ type: 'dismiss' }); }; });

  /* ---- render ---- */
  /* ---- guided setup for on-device summaries ---- */
  function stepIcon(state) {
    if (state === 'done') return '<span class="grid size-4 flex-none place-items-center rounded-full bg-emerald-400/15 text-emerald-400">' + svg('check', 'size-2.5') + '</span>';
    if (state === 'busy') return '<span class="grid size-4 flex-none place-items-center text-muted-foreground">' + svg('load', 'size-3.5 animate-spin') + '</span>';
    return '<span class="size-4 flex-none rounded-full border border-muted-foreground/40"></span>';
  }
  function setup(state) {
    var one = state === 'off' ? 'todo' : (state === 'unsupported' ? 'todo' : 'done');
    var two = state === 'ready' ? 'done' : (state === 'downloading' ? 'busy' : 'todo');
    var dim = function (st) { return st === 'todo' ? 'text-muted-foreground' : ''; };
    q('.su-rows').innerHTML =
      '<div class="flex h-7 items-center gap-2 text-sm ' + dim(one === 'todo' && state === 'unsupported' ? 'todo' : (one === 'todo' ? 'x' : 'done')) + '">' + stepIcon(one) + '<span class="flex-1">Turn on Apple Intelligence</span></div>' +
      '<div class="flex h-7 items-center gap-2 text-sm ' + dim(two) + '">' + stepIcon(two) + '<span class="flex-1">' + (two === 'busy' ? 'Downloading the model\u2026' : 'Let it download the model') + '</span></div>';
    var note = { off: 'Takes a few minutes the first time.', downloading: 'A few GB. Keep working, this finishes on its own.', ready: 'All set. Summaries now run on your Mac.', unsupported: "This Mac can't run it, so Perch keeps plain summaries." }[state];
    q('.su-note').textContent = note;
    var b = q('.su-btns');
    if (state === 'off') b.innerHTML = Button('ghost', 'Skip', '', 'x-skip') + Button('default', 'Open Settings', '', 'x-open');
    else if (state === 'ready') b.innerHTML = '';
    else if (state === 'downloading') b.innerHTML = Button('ghost', 'Close', '', 'x-skip') + Button('default', 'See progress', '', 'x-open');
    else b.innerHTML = Button('ghost', 'OK', '', 'x-skip');
    var sk = b.querySelector('.x-skip'); if (sk) sk.onclick = function () { post({ type: 'dismiss' }); };
    var op = b.querySelector('.x-open'); if (op) op.onclick = function () { post({ type: 'openSettings' }); };
  }

  var last = { phase: null, token: null };
  var snap = null;

  function fill(p) {
    q('.o-away').textContent = 'While you were away \u00b7 ' + p.away;
    q('.o-h').textContent = p.headline;
    q('.o-c').textContent = p.context;
    /* last line of defence: git housekeeping is never shown as a next step, whatever produced it (old cache included) */
    var nx = /\b(commit|push|merge|uncommitted|pull request|git)\b/i.test(p.next || '') ? '' : (p.next || '');
    q('.o-x').textContent = nx;
    q('.o-x').parentNode.style.display = nx ? '' : 'none';
    q('.o-st').innerHTML = Badge(StatusIcon(p.status) + p.status.text);
  }
  function list(s) {
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
    var r = q('#ring'); if (!r) return;
    r.style.transition = 'none'; r.style.strokeDashoffset = on ? '0' : '62.83';
    if (on) { void r.getBoundingClientRect(); r.style.transition = 'stroke-dashoffset 9s linear'; r.style.strokeDashoffset = '62.83'; }
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
      cr.style.transform = 'translate(' + (scr.hasNotch ? (-scr.notchW / 2 - d - 6) : -d / 2) + 'px,' + (scr.hasNotch ? (idleH - d) / 2 : 6) + 'px)';
    } else {
      cr.style.width = cr.style.height = '20px';
      cr.style.transform = 'translate(' + (-CARD_W / 2 + 16) + 'px,' + ((idleH - 20) / 2) + 'px)';
    }
    /* idle: nothing there until something needs you, then it pops out beside the notch with an orange dot */
    var news = st === 'idle' && s.projects.some(function (x) { return x.attention; });
    cr.style.opacity = (st === 'idle' && !news) ? 0 : 1;
    cr.dataset.news = news ? '1' : '';
    cr.dataset.m = st === 'idle' ? (news ? 'awake' : 'sleep') : (st === 'restore' ? 'happy' : 'awake');
    post({ type: 'size', width: w, height: h });
  }
  function apply(s) {
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore', setup: 'setup' }[s.phase];
    var p = s.projects[s.selected];
    if (st !== 'open') { snoozeMenu(false, true); replyMenu(false, true); }
    bRep.style.display = (st === 'open' && p) ? 'inline-flex' : 'none';
    if (st === 'setup') setup(s.setup);
    if (p) { fill(p); if (st === 'switch') list(s); if (st === 'restore') rest(p); }
    var glow = { attention: ['251,146,60', '255,196,140'], done: ['74,222,128', '166,247,196'] }, g = (st === 'open' && p && glow[p.status.kind]) || ['245,184,59', '255,222,140'];
    n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    layout(st, s);
    if (s.phase === 'open' && s.autoCollapse) { if (last.token !== s.timerToken || last.phase !== 'open' || !last.running) bar(true); last.running = true; }
    else { if (last.running) bar(false); last.running = false; }
    last.phase = s.phase; last.token = s.timerToken;
  }
  /* ---- the character: glances, follows the cursor, wakes with a hop, peeks while asleep ---- */
  var tracking = false, wasMood = 'sleep', inner = cr.querySelector('.cr-in');
  function look(x, y) { cr.style.setProperty('--lx', x.toFixed(2) + 'px'); cr.style.setProperty('--ly', y.toFixed(2) + 'px'); }
  function glance() {
    var m = cr.dataset.m;
    if (m === 'awake' && !tracking) look((Math.random() * 3.2) - 1.6, (Math.random() * 2) - 1);
    setTimeout(glance, 900 + Math.random() * 2200);
  }
  function peek() {
    if (cr.dataset.m === 'sleep') {
      cr.dataset.m = 'peek'; look(1.4, 0);
      setTimeout(function () { if (cr.dataset.m === 'peek') { cr.dataset.m = 'sleep'; look(0, 0); } }, 1100);
    }
    setTimeout(peek, 6000 + Math.random() * 7000);
  }
  new MutationObserver(function () {
    var m = cr.dataset.m;
    if (m === 'awake' && wasMood !== 'awake') { inner.classList.remove('hop'); void inner.offsetWidth; inner.classList.add('hop'); look(0, 0); }
    if (m !== 'peek') wasMood = m;
  }).observe(cr, { attributes: true, attributeFilter: ['data-m'] });
  /* cursor position in page coordinates, sent by Swift from anywhere on screen */
  var trackTimer = null;
  function cursor(x, y) {
    if (cr.dataset.m !== 'awake') return;
    var r = cr.getBoundingClientRect(), dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height / 2);
    var d = Math.max(1, Math.hypot(dx, dy)), k = Math.min(1, d / 40);
    tracking = true; look((dx / d) * 3.1 * k, (dy / d) * 2.2 * k);
    clearTimeout(trackTimer); trackTimer = setTimeout(function () { tracking = false; }, 1600);
  }
  if (!NATIVE) scene.addEventListener('mousemove', function (e) { cursor(e.clientX, e.clientY); });
  /* blinks at irregular intervals, sometimes twice */
  function blink() {
    if (cr.dataset.m === 'awake') {
      cr.classList.add('blink');
      setTimeout(function () { cr.classList.remove('blink'); if (Math.random() < 0.25) setTimeout(function () { cr.classList.add('blink'); setTimeout(function () { cr.classList.remove('blink'); }, 110); }, 140); }, 110);
    }
    setTimeout(blink, 1100 + Math.random() * 2000);
  }
  setTimeout(glance, 1500); setTimeout(peek, 4000); setTimeout(blink, 1200);

  window.perch = { apply: apply, cursor: cursor, snoozeMenu: function (o) { snoozeMenu(o); }, replyMenu: function (o) { if (o && bRep.style.display === 'none') return; replyMenu(o); } };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore', setup: 'setup' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  function dev(m) {
    if (!snap || m.type === 'size' || m.type === 'log' || m.type === 'snoozeMenu' || m.type === 'replyMenu') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'confirm' || m.type === 'dismiss' || m.type === 'snooze' || m.type === 'reply' || m.type === 'choose') s.phase = 'idle';
    if (m.type === 'switcher') s.phase = 'switcher';
    if (m.type === 'back') s.phase = 'open';
    s.timerToken++; s.autoCollapse = s.phase === 'open'; apply(s);
  }
  if (!NATIVE) {
    var P = [
      { id: 'onboarding', name: 'Onboarding flow', branch: 'main', away: '2h 14m', at: '11:32 AM', headline: 'You were fixing the permissions screen.', context: 'You swapped the sheet for a popover because it clipped on small windows.', next: 'Add the tooltip to the Accessibility row', topic: 'Permissions screen', app: 'xcode', attention: true, status: { kind: 'attention', text: 'Codex needs you' }, steps: [{ icon: 'win', text: 'Put 3 windows back' }, { icon: 'file', text: 'Opened PermissionsView.swift' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'website', name: 'Website', branch: 'feature/hero', away: '20h', at: 'Yesterday 5:05 PM', headline: 'You were tightening the hero spacing.', context: 'You dropped the full-bleed video because it slowed the page down.', next: 'Check the hero at phone width', topic: 'Hero spacing', app: 'claude', attention: false, status: { kind: 'done', text: 'Build passing' }, steps: [{ icon: 'win', text: 'Put 2 windows back' }, { icon: 'term', text: 'Started the dev server on :3000' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'finance', name: 'Finance', branch: '', away: '3d', at: 'Mon 3:40 PM', headline: 'You were reconciling September invoices.', context: 'You are matching by vendor and amount, not by date.', next: 'Answer: \u201cMatch by vendor first, or by amount?\u201d', topic: 'September invoices', app: 'numbers', attention: false, status: { kind: 'idle', text: 'No agents running' }, steps: [{ icon: 'win', text: 'Put 2 windows back' }, { icon: 'file', text: 'Opened Invoices, September' }, { icon: 'file', text: 'Scrolled to row 41' }] }
    ];
    var hash = (location.hash || '#open').slice(1);
    var phase = { idle: 'idle', open: 'open', switcher: 'switcher', restoring: 'restoring' }[hash] || 'open';
    var sel = +(new URLSearchParams(location.search).get('i') || 0);
    document.body.style.background = '#16201e';
    var base = { selected: sel, timerToken: 0, screen: { hasNotch: true, notchW: 185, notchH: 32 }, projects: P, setup: 'off' };
    apply(Object.assign({ phase: phase, autoCollapse: phase === 'open' }, base));
    var autoTimer;
    window.perchDev = {
      show: function (ph, setup, quiet) { clearTimeout(autoTimer); var s = Object.assign({}, base, { projects: quiet ? P.map(function (x) { return Object.assign({}, x, { attention: false }); }) : P, phase: ph, autoCollapse: ph === 'open', setup: setup || 'off', timerToken: Math.random() }); apply(s); },
      play: function () { var d = window.perchDev; d.show('idle'); autoTimer = setTimeout(function () { d.show('open'); }, 1200); },
      project: function (i) { base.selected = i; },
      step: function (d) { base.selected = (base.selected + d + P.length) % P.length; apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, timerToken: Math.random() })); }
    };
    document.addEventListener('keydown', function (e) {
      var ph = snap && snap.phase; if (!ph || ph === 'idle') return;
      if (e.key === 'Escape') { if (fSnz.style.display === 'flex') snoozeMenu(false, true); else window.perchDev.show('idle'); }
      else if (e.key === 'Enter' && (ph === 'open' || ph === 'switcher')) window.perchDev.show('idle');
      else if (e.key === 'Tab' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.key === 'Tab' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open'); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'switcher') { e.preventDefault(); window.perchDev.step(e.key === 'ArrowDown' ? 1 : -1); }
      else if ((e.key === 'n' || e.key === 'N') && ph === 'open') snoozeMenu(fSnz.style.display !== 'flex', true);
      else if (fSnz.style.display === 'flex' && /^[123]$/.test(e.key)) { snoozeMenu(false, true); window.perchDev.show('idle'); }
    });
  }
})();

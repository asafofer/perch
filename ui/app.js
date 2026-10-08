/* Perch notch UI. Swift owns the state machine and calls window.perch.apply(snapshot);
   this file only draws and reports user actions back through the "perch" message handler. */
(function () {
  var NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.perch);
  var CARD_W = 400;
  var COLORS = { attention: '#FB923C', done: '#4ADE80', idle: '#71717A', running: '#7DD3FC' };
  var DOME = { d: 'M2 19V13A10 10 0 0 1 5.4 5.5L5.2 2.6Q5 1.4 6 1.9L9.6 3.7A10 10 0 0 1 14.4 3.7L18.2 1.9Q19.2 1.4 18.8 2.6L18.6 5.5A10 10 0 0 1 22 13v6a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', et: '44%' };

  /* ---- shadcn recipes ---- */
  var ICON = {
    enter: '<polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    list: '<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>',
    load: '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
    win: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/>',
    file: '<path d="M10 12.5 8 15l2 2.5"/><path d="m14 12.5 2 2.5-2 2.5"/><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    gear: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
    term: '<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/>'
  };
  function svg(n, c) { return '<svg class="' + (c || 'size-3.5') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICON[n] + '</svg>'; }
  var BTN = 'inline-flex items-center justify-center gap-1 whitespace-nowrap rounded-md text-xs font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/50 h-6 px-2 cursor-pointer';
  function Button(v, label, extra, cls) {
    var c = { default: 'bg-primary text-primary-foreground hover:bg-primary/90', ghost: 'text-muted-foreground hover:bg-accent hover:text-accent-foreground' }[v];
    return '<button class="' + BTN + ' ' + c + ' ' + (cls || '') + '">' + label + (extra || '') + '</button>';
  }
  function Kbd(t, onPrimary) { return '<kbd class="pointer-events-none inline-flex h-4 min-w-4 items-center justify-center rounded-sm px-1 font-sans text-[10.5px] font-medium select-none ' + (onPrimary ? 'bg-primary-foreground/15 text-primary-foreground' : 'bg-muted text-muted-foreground') + '">' + t + '</kbd>'; }
  function Badge(inner, cls) { return '<span class="inline-flex w-fit items-center gap-1.5 whitespace-nowrap text-xs font-medium text-foreground/80 ' + (cls || '') + '">' + inner + '</span>'; }
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
  function Spinner(cls) { return '<svg class="animate-spin flex-none ' + (cls || 'size-3') + '" viewBox="0 0 24 24" fill="none" stroke="' + COLORS.running + '" stroke-width="3.5" stroke-linecap="round" aria-hidden="true"><path d="M12 3a9 9 0 1 1-9 9"/></svg>'; }
  function StatusIcon(st) {
    var color = COLORS[st.kind] || COLORS.idle;
    if (!icons[st.app]) return Dot(color);
    if (st.kind === 'running') return '<img class="size-3.5 flex-none rounded-[4px]" src="' + icons[st.app] + '" alt="">';
    return '<span class="relative flex size-3.5 flex-none"><img class="size-3.5 rounded-[4px]" src="' + icons[st.app] + '" alt=""><i class="absolute -bottom-[2px] -right-[2px] block size-1.5 rounded-full ring-[1.5px] ring-black" style="background:' + color + '"></i></span>';
  }
  function header(inner, right, i) { return '<div class="rv flex h-9 items-center gap-2 pl-4 pr-4" style="--i:' + (i || 0) + '"><div class="min-w-0 flex-1">' + inner + '</div>' + (right || '') + '</div>'; }

  /* ---- markup (built once) ---- */
  var scene = document.getElementById('scene');
  scene.innerHTML =
    '<div class="cr" data-m="sleep"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><path d="' + DOME.d + '"/></svg></i><i class="ey l"></i><i class="ey r"></i></div><i class="dot"></i></div>' +
    '<div class="n perch" data-s="idle"><i class="ear l"></i><i class="ear r"></i><div class="clip"><i class="glow"></i>' +
    '<div class="pane p-open">' + '<button aria-label="Settings" title="Settings (,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + '</button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '<svg class="pointer-events-none absolute -inset-[3px] size-6" viewBox="0 0 24 24" style="transform:rotate(-90deg)" aria-hidden="true"><circle id="ring" cx="12" cy="12" r="10" fill="none" stroke="rgba(250,250,250,.42)" stroke-width="1.3" stroke-linecap="round" stroke-dasharray="62.83" stroke-dashoffset="62.83"/></svg></button>' +
    '<div class="inner pt-8 pb-1.5">' +
      '<div class="rv flex items-center justify-between gap-2 px-4 pt-0.5" style="--i:0"><span class="o-away text-xs tabular-nums text-muted-foreground"></span><span class="o-st"></span></div>' +
      '<p dir="auto" class="o-h rv mt-2 px-4 text-[13.5px] font-semibold leading-[18px] tracking-[-0.02em]" style="--i:1"></p>' +
      '<p dir="auto" class="o-c rv mt-1 px-4 text-[13px] leading-[18px] text-muted-foreground line-clamp-3" style="--i:2"></p>' +
      '<p class="rv mt-3 flex items-baseline gap-2 px-4 text-[13px] leading-[18px]" style="--i:3"><span class="text-muted-foreground">Next</span><span dir="auto" class="o-x min-w-0 flex-1 text-foreground/80"></span></p>' +
      '<div class="rv mt-2 h-9 px-2.5" style="--i:4"><div class="f-main flex h-9 items-center gap-1">' + Button('ghost', 'Other projects', Kbd('Tab'), 'x-list') + '<span class="flex-1"></span>' + Button('ghost', 'Reply', Kbd('R'), 'x-rep hidden') + Button('ghost', 'Not now', Kbd('N'), 'x-esc') + Button('default', 'Pick up', Kbd(svg('enter', 'size-2'), 1), 'x-go pr-0.5') + '</div>' +
      '<div class="f-rep hidden h-9 items-center gap-1.5"><input class="r-in h-7 min-w-0 flex-1 rounded-lg bg-white/[0.1] px-2.5 text-[13px] text-foreground caret-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none transition-[background-color,box-shadow] duration-200 placeholder:text-white/35 focus:bg-white/[0.13] focus:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]" placeholder="Reply to Claude\u2026" spellcheck="false" autocomplete="off" aria-label="Reply">' + Button('default', 'Send', Kbd(svg('enter', 'size-2'), 1), 'x-send h-7 rounded-lg pr-1') + '</div>' +
      '<div class="f-snz hidden h-9 items-center gap-1"><span class="pl-1.5 text-[13px] text-muted-foreground">Remind me in</span><span class="flex-1"></span>' + Button('ghost', '30 min', Kbd('1'), 'x-s1') + Button('ghost', '2 hours', Kbd('2'), 'x-s2') + Button('ghost', 'Tomorrow', Kbd('3'), 'x-s3') + '</div></div>' +
    '</div></div>' +
    '<div class="pane p-switch">' + '<button aria-label="Settings" title="Settings (,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + '</button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
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
    '<div class="pane p-onb">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-3.5"><div class="onb"></div></div></div>' +
    '<div class="pane p-set">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-3.5"><div class="set"></div></div></div>' +
    '<div class="pane p-restore"><div class="inner pt-8">' +
      header('<div class="r-n text-sm font-medium leading-4"></div><div class="mt-0.5 text-xs leading-4 text-muted-foreground">Picking up where you left off</div>') +
      '<div class="rv px-4 pb-4 pt-0.5 r-l" style="--i:1"></div>' +
    '</div></div>' +
    '</div></div>';

  /* Inline markdown for summaries: **bold**, *italic*, `code`, [links](url) as plain text. Escaped first, so nothing can inject markup. */
  function md(t) {
    var h = String(t || '').replace(/^\s*(#{1,6}\s+|[-*]\s+)/, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return h.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/`([^`]+)`/g, '<code class="rounded bg-white/[0.09] px-1 py-px font-mono text-[11.5px] text-foreground/90">$1</code>')
      .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, function (m, a, b) { return '<strong class="font-semibold text-foreground">' + (a || b) + '</strong>'; })
      .replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?!\*)/g, '$1<em>$2</em>');
  }
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
  scene.querySelectorAll('.x-gear').forEach(function (b) { b.onclick = function () { post({ type: 'settings' }); }; });
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
    q('.o-h').innerHTML = md(p.headline);
    q('.o-c').innerHTML = md(p.context);
    /* last line of defence: git housekeeping is never shown as a next step, whatever produced it (old cache included) */
    var nx = /\b(commit|push|merge|uncommitted|pull request|git)\b/i.test(p.next || '') ? '' : (p.next || '');
    q('.o-x').innerHTML = md(nx);
    q('.o-x').parentNode.style.display = nx ? '' : 'none';
    q('.o-st').innerHTML = Badge(StatusIcon(p.status) + p.status.text + (p.status.kind === 'running' ? Spinner('size-3') : ''));
  }
  function list(s) {
    q('.s-l').innerHTML = s.projects.map(function (p, k) {
      return '<div class="row flex h-9 cursor-default items-center gap-2 rounded-md px-1.5 text-sm transition-colors ' + (k === s.selected ? 'bg-accent' : '') + '" data-i="' + k + '">' +
        App(p.app) +
        '<span class="min-w-0 flex-1 truncate"><span class="font-medium">' + p.name + '</span><span dir="auto" class="ml-2 text-muted-foreground">' + p.topic + '</span></span>' +
        (p.attention ? Dot(COLORS.attention) : '') +
        (p.status.kind === 'running' ? '<span class="flex items-center gap-1.5 text-xs" style="color:' + COLORS.running + '">' + Spinner('size-3') + 'Working</span>' : '<span class="text-xs tabular-nums text-muted-foreground">' + p.away + ' ago</span>') + '</div>';
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
    /* No hardware notch (an external display): draw a small black tab at the top centre, so there is always something to aim at. */
    var scr = s.screen, virt = !scr.hasNotch, idleW = virt ? 148 : scr.notchW, idleH = virt ? Math.min(scr.notchH || 24, 28) : scr.notchH;
    var w = st === 'idle' ? idleW : CARD_W, h = idleH;
    if (st !== 'idle') { var pane = q('.p-' + st); h = pane.querySelector('.inner').offsetHeight; }
    n.style.width = w + 'px'; n.style.marginLeft = (-w / 2) + 'px'; n.style.height = h + 'px';
    n.style.opacity = 1;
    n.dataset.virt = virt ? '1' : '';
    n.dataset.s = st;
    curH = h;
    if (st === 'idle') {
      var d = 18; cr.style.width = cr.style.height = d + 'px';
      idleXf = 'translate(' + (-idleW / 2 - d - 6) + 'px,' + ((idleH - d) / 2) + 'px)'; idleD = d;
      cr.style.transform = idleXf;
      if (helloNext) { helloNext = false; sayHello(); }
    } else if (!celebrating) {
      cr.style.width = cr.style.height = '20px';
      cr.style.transform = 'translate(' + (-CARD_W / 2 + 16) + 'px,' + ((idleH - 20) / 2) + 'px)';
    }
    /* idle: nothing there until something needs you, then it pops out beside the notch with an orange dot */
    var needN = st === 'idle' ? s.projects.filter(function (x) { return x.attention && x.id !== s.activeId; }).length : 0, news = needN > 0;
    var dotEl = cr.querySelector('.dot'); if (news) dotEl.textContent = needN > 9 ? '9+' : String(needN);
    if (news && cr.dataset.news !== '1') { var ci = cr.querySelector('.cr-in'); ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive'); }
    cr.style.opacity = (st === 'idle' && !news && !hello) ? 0 : 1;
    cr.dataset.news = news ? '1' : '';
    if (!celebrating) cr.dataset.m = st === 'idle' ? ((news || hello) ? 'awake' : 'sleep') : (st === 'restore' ? 'happy' : 'awake');
    post({ type: 'size', width: w, height: h });
  }
  function apply(s) {
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore', setup: 'setup', onboarding: 'onb', settings: 'set' }[s.phase];
    var p = s.projects[s.selected];
    if (st !== 'open') { snoozeMenu(false, true); replyMenu(false, true); }
    bRep.style.display = (st === 'open' && p) ? 'inline-flex' : 'none';
    if (p) rIn.placeholder = 'Reply to ' + (p.app === 'codex' || p.status.app === 'codex' || /codex/i.test(p.status.text) ? 'Codex' : 'Claude') + '\u2026';
    applyCharacter(s.character);
    if (st === 'onb') onb(s.onboarding); else { onbStep = -1; onbSig = ''; }
    if (st === 'set') settingsApply(s.settings); else setSig = '';
    if (st === 'setup') setup(s.setup);
    if (p) { fill(p); if (st === 'switch') list(s); if (st === 'restore') rest(p); }
    var glow = { attention: ['251,146,60', '255,196,140'], done: ['74,222,128', '166,247,196'] }, g = (st === 'open' && p && glow[p.status.kind]) || ['245,184,59', '255,222,140'];
    n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    n.dataset.g = (st === 'open' && p && glow[p.status.kind]) ? 'status' : 'char';
    var allDone = st === 'onb' && s.onboarding && s.onboarding.step === s.onboarding.total - 1;
    n.style.setProperty('--gcol', allDone ? '#4ADE80' : (s.character ? s.character.color : charNow.color));
    lastSt = st;
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
    var pv = q('.cr-pv'); if (pv) { var pr = pv.getBoundingClientRect(), px = x - (pr.left + pr.width / 2), py = y - (pr.top + pr.height / 2), pd = Math.max(1, Math.hypot(px, py)), pk = Math.min(1, pd / 60); pv.style.setProperty('--lx', ((px / pd) * 4.5 * pk).toFixed(2) + 'px'); pv.style.setProperty('--ly', ((py / pd) * 3 * pk).toFixed(2) + 'px'); }
    clearTimeout(trackTimer); trackTimer = setTimeout(function () { tracking = false; }, 1600);
  }
  if (!NATIVE) scene.addEventListener('mousemove', function (e) { cursor(e.clientX, e.clientY); });
  if (!NATIVE) scene.addEventListener('mousemove', function (e) {
    if (!snap || snap.phase !== 'idle') return;
    var r = n.getBoundingClientRect(), pad = 10;
    window.perch.hot(e.clientX > r.left - pad - 26 && e.clientX < r.right + pad && e.clientY < r.bottom + pad);
  });
  if (!NATIVE) scene.addEventListener('mouseleave', function () { window.perch.hot(false); });
  /* blinks at irregular intervals, sometimes twice */
  function blink() {
    if (cr.dataset.m === 'awake') {
      cr.classList.add('blink');
      setTimeout(function () { cr.classList.remove('blink'); if (Math.random() < 0.25) setTimeout(function () { cr.classList.add('blink'); setTimeout(function () { cr.classList.remove('blink'); }, 110); }, 140); }, 110);
    }
    setTimeout(blink, 1100 + Math.random() * 2000);
  }
  setTimeout(glance, 1500); setTimeout(peek, 4000); setTimeout(blink, 1200);



  /* ---- character: shape and colour, chosen in onboarding ---- */
  var SHAPES = [
    ['ears', 'Ears', 'M2 19V13A10 10 0 0 1 5.4 5.5L5.2 2.6Q5 1.4 6 1.9L9.6 3.7A10 10 0 0 1 14.4 3.7L18.2 1.9Q19.2 1.4 18.8 2.6L18.6 5.5A10 10 0 0 1 22 13v6a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', '44%'],
    ['dome', 'Dome', 'M2 19V12a10 10 0 0 1 20 0v7a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', '44%'],
    ['arch', 'Arch', 'M4 22V11a8 8 0 0 1 16 0v11H4z', '40%'],
    ['tile', 'Tile', 'M7 3h10a4 4 0 0 1 4 4v10a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4z', '38%'],
    ['peak', 'Peak', 'M10.3 4.3Q12 1.6 13.7 4.3L21.3 17.6Q22.9 20.6 19.6 20.6H4.4Q1.1 20.6 2.7 17.6Z', '55%', '35%', '51%']
  ];
  var PALETTE = [['Saffron', '#F5B83D'], ['Peach', '#FF9E7A'], ['Rose', '#F48FB1'], ['Lilac', '#B9A2F5'], ['Sky', '#7DC4F5'], ['Mint', '#7FD9A8'], ['Cream', '#F2EAD3']];
  var charNow = { shape: 'ears', color: '#F5B83D' };
  function shapeOf(k) { for (var i = 0; i < SHAPES.length; i++) if (SHAPES[i][0] === k) return SHAPES[i]; return SHAPES[0]; }
  function applyCharacter(c) {
    if (!c) return;
    charNow = { shape: c.shape, color: c.color };
    var sh = shapeOf(c.shape);
    scene.querySelectorAll('.cr:not(.cr-mini) .f path').forEach(function (p) { p.setAttribute('d', sh[2]); });
    scene.querySelectorAll('.cr:not(.cr-mini)').forEach(function (e) { e.style.setProperty('--et', sh[3]); e.style.setProperty('--el', sh[4] || '30%'); e.style.setProperty('--er', sh[5] || '56%'); });
    document.documentElement.style.setProperty('--cr', c.color);
    if (n && !(onbStep === 4 && n.dataset.s === 'onb')) n.style.setProperty('--gcol', c.color);
  }
  function crHtml(cls, size, sh, mood) {
    return '<div class="cr ' + cls + '" data-m="' + (mood || 'awake') + '" style="position:relative;left:auto;top:auto;width:' + size + 'px;height:' + size + 'px;transform:none;--et:' + sh[3] + ';--el:' + (sh[4] || '30%') + ';--er:' + (sh[5] || '56%') + '"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><path d="' + sh[2] + '"/></svg></i><i class="ey l"></i><i class="ey r"></i></div></div>';
  }

  /* ---- onboarding: five short steps inside the notch ---- */

  /* ---- moments: the party at the end of onboarding, and the first hello beside the notch ---- */
  var celebrating = false, hello = false, helloNext = false, curH = 232, idleXf = '', idleD = 18, lastSt = 'idle';
  function celebrate() {
    var box = q('.onb'), reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) return;
    celebrating = true;
    box.style.transition = 'opacity .35s'; box.style.opacity = '0';
    cr.dataset.m = 'happy';
    cr.style.width = cr.style.height = '70px';
    cr.style.transform = 'translate(-35px,' + Math.round(curH / 2 - 38) + 'px)';
    var ci = cr.querySelector('.cr-in'); ci.classList.remove('party'); void ci.offsetWidth; ci.classList.add('party');
    confetti();
    setTimeout(function () {
      celebrating = false; ci.classList.remove('party');
      cr.dataset.m = 'awake';
      if (snap) layout(lastSt, snap);               /* collapses back to the small one at the top left */
      box.style.opacity = ''; box.classList.remove('go'); void box.offsetWidth; box.classList.add('go');
    }, 1900);
  }
  function confetti() {
    var host = q('.p-onb'), cols = ['#4ADE80', '#86EFAC', charNow.color, '#FDE68A', '#FFFFFF'], k, html = '';
    for (k = 0; k < 18; k++) {
      var a = (k / 18) * Math.PI * 2 + Math.random() * 0.5, dist = 70 + Math.random() * 60;
      html += '<i class="cf" style="--x:' + Math.round(Math.cos(a) * dist) + 'px;--y:' + Math.round(Math.sin(a) * dist * 0.75 - 16) + 'px;--r:' + Math.round(Math.random() * 360) + 'deg;--d:' + (0.05 + Math.random() * 0.2).toFixed(2) + 's;background:' + cols[k % cols.length] + '"></i>';
    }
    var wrap = document.createElement('div'); wrap.className = 'cf-wrap'; wrap.style.top = Math.round(curH / 2 - 3) + 'px'; wrap.innerHTML = html; host.appendChild(wrap);
    setTimeout(function () { wrap.remove(); }, 1700);
  }
  /* After setup the character peeks out beside the notch, says hi, and tucks back in. */
  function sayHello() {
    hello = true;
    var ci = cr.querySelector('.cr-in');
    cr.style.opacity = 1; cr.dataset.m = 'awake';
    ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive');
    setTimeout(function () { ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); cr.dataset.m = 'happy'; }, 700);
    setTimeout(function () { cr.dataset.m = 'awake'; blinkEl(cr); }, 1500);
    setTimeout(function () { cr.style.transform = idleXf + ' translateX(' + (idleD + 4) + 'px) scale(.55)'; cr.style.opacity = 0; }, 2500);
    setTimeout(function () { hello = false; if (snap) layout(lastSt, snap); }, 3100);
  }

  var onbStep = -1, onbSig = '', onbLast = null;
  function oi(i, inner) { return '<div class="o-i" style="--i:' + i + '">' + inner + '</div>'; }
  function otitle(o, title, sub) {
    return oi(0, '<div class="px-4 pt-0.5 text-xs tabular-nums text-muted-foreground">' + (o.step + 1) + ' of ' + o.total + '</div>') +
      oi(1, '<p class="mt-1 px-4 text-[15px] font-semibold leading-5 tracking-[-0.02em]">' + title + '</p>') +
      oi(2, '<p class="mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground">' + sub + '</p>');
  }
  function ofoot(i, back, mid, label, action) {
    return oi(i, '<div class="mt-3 flex h-9 items-center gap-1 px-2.5">' + (back ? Button('ghost', 'Back', '', 'o-back') : '') + '<span class="flex-1"></span>' + (mid || '') +
      Button('default', label, Kbd(svg('enter', 'size-2'), 1), 'o-primary pr-0.5" data-a="' + action) + '</div>');
  }
  function tick(done) { return done ? '<span class="grid size-4 flex-none place-items-center rounded-full bg-emerald-400/15 text-emerald-400">' + svg('check', 'size-2.5') + '</span>' : '<span class="size-4 flex-none rounded-full border border-muted-foreground/40"></span>'; }
  function orow(icon, label, right) { return '<div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]">' + icon + '<span class="flex-1">' + label + '</span><span class="text-muted-foreground">' + right + '</span></div>'; }
  function ohint(left, text) { return '<div class="flex items-center gap-3"><span class="flex w-14 flex-none">' + left + '</span><span class="text-muted-foreground">' + text + '</span></div>'; }
  function onbDo(a) { if (a === 'finish') helloNext = true; if (a === 'settings') post({ type: 'openSettings' }); else post({ type: 'onb', action: a }); }
  function pickCharacter(c) {
    var shapeChanged = c.shape !== charNow.shape, box = q('.onb'), pv = q('.cr-pv');
    post({ type: 'character', shape: c.shape, color: c.color });
    var commit = function () { applyCharacter(charNow); };
    if (shapeChanged && pv) {
      /* squash, swap the shape at the lowest point, spring back */
      var f = pv.querySelector('.f'); f.classList.remove('swap'); void f.offsetWidth; f.classList.add('swap');
      setTimeout(commit, 120); setTimeout(function () { f.classList.remove('swap'); }, 560);
    } else commit();
    charNow = { shape: c.shape, color: c.color };
    document.documentElement.style.setProperty('--cr', c.color); if (n && !(onbStep === 4 && n.dataset.s === 'onb')) n.style.setProperty('--gcol', c.color);
    if (box) {
      box.querySelectorAll('.o-shape').forEach(function (b) {
        var on = b.dataset.k === c.shape;
        b.className = b.className.replace(/bg-white\/\[0\.14\] ring-1 ring-white\/40|bg-white\/\[0\.06\] hover:bg-white\/\[0\.1\]/, on ? 'bg-white/[0.14] ring-1 ring-white/40' : 'bg-white/[0.06] hover:bg-white/[0.1]');
      });
      box.querySelectorAll('.o-color').forEach(function (b) {
        var on = b.dataset.c === c.color;
        b.className = b.className.replace(/ring-2 ring-white ring-offset-2 ring-offset-black|hover:scale-110/, on ? 'ring-2 ring-white ring-offset-2 ring-offset-black' : 'hover:scale-110');
      });
    }
    if (pv) {
      pv.dataset.m = 'happy';
      var ci = pv.querySelector('.cr-in'); ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop');
      clearTimeout(pv._t); pv._t = setTimeout(function () { pv.dataset.m = 'awake'; }, 850);
    }
  }
  /* the preview and the little shape tiles are alive: they blink and glance about while you choose */
  function blinkEl(el) { el.classList.add('blink'); setTimeout(function () { el.classList.remove('blink'); }, 150); }
  (function previewLife() {
    var pv = q('.cr-pv');
    if (pv && pv.dataset.m === 'awake') {
      blinkEl(pv); if (Math.random() < 0.3) setTimeout(function () { blinkEl(pv); }, 280);
      pv.style.setProperty('--lx', ((Math.random() - 0.5) * 5).toFixed(2) + 'px'); pv.style.setProperty('--ly', ((Math.random() - 0.5) * 3).toFixed(2) + 'px');
    }
    scene.querySelectorAll('.cr-mini').forEach(function (m, i) { if (Math.random() < 0.55) setTimeout(function () { blinkEl(m); }, i * 130); });
    setTimeout(previewLife, 1700 + Math.random() * 2400);
  })();
  function onbRender(o, animate) {
    onbLast = o;
    var box = q('.onb'), h = '', g = o.accessibility, st = o.step;
    if (st === 0) {
      var shapes = SHAPES.map(function (sh) {
        return '<button class="o-shape grid size-11 cursor-pointer place-items-center rounded-lg transition active:scale-95 ' + (sh[0] === charNow.shape ? 'bg-white/[0.14] ring-1 ring-white/40' : 'bg-white/[0.06] hover:bg-white/[0.1]') + '" data-k="' + sh[0] + '" aria-label="' + sh[1] + '" title="' + sh[1] + '">' + crHtml('cr-mini', 24, sh) + '</button>';
      }).join('');
      var colors = PALETTE.map(function (c) {
        return '<button class="o-color size-5 cursor-pointer rounded-full transition ' + (c[1] === charNow.color ? 'ring-2 ring-white ring-offset-2 ring-offset-black' : 'hover:scale-110') + '" style="background:' + c[1] + '" data-c="' + c[1] + '" aria-label="' + c[0] + '" title="' + c[0] + '"></button>';
      }).join('');
      h = otitle(o, 'Make it yours', 'Pick a shape and a colour for your character.') +
        oi(3, '<div class="mt-3 flex items-center gap-4 px-4"><div class="relative grid size-[76px] flex-none place-items-center overflow-hidden rounded-2xl pv-tile"><i class="pv-bloom absolute inset-0"></i><span class="relative">' + crHtml('cr-pv', 52, shapeOf(charNow.shape)) + '</span></div><div class="flex min-w-0 flex-col gap-3"><div class="flex gap-1.5">' + shapes + '</div><div class="flex flex-wrap gap-2.5">' + colors + '</div></div></div>') +
        ofoot(4, false, '', 'Next', 'next');
    } else if (st === 1) {
      h = otitle(o, 'Let Perch reply for you', 'Perch pastes and sends your replies, and opens with \u2318\u2325. macOS asks you to allow it once.') +
        oi(3, '<div class="mt-3 px-4">' + orow(tick(g), 'Accessibility', g ? 'Allowed' : 'Waiting for you\u2026') + '</div>') +
        oi(4, g ? '' : '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">Switch Perch on in System Settings. Switched it on but nothing changes? <button class="o-restart cursor-pointer underline underline-offset-2 hover:text-foreground">Restart Perch</button></p>') +
        ofoot(5, true, g ? '' : Button('ghost', 'Skip', '', 'o-skip'), g ? 'Next' : 'Open System Settings', g ? 'next' : 'accessibility');
    } else if (st === 2) {
      var rows = o.sources.map(function (x) {
        var sub = o.scanning ? 'Scanning\u2026' : (x.count ? x.names.slice(0, 2).join(', ') + (x.count > 2 ? ', +' + (x.count - 2) : '') : 'Nothing found yet');
        var sw = '<button role="switch" aria-checked="' + x.enabled + '" aria-label="Include ' + x.name + '" data-id="' + x.id + '" class="o-sw relative h-[18px] w-[30px] flex-none cursor-pointer rounded-full transition-colors duration-200 ' + (x.enabled ? 'bg-emerald-400' : 'bg-white/20') + '"><i class="absolute top-[2px] block size-[14px] rounded-full bg-white shadow transition-all duration-200 ' + (x.enabled ? 'left-[14px]' : 'left-[2px]') + '"></i></button>';
        return '<div class="flex h-11 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3"><span class="flex-none ' + (x.enabled ? '' : 'opacity-50') + '">' + App(x.id, 'size-5') + '</span><span class="min-w-0 flex-1"><span class="block text-[13px] font-medium leading-4">' + x.name + '</span><span class="block truncate text-xs leading-4 text-muted-foreground">' + sub + '</span></span>' + (o.scanning ? Spinner('size-3.5') : '') + sw + '</div>';
      }).join('');
      h = otitle(o, 'Choose your apps', 'Perch only reads the ones you switch on. You can change this later from the menu bar.') +
        oi(3, '<div class="mt-3 flex flex-col gap-1.5 px-4">' + rows + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">macOS may ask to let Perch see a project folder. Choose Allow.</p>') +
        ofoot(5, true, '', 'Next', 'next');
    } else if (st === 3) {
      var sm = { ready: ['Apple Intelligence is on', 'All set. Summaries run on your Mac.'], off: ['Turn on Apple Intelligence', 'Takes a few minutes the first time.'], downloading: ['Downloading the model\u2026', 'A few GB. Keep working, this finishes on its own.'], unsupported: ["This Mac can't run it", 'Summaries stay plain, which still works.'] }[o.summaries] || ['', ''];
      var off = o.summaries === 'off';
      h = otitle(o, 'Better summaries', 'Written on your Mac. Nothing leaves it.') +
        oi(3, '<div class="mt-3 px-4">' + orow(o.summaries === 'downloading' ? '<span class="grid size-4 flex-none place-items-center">' + Spinner('size-3.5') + '</span>' : tick(o.summaries === 'ready'), sm[0], '') + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">' + sm[1] + '</p>') +
        ofoot(5, true, off ? Button('ghost', 'Skip', '', 'o-skip') : '', off ? 'Open Settings' : 'Next', off ? 'settings' : 'next');
    } else {
      h = otitle(o, 'You\u2019re all set', 'Here is how to reach Perch.') +
        oi(3, '<div class="mt-3 flex flex-col gap-2 px-4 text-[13px]">' + ohint(Kbd('\u2318\u2325'), 'Tap both to open or close Perch') + ohint(Kbd('\u2303\u2325P'), 'The welcome card') + ohint(Kbd('\u2303\u2325L'), 'Other projects') + ohint('<span class="text-xs text-muted-foreground">Hover</span>', 'Rest on the notch to peek') + '</div>') +
        ofoot(4, true, '', 'Done', 'finish');
    }
    box.className = 'onb' + (animate ? ' go' : '');
    box.innerHTML = h;
    box.querySelectorAll('.o-primary').forEach(function (b) { b.onclick = function () { onbDo(b.dataset.a); }; });
    box.querySelectorAll('.o-skip').forEach(function (b) { b.onclick = function () { onbDo('next'); }; });
    box.querySelectorAll('.o-back').forEach(function (b) { b.onclick = function () { onbDo('back'); }; });
    box.querySelectorAll('.o-restart').forEach(function (b) { b.onclick = function () { onbDo('restart'); }; });
    box.querySelectorAll('.o-sw').forEach(function (b) { b.onclick = function () { post({ type: 'source', id: b.dataset.id, enabled: b.getAttribute('aria-checked') !== 'true' }); }; });
    box.querySelectorAll('.o-shape').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: b.dataset.k, color: charNow.color }); }; });
    box.querySelectorAll('.o-color').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: charNow.shape, color: b.dataset.c }); }; });
  }
  function onb(o) {
    if (!o) return;
    var sig = [o.step, o.accessibility, o.summaries, o.scanning, o.sources.map(function (x) { return x.id + x.enabled + x.count; }).join(',')].join('|');
    if (sig === onbSig) return;
    var animate = o.step !== onbStep; onbStep = o.step; onbSig = sig; onbRender(o, animate);
    if (animate && o.step === o.total - 1) setTimeout(celebrate, 60);
  }
  /* Return and the arrow keys, forwarded from the app while the card has the keyboard. */
  function onbKey(k) {
    if (k === 'enter') { var b = q('.o-primary'); if (b) b.click(); return; }
    if (onbStep !== 0) return;
    var i = 0; SHAPES.forEach(function (sh, j) { if (sh[0] === charNow.shape) i = j; });
    i = (i + (k === 'right' ? 1 : -1) + SHAPES.length) % SHAPES.length;
    pickCharacter({ shape: SHAPES[i][0], color: charNow.color });
  }

  /* ---- settings, inside the notch ---- */
  var setLast = null, setSig = '';
  function swHtml(on, key, label) {
    return '<button role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-k="' + key + '" class="s-sw relative h-[18px] w-[30px] flex-none cursor-pointer rounded-full transition-colors duration-200 ' + (on ? 'bg-emerald-400' : 'bg-white/20') + '"><i class="absolute top-[2px] block size-[14px] rounded-full bg-white shadow transition-all duration-200 ' + (on ? 'left-[14px]' : 'left-[2px]') + '"></i></button>';
  }
  function srow(left, right) { return '<div class="flex h-8 items-center gap-2.5 px-4 text-[13px]">' + left + '<span class="flex-none">' + right + '</span></div>'; }
  function slabel(t, sub) { return '<span class="min-w-0 flex-1 truncate">' + t + (sub ? ' <span class="text-muted-foreground">' + sub + '</span>' : '') + '</span>'; }
  function settingsRender(o) {
    setLast = o;
    var sh = shapeOf(charNow.shape), colorName = ''; PALETTE.forEach(function (c) { if (c[1] === charNow.color) colorName = c[0].toLowerCase(); });
    var seg = [10, 20, 60].map(function (m) {
      return '<button class="s-idle h-5 cursor-pointer rounded px-2 text-xs transition-colors ' + (o.idleMinutes === m ? 'bg-white/[0.16] text-foreground' : 'text-muted-foreground hover:text-foreground') + '" data-m="' + m + '">' + (m === 60 ? '1 hour' : m + ' min') + '</button>';
    }).join('');
    var sum = { ready: 'On your Mac', off: 'Apple Intelligence is off', downloading: 'Downloading the model\u2026', unsupported: 'Not supported on this Mac' }[o.summaries] || '';
    var rows = [
      srow('<span class="flex-none">' + crHtml('cr-mini', 20, sh) + '</span>' + slabel('Character', '<span class="text-muted-foreground">' + sh[1] + ', ' + colorName + '</span>'), Button('ghost', 'Change', '', 's-change')),
      srow(slabel('Claude Code'), swHtml(o.sources[0].enabled, 'claude', 'Include Claude Code')),
      srow(slabel('Codex'), swHtml(o.sources[1].enabled, 'codex', 'Include Codex')),
      srow(slabel('Come back after'), '<span class="flex rounded-md bg-white/[0.07] p-0.5">' + seg + '</span>'),
      srow(slabel('Summaries', sum), o.summaries === 'off' ? Button('ghost', 'Set up', '', 's-sum') : ''),
      srow(slabel('Reply and shortcuts', o.accessibility ? 'allowed' : 'needs access'), o.accessibility ? '' : Button('ghost', 'Allow', '', 's-ax')),
      srow(slabel('Open at login'), swHtml(o.login, 'login', 'Open at login'))
    ].join('');
    var box = q('.set');
    box.innerHTML = '<p class="px-4 pt-0.5 text-[15px] font-semibold leading-5 tracking-[-0.02em]">Settings</p><div class="mt-1.5">' + rows + '</div>' +
      '<div class="mt-2 flex h-9 items-center gap-1 px-2.5">' + Button('ghost', 'Replay onboarding', '', 's-replay') + Button('ghost', 'Quit Perch', '', 's-quit') + '<span class="flex-1"></span>' + Button('default', 'Done', Kbd('esc', 1), 's-done') + '</div>';
    box.querySelectorAll('.s-sw').forEach(function (b) { b.onclick = function () {
      var on = b.getAttribute('aria-checked') !== 'true';
      if (b.dataset.k === 'login') post({ type: 'setting', key: 'login', value: on }); else post({ type: 'source', id: b.dataset.k, enabled: on });
    }; });
    box.querySelectorAll('.s-idle').forEach(function (b) { b.onclick = function () { post({ type: 'setting', key: 'idleMinutes', value: +b.dataset.m }); }; });
    var on = function (sel, fn) { box.querySelectorAll(sel).forEach(function (b) { b.onclick = fn; }); };
    on('.s-change', function () { post({ type: 'onbOpen', step: 0 }); });
    on('.s-replay', function () { post({ type: 'onbOpen', step: 0 }); });
    on('.s-sum', function () { post({ type: 'openSettings' }); });
    on('.s-ax', function () { post({ type: 'onb', action: 'accessibility' }); });
    on('.s-quit', function () { post({ type: 'quit' }); });
    on('.s-done', function () { post({ type: 'dismiss' }); });
  }
  function settingsApply(o) {
    if (!o) return;
    var sig = JSON.stringify([o, charNow]); if (sig === setSig) return; setSig = sig; settingsRender(o);
  }

  window.perch = { _icons: function (o) { icons = o; }, hot: function (on) { n.dataset.hot = on ? '1' : ''; }, onbKey: onbKey, apply: apply, cursor: cursor, snoozeMenu: function (o) { snoozeMenu(o); }, replyMenu: function (o) { if (o && bRep.style.display === 'none') return; replyMenu(o); } };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'restore', setup: 'setup', onboarding: 'onb', settings: 'set' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  function dev(m) {
    if (!snap || m.type === 'size' || m.type === 'log' || m.type === 'snoozeMenu' || m.type === 'replyMenu' || m.type === 'openSettings') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'confirm' || m.type === 'dismiss' || m.type === 'snooze' || m.type === 'reply' || m.type === 'choose') s.phase = 'idle';
    if (m.type === 'character') { s.character = { shape: m.shape, color: m.color }; }
    if (m.type === 'onb' && s.onboarding) {
      var o = s.onboarding;
      if (m.action === 'next') o.step = Math.min(o.step + 1, o.total - 1);
      else if (m.action === 'back') o.step = Math.max(o.step - 1, 0);
      else if (m.action === 'finish') s.phase = 'idle';
      else if (m.action === 'accessibility') o.accessibility = true;
      if (o.step === 2 && m.action === 'next') { o.scanning = true; var held = JSON.parse(JSON.stringify(s)); held.timerToken++; apply(held); setTimeout(function () { var d2 = JSON.parse(JSON.stringify(held)); d2.onboarding.scanning = false; apply(d2); }, 1200); return; }
    }
    if (m.type === 'source' && s.onboarding) { s.onboarding.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'settings') { s.phase = 'settings'; s.settings = s.settings || { sources: [], summaries: 'ready', accessibility: true, idleMinutes: 20, login: false }; if (!s.settings.sources.length) s.settings.sources = [{ id: 'claude', enabled: true }, { id: 'codex', enabled: true }]; }
    if (m.type === 'setting' && s.settings) { s.settings[m.key] = m.value; }
    if (m.type === 'source' && s.settings) { s.settings.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'onbOpen') { window.perchDev.onboarding(m.step || 0, true); return; }
    if (m.type === 'onb' && !s.onboarding) { if (m.action === 'accessibility' && s.settings) { s.settings.accessibility = true; } else return; }
    if (m.type === 'quit') { s.phase = 'idle'; }
    if (m.type === 'switcher') s.phase = 'switcher';
    if (m.type === 'back') s.phase = 'open';
    s.timerToken++; s.autoCollapse = s.phase === 'open'; apply(s);
  }
  if (!NATIVE) {
    var P = [
      { id: 'onboarding', name: 'Onboarding flow', branch: 'main', away: '2h 14m', at: '11:32 AM', headline: 'You were fixing the permissions screen.', context: 'You swapped the sheet for a popover because it clipped on small windows.', next: 'Add the tooltip to the Accessibility row', topic: 'Permissions screen', app: 'xcode', attention: true, status: { kind: 'attention', text: 'Codex needs you', app: 'codex' }, steps: [{ icon: 'win', text: 'Put 3 windows back' }, { icon: 'file', text: 'Opened PermissionsView.swift' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'website', name: 'Website', branch: 'feature/hero', away: '20h', at: 'Yesterday 5:05 PM', headline: 'You were tightening the hero spacing.', context: 'You dropped the full-bleed video because it slowed the page down.', next: 'Check the hero at phone width', topic: 'Hero spacing', app: 'claude', attention: false, status: { kind: 'done', text: 'Build passing' }, steps: [{ icon: 'win', text: 'Put 2 windows back' }, { icon: 'term', text: 'Started the dev server on :3000' }, { icon: 'term', text: 'Resumed your Claude Code session' }] },
      { id: 'docs', name: 'Docs', branch: 'main', away: '1m', at: '11:58 PM', headline: 'You were rewriting the install guide.', context: 'You are moving the setup steps above the troubleshooting section.', next: '', topic: 'Install guide', app: 'claude', attention: false, status: { kind: 'running', text: 'Claude Code is working', app: 'claude' }, steps: [{ icon: 'win', text: 'Opened the Claude app' }, { icon: 'term', text: 'Went back to your session' }] },
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
      show: function (ph, setup, quiet) { clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); var s = Object.assign({}, base, { character: charNow, projects: quiet ? P.map(function (x) { return Object.assign({}, x, { attention: false }); }) : P, phase: ph, autoCollapse: ph === 'open', setup: setup || 'off', timerToken: Math.random() }); apply(s); },
      setNotch: function (has) {
        base.screen = has ? { hasNotch: true, notchW: 185, notchH: 32 } : { hasNotch: false, notchW: 0, notchH: 24 };
        if (snap) apply(Object.assign({}, snap, { screen: base.screen, timerToken: Math.random() }));
      },
      settings: function (o) {
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        apply(Object.assign({}, base, { phase: 'settings', character: charNow, autoCollapse: false, timerToken: Math.random(),
          settings: Object.assign({ sources: [{ id: 'claude', enabled: true }, { id: 'codex', enabled: true }], summaries: 'ready', accessibility: true, idleMinutes: 20, login: false }, o || {}) }));
      },
      onboarding: function (step, accessibility, summaries) {
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        var sources = [{ id: 'claude', name: 'Claude Code', count: 3, names: ['Website', 'Docs', 'Finance'], enabled: true }, { id: 'codex', name: 'Codex', count: 1, names: ['Onboarding flow'], enabled: true }];
        apply(Object.assign({}, base, { phase: 'onboarding', character: charNow, autoCollapse: false, timerToken: Math.random(),
          onboarding: { step: step, total: 5, accessibility: !!accessibility, summaries: summaries || 'off', scanning: false, sources: sources } }));
      },
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

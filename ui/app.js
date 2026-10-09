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
    /* label and key share a baseline: the key's letter sits on the line of the words, its box around it */
    return '<button class="' + BTN + ' ' + c + ' ' + (cls || '') + '">' + (extra ? '<span class="inline-flex items-baseline gap-1">' + label + extra + '</span>' : label) + '</button>';
  }
  /* an icon key gets an invisible character, so it has a text baseline like a letter key */
  function Kbd(t, onPrimary) { return '<kbd class="pointer-events-none inline-flex h-4 ' + (/^</.test(t) ? 'min-w-[22px]' : 'min-w-4') + ' items-center justify-center rounded-sm px-1 font-sans text-[10.5px] font-medium select-none ' + (onPrimary ? 'bg-primary-foreground/15 text-primary-foreground' : 'bg-muted text-muted-foreground') + '">' + (/^</.test(t) ? '\u200b' : '') + t + '</kbd>'; }
  var icons = {};
  function App(k, c) {
    if (icons[k]) return '<img class="' + (c || 'size-5') + ' flex-none rounded-[5px]" src="' + icons[k] + '" alt="">';
    /* stand-ins for the design page; the app always has the real icons */
    var g = {
      claude: ['#D97757', '<g stroke="#fff" stroke-width="1.7" stroke-linecap="round"><path d="M12 5.5v13"/><path d="M5.5 12h13"/><path d="M7.4 7.4l9.2 9.2"/><path d="M16.6 7.4l-9.2 9.2"/></g>'],
      codex: ['#F4F4F5', '<path d="M8 9.2l3 2.8-3 2.8M12.6 15h3.6" stroke="#18181B" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>']
    }[k] || ['#52525B', ''];
    return '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="' + g[0] + '"/>' + g[1] + '</svg>';
  }
  function Spinner(cls) { return '<svg class="animate-spin flex-none ' + (cls || 'size-3') + '" viewBox="0 0 24 24" fill="none" stroke="' + COLORS.running + '" stroke-width="3.5" stroke-linecap="round" aria-hidden="true"><path d="M12 3a9 9 0 1 1-9 9"/></svg>'; }
  /* what a session's status is, in words: the card's top line and each row of the list. `short` is the list's version. */
  function phrase(p, short) {
    var a = p.ask, k = p.status.kind;
    if (a) return { t: { permission: 'Needs your OK', question: 'Asked you something', plan: 'Has a plan for you' }[a.kind] || 'Needs you', c: COLORS.attention };
    if (k === 'attention') return { t: /error/.test(p.status.text) ? 'Stopped on an error' : (short ? 'Needs you' : (p.line || 'Needs you')), c: COLORS.attention };
    if (k === 'running') return { t: 'Working', c: COLORS.running, spin: true };
    if (k === 'done' && p.fresh !== false) return { t: short ? 'Finished' : (p.line || 'Finished'), c: COLORS.done };
    return { t: short || !p.line ? p.away + ' ago' : p.line, c: '' };
  }
  function Phrase(ph) { return (ph.spin ? Spinner('size-3') : '') + '<span class="' + (ph.c ? '' : 'text-muted-foreground') + '"' + (ph.c ? ' style="color:' + ph.c + '"' : '') + '>' + esc(ph.t) + '</span>'; }
  var ENTER = svg('enter', 'size-2');
  /* a footer action: `act` is what it does, `key` its shortcut */
  function Act(v, label, key, act) { return Button(v, label, key ? Kbd(key, v === 'default') : '', (v === 'default' ? 'pr-0.5' : '') + '" data-act="' + act); }
  function header(inner, right, i) { return '<div class="rv flex h-9 items-center gap-2 pl-4 pr-4" style="--i:' + (i || 0) + '"><div class="min-w-0 flex-1">' + inner + '</div>' + (right || '') + '</div>'; }

  /* ---- markup (built once) ---- */
  var scene = document.getElementById('scene');
  scene.innerHTML =
    '<div class="cr" data-m="sleep"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><path d="' + DOME.d + '"/><path class="pl" d=""/><path class="fd" d=""/></svg></i><i class="ck l"></i><i class="ck r"></i><i class="ey l"></i><i class="ey r"></i></div><i class="dot"></i><i class="say"></i></div>' +
    '<div class="n perch" data-s="idle"><i class="ear l"></i><i class="ear r"></i><div class="clip"><i class="glow"></i>' +
    '<div class="pane p-open">' + '<button aria-label="Settings" title="Settings (S)" class="x-gear rv absolute right-[30px] top-[7px] z-10 flex h-[18px] cursor-pointer items-center gap-1 rounded-md pl-[3px] pr-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + Kbd('S') + '</button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-1.5">' +
      /* the project is the heading; its status, in words, sits on the same line */
      '<div class="rv mt-1.5 flex h-[18px] items-center gap-2 px-4" style="--i:1"><span class="o-app flex flex-none"></span><span dir="auto" class="o-name min-w-0 flex-1 truncate text-[13.5px] font-semibold tracking-[-0.02em]"></span><span class="o-st flex flex-none items-center gap-1.5 text-xs"></span></div>' +
      '<p dir="auto" class="o-h rv mt-1.5 px-4 text-[13px] leading-[18px]" style="--i:2"></p>' +
      '<p dir="auto" class="o-c rv mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground line-clamp-2" style="--i:2"></p>' +
      '<div class="o-ask rv px-4" style="--i:3"></div>' +
      '<p class="o-nx rv mt-2.5 flex items-baseline gap-2 px-4 text-[13px] leading-[18px]" style="--i:3"><span class="o-nl font-medium text-foreground/70">Next</span><span dir="auto" class="o-x min-w-0 flex-1 text-foreground"></span></p>' +
      '<div class="rv relative mt-2 h-9 px-2.5" style="--i:4"><div class="f-main flex h-9 items-center gap-1">' + Button('ghost', 'All sessions', Kbd('Tab'), 'x-list pl-1.5') + '<span class="flex-1"></span><span class="o-acts flex items-center gap-1"></span></div>' +
      '<div class="f-rep hidden h-9 items-center gap-1.5"><button aria-label="Close reply" title="Close (Esc)" class="x-rclose grid size-7 flex-none cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground">' + svg('x', 'size-3') + '</button><input class="r-in h-7 min-w-0 flex-1 rounded-lg bg-white/[0.1] px-2.5 text-[13px] text-foreground caret-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none transition-[background-color,box-shadow] duration-200 placeholder:text-white/35 focus:bg-white/[0.13] focus:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]" placeholder="Reply to Claude\u2026" spellcheck="false" autocomplete="off" aria-label="Reply">' + Button('default', '<span class="x-send-l">Send</span>', Kbd(svg('enter', 'size-2'), 1), 'x-send h-7 rounded-lg pr-1') + '</div>' +
      '<div class="f-snz hidden h-9 items-center gap-1"><span class="pl-1.5 text-[13px] text-muted-foreground">Remind me in</span><span class="flex-1"></span>' + Button('ghost', '30 min', Kbd('1'), 'x-s1') + Button('ghost', '2 hours', Kbd('2'), 'x-s2') + Button('ghost', 'Tomorrow', Kbd('3'), 'x-s3') + '</div></div>' +
    '</div></div>' +
    /* in the list, letters type into the filter, so Settings is Command+comma here */
    '<div class="pane p-switch">' + '<button aria-label="Settings" title="Settings (\u2318,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 flex h-[18px] cursor-pointer items-center gap-1 rounded-md pl-[3px] pr-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + Kbd('\u2318,') + '</button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="s-h truncate text-sm font-medium leading-4">Jump back in</div>', '<span class="s-n flex-none text-xs text-muted-foreground">Type to filter</span>') +
      '<div class="rv s-l max-h-[184px] overflow-y-auto px-1.5 pb-1" style="--i:1"></div>' +
      '<div class="rv s-ft flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground" style="--i:3"><span class="flex items-baseline gap-1.5">' + Kbd('\u2191\u2193') + 'Choose</span><button class="x-back flex cursor-pointer items-baseline gap-1.5 rounded-md px-1 text-muted-foreground transition-colors hover:text-foreground">' + Kbd('Tab') + 'Details</button><span class="flex items-baseline gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Open</span><span class="flex items-baseline gap-1.5">' + Kbd('esc') + 'Close</span></div>' +
    '</div></div>' +
    '<div class="pane p-setup">' + '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="text-sm font-medium leading-4">Better summaries</div><div class="mt-0.5 text-xs leading-4 text-muted-foreground">Written on your Mac. Nothing leaves it.</div>') +
      '<div class="rv flex flex-col gap-0.5 px-4 pb-1 pt-0.5 su-rows" style="--i:1"></div>' +
      '<div class="rv flex h-9 items-center gap-1 px-2.5" style="--i:2"><span class="su-note min-w-0 flex-1 pl-1.5 text-xs text-muted-foreground"></span><span class="su-btns flex items-center gap-1"></span></div>' +
    '</div></div>' +
    '<div class="pane p-onb">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-1.5"><div class="onb"></div></div></div>' +
    '<div class="pane p-set">' + '<span class="rv absolute left-11 top-[7px] z-10 flex h-[18px] items-center text-[13px] font-medium tracking-[-0.01em]" style="--i:0">Settings</span>' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-1.5"><div class="set"></div></div></div>' +
    '</div></div>';

  /* Inline markdown for summaries: **bold**, *italic*, `code`, [links](url) as plain text. Escaped first, so nothing can inject markup. */
  function md(t) {
    var h = String(t || '').replace(/^\s*(#{1,6}\s+|[-*]\s+)/, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return h.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/`([^`]+)`/g, '<code class="rounded bg-white/[0.09] px-1 py-px font-mono text-[11.5px] text-foreground/90">$1</code>')
      .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, function (m, a, b) { return '<strong class="font-semibold text-foreground">' + (a || b) + '</strong>'; })
      .replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?!\*)/g, '$1<em>$2</em>');
  }
  /* Everything that comes from a session (names, titles, prompts) is text, never markup. */
  function esc(t) { return String(t == null ? '' : t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
  function q(c) { return scene.querySelector(c); }
  var n = q('.n'), cr = q('.cr');
  /* the card's actions are drawn per state (Pick up, Allow, an option...); one listener handles them all */
  q('.p-open').addEventListener('click', function (e) {
    var b = e.target.closest('[data-act]'); if (!b) return;
    var a = b.dataset.act;
    if (a === 'go') post({ type: 'confirm' });
    else if (a === 'reply') replyMenu(true);
    else if (a === 'snooze') snoozeMenu(true);
    else if (a === 'allow' || a === 'deny') post({ type: 'answer', choice: a });
    else if (a === 'pick') askKey(String(+b.dataset.i + 1));
    else if (a === 'qback') askKey('back');
    else if (a === 'qnext') askKey('next');
  });
  /* "Not now" asks when to come back: 30 min, 2 hours or tomorrow morning. */
  var fMain = q('.f-main'), fSnz = q('.f-snz'), fRep = q('.f-rep'), footers = [fMain, fSnz, fRep];
  /* The footer changes between its actions, Reply and Not now. The old row fades up and away while the new one rises in. */
  function footer(el) {
    footers.forEach(function (f) { if (f._out) { f._out.cancel(); f._out = null; f.style.position = f.style.left = f.style.right = f.style.top = ''; f.style.display = 'none'; } });
    var was = footers.filter(function (f) { return f.style.display !== 'none' && getComputedStyle(f).display !== 'none'; })[0];
    if (was === el) return;
    footers.forEach(function (f) { if (f !== was) f.style.display = f === el ? 'flex' : 'none'; });
    if (!was) return;
    if (!n.offsetParent || n.dataset.s !== 'open' || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) { was.style.display = 'none'; return; }
    was.style.position = 'absolute'; was.style.left = was.style.right = '10px'; was.style.top = '0';
    var out = was._out = was.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-6px)' }], { duration: 150, easing: 'cubic-bezier(.4,0,1,1)' });
    var done = function () { if (was._out !== out) return; was._out = null; out.cancel(); was.style.display = 'none'; was.style.position = was.style.left = was.style.right = was.style.top = ''; };
    out.onfinish = done; setTimeout(done, 220);   /* the timer finishes it even when animations are paused */
    el.animate([{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }], { duration: 260, delay: 70, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
  }
  function snoozeMenu(open, quiet) {
    footer(open ? fSnz : fMain);
    if (!quiet) post({ type: 'snoozeMenu', open: open });
  }
  /* "Reply": answer a question Claude asked without opening the session first. The reply is pasted into the session. */
  var rIn = q('.r-in');
  function replyMenu(open, quiet) {
    footer(open ? fRep : fMain);
    if (open) setTimeout(function () { rIn.focus(); }, 30); else { rIn.value = ''; rIn.blur(); }
    if (!quiet) post({ type: 'replyMenu', open: open });
  }
  function sendReply() { var t = rIn.value.trim(); if (!t) return; replyMenu(false, true); post({ type: 'reply', text: t }); }
  q('.x-send').onclick = sendReply;
  q('.x-rclose').onclick = function () { replyMenu(false); };
  rIn.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); sendReply(); } else if (e.key === 'Escape') { e.preventDefault(); replyMenu(false); } e.stopPropagation(); });
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

  /* Questions, one at a time: a number answers and moves on, Back returns, the last one sends them all together. */
  var asking = { key: '', step: 0, picks: [], p: null };
  function questionCard(p, a) {
    var key = p.id + '|' + a.subject + '|' + a.questions.length;
    if (asking.key !== key) asking = { key: key, step: 0, picks: a.questions.map(function () { return []; }), p: p };
    asking.p = p;
    var n = a.questions.length, qn = a.questions[asking.step], picks = asking.picks[asking.step];
    q('.o-st').innerHTML = Phrase({ t: n > 1 ? 'Question ' + (asking.step + 1) + ' of ' + n : 'Asked you something', c: COLORS.attention });
    var h = q('.o-h'); h.innerHTML = esc(qn.text) + (qn.multi ? ' <span class="text-muted-foreground">Choose any</span>' : ''); h.title = qn.text; h.classList.add('line-clamp-2');
    var c = q('.o-c'); c.textContent = ''; c.style.display = 'none';
    q('.o-ask').innerHTML = '<div class="-mx-2 mt-1.5 flex flex-col">' + qn.options.map(function (o, i) {
      var on = picks.indexOf(o) >= 0, rec = /\s*\(recommended\)\s*$/i, label = o.replace(rec, ''), note = qn.notes[i] || '';
      return '<button data-act="pick" data-i="' + i + '" title="' + esc(note) + '" class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-2 py-1 text-left transition-colors ' + (on ? 'bg-white/[0.1]' : 'hover:bg-white/[0.06]') + '">' +
        Kbd(String(i + 1)) + '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">' + esc(label) + (rec.test(o) ? '<span class="ml-1.5 text-xs text-muted-foreground">Recommended</span>' : '') + '</span>' +
        (note ? '<span class="block truncate text-[11.5px] leading-[14px] text-muted-foreground">' + esc(note) + '</span>' : '') + '</span>' +
        (qn.multi ? '<span class="flex-none ' + (on ? 'text-emerald-400' : 'text-transparent') + '">' + svg('check', 'size-3') + '</span>' : '') + '</button>';
    }).join('') + '</div>';
    q('.o-nx').style.display = 'none';
    var last = asking.step === n - 1, ready = qn.multi && picks.length;
    q('.o-acts').innerHTML = (asking.step ? Act('ghost', 'Back', '\u2190', 'qback') : Act('ghost', 'Not now', 'N', 'snooze')) +
      (ready ? Act('default', last ? 'Send' : 'Next', ENTER, 'qnext') : Act(asking.step ? 'ghost' : 'default', 'Pick up', ENTER, 'go'));
  }
  function askKey(k) {
    var a = asking.p && asking.p.ask; if (!a || !a.questions || !a.questions.length) return;
    var n = a.questions.length, qn = a.questions[asking.step], picks = asking.picks[asking.step];
    var redraw = function () {
      questionCard(asking.p, a); if (snap) layout(lastSt, snap);
      if (!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) [q('.o-h'), q('.o-ask')].forEach(function (el) { el.animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 220, easing: 'cubic-bezier(.2,.9,.3,1)' }); });
    };
    var forward = function () {
      if (asking.step < n - 1) { asking.step++; redraw(); return; }
      var answers = {}; a.questions.forEach(function (x, i) { answers[x.text] = asking.picks[i].join(', '); });
      post({ type: 'answer', answers: answers });
    };
    if (/^[1-9]$/.test(k)) {
      var o = qn.options[+k - 1]; if (!o) return;
      if (qn.multi) { var at = picks.indexOf(o); if (at >= 0) picks.splice(at, 1); else picks.push(o); redraw(); }
      else { asking.picks[asking.step] = [o]; forward(); }
    } else if (k === 'back') { if (asking.step) { asking.step--; redraw(); } }
    else if (k === 'next') { if (picks.length) forward(); }
    else if (k === 'enter') { if (qn.multi && picks.length) forward(); else post({ type: 'confirm' }); }
  }

  function fill(p) {
    var a = p.ask, ph = phrase(p), h = q('.o-h'), c = q('.o-c'), box = q('.o-ask');
    q('.o-app').innerHTML = App(p.app, 'size-3.5');
    q('.o-name').textContent = p.name;
    var st = q('.o-st'); st.innerHTML = Phrase(ph); st.title = p.status.text;
    h.classList.remove('line-clamp-2'); h.title = '';
    if (a && a.kind === 'question' && a.answerable && a.questions && a.questions.length) { questionCard(p, a); return; }
    if (a) {
      /* what the agent is asking, and the means to answer it right here */
      h.textContent = a.kind === 'question' ? a.subject : a.title;
      c.textContent = a.kind === 'plan' ? a.subject : '';
      box.innerHTML = a.kind === 'permission' && a.subject
        ? '<div dir="auto" class="mt-2 line-clamp-2 break-all rounded-md bg-white/[0.07] px-2.5 py-1.5 font-mono text-xs leading-[18px] text-foreground/90">' + esc(a.subject) + '</div>'
        : '';
    } else {
      h.innerHTML = md(p.headline); c.innerHTML = md(p.context); box.innerHTML = '';
    }
    c.style.display = c.innerHTML ? '' : 'none';
    /* last line of defence: git housekeeping is never shown as a next step, whatever produced it (old cache included) */
    var nx = a || /^\W*(next:\s*)?(commit|push|merge|rebase|stage)\b(?! notification)|\b(pull request|uncommitted|git (add|commit|push|merge|rebase))\b|\bopen (a|the) pr\b/i.test(p.next || '') ? '' : (p.next || '');
    nx = nx.replace(/^\s*next\s*[:,-]\s*/i, '');   /* the row is already labelled Next (old cache, model output) */
    /* while it works, the same row says what it is doing right now */
    var now = !a && p.status.kind === 'running' && p.now;
    if (now) nx = now;
    q('.o-nl').textContent = now ? 'Now' : 'Next';
    q('.o-x').classList.toggle('truncate', !!now);   /* the step changes every few seconds: one line, never a jump in height */
    q('.o-x').innerHTML = md(nx);
    q('.o-nx').style.display = nx ? '' : 'none';
    q('.o-acts').innerHTML = a && a.answerable && a.kind === 'permission' ? Act('ghost', 'Deny', 'D', 'deny') + Act('ghost', 'Pick up', ENTER, 'go') + Act('default', 'Allow', 'A', 'allow')
      : a ? Act('ghost', 'Not now', 'N', 'snooze') + Act('default', 'Pick up', ENTER, 'go')
      : Act('ghost', 'Reply', 'R', 'reply') + Act('ghost', 'Not now', 'N', 'snooze') + Act('default', 'Pick up', ENTER, 'go');
  }
  /* Five rows show at a time; the rest scroll, with a soft edge where there is more. */
  var sl = q('.s-l'), listSig = '', lastSel = -1;
  function edges() {
    var up = sl.scrollTop > 1, down = sl.scrollTop + sl.clientHeight < sl.scrollHeight - 1;
    sl.style.webkitMaskImage = sl.style.maskImage = up || down ? 'linear-gradient(' + (up ? 'transparent, #000 24px' : '#000, #000') + ', ' + (down ? '#000 calc(100% - 24px), transparent' : '#000') + ')' : '';
  }
  sl.addEventListener('scroll', edges, { passive: true });
  function list(s) {
    var empty = !s.projects.length, typed = s.query || '', rows = s.shown || s.projects.map(function (p, k) { return k; });
    q('.s-ft').style.display = empty ? 'none' : '';
    /* what you typed replaces the title, with a caret; the right side counts what is left */
    q('.s-h').innerHTML = typed ? '<span dir="auto">' + esc(typed) + '</span><i class="s-caret"></i>' : 'Jump back in';
    q('.s-n').textContent = typed ? rows.length + ' of ' + s.projects.length : (s.projects.length > 1 ? 'Type to filter' : '');
    if (!empty && !rows.length) {
      listSig = ''; marquee(null);
      sl.innerHTML = '<div class="px-2.5 pb-3 pt-1 text-[13px] leading-[18px] text-muted-foreground">No sessions match</div>';
      edges(); return;
    }
    if (empty) {
      listSig = ''; marquee(null);
      /* asked for before the first scan finished, or nothing in the last two weeks: say so instead of showing nothing */
      sl.innerHTML = '<div class="flex flex-col gap-0.5 px-2.5 pb-3 pt-1 text-[13px] leading-[18px]">' +
        (s.scanning ? '<span class="flex items-center gap-2 text-muted-foreground">' + Spinner('size-3') + 'Looking for your sessions\u2026</span>'
          : '<span class="text-foreground">Nothing to pick up yet</span><span class="text-muted-foreground">Claude Code and Codex sessions from the last two weeks show up here.</span>') + '</div>';
      edges(); return;
    }
    /* rows are drawn again only when they change, so a row that is reading itself out is not cut short */
    var html = rows.map(function (k) {
      var p = s.projects[k];
      return '<div class="row flex h-9 cursor-default items-center gap-2 rounded-md px-1.5 text-sm transition-colors" data-i="' + k + '">' +
        App(p.app) +
        /* name and title each truncate on their own, so a Hebrew title loses its end, not its start */
        '<span class="flex min-w-0 flex-1 items-baseline gap-2"><span class="mq nm min-w-0 flex-[0_1_auto] truncate font-medium"><span class="mq-in">' + esc(p.name) + '</span></span>' +
        (p.topic ? '<span dir="auto" class="mq tp min-w-0 flex-[1_1_0%] truncate text-left text-muted-foreground"><span class="mq-in">' + esc(p.topic) + '</span></span>' : '') + '</span>' +
        '<span class="st flex flex-none items-center gap-2 text-xs tabular-nums"></span></div>';
    }).join('');
    if (html !== listSig) {
      listSig = html; hovered = null; lastSel = -1; marquee(null); sl.innerHTML = html;
      /* a row shows that session's card in the notch; Return (or the card's Pick up) opens it */
      sl.querySelectorAll('.row').forEach(function (r) {
        r.onclick = function () { post({ type: 'details', index: +r.dataset.i }); };
        r.ondblclick = function () { post({ type: 'choose', index: +r.dataset.i }); };
        r.onmouseenter = function () { hovered = r; marquee(r); };
        r.onmouseleave = function () { hovered = null; marquee(sl.querySelector('.row.bg-accent')); };
      });
    }
    var sel = null;
    sl.querySelectorAll('.row').forEach(function (r) {
      var on = +r.dataset.i === s.selected; r.classList.toggle('bg-accent', on); if (on) sel = r;
      var st = rowStatus(s.projects[+r.dataset.i]), el = r.querySelector('.st'); if (el.innerHTML !== st) el.innerHTML = st;
    });
    /* the chosen row stays in view, clear of the edge fades, as the arrows move past the fifth */
    if (sel) {
      var top = sel.offsetParent === sl ? sel.offsetTop : sel.offsetTop - sl.offsetTop, pad = 20;
      if (top - pad < sl.scrollTop) sl.scrollTop = top - pad;
      else if (top + sel.offsetHeight > sl.scrollTop + sl.clientHeight - pad) sl.scrollTop = top + sel.offsetHeight - sl.clientHeight + pad;
    }
    edges();
    /* whichever moved last reads out: the arrows' choice, or the row under the pointer */
    if (s.selected !== lastSel || !hovered) { lastSel = s.selected; marquee(sel); }
  }
  /* a row's status in words when it is news or needs you, and how long ago at the right edge. Working has no age: it sits at the edge itself. */
  function rowStatus(p) {
    var ph = phrase(p, true), word = ph.c ? '<span class="flex items-center gap-1.5">' + Phrase(ph) + '</span>' : '';
    if (p.status.kind === 'running') return word;
    return word + '<span class="min-w-[22px] text-right text-muted-foreground">' + esc(String(p.away || '').split(' ')[0]) + '</span>';
  }
  /* A row cut short reads itself out: after a second on it (hovered or chosen), its text glides left to the end, rests, and comes back. */
  var mq = { el: null, t: 0, anims: [] }, hovered = null;
  function marquee(row) {
    if (row && mq.el === row) return;
    clearTimeout(mq.t); mq.anims.forEach(function (a) { a.cancel(); });
    if (mq.el) mq.el.querySelectorAll('.mq-on').forEach(function (b) { b.classList.remove('mq-on', 'mq-rtl'); });
    mq = { el: row, t: 0, anims: [] };
    if (!row || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) return;
    mq.t = setTimeout(function () {
      /* the title if it is cut short, else the name; a right-to-left title glides the other way */
      var box = [row.querySelector('.tp'), row.querySelector('.nm')].filter(function (b) { return b && b.scrollWidth - b.clientWidth >= 4; })[0];
      if (!box || mq.el !== row) return;
      var inner = box.querySelector('.mq-in'), rtl = getComputedStyle(box).direction === 'rtl';
      var over = box.scrollWidth - box.clientWidth + 14;   /* clear of the fade at the far edge */
      box.classList.add('mq-on'); if (rtl) box.classList.add('mq-rtl');
      var go = over / 45 * 1000, rest = 1600, back = 600, wait = 1400, all = go + rest + back + wait;
      var at = function (ms) { return ms / all; };
      var x = function (v) { return { transform: 'translateX(' + (rtl ? -v : v) + 'px)' }; };
      mq.anims.push(inner.animate([
        Object.assign(x(0), { offset: 0, easing: 'cubic-bezier(.45,0,.55,1)' }), Object.assign(x(-over), { offset: at(go) }),
        Object.assign(x(-over), { offset: at(go + rest), easing: 'cubic-bezier(.4,0,.2,1)' }), Object.assign(x(0), { offset: at(go + rest + back) }), Object.assign(x(0), { offset: 1 })
      ], { duration: all, iterations: Infinity }));
      /* the left edge fades in only while the text is away from its start */
      mq.anims.push(box.animate([
        { '--mql': '0px', offset: 0 }, { '--mql': '12px', offset: at(Math.min(300, go)) }, { '--mql': '12px', offset: at(go + rest) },
        { '--mql': '0px', offset: at(go + rest + back) }, { '--mql': '0px', offset: 1 }
      ], { duration: all, iterations: Infinity }));
    }, 1000);
  }
  /* the auto-dismiss countdown: the glow slowly settles, nothing else on the card moves */
  function bar(on) {
    var g = q('.glow'); g.style.transition = 'none'; g.style.opacity = '';
    if (on) { void g.offsetWidth; g.style.transition = 'opacity 9s linear'; g.style.opacity = '.3'; }
    else g.style.transition = '';
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
    /* what needs you, in words, on a black pill beside the character: never a bare number on its corner */
    var dotEl = cr.querySelector('.dot');
    if (news) { var one = s.projects.filter(function (x) { return x.attention && x.id !== s.activeId; })[0]; dotEl.textContent = needN > 1 ? needN + ' need you' : phrase(one, true).t; }
    if (news && cr.dataset.news !== '1') { var ci = cr.querySelector('.cr-in'); ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive'); }
    /* on the character page the big preview is the character, so the small one steps out of its corner, and comes back after */
    var choosing = st === 'onb' && (onbStep === 0 || onbStep === 1) && !celebrating;
    if (choosing) cr.style.transform += ' translateY(-6px) scale(.3)';
    cr.style.opacity = (st === 'idle' && !news && !hello) || choosing ? 0 : 1;
    cr.dataset.news = news ? '1' : '';
    /* its face says how things are: wide-eyed when something needs you, happy when something finished */
    var cp = st === 'open' ? s.projects[s.selected] : null;
    if (!celebrating && !hello) cr.dataset.m = st === 'idle' ? (news ? 'alert' : 'sleep')
      : (cp && cp.status.kind === 'attention' ? 'alert' : (cp && cp.status.kind === 'done' && cp.fresh ? 'happy' : 'awake'));
    post({ type: 'size', width: w, height: h });
  }
  function apply(s) {
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', setup: 'setup', onboarding: 'onb', settings: 'set' }[s.phase];
    var p = s.projects[s.selected];
    if (st !== 'open') { snoozeMenu(false, true); replyMenu(false, true); }
    if (p) rIn.placeholder = 'Reply to ' + (p.app === 'codex' || p.status.app === 'codex' || /codex/i.test(p.status.text) ? 'Codex' : 'Claude') + '\u2026';
    applyCharacter(s.character);
    if (st === 'onb') onb(s.onboarding); else { onbStep = -1; onbSig = ''; }
    if (st === 'set') settingsApply(s.settings); else { setSig = ''; setFocus = 0; setAppAt = 0; }
    if (st === 'setup') setup(s.setup);
    if (p) fill(p);
    moments(s, st);
    if (st === 'switch') list(s); else { marquee(null); lastSel = -1; }
    /* Without Accessibility Perch cannot type for you: Reply copies the answer and opens the session. */
    var canSend = s.canSend !== false;
    q('.x-send-l').textContent = canSend ? 'Send' : 'Copy and open';
    q('.x-send').title = canSend ? '' : 'Perch needs Accessibility to type for you. Your reply is copied, ready to paste.';
    /* green only while a finished session is news; one you have already seen glows in the character's colour */
    var glow = { attention: ['251,146,60', '255,196,140'], done: ['74,222,128', '166,247,196'] };
    var gk = st === 'open' && p && glow[p.status.kind] && !(p.status.kind === 'done' && p.fresh === false) ? glow[p.status.kind] : null, g = gk || ['245,184,59', '255,222,140'];
    n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    n.dataset.g = gk ? 'status' : 'char';
    var allDone = st === 'onb' && s.onboarding && s.onboarding.step === s.onboarding.total - 1;
    n.style.setProperty('--gcol', allDone ? '#4ADE80' : (st === 'onb' && introGlow) || (s.character ? s.character.color : charNow.color));
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
    /* it hops when it wakes up, not every time its face changes */
    if ((m === 'awake' || m === 'alert') && (wasMood === 'sleep' || wasMood === 'peek')) { inner.classList.remove('hop'); void inner.offsetWidth; inner.classList.add('hop'); look(0, 0); }
    if (m !== 'peek') wasMood = m;
  }).observe(cr, { attributes: true, attributeFilter: ['data-m'] });
  /* cursor position in page coordinates, sent by Swift from anywhere on screen */
  var trackTimer = null;
  function cursor(x, y) {
    if (cr.dataset.m !== 'awake' && cr.dataset.m !== 'alert') return;
    var r = cr.getBoundingClientRect(), dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height / 2);
    var d = Math.max(1, Math.hypot(dx, dy)), k = Math.min(1, d / 40);
    tracking = true; look((dx / d) * 3.1 * k, (dy / d) * 2.2 * k);
    var pv = q('.cr-pv') || q('.cr-hi'); if (pv) { var pr = pv.getBoundingClientRect(), px = x - (pr.left + pr.width / 2), py = y - (pr.top + pr.height / 2), pd = Math.max(1, Math.hypot(px, py)), pk = Math.min(1, pd / 60); pv.style.setProperty('--lx', ((px / pd) * 4.5 * pk).toFixed(2) + 'px'); pv.style.setProperty('--ly', ((py / pd) * 3 * pk).toFixed(2) + 'px'); }
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
  var still = false;   /* snapshots: eyes open, no blink mid-capture */
  function blink() {
    if (!still && (cr.dataset.m === 'awake' || cr.dataset.m === 'alert')) {
      cr.classList.add('blink');
      setTimeout(function () { cr.classList.remove('blink'); if (Math.random() < 0.25) setTimeout(function () { cr.classList.add('blink'); setTimeout(function () { cr.classList.remove('blink'); }, 110); }, 140); }, 110);
    }
    setTimeout(blink, 1100 + Math.random() * 2000);
  }
  setTimeout(glance, 1500); setTimeout(peek, 4000); setTimeout(blink, 1200);



  /* ---- character: shape and colour, chosen in onboarding ---- */
  var SHAPES = [
    /* [id, name, path, eye top, left eye, right eye, eye width, line details, filled details]. Details show from 22px up. */
    ['ears', 'Ears', 'M2 19V13.5A10 9.5 0 0 1 4.7 6.9L4.2 3.6Q4 2 5.5 2.6L9.3 4.4Q12 3.6 14.7 4.4L18.5 2.6Q20 2 19.8 3.6L19.3 6.9A10 9.5 0 0 1 22 13.5v5.5a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', '46%', '', '', '',
      'M3 15.4L5.4 15.8M3.2 17.6L5.5 17.2M21 15.4L18.6 15.8M20.8 17.6L18.5 17.2', 'M5.3 4.1Q5.4 3.6 5.9 3.8L8 4.9Q6.8 5.7 6 6.6Z M18.7 4.1Q18.6 3.6 18.1 3.8L16 4.9Q17.2 5.7 18 6.6Z'],
    /* a ghost: a dome over a hem of three even lobes, edge to edge */
    ['dome', 'Ghost', 'M2 20.6V12a10 10 0 0 1 20 0v8.6Q18.67 24.6 15.33 20.8Q12 24.6 8.67 20.8Q5.33 24.6 2 20.6z', '42%'],
    /* a bao, after the Bun mascot: broad and soft with a rounded top, pleats and blush cheeks */
    ['bun', 'Bun', 'M12 4.2C15.4 4.2 18.4 6.6 20.4 9.6C21.9 11.9 22.7 13.9 22.7 16.1C22.7 19.6 18.2 21.6 12 21.6S1.3 19.6 1.3 16.1C1.3 13.9 2.1 11.9 3.6 9.6C5.6 6.6 8.6 4.2 12 4.2Z', '54%', '31%', '55%', '14%',
      'M9.4 9Q10.3 6.8 11.5 5.8M12.1 9.2Q12.3 7.1 12.4 5.5M14.6 8.9Q14.2 6.9 13.3 5.7'],
    /* a small robot: an antenna on a rounded tile */
    ['tile', 'Tile', 'M7 3h10a4 4 0 0 1 4 4v10a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4z', '40%', '', '', '', 'M12 3.2V1.6', 'M12 .3a1.15 1.15 0 1 1 0 2.3a1.15 1.15 0 1 1 0-2.3z'],
    /* an onigiri: a soft rice triangle with its band of nori */
    ['peak', 'Onigiri', 'M10.2 3.6Q12 .9 13.8 3.6L22 17.2Q23.8 21 19.6 21H4.4Q.2 21 2 17.2Z', '40%', '33%', '55%', '12%', '', 'M8.2 17.2h7.6v3.8H8.2z']
  ];
  var PALETTE = [['Saffron', '#F5B83D'], ['Peach', '#FF9E7A'], ['Rose', '#F48FB1'], ['Lilac', '#B9A2F5'], ['Sky', '#7DC4F5'], ['Mint', '#7FD9A8'], ['Cream', '#F2EAD3']];
  var charNow = { shape: 'ears', color: '#F5B83D' };
  function shapeOf(k) { if (k === 'arch') k = 'bun'; /* Arch became Bun */ for (var i = 0; i < SHAPES.length; i++) if (SHAPES[i][0] === k) return SHAPES[i]; return SHAPES[0]; }
  function applyCharacter(c) {
    if (!c) return;
    charNow = { shape: c.shape, color: c.color };
    var sh = shapeOf(c.shape);
    scene.querySelectorAll('.cr:not(.cr-mini) .f path:not(.pl):not(.fd)').forEach(function (p) { p.setAttribute('d', sh[2]); });
    scene.querySelectorAll('.cr:not(.cr-mini) .f path.fd').forEach(function (p) { p.setAttribute('d', sh[8] || ''); });
    scene.querySelectorAll('.cr:not(.cr-mini) .f path.pl').forEach(function (p) { p.setAttribute('d', sh[7] || ''); });
    scene.querySelectorAll('.cr:not(.cr-mini)').forEach(function (e) { e.style.setProperty('--et', sh[3]); e.style.setProperty('--el', sh[4] || '30%'); e.style.setProperty('--er', sh[5] || '56%'); e.style.setProperty('--ew', sh[6] || '14%'); e.dataset.shape = sh[0]; });
    document.documentElement.style.setProperty('--cr', c.color);
    if (n && !(onbLast && onbStep === onbLast.total - 1 && n.dataset.s === 'onb')) n.style.setProperty('--gcol', c.color);
  }
  function crHtml(cls, size, sh, mood) {
    return '<div class="cr ' + cls + '" data-shape="' + sh[0] + '" data-m="' + (mood || 'awake') + '" style="position:relative;left:auto;top:auto;width:' + size + 'px;height:' + size + 'px;transform:none;--et:' + sh[3] + ';--el:' + (sh[4] || '30%') + ';--er:' + (sh[5] || '56%') + ';--ew:' + (sh[6] || '14%') + '"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><path d="' + sh[2] + '"/><path class="pl" d="' + (sh[7] || '') + '"/><path class="fd" d="' + (sh[8] || '') + '"/></svg></i><i class="ck l"></i><i class="ck r"></i><i class="ey l"></i><i class="ey r"></i></div></div>';
  }

  /* ---- onboarding: six short steps inside the notch ---- */

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
  /* A short moment beside the notch: the character pops out with a face (and maybe a word), then tucks back in. */
  function pop(mood, ms, text, tries) {
    if (hello || celebrating || lastSt !== 'idle') {
      /* a word is news; it waits for the moment in progress (or the closing card) instead of being lost */
      if (text && (tries || 0) < 6) setTimeout(function () { pop(mood, ms, text, (tries || 0) + 1); }, 600);
      return;
    }
    hello = true;
    var ci = cr.querySelector('.cr-in'), say = cr.querySelector('.say');
    say.textContent = text || ''; cr.dataset.say = text ? '1' : '';
    cr.style.transform = idleXf; cr.style.opacity = 1; cr.dataset.m = 'awake';
    ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive');
    setTimeout(function () { ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); cr.dataset.m = mood; }, 420);
    setTimeout(function () { cr.dataset.say = ''; cr.style.transform = idleXf + ' translateX(' + (idleD + 4) + 'px) scale(.55)'; cr.style.opacity = 0; }, ms);
    setTimeout(function () { hello = false; if (snap) layout(lastSt, snap); }, ms + 600);
  }
  /* While you are at the Mac, rare and small: a session you are not in finished, or the last thing waiting on you was answered. */
  var known = null;
  function moments(s, st) {
    if (st !== 'idle') return;
    var done = s.projects.filter(function (p) { return p.status.kind === 'done' && p.fresh && p.id !== s.activeId; }).map(function (p) { return p.id; });
    var need = s.projects.filter(function (p) { return p.attention && p.id !== s.activeId; }).length;
    if (known && !need) {
      var landed = done.some(function (id) { return known.done.indexOf(id) < 0; });
      if (landed) setTimeout(function () { pop('happy', 1900); }, 250);
      else if (known.need > 0) setTimeout(function () { pop('happy', 1500, 'All clear'); }, 250);
    }
    known = { done: done, need: need };
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
    /* the hello is not a step of the setup: the count starts after it */
    return (o.only ? '' : oi(0, '<div class="px-4 pt-0.5 text-xs tabular-nums text-muted-foreground">' + o.step + ' of ' + (o.total - 1) + '</div>')) +
      oi(1, '<p class="' + (o.only ? 'pt-0.5' : 'mt-1') + ' px-4 text-[15px] font-semibold leading-5 tracking-[-0.02em]">' + title + '</p>') +
      oi(2, '<p class="mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground">' + sub + '</p>');
  }
  /* `left` sits where Back would be: the keyboard hints on the character step */
  function ofoot(i, back, mid, label, action, left) {
    return oi(i, '<div class="mt-3 flex h-9 items-center gap-1 px-2.5">' + (back ? Button('ghost', 'Back', Kbd('\u2190'), 'o-back') : (left || '')) + '<span class="flex-1"></span>' + (mid || '') +
      Button('default', label, Kbd(svg('enter', 'size-2'), 1), 'o-primary pr-0.5" data-a="' + action) + '</div>');
  }
  function tick(done) { return done ? '<span class="grid size-4 flex-none place-items-center rounded-full bg-emerald-400/15 text-emerald-400">' + svg('check', 'size-2.5') + '</span>' : '<span class="size-4 flex-none rounded-full border border-muted-foreground/40"></span>'; }
  function orow(icon, label, right) { return '<div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]">' + icon + '<span class="flex-1">' + label + '</span><span class="text-muted-foreground">' + right + '</span></div>'; }
  function ohint(left, text) { return '<div class="flex items-baseline gap-3"><span class="flex w-14 flex-none">' + left + '</span><span class="text-muted-foreground">' + text + '</span></div>'; }
  function onbDo(a) {
    if (a === 'finish') helloNext = true;
    if (a === 'settings') post({ type: 'openSettings' }); else if (a === 'hooks') post({ type: 'hooks', on: true }); else post({ type: 'onb', action: a });
  }
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
    document.documentElement.style.setProperty('--cr', c.color); if (n && !(onbLast && onbStep === onbLast.total - 1 && n.dataset.s === 'onb')) n.style.setProperty('--gcol', c.color);
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
      pv._busy = Date.now() + 1500;
      pv.dataset.m = 'happy';
      var ci = pv.querySelector('.cr-in'); ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop');
      clearTimeout(pv._t); pv._t = setTimeout(function () { pv.dataset.m = 'awake'; }, 850);
    }
  }
  /* the preview and the little shape tiles are alive: they blink and glance about while you choose */
  function blinkEl(el) { el.classList.add('blink'); setTimeout(function () { el.classList.remove('blink'); }, 150); }
  /* while you choose, the big preview plays: a hop, a wiggle, a flip, a squish, a short nap, a happy bounce. Never the same twice in a row. */
  var TRICKS = ['hop', 'wiggle', 'flip', 'squish', 'nap', 'happy'], lastTrick = '';
  function trick(pv) {
    var ci = pv.querySelector('.cr-in'), pick = TRICKS.filter(function (t) { return t !== lastTrick; })[Math.floor(Math.random() * (TRICKS.length - 1))];
    lastTrick = pick; pv._busy = Date.now() + 1800;
    var play = function (cls, ms) { ci.classList.remove(cls); void ci.offsetWidth; ci.classList.add(cls); setTimeout(function () { ci.classList.remove(cls); }, ms); };
    if (pick === 'nap') {
      pv.dataset.m = 'sleep'; pv.style.setProperty('--lx', '0px'); pv.style.setProperty('--ly', '0px');
      setTimeout(function () { if (pv.dataset.m === 'sleep') { pv.dataset.m = 'awake'; play('hop', 600); } }, 1500);
    } else if (pick === 'happy') {
      pv.dataset.m = 'happy'; play('hop', 600);
      setTimeout(function () { if (pv.dataset.m === 'happy') pv.dataset.m = 'awake'; }, 900);
    } else play(pick, 950);
  }
  (function previewLife() {
    var pv = q('.cr-pv');
    if (pv && pv.dataset.m === 'awake' && !(pv._busy > Date.now()) && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) && Math.random() < 0.4) trick(pv);
    else if (pv && pv.dataset.m === 'awake' && !(pv._busy > Date.now())) {
      blinkEl(pv); if (Math.random() < 0.3) setTimeout(function () { blinkEl(pv); }, 280);
      pv.style.setProperty('--lx', ((Math.random() - 0.5) * 5).toFixed(2) + 'px'); pv.style.setProperty('--ly', ((Math.random() - 0.5) * 3).toFixed(2) + 'px');
    }
    var hi = q('.cr-hi'); if (hi && hi.dataset.m === 'awake' && Math.random() < 0.6) blinkEl(hi);
    scene.querySelectorAll('.cr-mini').forEach(function (m, i) { if (Math.random() < 0.55) setTimeout(function () { blinkEl(m); }, i * 130); });
    setTimeout(previewLife, 1700 + Math.random() * 2400);
  })();
  function onbRender(o, animate) {
    onbLast = o;
    var box = q('.onb'), h = '', g = o.accessibility, st = o.step;
    if (st === 0) {
      /* Hello: the character lands on the notch, wakes up and says who it is, then shows what it does with two sessions */
      h = oi(0, '<div class="flex items-start gap-3 px-4 pt-0.5"><div class="hi-cr relative grid size-[60px] flex-none place-items-center">' + crHtml('cr-hi', 52, shapeOf(charNow.shape), 'sleep') + '</div>' +
            '<div class="min-w-0 flex-1 pt-1"><p class="hi-say inline-block rounded-2xl rounded-bl-md bg-white/[0.09] px-3 py-1.5 text-[15px] font-semibold leading-5 tracking-[-0.02em]"><span class="hi-t"></span><span class="hi-ghost invisible">Hi, I\u2019m Perch.</span></p>' +
            '<p class="hi-sub mt-2 text-[13px] leading-[18px] text-muted-foreground">I live on your notch. While you\u2019re away I keep an eye on Claude Code and Codex, and when you\u2019re back I\u2019ll tell you where you left off.</p></div></div>') +
        oi(1, '<div class="hi-demo mt-3 flex flex-col gap-1 px-2.5">' + introRow(0, 'claude', 'Website', 'Hero spacing') + introRow(1, 'codex', 'Docs', 'Install guide') + '</div>') +
        ofoot(2, false, '', 'Nice to meet you', 'next');
    } else if (st === 1) {
      var shapes = SHAPES.map(function (sh) {
        return '<button class="o-shape grid size-11 cursor-pointer place-items-center rounded-lg transition active:scale-95 ' + (sh[0] === charNow.shape ? 'bg-white/[0.14] ring-1 ring-white/40' : 'bg-white/[0.06] hover:bg-white/[0.1]') + '" data-k="' + sh[0] + '" aria-label="' + sh[1] + '" title="' + sh[1] + '">' + crHtml('cr-mini', 24, sh) + '</button>';
      }).join('');
      var colors = PALETTE.map(function (c) {
        return '<button class="o-color size-5 cursor-pointer rounded-full transition ' + (c[1] === charNow.color ? 'ring-2 ring-white ring-offset-2 ring-offset-black' : 'hover:scale-110') + '" style="background:' + c[1] + '" data-c="' + c[1] + '" aria-label="' + c[0] + '" title="' + c[0] + '"></button>';
      }).join('');
      h = (o.only ? otitle(o, 'Make it yours', 'Pick a shape and a colour for your character.') : otitle(o, 'Make me yours', 'Pick a shape and a colour for me.')) +
        oi(3, '<div class="mt-3 flex items-center gap-4 px-4"><div class="relative grid size-[76px] flex-none place-items-center overflow-hidden rounded-2xl pv-tile"><i class="pv-bloom absolute inset-0"></i><span class="relative">' + crHtml('cr-pv', 52, shapeOf(charNow.shape)) + '</span></div><div class="flex min-w-0 flex-col gap-3"><div class="flex gap-1.5">' + shapes + '</div><div class="flex flex-wrap gap-2.5">' + colors + '</div></div></div>') +
        ofoot(4, false, '', o.only ? 'Done' : 'Next', 'next',
          '<span class="flex items-center gap-3.5 pl-1.5 text-xs text-muted-foreground"><span class="flex items-baseline gap-1.5">' + Kbd('\u2190\u2192') + 'Shape</span><span class="flex items-baseline gap-1.5">' + Kbd('\u2191\u2193') + 'Colour</span></span>');
    } else if (st === 2) {
      h = otitle(o, 'Let Perch reply for you', 'Perch pastes and sends your replies, and opens with \u2318\u2325. macOS asks you to allow it once.') +
        oi(3, '<div class="mt-3 px-4">' + orow(tick(g), 'Accessibility', g ? 'Allowed' : 'Waiting for you\u2026') + '</div>') +
        oi(4, g ? '' : '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">Switch Perch on in System Settings. Switched it on but nothing changes? <button class="o-restart cursor-pointer underline underline-offset-2 hover:text-foreground">Restart Perch</button></p>') +
        ofoot(5, true, g ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), g ? 'Next' : 'Open System Settings', g ? 'next' : 'accessibility');
    } else if (st === 3) {
      var rows = o.sources.map(function (x) {
        var sub = o.scanning ? 'Scanning\u2026' : (x.count ? esc(x.names.slice(0, 2).join(', ')) + (x.count > 2 ? ', +' + (x.count - 2) : '') : 'Nothing found yet');
        var sw = '<button role="switch" aria-checked="' + x.enabled + '" aria-label="Include ' + x.name + '" data-id="' + x.id + '" class="o-sw relative h-[18px] w-[30px] flex-none cursor-pointer rounded-full transition-colors duration-200 ' + (x.enabled ? 'bg-emerald-400' : 'bg-white/20') + '"><i class="absolute top-[2px] block size-[14px] rounded-full bg-white shadow transition-all duration-200 ' + (x.enabled ? 'left-[14px]' : 'left-[2px]') + '"></i></button>';
        return '<div class="flex h-11 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3"><span class="flex-none ' + (x.enabled ? '' : 'opacity-50') + '">' + App(x.id, 'size-5') + '</span><span class="min-w-0 flex-1"><span class="block text-[13px] font-medium leading-4">' + x.name + '</span><span class="block truncate text-xs leading-4 text-muted-foreground">' + sub + '</span></span>' + (o.scanning ? Spinner('size-3.5') : '') + sw + '</div>';
      }).join('');
      h = otitle(o, 'Choose your apps', 'Perch only reads the ones you switch on. You can change this later from the menu bar.') +
        oi(3, '<div class="mt-3 flex flex-col gap-1.5 px-4">' + rows + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">macOS may ask to let Perch see a project folder. Choose Allow.</p>') +
        ofoot(5, true, '', 'Next', 'next');
    } else if (st === 4) {
      var live = o.live === 'on';
      h = otitle(o, 'Know the moment they need you', 'Claude Code and Codex tell Perch when they finish or need your OK, and you can answer from the notch.') +
        oi(3, '<div class="mt-3 px-4">' + orow(tick(live), 'Live status', live ? 'On' : '') + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">' + (live ? 'Codex may ask you once to trust the new hook.' : 'Adds a small hook to each app. You can remove it in Settings.') + '</p>') +
        ofoot(5, true, live ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), live ? 'Next' : 'Turn on', live ? 'next' : 'hooks');
    } else if (st === 5) {
      var sm = { ready: ['Apple Intelligence is on', 'All set. Summaries run on your Mac.'], off: ['Turn on Apple Intelligence', 'Takes a few minutes the first time.'], downloading: ['Downloading the model\u2026', 'A few GB. Keep working, this finishes on its own.'], unsupported: ["This Mac can't run it", 'Summaries stay plain, which still works.'] }[o.summaries] || ['', ''];
      var off = o.summaries === 'off';
      h = otitle(o, 'Better summaries', 'Written on your Mac. Nothing leaves it.') +
        oi(3, '<div class="mt-3 px-4">' + orow(o.summaries === 'downloading' ? '<span class="grid size-4 flex-none place-items-center">' + Spinner('size-3.5') + '</span>' : tick(o.summaries === 'ready'), sm[0], '') + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">' + sm[1] + '</p>') +
        ofoot(5, true, off ? Button('ghost', 'Skip', Kbd('S'), 'o-skip') : '', off ? 'Open Settings' : 'Next', off ? 'settings' : 'next');
    } else {
      h = otitle(o, 'You\u2019re all set', 'Here is how to reach Perch.') +
        oi(3, '<div class="mt-3 flex flex-col gap-2 px-4 text-[13px]">' + ohint(Kbd('\u2318\u2325'), 'Tap both to open or close Perch') + ohint(Kbd('\u2303\u2325P'), 'The welcome card') + ohint(Kbd('\u2303\u2325L'), 'Other projects') + ohint('<span class="text-xs text-muted-foreground">Hover</span>', 'Rest on the notch to peek') + '</div>') +
        ofoot(4, true, '', 'Done', 'finish');
    }
    box.className = 'onb' + (animate ? ' go' : '');
    box.innerHTML = h;
    introToken++; introGlow = '';
    if (st === 0) introduce(animate);
    box.querySelectorAll('.o-primary').forEach(function (b) { b.onclick = function () { onbDo(b.dataset.a); }; });
    box.querySelectorAll('.o-skip').forEach(function (b) { b.onclick = function () { onbDo('next'); }; });
    box.querySelectorAll('.o-back').forEach(function (b) { b.onclick = function () { onbDo('back'); }; });
    box.querySelectorAll('.o-restart').forEach(function (b) { b.onclick = function () { onbDo('restart'); }; });
    box.querySelectorAll('.o-sw').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setSw(b, on); post({ type: 'source', id: b.dataset.id, enabled: on }); }; });
    box.querySelectorAll('.o-shape').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: b.dataset.k, color: charNow.color }); }; });
    box.querySelectorAll('.o-color').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: charNow.shape, color: b.dataset.c }); }; });
  }
  /* ---- the introduction: Perch says who it is (names start with intro: `hello` is the hello beside the notch after setup) ---- */
  var introToken = 0, introGlow = '';
  function introRow(i, app, name, topic) {
    return '<div class="hi-row flex h-8 items-center gap-2 rounded-md bg-white/[0.045] px-2 text-[13px]" data-i="' + i + '">' + App(app, 'size-4') +
      '<span class="min-w-0 flex-1 truncate"><span class="font-medium">' + name + '</span><span class="ml-2 text-muted-foreground">' + topic + '</span></span>' +
      '<span class="hi-st flex flex-none items-center gap-1.5 text-xs">' + Phrase({ t: 'Working', c: COLORS.running, spin: true }) + '</span></div>';
  }
  function introduce(animate) {
    var tok = introToken, box = q('.onb'), hi = box.querySelector('.cr-hi'), ci = hi.querySelector('.cr-in');
    var say = box.querySelector('.hi-t'), ghost = box.querySelector('.hi-ghost'), bubble = box.querySelector('.hi-say'), sub = box.querySelector('.hi-sub'), rows = box.querySelectorAll('.hi-row');
    var words = 'Hi, I\u2019m Perch.', reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    var at = function (ms, fn) { setTimeout(function () { if (tok === introToken && onbStep === 0) fn(); }, ms); };
    var play = function (cls, ms) { ci.classList.remove(cls); void ci.offsetWidth; ci.classList.add(cls); setTimeout(function () { ci.classList.remove(cls); }, ms); };
    var status = function (i, ph, mood, glow) {
      rows[i].querySelector('.hi-st').innerHTML = Phrase(ph);
      if (!reduce) rows[i].querySelector('.hi-st').animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 260, easing: 'cubic-bezier(.2,.9,.3,1)' });
      hi.dataset.m = mood; play('hop', 600);
      introGlow = glow; n.style.setProperty('--gcol', glow || charNow.color);
    };
    var finished = function () { status(0, { t: 'Finished', c: COLORS.done }, 'happy', '#4ADE80'); };
    var needs = function () { status(1, { t: 'Needs your OK', c: COLORS.attention }, 'alert', '#FB923C'); };
    if (reduce || !animate) {
      say.textContent = words; ghost.textContent = ''; hi.dataset.m = 'awake';
      rows[0].querySelector('.hi-st').innerHTML = Phrase({ t: 'Finished', c: COLORS.done });
      rows[1].querySelector('.hi-st').innerHTML = Phrase({ t: 'Needs your OK', c: COLORS.attention });
      return;
    }
    /* 1. it drops onto its perch, asleep, and lands with a squash */
    bubble.style.opacity = 0; sub.style.opacity = 0; rows.forEach(function (r) { r.style.opacity = 0; });
    play('perch', 900);
    /* 2. wakes, blinks, hops, looks at you */
    at(750, function () { hi.dataset.m = 'awake'; blinkEl(hi); play('hop', 600); });
    /* 3. says hello, a letter at a time, bobbing as it talks */
    at(1050, function () {
      bubble.style.opacity = ''; bubble.animate([{ opacity: 0, transform: 'scale(.6)' }, { opacity: 1, transform: 'none' }], { duration: 380, easing: 'cubic-bezier(.3,1.4,.5,1)' });
      ci.classList.add('talk');
      words.split('').forEach(function (ch, k) { at(120 + k * 48, function () { say.textContent += ch; ghost.textContent = words.slice(say.textContent.length); }); });
      at(140 + words.length * 48, function () { ci.classList.remove('talk'); });
    });
    /* 4. what it does, then two sessions to show it */
    at(2150, function () { sub.style.opacity = ''; sub.animate([{ opacity: 0, transform: 'translateY(4px)', filter: 'blur(3px)' }, { opacity: 1, transform: 'none', filter: 'none' }], { duration: 500, easing: 'cubic-bezier(.2,.9,.3,1)' }); });
    rows.forEach(function (r, k) { at(2900 + k * 120, function () { r.style.opacity = ''; r.animate([{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }], { duration: 420, easing: 'cubic-bezier(.2,.9,.3,1)' }); }); });
    /* 5. one finishes (happy, green), the other needs you (wide-eyed, orange) */
    at(4400, finished);
    at(5900, needs);
    /* 6. back to its own colour, and a glance at the button */
    at(7500, function () {
      introGlow = ''; n.style.setProperty('--gcol', charNow.color); hi.dataset.m = 'awake';
      hi.style.setProperty('--lx', '2.6px'); hi.style.setProperty('--ly', '2px');
    });
  }
  function onb(o) {
    if (!o) return;
    var sig = [o.step, o.only, o.accessibility, o.summaries, o.scanning, o.live, o.sources.map(function (x) { return x.id + x.enabled + x.count; }).join(',')].join('|');
    if (sig === onbSig) return;
    /* the introduction uses none of this data: a scan finishing must not cut it short */
    if (o.step === 0 && onbStep === 0 && onbSig && o.only === (onbLast && onbLast.only)) { onbSig = sig; onbLast = o; return; }
    /* only a switch changed: slide it in place */
    var same = function (s) { return s.split('|').slice(0, 6).join('|'); };
    if (onbSig && o.step === onbStep && same(sig) === same(onbSig) && onbLast && onbLast.sources.map(function (x) { return x.id + x.count; }).join() === o.sources.map(function (x) { return x.id + x.count; }).join()) {
      onbSig = sig; onbLast = o;
      q('.onb').querySelectorAll('.o-sw').forEach(function (b) { o.sources.forEach(function (x) { if (x.id === b.dataset.id) setSw(b, x.enabled); }); });
      return;
    }
    var animate = o.step !== onbStep; onbStep = o.step; onbSig = sig; onbRender(o, animate);
    if (animate && o.step === o.total - 1) setTimeout(celebrate, 60);
  }
  /* Return and the arrow keys, forwarded from the app while the card has the keyboard. */
  function onbKey(k) {
    if (k === 'enter') { var b = q('.o-primary'); if (b) b.click(); return; }
    /* S skips a step that can be skipped; Left goes back, except on the character page where it changes the shape */
    if (k === 'skip') { var sk = q('.o-skip'); if (sk) sk.click(); return; }
    if (k === 'left' && onbStep !== 1) { var bk = q('.o-back'); if (bk) bk.click(); return; }
    if (onbStep !== 1) return;
    /* left and right change the shape, up and down the colour; both wrap */
    var d = (k === 'right' || k === 'down') ? 1 : -1, i = 0;
    if (k === 'up' || k === 'down') {
      PALETTE.forEach(function (c, j) { if (c[1] === charNow.color) i = j; });
      i = (i + d + PALETTE.length) % PALETTE.length;
      pickCharacter({ shape: charNow.shape, color: PALETTE[i][1] });
      return;
    }
    SHAPES.forEach(function (sh, j) { if (sh[0] === charNow.shape) i = j; });
    i = (i + d + SHAPES.length) % SHAPES.length;
    pickCharacter({ shape: SHAPES[i][0], color: charNow.color });
  }

  /* ---- settings, inside the notch ---- */
  var setLast = null, setSig = '';
  /* a switch changes in place so it slides; redrawing it would just snap to the new state */
  function setSw(b, on) {
    b.setAttribute('aria-checked', String(on));
    b.classList.toggle('bg-emerald-400', on); b.classList.toggle('bg-white/20', !on);
    var k = b.querySelector('i'); k.classList.toggle('left-[14px]', on); k.classList.toggle('left-[2px]', !on);
  }
  var APP_ON = 'bg-white/[0.12] text-foreground', APP_OFF = 'text-muted-foreground opacity-60 hover:opacity-100';
  function setApp(b, on) {
    b.setAttribute('aria-checked', String(on));
    (on ? APP_OFF : APP_ON).split(' ').forEach(function (c) { b.classList.remove(c); });
    (on ? APP_ON : APP_OFF).split(' ').forEach(function (c) { b.classList.add(c); });
  }
  function swHtml(on, key, label) {
    return '<button role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-k="' + key + '" class="s-sw relative h-[18px] w-[30px] flex-none cursor-pointer rounded-full transition-colors duration-200 ' + (on ? 'bg-emerald-400' : 'bg-white/20') + '"><i class="absolute top-[2px] block size-[14px] rounded-full bg-white shadow transition-all duration-200 ' + (on ? 'left-[14px]' : 'left-[2px]') + '"></i></button>';
  }
  function srow(left, right) { return '<div class="s-row mx-2 flex h-[30px] items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors">' + left + '<span class="flex-none">' + right + '</span></div>'; }
  function slabel(t, sub) { return '<span class="min-w-0 flex-1 truncate">' + t + (sub ? ' <span class="text-muted-foreground">' + sub + '</span>' : '') + '</span>'; }
  var axAsked = false;   /* Allow was clicked: if it is still not working, the switch in System Settings is stale */
  function settingsRender(o) {
    setLast = o;
    var sh = shapeOf(charNow.shape), colorName = ''; PALETTE.forEach(function (c) { if (c[1] === charNow.color) colorName = c[0].toLowerCase(); });
    var seg = [10, 20, 60].map(function (m) {
      return '<button class="s-idle h-5 cursor-pointer rounded px-2 text-xs transition-colors ' + (o.idleMinutes === m ? 'bg-white/[0.16] text-foreground' : 'text-muted-foreground hover:text-foreground') + '" data-m="' + m + '">' + (m === 60 ? '1 hour' : m + ' min') + '</button>';
    }).join('');
    var sum = { ready: 'On your Mac', off: 'Apple Intelligence is off', downloading: 'Downloading the model\u2026', unsupported: 'Not supported on this Mac' }[o.summaries] || '';
    var rows = [
      srow(slabel('Character', sh[1] + ', ' + colorName), Button('ghost', 'Change', '', 's-change')).replace('<div class="', '<div class="s-char '),
      srow(slabel('Apps'), '<span class="flex gap-1">' + o.sources.map(function (x) {
        return '<button role="switch" aria-checked="' + x.enabled + '" aria-label="Include ' + x.name + '" data-k="' + x.id + '" class="s-app inline-flex h-6 cursor-pointer items-center gap-1.5 rounded-md pl-1 pr-2 text-xs transition ' + (x.enabled ? APP_ON : APP_OFF) + '">' + App(x.id, 'size-4') + (x.id === 'codex' ? 'Codex' : 'Claude') + '</button>';
      }).join('') + '</span>'),
      srow(slabel('Live status', '<span class="s-live">' + (o.live === 'on' ? 'on' : 'off') + '</span>'), swHtml(o.live === 'on', 'live', 'Live status')),
      srow(slabel('Come back after'), '<span class="flex rounded-md bg-white/[0.07] p-0.5">' + seg + '</span>'),
      srow(slabel('Summaries', sum), o.summaries === 'off' ? Button('ghost', 'Set up', '', 's-sum') : ''),
      srow(slabel('Reply and shortcuts', o.accessibility ? 'allowed' : (axAsked ? 'turn Perch off and on there' : 'needs access')), o.accessibility ? '' : Button('ghost', axAsked ? 'Open' : 'Allow', '', 's-ax" title="Opens Accessibility in System Settings. If Perch is already on there, switch it off and on again: a new build of Perch needs a fresh grant.')),
      srow(slabel('Open at login'), swHtml(o.login, 'login', 'Open at login'))
    ].join('');
    var box = q('.set');
    box.innerHTML = '<div>' + rows + '</div>' +
      /* the keys, like the list's: every setting can be changed without the mouse */
      '<div class="mt-2 flex h-9 items-center gap-1 px-2.5"><span class="flex items-center gap-3.5 pl-1.5 text-xs text-muted-foreground"><span class="flex items-baseline gap-1.5">' + Kbd('\u2191\u2193') + 'Choose</span><span class="flex items-baseline gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Change</span></span>' +
      '<span class="flex-1"></span>' + Button('ghost', 'Quit Perch', '', 's-quit') + Button('default', 'Done', Kbd('esc', 1), 's-done') + '</div>';
    box.querySelectorAll('.s-row').forEach(function (r, i) { r.addEventListener('mouseenter', function () { setFocus = i; paintFocus(); }); });
    paintFocus();
    box.querySelectorAll('.s-sw').forEach(function (b) { b.onclick = function () {
      var on = b.getAttribute('aria-checked') !== 'true';
      setSw(b, on);   /* slide now; the app confirms (or puts it back) a moment later */
      if (b.dataset.k === 'login') post({ type: 'setting', key: 'login', value: on });
      else if (b.dataset.k === 'live') post({ type: 'hooks', on: on });
    }; });
    box.querySelectorAll('.s-app').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setApp(b, on); post({ type: 'source', id: b.dataset.k, enabled: on }); }; });
    var row = box.querySelector('.s-char');
    if (row) { row.onmouseenter = function () { if (cr.dataset.m === 'awake') { cr.dataset.m = 'happy'; look(-1.2, 1.6); } }; row.onmouseleave = function () { if (cr.dataset.m === 'happy') cr.dataset.m = 'awake'; }; }
    box.querySelectorAll('.s-idle').forEach(function (b) { b.onclick = function () { post({ type: 'setting', key: 'idleMinutes', value: +b.dataset.m }); }; });
    var on = function (sel, fn) { box.querySelectorAll(sel).forEach(function (b) { b.onclick = fn; }); };
    on('.s-change', function () { post({ type: 'onbOpen', step: 1, only: true }); });
    on('.s-sum', function () { post({ type: 'openSettings' }); });
    on('.s-ax', function () { axAsked = true; post({ type: 'onb', action: 'accessibility' }); });
    on('.s-quit', function () { post({ type: 'quit' }); });
    on('.s-done', function () { post({ type: 'dismiss' }); });
  }
  /* the highlighted row, moved with the arrow keys or the pointer; on Apps, which app */
  var setFocus = 0, setAppAt = 0;
  function paintFocus() {
    var box = q('.set'), rows = box.querySelectorAll('.s-row');
    setFocus = Math.max(0, Math.min(setFocus, rows.length - 1));
    rows.forEach(function (r, i) { r.classList.toggle('bg-white/[0.06]', i === setFocus); });
    var apps = rows[setFocus] ? rows[setFocus].querySelectorAll('.s-app') : [];
    box.querySelectorAll('.s-app').forEach(function (b) { b.classList.remove('ring-1', 'ring-white/40'); });
    if (apps.length) { setAppAt = Math.min(setAppAt, apps.length - 1); apps[setAppAt].classList.add('ring-1', 'ring-white/40'); }
  }
  /* arrows, Return and Space, forwarded from the app while Settings has the keyboard */
  function settingsKey(k) {
    var box = q('.set'), rows = box.querySelectorAll('.s-row'), row = rows[setFocus];
    if (k === 'down' || k === 'up') { setFocus = (setFocus + (k === 'down' ? 1 : -1) + rows.length) % rows.length; paintFocus(); return; }
    if (!row) return;
    var seg = row.querySelectorAll('.s-idle'), apps = row.querySelectorAll('.s-app');
    if (k === 'left' || k === 'right') {
      var d = k === 'right' ? 1 : -1;
      if (apps.length) { setAppAt = (setAppAt + d + apps.length) % apps.length; paintFocus(); }
      else if (seg.length && setLast) {
        var vals = [].map.call(seg, function (b) { return +b.dataset.m; }), i = Math.max(0, vals.indexOf(setLast.idleMinutes));
        post({ type: 'setting', key: 'idleMinutes', value: vals[Math.max(0, Math.min(vals.length - 1, i + d))] });
      }
      return;
    }
    /* Return or Space: flip the switch, pick the app, or press the row's button */
    if (apps.length) { apps[setAppAt].click(); return; }
    if (seg.length && setLast) { var v = [].map.call(seg, function (b) { return +b.dataset.m; }); post({ type: 'setting', key: 'idleMinutes', value: v[(v.indexOf(setLast.idleMinutes) + 1) % v.length] }); return; }
    var c = row.querySelector('.s-sw, button'); if (c) c.click();
  }
  function settingsApply(o) {
    if (!o) return;
    var sig = JSON.stringify([o, charNow]); if (sig === setSig) return;
    /* the same rows with new values: change them in place, so switches and the segment animate */
    var shape = JSON.stringify([o.summaries, o.accessibility, o.sources.map(function (x) { return x.id; }), charNow]), box = q('.set');
    if (setSig && box.dataset.shape === shape) {
      setSig = sig; setLast = o;
      box.querySelectorAll('.s-sw').forEach(function (b) { setSw(b, b.dataset.k === 'login' ? !!o.login : o.live === 'on'); });
      box.querySelectorAll('.s-app').forEach(function (b) { o.sources.forEach(function (x) { if (x.id === b.dataset.k) setApp(b, x.enabled); }); });
      var lv = box.querySelector('.s-live'); if (lv) lv.textContent = o.live === 'on' ? 'on' : 'off';
      box.querySelectorAll('.s-idle').forEach(function (b) {
        var on = +b.dataset.m === o.idleMinutes;
        ['bg-white/[0.16]', 'text-foreground'].forEach(function (c) { b.classList.toggle(c, on); });
        ['text-muted-foreground', 'hover:text-foreground'].forEach(function (c) { b.classList.toggle(c, !on); });
      });
      return;
    }
    setSig = sig; settingsRender(o); box.dataset.shape = shape;
  }

  window.perch = { _icons: function (o) { icons = o; }, hot: function (on) { n.dataset.hot = on ? '1' : ''; }, onbKey: onbKey, setKey: settingsKey, askKey: askKey, still: function () { still = true; cr.classList.remove('blink'); }, apply: apply, cursor: cursor, snoozeMenu: function (o) { snoozeMenu(o); }, replyMenu: function (o) { if (o && !q('.o-acts [data-act=reply]')) return; replyMenu(o); }, say: function (t) { pop('awake', 2600, t); } };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', setup: 'setup', onboarding: 'onb', settings: 'set' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  function dev(m) {
    if (!snap || m.type === 'size' || m.type === 'log' || m.type === 'snoozeMenu' || m.type === 'replyMenu' || m.type === 'openSettings') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'confirm' || m.type === 'dismiss' || m.type === 'snooze' || m.type === 'reply' || m.type === 'choose' || m.type === 'answer') s.phase = 'idle';
    if (m.type === 'answer' && s.projects[s.selected]) {
      /* the agent goes on: the request is settled and it is working again */
      s.projects[s.selected] = Object.assign({}, s.projects[s.selected], { ask: null, attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'Claude Code is working', app: 'claude' } });
      var nowEl = document.getElementById('now'); if (nowEl) nowEl.textContent = m.answers ? 'Sent: ' + Object.keys(m.answers).map(function (k) { return m.answers[k]; }).join(' / ') : (m.choice === 'deny' ? 'Denied. Claude is told no and goes on.' : 'Allowed. Claude runs it.');
    }
    if (m.type === 'hooks') { if (s.settings) s.settings.live = m.on ? 'on' : 'off'; if (s.onboarding) s.onboarding.live = m.on ? 'on' : 'off'; }
    if (m.type === 'character') { s.character = { shape: m.shape, color: m.color }; }
    if (m.type === 'onb' && s.onboarding) {
      var o = s.onboarding;
      if (m.action === 'next') o.step = Math.min(o.step + 1, o.total - 1);
      else if (m.action === 'back') o.step = Math.max(o.step - 1, 0);
      else if (m.action === 'finish') s.phase = 'idle';
      else if (m.action === 'accessibility') o.accessibility = true;
      if (o.step === 3 && m.action === 'next') { o.scanning = true; var held = JSON.parse(JSON.stringify(s)); held.timerToken++; apply(held); setTimeout(function () { var d2 = JSON.parse(JSON.stringify(held)); d2.onboarding.scanning = false; apply(d2); }, 1200); return; }
    }
    if (m.type === 'source' && s.onboarding) { s.onboarding.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'settings') { s.phase = 'settings'; s.settings = s.settings || { sources: [], summaries: 'ready', accessibility: true, idleMinutes: 20, login: false, live: 'on' }; if (!s.settings.sources.length) s.settings.sources = [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }]; }
    if (m.type === 'setting' && s.settings) { s.settings[m.key] = m.value; }
    if (m.type === 'source' && s.settings) { s.settings.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'onbOpen') { window.perchDev.onboarding(m.step || 0, true, null, m.only); return; }
    if (m.type === 'onb' && m.action === 'next' && s.onboarding && s.onboarding.only) { window.perchDev.settings(); return; }
    if (m.type === 'onb' && !s.onboarding) { if (m.action === 'accessibility' && s.settings) { s.settings.accessibility = true; } else return; }
    if (m.type === 'quit') { s.phase = 'idle'; }
    if (m.type === 'switcher') s.phase = 'switcher';
    if (m.type === 'details') { s.selected = m.index; s.phase = 'open'; s.autoCollapse = false; }
    if (m.type === 'back') s.phase = 'open';
    s.timerToken++; s.autoCollapse = s.phase === 'open'; apply(s);
  }
  if (!NATIVE) {
    var P = [
      { id: 'onboarding', name: 'Onboarding flow', branch: 'main', away: '4m', at: '11:32 AM', headline: 'You were fixing the permissions screen.', context: 'Swapped the sheet for a popover because it clipped on small windows.', next: '', topic: 'Permissions screen', app: 'claude', attention: true, fresh: true, line: 'Waiting on you for 4m', status: { kind: 'attention', text: 'Claude wants to run a command', app: 'claude' }, ask: { kind: 'permission', title: 'Claude wants to run a command', subject: 'npm run build && npm test -- --watch=false', options: [], answerable: true } },
      { id: 'website', name: 'Website', branch: 'feature/hero', away: '48m', at: '10:44 AM', headline: 'You were tightening the hero spacing.', context: 'The hero now fits at phone width. The full-bleed video is gone because it slowed the page.', next: 'Check the hero on a real phone', topic: 'Hero spacing', app: 'claude', attention: false, fresh: true, line: 'Finished 12m after you left', status: { kind: 'done', text: 'Claude finished', app: 'claude' } },
      { id: 'docs', name: 'Docs', branch: 'main', away: '1m', at: '11:58 AM', headline: 'Rewriting the install guide.', context: 'Moving the setup steps above troubleshooting, then cutting the duplicate FAQ.', now: 'Editing install.md', next: '', topic: 'Install guide', app: 'codex', attention: false, fresh: true, line: 'Working now', status: { kind: 'running', text: 'Codex is working', app: 'codex' } },
      { id: 'finance', name: 'Finance', branch: '', away: '3d', at: 'Mon 3:40 PM', headline: 'You were reconciling September invoices.', context: 'Matched 41 of 43 invoices by vendor and amount; two are still open.', next: '', topic: 'September invoices', app: 'claude', attention: false, fresh: false, line: '3d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      /* more than five: the list scrolls. Long topics read themselves out after a second on the row. */
      { id: 'planner', name: 'room-planner-prototype', branch: 'main', away: '5h', at: '10:12 AM', headline: 'You were measuring the missing areas of the apartment.', context: 'The camera saw more than the model kept; the walls now come from the depth pass.', next: '', topic: 'Video to 3D world with measured walls and the missing areas filled in', app: 'claude', attention: false, fresh: false, line: '5h ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      { id: 'repo', name: 'Fetch and review the Perch repo, then list what to fix first', branch: '', away: '6h', at: '9:40 AM', headline: 'You were reviewing the Perch repo.', context: 'Read the README and the provider; three fixes are listed.', next: '', topic: '', app: 'codex', attention: false, fresh: false, line: '6h ago', status: { kind: 'idle', text: 'Codex finished', app: 'codex' } },
      { id: 'lukatz', name: 'lukatz_website', branch: 'main', away: '1d', at: 'Yesterday', headline: 'You were adding the team to the town map.', context: 'Each team member walks the map as a small character.', next: '', topic: '\u05d4\u05d5\u05e1\u05e3 \u05d3\u05de\u05d5\u05d9\u05d5\u05ea NPC \u05e9\u05dc \u05d4\u05e6\u05d5\u05d5\u05ea \u05dc\u05de\u05e4\u05d4 \u05e9\u05dc \u05d4\u05e2\u05d9\u05e8 \u05d5\u05e2\u05d5\u05d3 \u05db\u05de\u05d4 \u05d3\u05d1\u05e8\u05d9\u05dd', app: 'claude', attention: false, fresh: false, line: '1d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      { id: 'fluid', name: 'FluidAgent', branch: 'main', away: '23h', at: 'Yesterday', headline: 'You were stopping a runaway tool loop.', context: 'The agent now stops after three identical calls.', next: '', topic: 'Stop it when the tool loop runs away', app: 'codex', attention: false, fresh: false, line: '23h ago', status: { kind: 'idle', text: 'Codex finished', app: 'codex' } },
      { id: 'gaps', name: 'spec-gap-finder', branch: 'main', away: '2d', at: 'Wed', headline: 'You were setting up the PDF gap finder.', context: 'It reads a spec and a supplier answer and lists what is missing.', next: '', topic: 'PDF gap analysis app and the supplier questionnaire', app: 'claude', attention: false, fresh: false, line: '2d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } }
    ];
    var hash = (location.hash || '#open').slice(1);
    var phase = { idle: 'idle', open: 'open', switcher: 'switcher', restoring: 'restoring' }[hash] || 'open';
    var sel = +(new URLSearchParams(location.search).get('i') || 0);
    document.body.style.background = '#16201e';
    function d0() { clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); }
    var base = { selected: sel, timerToken: 0, screen: { hasNotch: true, notchW: 185, notchH: 32 }, projects: P, setup: 'off' };
    apply(Object.assign({ phase: phase, autoCollapse: phase === 'open' }, base));
    var autoTimer, devQuery = '';
    function devShown() {
      var words = devQuery.toLowerCase().split(/\s+/).filter(Boolean);
      return P.map(function (p, k) { return k; }).filter(function (k) { var hay = (P[k].name + ' ' + P[k].topic).toLowerCase(); return words.every(function (w) { return hay.indexOf(w) >= 0; }); });
    }
    window.perchDev = {
      show: function (ph, setup, quiet) { clearTimeout(autoTimer); devQuery = ''; if (base.once) base.once = false; else base.canSend = true; snoozeMenu(false, true); replyMenu(false, true); var s = Object.assign({}, base, { character: charNow, projects: quiet ? P.map(function (x) { return Object.assign({}, x, { attention: false }); }) : P, phase: ph, autoCollapse: ph === 'open', setup: setup || 'off', timerToken: Math.random() }); apply(s); },
      setNotch: function (has) {
        base.screen = has ? { hasNotch: true, notchW: 185, notchH: 32 } : { hasNotch: false, notchW: 0, notchH: 24 };
        if (snap) apply(Object.assign({}, snap, { screen: base.screen, timerToken: Math.random() }));
      },
      settings: function (o) {
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        apply(Object.assign({}, base, { phase: 'settings', character: charNow, autoCollapse: false, timerToken: Math.random(),
          settings: Object.assign({ sources: [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }], summaries: 'ready', accessibility: true, idleMinutes: 20, login: false, live: 'on' }, o || {}) }));
      },
      onboarding: function (step, accessibility, summaries, only, live) {
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        var sources = [{ id: 'claude', name: 'Claude Code', count: 3, names: ['Website', 'Docs', 'Finance'], enabled: true }, { id: 'codex', name: 'Codex', count: 1, names: ['Onboarding flow'], enabled: true }];
        apply(Object.assign({}, base, { phase: 'onboarding', character: charNow, autoCollapse: false, timerToken: Math.random(),
          onboarding: { step: step, total: 7, accessibility: !!accessibility, summaries: summaries || 'off', scanning: false, sources: sources, only: !!only, live: live || 'off' } }));
      },
      variant: function (i, o) { clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); base.canSend = true; apply(Object.assign({}, base, { character: charNow, selected: i, projects: P.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), phase: 'open', autoCollapse: true, setup: 'off', timerToken: Math.random() })); },
      empty: function (scanning) { clearTimeout(autoTimer); apply(Object.assign({}, base, { character: charNow, projects: [], selected: 0, phase: 'switcher', autoCollapse: false, scanning: !!scanning, timerToken: Math.random() })); },
      noAccess: function () { base.canSend = false; base.once = true; },
      /* a session you are not in finishes while you work: the character pops out, happy, and tucks back in */
      finish: function () { var q2 = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, status: x.id === 'docs' ? { kind: 'running', text: 'Codex is working', app: 'codex' } : x.status, fresh: false }); }); apply(Object.assign({}, base, { character: charNow, projects: q2, phase: 'idle', timerToken: Math.random() }));
        setTimeout(function () { q2 = q2.map(function (x) { return x.id === 'docs' ? Object.assign({}, x, { status: { kind: 'done', text: 'Codex finished', app: 'codex' }, fresh: true }) : x; }); apply(Object.assign({}, base, { character: charNow, projects: q2, phase: 'idle', timerToken: Math.random() })); }, 900); },
      /* the last thing waiting on you was answered */
      clear: function () { d0(); apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'idle', timerToken: Math.random() }));
        setTimeout(function () { apply(Object.assign({}, base, { character: charNow, projects: P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'attention' ? { kind: 'running', text: 'Claude Code is working', app: 'claude' } : x.status }); }), phase: 'idle', timerToken: Math.random() })); }, 1600); },
      say: function (t) { window.perch.say(t); },
      /* the whole permission moment: working quietly, a request arrives, you look, you answer, all clear */
      permission: function () {
        d0(); base.selected = 0;
        var calm = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, line: x.id === 'onboarding' ? 'Working now' : x.line, status: x.id === 'onboarding' ? { kind: 'running', text: 'Claude Code is working', app: 'claude' } : x.status }); });
        var now = document.getElementById('now'), say = function (t) { if (now) now.textContent = t; };
        apply(Object.assign({}, base, { character: charNow, projects: calm, phase: 'idle', timerToken: Math.random() }));
        say('You are working. Claude is busy in Onboarding flow.');
        autoTimer = setTimeout(function () {
          apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'idle', timerToken: Math.random() }));
          say('Claude wants to run a command. The character pops out, eyes wide.');
          autoTimer = setTimeout(function () {
            apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'open', autoCollapse: false, timerToken: Math.random() }));
            say('You hover the notch. Click Allow or Deny, or press A or D.');
          }, 2200);
        }, 1600);
      },
      play: function () { var d = window.perchDev; d.show('idle'); autoTimer = setTimeout(function () { d.show('open'); }, 1200); },
      project: function (i) { base.selected = i; },
      step: function (d) {
        var shown = devShown(), at = shown.indexOf(base.selected);
        if (!shown.length) return;
        base.selected = at < 0 ? shown[0] : shown[(at + d + shown.length) % shown.length];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, shown: devQuery ? shown : null, timerToken: Math.random() }));
      },
      /* the same narrowing as ListFilter in Swift: every word must appear in the name or the title */
      type: function (t) {
        devQuery = t; var shown = devShown(); if (shown.length) base.selected = shown[0];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, shown: devQuery ? shown : null, timerToken: Math.random() }));
      }
    };
    document.addEventListener('keydown', function (e) {
      var ph = snap && snap.phase; if (!ph || ph === 'idle') return;
      var arrows = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' };
      if (ph === 'onboarding' && (arrows[e.key] || e.key === 'Enter' || e.key === 's' || e.key === 'S')) { e.preventDefault(); onbKey(arrows[e.key] || (e.key === 'Enter' ? 'enter' : 'skip')); return; }
      if (ph === 'settings' && (arrows[e.key] || e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); settingsKey(arrows[e.key] || 'enter'); return; }
      /* the same keys as the app when the card asks something: A allows, D denies; for questions a number, Return, Left and Right */
      var ask = ph === 'open' && snap.projects[snap.selected] && snap.projects[snap.selected].ask;
      if (ask && ask.answerable && fRep.style.display !== 'flex') {
        var k = e.key.toLowerCase();
        if (ask.kind === 'permission' && (k === 'a' || k === 'd')) { dev({ type: 'answer', choice: k === 'a' ? 'allow' : 'deny' }); return; }
        if (ask.kind === 'question') { var m2 = { Enter: 'enter', Backspace: 'back', ArrowLeft: 'back', ArrowRight: 'next' }[e.key] || (/^[1-9]$/.test(k) ? k : null); if (m2) { e.preventDefault(); askKey(m2); return; } }
      }
      if (e.key === 'Escape' && ph === 'switcher' && devQuery) { window.perchDev.type(''); return; }
      if (e.key === 'Escape') { if (fSnz.style.display === 'flex') snoozeMenu(false, true); else window.perchDev.show('idle'); }
      else if (e.key === 'Enter' && (ph === 'open' || ph === 'switcher')) window.perchDev.show('idle');
      else if (e.key === 'Tab' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.key === 'Tab' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open'); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'switcher') { e.preventDefault(); window.perchDev.step(e.key === 'ArrowDown' ? 1 : -1); }
      else if ((e.metaKey && e.key === ',') || (ph === 'open' && (e.key === 's' || e.key === 'S'))) { e.preventDefault(); window.perchDev.settings(); }
      else if (ph === 'switcher' && (e.key === 'Backspace' || (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !(e.key === ' ' && !devQuery)))) { e.preventDefault(); window.perchDev.type(e.key === 'Backspace' ? devQuery.slice(0, -1) : devQuery + e.key); }
      else if ((e.key === 'n' || e.key === 'N') && ph === 'open') snoozeMenu(fSnz.style.display !== 'flex', true);
      else if (fSnz.style.display === 'flex' && /^[123]$/.test(e.key)) { snoozeMenu(false, true); window.perchDev.show('idle'); }

    });
  }
})();

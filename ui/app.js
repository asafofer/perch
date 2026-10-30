/* Perch notch UI. Swift owns the state machine and calls window.perch.apply(snapshot);
   this file only draws and reports user actions back through the "perch" message handler. */
(function () {
  var NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.perch);
  var CARD_W = 400, CARD_MAX_H = 428;   /* what shows of the panel (440 less a hair): a card taller than it is cut off */
  var COLORS = { attention: '#E9A877', done: '#8CCFA4', idle: '#71717A', running: '#8DC8E8' };
  var DOME = { d: 'M2 19V13A10 10 0 0 1 5.4 5.5L5.2 2.6Q5 1.4 6 1.9L9.6 3.7A10 10 0 0 1 14.4 3.7L18.2 1.9Q19.2 1.4 18.8 2.6L18.6 5.5A10 10 0 0 1 22 13v6a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', et: '44%' };

  /* ---- shadcn recipes ---- */
  var ICON = {
    enter: '<polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    open: '<path d="M7 7h10v10"/><path d="M7 17 17 7"/>',
    chev: '<path d="m6 9 6 6 6-6"/>',
    list: '<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>',
    load: '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
    win: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/>',
    doc: '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
    file: '<path d="M10 12.5 8 15l2 2.5"/><path d="m14 12.5 2 2.5-2 2.5"/><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    down: '<path d="M12 4.5v11"/><path d="M7.5 11.5l4.5 4.5 4.5-4.5"/><path d="M5 19.5h14"/>',
    restart: '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4.5v4h-4"/>',
    pr: '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M13 6h3a2 2 0 0 1 2 2v7"/><path d="M6 9v12"/>',
    gear: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
    appwin: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M7 6h.01"/>',
    bot: '<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/>',
    term: '<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/>',
    /* Settings rows (Lucide, lucide.dev, ISC) */
    keyboard: '<path d="M10 8h.01"/><path d="M12 12h.01"/><path d="M14 8h.01"/><path d="M16 12h.01"/><path d="M18 8h.01"/><path d="M6 8h.01"/><path d="M7 16h10"/><path d="M8 12h.01"/><rect width="20" height="16" x="2" y="4" rx="2"/>',
    cat: '<path d="M12 5c.67 0 1.35.09 2 .26 1.78-2 5.03-2.84 6.42-2.26 1.4.58-.42 7-.42 7 .57 1.07 1 2.24 1 3.44C21 17.9 16.97 21 12 21s-9-3-9-7.56c0-1.25.5-2.4 1-3.44 0 0-1.89-6.42-.5-7 1.39-.58 4.72.23 6.5 2.23A9.04 9.04 0 0 1 12 5Z"/><path d="M8 14v.5"/><path d="M16 14v.5"/><path d="M11.25 16.25h1.5L12 17l-.75-.75Z"/>',
    grid: '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
    bell: '<path d="M10.268 21a2 2 0 0 0 3.464 0"/><path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"/>',
    pulse: '<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>',
    timer: '<line x1="10" x2="14" y1="2" y2="2"/><line x1="12" x2="15" y1="14" y2="11"/><circle cx="12" cy="14" r="8"/>',
    hourglass: '<path d="M5 22h14"/><path d="M5 2h14"/><path d="M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22"/><path d="M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2"/>',
    monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/>',
    pointer: '<path d="M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z"/>',
    access: '<circle cx="16" cy="4" r="1"/><path d="m18 19 1-7-6 1"/><path d="m5 8 3-3 5.5 3-2.36 3.5"/><path d="M4.24 14.5a5 5 0 0 0 6.88 6"/><path d="M13.76 17.5a5 5 0 0 0-6.88-6"/>',
    login: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/><line x1="15" x2="3" y1="12" y2="12"/>',
    /* the new session flow (Lucide) */
    folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    chat: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    folderPlus: '<path d="M12 10v6"/><path d="M9 13h6"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    chevR: '<path d="m9 18 6-6-6-6"/>',
    chevD: '<path d="m6 9 6 6 6-6"/>',
    chevU: '<path d="m18 15-6-6-6 6"/>',
    tag: '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/>',
    clip: '<path d="m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551"/>',
    refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>'
  };
  function svg(n, c) { return '<svg class="' + (c || 'size-3.5') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICON[n] + '</svg>'; }
  var BTN = 'inline-flex items-center justify-center gap-1 whitespace-nowrap rounded-md text-xs font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/50 h-6 px-2 cursor-pointer';
  function Button(v, label, extra, cls) {
    var c = { default: 'bg-primary text-primary-foreground hover:bg-primary/90', ghost: 'text-muted-foreground hover:bg-accent hover:text-accent-foreground' }[v];
    /* label and key share a baseline: the key's letter sits on the line of the words, its box around it */
    return '<button class="' + BTN + ' ' + c + ' ' + (cls || '') + '">' + (extra ? '<span class="inline-flex items-baseline gap-1">' + label + extra + '</span>' : label) + '</button>';
  }
  /* an icon key gets an invisible character, so it has a text baseline like a letter key */
  /* two keys that go together (the arrows): each in its own box, a little apart */
  function Keys(a, b) { return '<span class="inline-flex items-baseline gap-[3px]">' + Kbd(a) + Kbd(b) + '</span>'; }
  /* Return (the only key drawn as an icon) is a little wider with its arrow at the right, like the key itself */
  function Kbd(t, onPrimary) { return '<kbd class="pointer-events-none inline-flex h-4 ' + (/^</.test(t) ? 'min-w-[28px] justify-end' : 'min-w-4 justify-center') + ' items-center rounded-sm px-1 font-sans text-[10.5px] font-medium select-none ' + (onPrimary ? 'bg-primary-foreground/15 text-primary-foreground shadow-[inset_0_0_0_1px_rgba(0,0,0,0.12)]' : 'bg-muted text-muted-foreground shadow-[inset_0_0_0_1px_rgba(255,255,255,0.1)]') + '">' + (/^</.test(t) ? '\u200b' : '') + t + '</kbd>'; }
  var icons = {};
  /* each agent's name, and the short one sentences and buttons use */
  var AGENTS = { claude: ['Claude Code', 'Claude'], codex: ['Codex', 'Codex'], opencode: ['OpenCode', 'OpenCode'], pi: ['pi', 'pi'], cursor: ['Cursor', 'Cursor'], muse: ['Muse', 'Muse'], dots: ['Dots', 'Dots'], grokbot: ['Grok Bot', 'Grok Bot'], cowork: ['Claude tasks', 'Claude'], chat: ['Claude chats', 'Claude'] };
  function agentName(k) { return (AGENTS[k] || AGENTS.claude)[0]; }
  function agentShort(k) { return (AGENTS[k] || AGENTS.claude)[1]; }
  /* The agents by how you use them, so a long list is three choices first (onboarding's apps step and Settings, Agents): in
     a terminal, in a coding app, or as a personal agent. `places` are what Perch also works in for that group. */
  var GROUPS = [
    { id: 'term', name: 'Terminal agents', ic: 'term', ids: ['claude', 'codex', 'opencode', 'pi', 'muse'], places: ['herdr', 'tmux', 'cmux', 'agterm'] },
    { id: 'code', name: 'Coding apps', ic: 'appwin', ids: ['cursor'], places: ['conductor'] },
    { id: 'personal', name: 'Personal agents', ic: 'bot', ids: ['cowork', 'chat', 'dots', 'grokbot'], places: [] }
  ];
  function groupsOf(sources, places) {
    var known = function (id) { return GROUPS.some(function (g) { return g.ids.indexOf(id) >= 0; }); };
    return GROUPS.map(function (g) {
      var list = sources.filter(function (x) { return g.ids.indexOf(x.id) >= 0 || (g.id === 'term' && !known(x.id)); });
      list.sort(function (a, b) { return g.ids.indexOf(a.id) - g.ids.indexOf(b.id); });
      return { g: g, list: list, places: (places || []).filter(function (x) { return g.places.indexOf(x.id) >= 0; }) };
    }).filter(function (x) { return x.list.length; });
  }
  /* the group's agents as icons, the ones that are off faded; more than four show three and how many more. In Settings
     they sit side by side (`flat`); on the apps step they overlap, their rim the tile's own colour. */
  function faceStack(list, size, flat) {
    var many = list.length > 4, shown = many ? list.slice(0, 3) : list;
    return '<span class="og-fc flex flex-none items-center' + (flat ? ' gap-[3px]' : '') + '">' + shown.map(function (x, i) {
      return '<span class="og-f' + (flat ? ' flat' : '') + (x.enabled ? '' : ' off') + '"' + (flat ? '' : ' style="margin-left:' + (i ? '-6px' : '0') + ';z-index:' + (9 - i) + '"') + '>' + App(x.id, size) + '</span>';
    }).join('') + (many ? '<span class="og-more ml-1 text-xs tabular-nums text-muted-foreground">+' + (list.length - 3) + '</span>' : '') + '</span>';
  }
  /* Codex's own mark, the icon its app ships (icon-codex-light.png), for when Codex is only a command on this Mac and for
     the design page. The app itself now wears ChatGPT's icon; Swift sends this same mark from inside it. */
  /* Claude's own icon too, the one Claude.app ships, so no page ever draws a stand-in for it */
  var MARKS = { claude: 'data:image/png;base64,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', codex: 'data:image/png;base64,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' };
  /* Claude tasks (Cowork) and chats live in the Claude app and wear its icon */
  /* the places Perch follows a session into that have no app: herdr's own ram (herdr.dev) and tmux's logomark (tmux/tmux) */
  MARKS.herdr = 'data:image/png;base64,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';
  MARKS.tmux = 'data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A//www.w3.org/2000/svg%22%20viewBox%3D%220%200%20160%20160%22%3E%3Cpath%20fill%3D%22%233C3C3C%22%20d%3D%22M83%2070V0h-6v146h6V76h77v-6H83zM0%2015C0%206.7%206.7%200%2015%200h130c8.3%200%2015%206.7%2015%2015v131H0V15z%22/%3E%3Cpath%20fill%3D%22%231BB91F%22%20d%3D%22M0%20116h160v29c0%208.3-6.7%2015-15%2015H15c-8.3%200-15-6.7-15-15v-29z%22/%3E%3C/svg%3E';
  function iconOf(k) { if (k === 'cowork' || k === 'chat') k = 'claude'; return icons[k] || MARKS[k]; }
  function App(k, c) {
    if (iconOf(k)) return '<img class="' + (c || 'size-5') + ' flex-none ' + (c === 'size-[34px]' ? 'rounded-[8px]' : 'rounded-[5px]') + '" src="' + iconOf(k) + '" alt="">';
    /* stand-ins for the design page; the app has the real icons. pi has no app, and OpenCode's app is optional: both draw
       their own published marks (pi.dev's logo, opencode.ai's), not ours. */
    var g = {
      opencode: ['#131010', '<path d="M9 10.5h6v6H9z" fill="#5A5858"/><path fill-rule="evenodd" d="M18 19.5H6v-15h12zM15 7.5H9v9h6z" fill="#fff"/>'],
      cursor: ['#14120B', '<path d="M12 4.5l6.5 3.75v7.5L12 19.5l-6.5-3.75v-7.5z" fill="#EDECEC"/><path d="M12 4.5l6.5 3.75L12 12z" fill="#B8B6B0"/><path d="M12 12l6.5-3.75v7.5z" fill="#8A8883"/>'],
      /* Muse, Dots and Grok Bot: stand-ins until the app sends each one's real icon (`icons`) */
      muse: ['#0F172A', '<path d="M6.5 16.5v-6a2.75 2.75 0 0 1 5.5 0v6m0-6a2.75 2.75 0 0 1 5.5 0v6" fill="none" stroke="#E2E8F0" stroke-width="2" stroke-linecap="round"/>'],
      dots: ['#18181B', '<circle cx="6.75" cy="12" r="2" fill="#fff"/><circle cx="12" cy="12" r="2" fill="#fff" fill-opacity=".62"/><circle cx="17.25" cy="12" r="2" fill="#fff" fill-opacity=".32"/>'],
      grokbot: ['#000', '<circle cx="11" cy="13" r="4.6" fill="none" stroke="#fff" stroke-width="1.8"/><path d="M9.1 15.1L17.6 6.4" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>'],
      pi: ['#18181B', '<g transform="translate(.07 .07) scale(.02982)"><path fill="#F09082" d="M165.29 165.29H517.36V400H400V282.65H165.29Z"/><path fill="#4D9ABF" d="M165.29 282.65H282.65V400H400V517.36H282.65V634.72H165.29Z"/><path fill="#F1BE58" d="M517.36 400H634.72V634.72H517.36Z"/></g>']
    }[k] || ['#52525B', ''];
    return '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="' + g[0] + '"/>' + g[1] + '</svg>';
  }
  /* A terminal session: the icon says where Pick up takes you, so it is the terminal's, with the agent (Claude, Codex,
     OpenCode, pi) as a small badge on its corner. A session in the Claude or Codex app keeps that app's icon. In herdr,
     the terminal is the one showing herdr. */
  var TERMS = { terminal: 'Terminal', iterm: 'iTerm2', ghostty: 'Ghostty', cmux: 'cmux', agterm: 'agterm', warp: 'Warp', kitty: 'kitty', wezterm: 'WezTerm', vscode: 'VS Code', cursor: 'Cursor', zed: 'Zed', conductor: 'Conductor' };
  function AppOf(p, c) {
    /* a session Conductor runs wears Conductor's icon the way a terminal session wears its terminal's; Reply still goes through the card (no `via`) */
    var host = p.via || p.opens;
    if (!host) return App(p.app, c);
    var small = c === 'size-3.5', tile = c === 'size-[34px]', b = small ? 'size-2 -bottom-[2px] -right-[3px]' : tile ? 'size-[17px] -bottom-[3px] -right-[4px]' : 'size-[11px] -bottom-[3px] -right-[3px]';
    var term = icons[host] ? '<img class="' + (c || 'size-5') + ' flex-none ' + (tile ? 'rounded-[8px]' : 'rounded-[5px]') + '" src="' + icons[host] + '" alt="">'
      : '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="#27272A"/><path d="M7 8l4 4-4 4M12.5 16.5h5" stroke="#E4E4E7" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    return '<span class="relative flex flex-none" title="' + agentName(p.app) + ' in ' + (p.host ? esc(p.host) + ', in ' : '') + esc(TERMS[host] || 'a terminal') + '">' + term +
      /* a real app icon has a clear margin around its rounded square (Apple's icon grid): in a badge it is scaled past it, so
         the ring sits on the icon's own edge instead of leaving a dark band between them */
      '<span class="absolute ' + b + ' flex overflow-hidden ' + (tile ? 'rounded-[5px] ring-2' : 'rounded-[3px] ring-[1.5px]') + ' ring-black">' + App(p.app, iconOf(p.app) ? 'size-full scale-[1.24]' : 'size-full') + '</span></span>';
  }
  /* where the main button takes you, by name: "Open Claude", "Open Ghostty" */
  function goLabel(p) { return 'Open ' + (p && (p.via || p.opens) ? TERMS[p.via || p.opens] || 'Terminal' : agentShort(p && (p.app || (p.status && p.status.app)))); }
  /* The arc turns inside its own drawing, around its own centre (12, 12). Turning the whole icon with CSS made it wobble
     wherever it sat on a fraction of a pixel (beside a project name of any width): it circled a centre a little off its own. */
  var STILL = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  /* ---- small motions from transitions.dev (their styles are in input.css). `still` puts the end state in at once. ---- */
  var SMOOTH = 'cubic-bezier(.22,1,.36,1)';
  /* icon swap: the new icon joins the slot small and blurred and sharpens while the old one shrinks away; the same icon again
     is left alone, so a spinner keeps its turn */
  function iconSwap(slot, html, still) {
    var old = null;
    [].slice.call(slot.children).forEach(function (c) { if (!c.classList.contains('t-icon')) c.remove(); else if (c.classList.contains('on')) old = c; });
    if (old && old._h === html) return;
    if (old) { old.classList.remove('on'); if (still || STILL) old.remove(); else setTimeout(function () { old.remove(); }, 260); }
    if (!html) return;
    var e = document.createElement('span'); e.className = 't-icon'; e._h = html; e.innerHTML = html;
    slot.appendChild(e);
    if (still || STILL || !old) { e.style.transition = 'none'; e.classList.add('on'); void e.offsetWidth; e.style.transition = ''; }
    else { void e.offsetWidth; e.classList.add('on'); }
  }
  /* text states swap: the old words go up and blur away, the new ones come up from below */
  function swapText(el, text, color, still) {
    if (el._t === text && el._c === color) return;
    var first = el._t == null; el._t = text; el._c = color; clearTimeout(el._sw);
    var put = function () { el.textContent = text; el.style.color = color || ''; };
    if (first || still || STILL) { el.classList.remove('is-exit', 'is-enter'); put(); return; }
    el.classList.add('is-exit');
    el._sw = setTimeout(function () { put(); el.classList.remove('is-exit'); el.classList.add('is-enter'); void el.offsetWidth; el.classList.remove('is-enter'); }, 150);
  }
  /* text morph: the letters both share stay where they are; only the rest cross-blurs, while its width eases */
  function morphText(el, next, still) {
    var prev = el._t != null ? el._t : el.textContent;
    if (prev === next) return;   /* the same words again (a refresh) leave a change under way to finish */
    clearTimeout(el._sw); el.classList.remove('is-exit', 'is-enter');
    el._t = next;
    if (still || STILL) { el.textContent = next; return; }
    var a = 0; while (a < prev.length && a < next.length && prev[a] === next[a]) a++;
    var b = 0; while (b < prev.length - a && b < next.length - a && prev[prev.length - 1 - b] === next[next.length - 1 - b]) b++;
    var swap = document.createElement('span'), out = document.createElement('span'), inn = document.createElement('span');
    swap.className = 't-morph-swap'; out.className = 't-morph-old'; inn.className = 't-morph-new'; out.setAttribute('aria-hidden', 'true');
    out.textContent = prev.slice(a, prev.length - b); inn.textContent = next.slice(a, next.length - b);
    swap.appendChild(out); swap.appendChild(inn);
    el.textContent = ''; el.appendChild(document.createTextNode(next.slice(0, a))); el.appendChild(swap); el.appendChild(document.createTextNode(next.slice(next.length - b)));
    swap.style.width = out.getBoundingClientRect().width + 'px'; void swap.offsetWidth;
    swap.classList.add('is-morphing'); swap.style.width = inn.getBoundingClientRect().width + 'px';
    el._sw = setTimeout(function () { if (el._t === next) el.textContent = next; }, 280);
  }
  /* text swap soft, for whole blocks: a copy of what was there stays where it was and fades out while the new words fade in,
     so nothing beside them moves. `seen` is taken before the change, `crossIn` after it. */
  function crossSeen(box, sels) {
    var br = box.getBoundingClientRect();
    return sels.map(function (s) {
      var el = box.querySelector(s); if (!el) return null;
      var r = el.getBoundingClientRect(), g = null;
      if (el.offsetParent && r.width && r.height) {
        g = el.cloneNode(true); g.removeAttribute('title');
        /* the copy keeps its own look (it comes after the real one, so q() still finds the real one) but none of the names
           inside it answer, and it takes no part in the rise or the glide (.rv) */
        g.classList.remove('rv');
        [].slice.call(g.querySelectorAll('[class]')).forEach(function (x) {
          x.setAttribute('class', (x.getAttribute('class') || '').split(/\s+/).filter(function (c) { return c && !/^(rv|nw|nrow)$|^(o|x|nw)-/.test(c); }).join(' '));
        });
        g.classList.add('xb-ghost');
        g.style.left = (r.left - br.left) + 'px'; g.style.top = (r.top - br.top) + 'px'; g.style.width = r.width + 'px'; g.style.height = r.height + 'px';
      }
      return { el: el, html: el.innerHTML, shown: !!g, g: g };
    }).filter(Boolean);
  }
  function crossIn(box, seen, icon) {
    if (STILL) return;
    seen.forEach(function (x) {
      var el = x.el, now = !!el.offsetParent, isIcon = el === icon;
      if (x.html === el.innerHTML && x.shown === now) return;
      /* an icon also shrinks and grows (icon swap); words only blur, so a block's own glide (settleCard) keeps its transform */
      var d = isIcon ? 250 : 200, on = { opacity: 1, filter: 'blur(0)' }, off = { opacity: 0, filter: 'blur(2px)' };
      if (isIcon) { on.transform = 'none'; off.transform = 'scale(.25)'; }
      if (x.g) {
        box.appendChild(x.g);
        var g = x.g, gone = function () { g.remove(); };
        g.animate([on, off], { duration: d, easing: 'ease-in-out', fill: 'forwards' }).onfinish = gone;
        setTimeout(gone, d + 120);   /* the timer finishes it even when animations are paused */
      }
      if (now) el.animate([off, on], { duration: d, easing: 'ease-in-out' });
    });
  }
  function Spinner(cls, style) { return '<svg class="flex-none ' + (cls || 'size-3') + '" viewBox="0 0 24 24" fill="none" stroke="' + COLORS.running + '" stroke-width="3.5" stroke-linecap="round" aria-hidden="true"' + (style ? ' style="' + style + '"' : '') + '><path d="M12 3a9 9 0 1 1-9 9">' + (STILL ? '' : '<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="1s" repeatCount="indefinite"/>') + '</path></svg>'; }
  /* what a session's status is, in words: the card's top line and each row of the list. `short` is the list's version. */
  function phrase(p, short) {
    var a = p.ask, k = p.status.kind;
    if (a) return { t: { permission: 'Needs your OK', question: 'Asked you something', plan: 'Has a plan for you' }[a.kind] || 'Needs you', c: COLORS.attention };
    if (k === 'attention') return { t: /error/.test(p.status.text) ? (short ? 'Hit an error' : 'Stopped on an error') : (short ? 'Needs you' : (p.line || 'Needs you')), c: COLORS.attention };
    if (k === 'running') return { t: 'Working', c: COLORS.running, spin: true };
    if (k === 'done' && p.fresh !== false) return { t: short ? 'Finished' : (p.line || 'Finished'), c: COLORS.done };
    return { t: short || !p.line ? p.away + ' ago' : p.line, c: '' };
  }
  /* The status marks, shared by the list, the notch while you work and the checklists: a ring drawn like the spinner, in
     the card's colours, with a faint still glow, and what it is inside: a check when it finished (or a step is done),
     ? for a question, the prompt for a command waiting for your OK, a list for a plan, ! for anything else waiting. */
  var RING = { done: '<path d="M8 12.3l2.7 2.7L16.2 9.4"/>', question: '<path d="M9.6 9.6a2.5 2.5 0 1 1 3.4 2.3c-.6.3-1 .8-1 1.5"/><path d="M12 16.6h.01" stroke-width="3"/>',
    permission: '<path d="M8 9.4l2.6 2.6L8 14.6"/><path d="M12.6 15h3.6"/>', plan: '<path d="M8.5 9.5h7M8.5 12h7M8.5 14.5h4.5"/>', need: '<path d="M12 7.6v5"/><path d="M12 16.4h.01" stroke-width="3"/>', down: '<path d="M12 7.6v7.4"/><path d="M8.7 12l3.3 3.3 3.3-3.3"/>' };
  function glow(c) { return 'filter:drop-shadow(0 0 1px ' + c + '80) drop-shadow(0 0 3.5px ' + c + '4d)'; }
  function Ring(k, label) {
    var c = k === 'done' ? COLORS.done : k === 'down' ? COLORS.running : COLORS.attention;
    return '<svg class="size-4 flex-none" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" style="' + glow(c) + '"' + (label ? ' aria-label="' + esc(label) + '"' : ' aria-hidden="true"') + '><circle cx="12" cy="12" r="9.5"/>' + (RING[k] || RING.need) + '</svg>';
  }
  /* A session's pull requests (p.prs, a list; each: number, repo, url, state open|draft|merged|closed, checks pass|fail|running, review approved|changes,
     conflict). Icon only. Its colour is the PR's state, in GitHub's: green open, purple merged, red closed, grey draft. When it is
     yours to act on (checks failing, changes requested, conflicts) the whole icon turns orange. The number and the words show in a
     small label while the pointer is on it (prTip); clicking it opens the pull request. */
  var PRC = { open: '#3FB950', merged: '#A371F7', closed: '#F85149', draft: '#8B949E' };
  var PRI = { open: '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M13 6h3a2 2 0 0 1 2 2v7"/><path d="M6 9v12"/>',
    merged: '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 21V9a9 9 0 0 0 9 9"/>',
    draft: '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 9v12"/><path d="M18 5.5v.01"/><path d="M18 8.5v.01"/><path d="M18 11.5v.01"/>',
    closed: '<circle cx="6" cy="6" r="3"/><circle cx="18" cy="18" r="3"/><path d="M6 9v12"/><path d="M21 3l-6 6"/><path d="M21 9l-6-6"/><path d="M18 11.5V15"/>' };
  function prWord(pr) {
    if (pr.state === 'merged') return { t: 'Merged' };
    if (pr.state === 'closed') return { t: 'Closed' };
    if (pr.state === 'draft') return { t: 'Draft' };
    if (pr.conflict) return { t: 'Conflicts', c: COLORS.attention };
    if (pr.checks === 'fail') return { t: 'Checks failing', c: COLORS.attention };
    if (pr.review === 'changes') return { t: 'Changes requested', c: COLORS.attention };
    if (pr.checks === 'running') return { t: 'Checks running' };
    if (pr.review === 'approved' && pr.checks === 'pass') return { t: 'Ready to merge', c: COLORS.done };
    if (pr.review === 'approved') return { t: 'Approved', c: COLORS.done };
    return { t: 'Open' };
  }
  /* the icon's colour, and the words say it in the same colour */
  function prColor(pr) { return prWord(pr).c === COLORS.attention ? COLORS.attention : PRC[pr.state]; }
  function PRIcon(pr, cls) {
    var w = prWord(pr), c = prColor(pr);
    return '<svg class="' + (cls || 'size-3.5') + ' flex-none cursor-pointer" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" style="' + glow(c) + '" role="img" aria-label="' + esc('#' + pr.number + ' ' + w.t) + '">' + (PRI[pr.state] || PRI.open) + '</svg>';
  }
  /* One session can open several pull requests. Its mark shows the one that matters most (it needs you, then open, draft,
     merged, closed) with a small count when there are more; the label lists them all. */
  var PRRANK = { open: 1, draft: 2, merged: 3, closed: 4 };
  function prTop(list) {
    return list.slice().sort(function (a, b) {
      var ra = prWord(a).c === COLORS.attention ? 0 : PRRANK[a.state] || 5, rb = prWord(b).c === COLORS.attention ? 0 : PRRANK[b.state] || 5;
      return ra - rb;
    })[0];
  }
  /* a session's pull requests as the page shows them: none at all while Show pull requests is off */
  function prsOf(p) { return snap && (snap.showPRs === false || snap.settings && snap.settings.showPRs === false) || !p.prs || !p.prs.length ? null : p.prs; }
  function PRMark(list, cls) {
    return '<span class="flex items-center gap-1">' + PRIcon(prTop(list), cls) + (list.length > 1 ? '<span class="text-[11px] tabular-nums leading-none text-muted-foreground">' + list.length + '</span>' : '') + '</span>';
  }
  /* One label for every PR mark, drawn above the one under the pointer (below it when there is no room). It is Perch's own,
     since a card hovered open gets no native tooltips (hoverAt plays the enter and leave). */
  var prTip = document.createElement('div'); prTip.className = 'pr-tip'; document.body.appendChild(prTip);
  /* The label stays while the pointer is on it: leaving the icon waits a moment, so the pointer can cross to the label, and each
     pull request in it lights on hover and opens that pull request on a click. */
  var prHideT = 0, prShown = null, prAnchor = null, prWatch = 0, prCard = null, prSig = '';
  /* gone at once: its icon was drawn again (the list redrew, the card changed) and no leave came */
  function prNow() { clearTimeout(prHideT); clearInterval(prWatch); prTip.classList.remove('on'); prShown = null; prAnchor = null; prSig = ''; }
  function prHide() { clearTimeout(prHideT); prHideT = setTimeout(prNow, 160); }
  function prKeep() { clearTimeout(prHideT); }
  /* a refresh gave the mark under the label a different list of pull requests: the label (and a click on it) would still be the old one */
  function prStale(el) { if (el === prAnchor && JSON.stringify(el._prs) !== prSig) prNow(); }
  prTip.onmouseenter = prKeep; prTip.onmouseleave = prHide;
  prTip.onclick = function (e) {
    var it = e.target.closest('.pi'), pr = it && prShown && prShown[+it.dataset.i];
    e.stopPropagation(); if (pr && pr.url) post({ type: 'openpr', url: pr.url });
  };
  function prHover(el) {
    if (el.dataset.b) return; el.dataset.b = '1';
    el.onmouseenter = function () {
      var list = el._prs; if (!list || !list.length) return;
      prKeep(); prShown = list; prAnchor = el; prSig = JSON.stringify(list);
      clearInterval(prWatch); prWatch = setInterval(function () { if (!prAnchor || !prAnchor.isConnected || !prAnchor.getClientRects().length) { prNow(); } }, 300);
      prTip.innerHTML = list.map(function (pr, i) {
        var w = prWord(pr), col = prColor(pr), repo = pr.repo ? esc(pr.repo) + ' ' : '';
        /* with its title: the title, then the status and where it lives; without one (it comes with PR checks), one row */
        if (pr.title) return '<div class="pi p2" data-i="' + i + '"><div class="fade t">' + esc(pr.title) + '</div><div class="r">' + PRIcon(pr, 'size-3.5') + '<span style="color:' + col + '">' + esc(w.t) + '</span><span class="m tabular-nums">' + repo + '#' + pr.number + '</span></div></div>';
        return '<div class="pi" data-i="' + i + '"><div class="r">' + PRIcon(pr, 'size-3.5') + '<span style="color:' + col + '">' + esc(w.t) + '</span>' + (list.length > 1 && pr.repo ? '<span class="m">' + esc(String(pr.repo).split('/').pop()) + '</span>' : '') + '<span class="m tabular-nums">#' + pr.number + '</span></div></div>';
      }).join('');
      /* only as wide as its words, right edges together with the icon, and never past the card */
      var nb = n.getBoundingClientRect(), r = el.getBoundingClientRect(); prTip.style.left = '0px'; prTip.style.width = 'max-content'; prTip.style.maxWidth = (nb.width - 24) + 'px';   /* from the edge, so where it was last never narrows it */
      prTip.querySelectorAll('.fade').forEach(function (t) { t.classList.toggle('cut', t.scrollWidth - t.clientWidth > 1); });
      var tw = prTip.offsetWidth, th = prTip.offsetHeight;
      prTip.style.left = Math.max(nb.left + 12, Math.min(r.right - tw + 6, nb.right - tw - 12)) + 'px';
      /* below the icon; above it when that is where the room is; else held inside the card */
      var below = r.bottom + 4, above = r.top - th - 4, top = below + th <= nb.bottom - 6 ? below : above >= nb.top + 6 ? above : Math.max(nb.top + 6, nb.bottom - th - 6);
      prTip.style.top = top + 'px'; prTip.classList.add('on');
    };
    el.onmouseleave = prHide;
    el.onclick = function (e) { e.stopPropagation(); var t = el._prs && el._prs.length ? prTop(el._prs) : null; if (t && t.url) post({ type: 'openpr', url: t.url }); };
  }
  function Phrase(ph) { return (ph.spin ? Spinner('size-3', glow(COLORS.running)) : '') + '<span class="' + (ph.c ? '' : 'text-muted-foreground') + '"' + (ph.c ? ' style="color:' + ph.c + '"' : '') + '>' + esc(ph.t) + '</span>'; }
  var ENTER = svg('enter', 'size-2');
  /* a footer action: `act` is what it does, `key` its shortcut */
  function Act(v, label, key, act) { return Button(v, label, key ? Kbd(key, v === 'default') : '', (v === 'default' ? 'pr-0.5' : '') + '" data-act="' + act); }
  /* On a card you opened, Up and Down flip to the next session's card; it says so, since nothing else would tell you.
     The card Perch opened by itself says nothing there: it offers no button for Not now (N still snoozes). */
  function Flip() {
    if (snap && snap.proactive) return '';
    return snap && snap.projects.length > 1 ? Button('ghost', 'Sessions', Keys('\u2191', '\u2193'), 'pr-1" data-act="flip') : '';
  }
  function header(inner, right, i) { return '<div class="rv flex h-9 items-center gap-2 pl-4 pr-4" style="--i:' + (i || 0) + '"><div class="min-w-0 flex-1">' + inner + '</div>' + (right || '') + '</div>'; }

  /* ---- the character's coat: light from the top left, a rounded form, a rim of light and a soft fuzzy edge ----
     One SVG filter on the body (g.coat); the eyes sit on top of it, untouched. It works in the character's own 24-unit box,
     so it looks the same at every size. Shading compares the rounded height with a copy shifted toward the light: rising
     toward the light is lit, falling away is shade. (feDiffuseLighting measures slopes per pixel and turns the tiny steps
     of a soft blur into rings.) Two copies: from 30 px up, a fuzzy edge, faint grain and a ground shadow; smaller, they would
     only read as blur and dirt, so the small one keeps a crisp outline and gets its depth from the shading alone. */
  var COAT = { az: 235, el: 50, lit: .6, shade: 1, deep: 1.4, rim: .45, rimw: .5, rimb: 1.5, puff: 6.5, depth: 5, ao: .35, below: .3, fur: .6, fine: 8, strands: 3, grain: .14, gsize: 12, shine: .15, tight: 4 };
  function coatFilter(id, big) {
    var C = COAT, a = C.az * Math.PI / 180, lo = (C.fine / C.strands).toFixed(3), d = C.puff * .6, K = C.depth * 1.12 * Math.cos(C.el * Math.PI / 180);
    var Kd = (K * C.shade).toFixed(3), Kl = (K * C.lit).toFixed(3), len = .3 + .9 * (1 - C.el / 90);
    var rgb = function (f) { return '<feFuncR ' + f + '/><feFuncG ' + f + '/><feFuncB ' + f + '/>'; };
    var mix = function (i1, i2, k, out) { return '<feComposite in="' + i1 + '" in2="' + i2 + '" operator="arithmetic" ' + k + ' result="' + out + '"/>'; };
    return '<filter id="' + id + '" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">' +
      /* fur: the edge pushed around by noise, sideways along the sides and up and down along the top and bottom, so strands point outward */
      (big ? '<feTurbulence type="fractalNoise" baseFrequency="' + lo + ' ' + C.fine + '" numOctaves="2" seed="3" result="nA"/>' +
        '<feTurbulence type="fractalNoise" baseFrequency="' + C.fine + ' ' + lo + '" numOctaves="2" seed="9" result="nB"/>' +
        '<feColorMatrix in="nA" type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0 1" result="mA"/>' +
        '<feColorMatrix in="nB" type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 0 1" result="mB"/>' +
        mix('mA', 'mB', 'k2="1" k3="1"', 'strands') +
        '<feGaussianBlur in="SourceGraphic" stdDeviation="' + Math.min(.25, C.fur * .25) + '" result="soft"/>' +
        '<feDisplacementMap in="soft" in2="strands" scale="' + C.fur + '" xChannelSelector="R" yChannelSelector="G" result="spiky"/>' +
        '<feGaussianBlur in="spiky" stdDeviation="' + Math.min(.06, C.fur * .1) + '" result="fuzzy"/>'
        : '<feMerge result="fuzzy"><feMergeNode in="SourceGraphic"/></feMerge>') +
      /* form: a blurred silhouette is a pillow, high in the middle and falling to the edge, as grey */
      '<feGaussianBlur in="fuzzy" stdDeviation="' + C.puff + '" result="pillow"/>' +
      '<feColorMatrix in="pillow" type="matrix" values="0 0 0 1 0  0 0 0 1 0  0 0 0 1 0  0 0 0 0 1" result="H"/>' +
      '<feOffset in="H" dx="' + (-Math.cos(a) * d).toFixed(2) + '" dy="' + (-Math.sin(a) * d).toFixed(2) + '" result="Hs"/>' +
      /* shade (1 on the lit side, less away from the light) and light (brighter toward it), with a little shine on the brightest part */
      mix('H', 'Hs', 'k2="' + Kd + '" k3="-' + Kd + '" k4="1"', 'S') +
      mix('H', 'Hs', 'k2="-' + Kl + '" k3="' + Kl + '" k4="1"', 'Q') +
      '<feComponentTransfer in="Q" result="L">' + rgb('type="linear" slope="-1" intercept="1"') + '</feComponentTransfer>' +
      '<feComponentTransfer in="L" result="Sh">' + rgb('type="gamma" amplitude="' + C.shine + '" exponent="' + C.tight + '" offset="0"') + '</feComponentTransfer>' +
      mix('L', 'Sh', 'k2="1" k3="1"', 'A') +
      /* the rim falls into a little shade all round */
      '<feComponentTransfer in="H" result="AO">' + rgb('type="linear" slope="' + C.ao + '" intercept="' + (1 - C.ao).toFixed(2) + '"') + '</feComponentTransfer>' +
      mix('S', 'AO', 'k1="1"', 'SA') +
      /* colour: shade deepens it (toward the colour raised to a power, richer and darker) instead of greying it; light brightens it */
      '<feComponentTransfer in="fuzzy" result="opaque"><feFuncA type="linear" slope="0" intercept="1"/></feComponentTransfer>' +
      '<feComponentTransfer in="opaque" result="deep">' + rgb('type="gamma" amplitude="' + (1 - C.deep * .25) + '" exponent="' + (1 + C.deep) + '" offset="0"') + '</feComponentTransfer>' +
      '<feComponentTransfer in="SA" result="iSA">' + rgb('type="linear" slope="-1" intercept="1"') + '</feComponentTransfer>' +
      mix('opaque', 'SA', 'k1="1"', 'cS') + mix('deep', 'iSA', 'k1="1"', 'dS') + mix('cS', 'dS', 'k2="1" k3="1"', 'dark') +
      mix('dark', 'A', 'k1="1" k2="1" k3=".25"', 'lit') +
      /* grain: fine, like the tips of fur */
      (big ? '<feTurbulence type="fractalNoise" baseFrequency="' + C.gsize + '" numOctaves="3" seed="5" result="gN"/>' +
        '<feColorMatrix in="gN" type="matrix" values="1 0 0 0 0  1 0 0 0 0  1 0 0 0 0  0 0 0 0 1" result="G"/>' +
        mix('lit', 'G', 'k1="' + 2 * C.grain + '" k2="' + (1 - C.grain) + '"', 'grainy') : '<feMerge result="grainy"><feMergeNode in="lit"/></feMerge>') +
      /* rim light: the fringe catches light all round, most on the shadow side, like fur with a lamp behind it */
      '<feGaussianBlur in="fuzzy" stdDeviation="' + C.rimw + '" result="rb"/>' +
      '<feColorMatrix in="rb" type="matrix" values="0 0 0 -1 1  0 0 0 -1 1  0 0 0 -1 1  0 0 0 0 1" result="R0"/>' +
      '<feComponentTransfer in="R0" result="R1">' + rgb('type="linear" slope="1.8" intercept="0"') + '</feComponentTransfer>' +
      mix('R1', 'S', 'k1="-' + C.rimb + '" k2="' + (1 + C.rimb) + '"', 'R') +
      mix('grainy', 'R', 'k1="' + (C.rim * .9).toFixed(3) + '" k2="1" k3="' + (C.rim * .08).toFixed(3) + '"', 'rimmed') +
      '<feComposite in="rimmed" in2="fuzzy" operator="in" result="body"/>' +
      /* a soft shadow under it, away from the light */
      (big ? '<feGaussianBlur in="fuzzy" stdDeviation="1" result="sb"/>' +
        '<feOffset in="sb" dx="' + (-Math.cos(a) * len).toFixed(2) + '" dy="' + (-Math.sin(a) * len * .6 + .7).toFixed(2) + '" result="so"/>' +
        '<feFlood flood-color="#000" flood-opacity="' + C.below + '"/><feComposite in2="so" operator="in" result="shadow"/>' +
        '<feMerge><feMergeNode in="shadow"/><feMergeNode in="body"/></feMerge>' : '') + '</filter>';
  }
  document.body.insertAdjacentHTML('beforeend', '<svg width="0" height="0" style="position:absolute" aria-hidden="true">' + coatFilter('coat', true) + coatFilter('coat-sm', false) + '</svg>');

  /* ---- markup (built once) ---- */
  var scene = document.getElementById('scene');
  scene.innerHTML =
    '<div class="cr" data-m="sleep"><i class="puff"></i><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><g class="coat"><path d="' + DOME.d + '"/><path class="pl" d=""/><path class="fd" d=""/></g></svg></i><i class="ey l"></i><i class="ey r"></i></div><i class="dot"></i><i class="say"></i></div>' +
    '<div class="n perch" data-s="idle"><i class="ear l"></i><i class="ear r"></i><div class="clip"><i class="glow"></i><div class="act"></div>' +
    '<div class="pane p-open">' + '<button aria-label="Settings" title="Settings (\u2318,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 flex h-[18px] cursor-pointer items-center gap-1 rounded-md pl-[3px] pr-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + Kbd('\u2318,') + '</button>' +
    '<button class="upd-chip rv absolute left-[44px] top-[7px] z-10 hidden h-[18px] cursor-pointer items-center gap-1 rounded-md px-1.5 text-[11px] font-medium transition-colors" style="--i:0"></button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-2">' +
      /* the chat's title is the heading, the whole line its own; its status, in words, ends the grey line under it */
      /* the app's icon at full size, like a notification, beside two lines: the title, the whole line its own, and in grey
         the project and what you were doing with the status at its right. Then, apart, what happened; then Next. Read top
         to bottom in a glance. */
      '<div class="rv mt-1.5 flex items-center gap-[11px] px-4" style="--i:1"><span class="o-app flex flex-none"></span><div class="flex min-w-0 flex-1 flex-col gap-px">' +
        '<span dir="auto" class="o-name fade min-w-0 text-left text-sm font-semibold leading-[19px] tracking-[-0.02em]"></span>' +
        '<div class="flex min-w-0 items-baseline gap-2"><p dir="auto" class="o-sub fade min-w-0 flex-1 text-left text-[13px] leading-[18px] text-muted-foreground"></p><span class="o-pr mt-px flex-none self-start"></span><span class="o-st ml-auto flex flex-none items-center gap-1.5 text-xs"></span></div></div></div>' +
      '<p dir="auto" class="o-h rv mt-2.5 px-4 text-[13px] leading-[18px]" style="--i:2"></p>' +
      '<p dir="auto" class="o-c rv mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground line-clamp-2" style="--i:2"></p>' +
      '<div class="o-ask rv px-4" style="--i:3"></div>' +
      /* while you reply: what the agent actually said, in place of the summary, so you answer what you read */
      '<div class="o-said rv mt-2.5 px-4" style="--i:2"><div class="o-said-in max-h-[150px] overflow-y-auto rounded-lg bg-black/[0.18] px-3 py-1.5 text-[13px] leading-[19px] text-foreground/90"></div></div>' +
      '<p class="o-nx rv mt-2.5 flex items-baseline gap-2 px-4 text-[13px] leading-[18px]" style="--i:3"><span class="o-nl font-medium text-muted-foreground">Next</span><span class="o-orb -my-px hidden flex-none self-center"><svg></svg></span><span dir="auto" class="o-x min-w-0 flex-1 text-foreground line-clamp-2"></span></p>' +
      /* files for the reply, as chips over its field (attChips) */
      '<div class="r-att rv hidden mt-2 ml-[47px] mr-[74px] gap-1 overflow-x-auto" style="--i:4"></div>' +
      '<div class="rv relative mt-2 h-9 px-2.5" style="--i:4"><div class="f-main flex h-9 items-end gap-0.5">' + Button('ghost', 'All sessions', Kbd('\u2190'), 'x-list pl-1.5') + '<span class="flex-1"></span><span class="o-acts flex items-center gap-0.5"></span></div>' +
      '<div class="f-rep hidden h-9 items-end gap-1.5"><button aria-label="Close reply" title="Close (Esc)" class="x-rclose flex h-7 flex-none cursor-pointer items-center rounded-md px-0.5 opacity-75 transition-opacity hover:opacity-100">' + Kbd('esc') + '</button><input class="r-in h-7 cursor-text min-w-0 flex-1 rounded-lg bg-white/[0.1] px-2.5 text-[13px] text-foreground caret-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none transition-[background-color,box-shadow] duration-200 placeholder:text-white/35 focus:bg-white/[0.13] focus:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]" placeholder="Reply to Claude\u2026" spellcheck="false" autocomplete="off" aria-label="Reply">' + Button('default', '<span class="x-send-l">Send</span>', Kbd(svg('enter', 'size-2'), 1), 'x-send h-7 rounded-lg pr-1') + '</div>' +
      '<div class="f-prev hidden h-9 items-end gap-0.5">' + Button('ghost', 'Back', Kbd('esc'), 'x-pvback" title="Back (Esc)') + '<span class="flex-1"></span><span class="o-pacts flex items-center gap-0.5"></span></div>' +
      '<div class="f-snz hidden h-9 items-end gap-1"><span class="pl-1.5 text-[13px] text-muted-foreground">Remind me in</span><span class="flex-1"></span>' + Button('ghost', '30 min', Kbd('1'), 'x-s1') + Button('ghost', '2 hours', Kbd('2'), 'x-s2') + Button('ghost', 'Tomorrow', Kbd('3'), 'x-s3') + '</div></div>' +
    '</div></div>' +
    /* Settings is Command+comma, here and on the card: in the list, letters type into the filter */
    '<div class="pane p-switch">' + '<button aria-label="Settings" title="Settings (\u2318,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 flex h-[18px] cursor-pointer items-center gap-1 rounded-md pl-[3px] pr-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + Kbd('\u2318,') + '</button>' +
    '<button class="upd-chip rv absolute left-[44px] top-[7px] z-10 hidden h-[18px] cursor-pointer items-center gap-1 rounded-md px-1.5 text-[11px] font-medium transition-colors" style="--i:0"></button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="s-h truncate text-sm font-medium leading-4">Jump back in</div>', '<span class="s-n flex-none text-xs text-muted-foreground">Type to filter</span>') +
      '<div class="rv relative" style="--i:1"><div class="s-l max-h-[196px] overflow-y-auto px-1.5 pb-1"></div><div class="s-bar"><i></i></div></div>' +
      '<div class="rv s-ft flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground" style="--i:3"><span class="flex items-baseline gap-1.5">' + Keys('\u2191', '\u2193') + 'Choose</span><button class="x-back flex cursor-pointer items-baseline gap-1.5 rounded-md px-1 text-muted-foreground transition-colors hover:text-foreground">' + Kbd('\u2192') + 'Details</button><span class="flex items-baseline gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Open</span><button class="x-new flex cursor-pointer items-baseline gap-1.5 rounded-md px-1 text-muted-foreground transition-colors hover:text-foreground" title="New session (\u2325\u2318N), from anywhere">' + Kbd('\u2325\u2318N') + 'New session</button></div>' +
    '</div></div>' +
    /* a new session: which agent, which folder (or none), then what to ask; the three choices read along the top as you make them */
    '<div class="pane p-ns">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8"><div class="nw"></div></div></div>' +
    '<div class="pane p-onb">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-2"><div class="onb"></div></div></div>' +
    '<div class="pane p-set">' + '<span class="s-title rv absolute left-11 top-[7px] z-10 flex h-[18px] items-center gap-1 text-[13px] font-medium tracking-[-0.01em]" style="--i:0">Settings</span>' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-2"><div class="set"></div></div></div>' +
    /* what is new after an update: shown once, on the first start of the new version. Got it goes on to the list. */
    '<div class="pane p-new">' + '<button aria-label="Close" title="Close" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-2"><div class="wn"></div></div></div>' +
    '</div></div>';

  /* Inline markdown for summaries: **bold**, *italic*, `code`, [links](url) as plain text. Escaped first, so nothing can inject markup. */
  /* a whole message, not one line: paragraphs, lists and code blocks; the words inside them as md() draws a line */
  function mdBlock(t) {
    return String(t || '').split('```').map(function (part, i) {
      if (i % 2) return '<pre class="my-1.5 overflow-x-auto rounded-md bg-black/40 px-2 py-1.5 font-mono text-[11.5px] leading-4 md-code">' + esc(part.replace(/^[\w-]*\n/, '').replace(/\n$/, '')) + '</pre>';
      return part.split(/\n{2,}/).map(function (para) {
        var lines = para.replace(/^\s*\n/, '').replace(/\s+$/, '').split('\n').filter(function (l) { return l.trim(); }); if (!lines.length) return '';
        /* a table can follow a line of text with no blank line between: the paragraph is cut into text and tables */
        var out = '', text = [];
        for (var k = 0; k < lines.length; k++) {
          if (lines[k].indexOf('|') < 0 || !mdSep(lines[k + 1])) { text.push(lines[k]); continue; }
          var end = k + 2; while (end < lines.length && lines[end].indexOf('|') >= 0) end++;
          out += mdLines(text) + mdTable(lines.slice(k, end)); text = []; k = end - 1;
        }
        return out + mdLines(text);
      }).join('');
    }).join('');
  }
  /* Lines of one paragraph: text, headings, and lists. A list can follow a bold line with no blank line, a deeper indent nests,
     and an indented line under an item carries on that item. */
  function mdLines(lines) {
    var out = '', text = [], items = [], stack = [];
    var flushText = function () { if (text.length) out += '<p dir="auto" class="my-2">' + text.map(function (l) { return md(l); }).join('<br>') + '</p>'; text = []; };
    var flushItems = function () {
      if (items.length) out += '<ul class="my-2 flex flex-col gap-0.5">' + items.map(function (it) {
        return '<li class="flex gap-2"' + (it.lvl ? ' style="margin-left:' + it.lvl * 16 + 'px"' : '') + '><span class="md-mk flex-none text-muted-foreground' + (it.num ? ' min-w-[1.1em] text-right tabular-nums' : '') + '">' + it.mark + '</span><span dir="auto" class="min-w-0">' + it.text.split('\n').map(function (l) { return md(l); }).join('<br>') + '</span></li>';
      }).join('') + '</ul>';
      items = []; stack = [];
    };
    lines.forEach(function (raw) {
      var l = raw.replace(/\t/g, '    '), m = /^(\s*)([-*\u2022]|\d+[.)])\s+(\S.*)$/.exec(l);
      if (m) {
        flushText();
        var ind = m[1].length; while (stack.length && ind < stack[stack.length - 1]) stack.pop();
        if (!stack.length || ind > stack[stack.length - 1]) stack.push(ind);
        items.push({ lvl: stack.length - 1, num: /\d/.test(m[2]), mark: /\d/.test(m[2]) ? m[2].replace(')', '.') : '\u2022', text: m[3] });
      } else if (/^\s*#{1,6}\s/.test(l)) { flushItems(); flushText(); out += '<p dir="auto" class="my-2 font-semibold text-foreground">' + md(l) + '</p>'; }
      else if (items.length && /^\s/.test(l)) items[items.length - 1].text += '\n' + l.trim();
      else { flushItems(); text.push(l); }
    });
    flushItems(); flushText();
    return out;
  }
  /* | a | b | rows: the cells, an escaped \| kept as a pipe */
  function mdCells(l) {
    return l.replace(/\\\|/g, '\u0000').trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(function (c) { return c.replace(/\u0000/g, '|').trim(); });
  }
  /* the line under a table's header: |---|:---:|---:| */
  function mdSep(l) {
    return !!l && l.indexOf('|') >= 0 && l.indexOf('-') >= 0 && mdCells(l).every(function (c) { return /^:?-+:?$/.test(c); });
  }
  /* A table, without lines: the header in grey, a faint band on every other row, numbers in even columns. A column the
     separator does not align is right-aligned when it holds only numbers. Short columns stay on one line and a wide table
     scrolls sideways in the message; a column of long text wraps instead. */
  function mdTable(rows) {
    var head = mdCells(rows[0]), n = head.length, fit = function (r) { r = r.slice(0, n); while (r.length < n) r.push(''); return r; };
    var body = rows.slice(2).map(function (r) { return fit(mdCells(r)); });
    var align = fit(mdCells(rows[1])).map(function (c, j) {
      if (/^:-+:$/.test(c)) return 'c';
      if (/-:$/.test(c)) return 'r';
      if (/^:-/.test(c)) return '';
      var vals = body.map(function (r) { return r[j]; }).filter(function (v) { return !/^(|-|\u2013|\u2014|n\/a)$/i.test(v); });
      return vals.length && vals.every(function (v) { return /^[-+~\u2212\u2248]?[$\u20ac\u00a3]?\d[\d,.]*\s?(%|\u00d7|[a-z\u00b5]{1,3})?$/i.test(v.replace(/\*\*/g, '')); }) ? 'r' : '';
    });
    var long = head.map(function (h, j) { return [h].concat(body.map(function (r) { return r[j]; })).some(function (v) { return v.length > 28; }); });
    var cell = function (tag, v, j) { return '<' + tag + ' dir="auto"' + (align[j] ? ' data-a="' + align[j] + '"' : '') + (long[j] ? ' data-w="1"' : '') + '>' + md(v) + '</' + tag + '>'; };
    /* the fades sit on a still wrapper (md-tw), not on the table that scrolls: WebKit repaints a masked scroller every frame */
    return '<div class="md-tw -mx-3 my-1.5"><div class="md-tbl px-1"><table><thead><tr>' + head.map(function (h, j) { return cell('th', h, j); }).join('') + '</tr></thead><tbody>' +
      body.map(function (r) { return '<tr>' + r.map(function (v, j) { return cell('td', v, j); }).join('') + '</tr>'; }).join('') + '</tbody></table></div></div>';
  }
  function md(t) {
    var h = String(t || '').replace(/^\s*(#{1,6}\s+|[-*]\s+)/, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return h.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/`([^`]+)`/g, '<code class="rounded bg-white/[0.09] px-1 py-px font-mono text-[11.5px] md-code">$1</code>')
      .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, function (m, a, b) { return '<strong class="font-semibold text-foreground">' + (a || b) + '</strong>'; })
      .replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?!\*)/g, '$1<em>$2</em>')
      .replace(/(^|[^\w])_([^_\s][^_]*)_(?![\w])/g, '$1<em>$2</em>');
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
    else if (a === 'copy') previewCopy();
    else if (a === 'snooze') snoozeMenu(true);
    else if (a === 'allow' || a === 'deny') post({ type: 'answer', choice: a });
    else if (a === 'pick') askKey(String(+b.dataset.i + 1));
    else if (a === 'other') otherMenu(true);
    else if (a === 'qback') askKey('back');
    else if (a === 'qnext') askKey('next');
    else if (a === 'flip') post({ type: 'flip' });
    else if (a === 'preview') previewMenu(true);
    else if (a === 'live') { liveNext = true; post({ type: 'settings' }); }   /* the reason line's Settings: opens it with Live status chosen */
  });
  /* "Not now" asks when to come back: 30 min, 2 hours or tomorrow morning. */
  var fMain = q('.f-main'), fSnz = q('.f-snz'), fRep = q('.f-rep'), fPrev = q('.f-prev'), footers = [fMain, fSnz, fRep, fPrev];
  /* The footer changes between its actions, Reply and Not now. The old row fades up and away while the new one rises in. */
  function footer(el) {
    footers.forEach(function (f) { if (f._out) { f._out.cancel(); f._out = null; f.style.position = f.style.left = f.style.right = f.style.top = ''; f.style.display = 'none'; } });
    var was = footers.filter(function (f) { return f.style.display !== 'none' && getComputedStyle(f).display !== 'none'; })[0];
    if (was === el) return;
    footers.forEach(function (f) { if (f !== was) f.style.display = f === el ? 'flex' : 'none'; });
    if (!was) return;
    if (!n.offsetParent || n.dataset.s !== 'open' || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) { was.style.display = 'none'; return; }
    was.style.position = 'absolute'; was.style.left = was.style.right = '10px'; was.style.top = '0';
    /* transitions.dev text states swap: the old row goes up and blurs away, then the new one comes up from below (it is there
       at once, out of sight, so a field in it can take the caret) */
    var out = was._out = was.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateY(-4px)', filter: 'blur(2px)' }], { duration: 150, easing: 'ease-in-out' });
    var done = function () { if (was._out !== out) return; was._out = null; out.cancel(); was.style.display = 'none'; was.style.position = was.style.left = was.style.right = was.style.top = ''; };
    out.onfinish = done; setTimeout(done, 220);   /* the timer finishes it even when animations are paused */
    el.animate([{ opacity: 0, transform: 'translateY(4px)', filter: 'blur(2px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], { duration: 150, delay: 150, easing: 'ease-in-out', fill: 'backwards' });
  }
  function snoozeMenu(open, quiet) {
    footer(open ? fSnz : fMain);
    if (!quiet) post({ type: 'snoozeMenu', open: open });
  }
  /* "Reply": answer a question Claude asked without opening the session first. The reply is pasted into the session. */
  var rIn = q('.r-in');
  /* the notch's clip never scrolls, whatever asks it to (focus, scrollIntoView): its content only ever grows into place */
  if (window.webkit && window.webkit.messageHandlers) window.addEventListener('scroll', function () { if (window.scrollX || window.scrollY) window.scrollTo(0, 0); });
  n.querySelector('.clip').addEventListener('scroll', function (e) { if (e.target.scrollTop || e.target.scrollLeft) { e.target.scrollTop = 0; e.target.scrollLeft = 0; } });
  /* the session the open reply is for; what you type there is kept as its draft (Swift holds them, snap.drafts) */
  var replyFor = '';
  function replyMenu(open, quiet) {
    if (asking.typing) { if (!open) otherMenu(false, quiet); return; }
    /* from Preview, the message stays where you scrolled it and the field comes in under it (Swift hears replyMenu and leaves Preview) */
    if (previewOn) { previewOn = false; previewFrom = ''; q('.p-open').dataset.prev = ''; if (!open && !quiet) post({ type: 'previewMenu', open: false }); if (snap && lastSt === 'open') layout('open', snap); }
    footer(open ? fRep : fMain);
    showSaid(open);
    var p = snap && snap.projects[snap.selected];
    /* the words you left in this session's reply are still there, the caret after them */
    if (open && p && p.id !== replyFor) { replyFor = p.id; rIn.value = (snap.drafts && snap.drafts[p.id]) || ''; }
    repOn = !!open; repAtt();
    /* focus without scrolling: the card is still growing, and a scroll to the field would shove the whole notch up */
    if (open) setTimeout(function () { caretAt(rIn.value.length); }, 30); else { replyFor = ''; rIn.value = ''; rIn.blur(); }
    if (!quiet) post({ type: 'replyMenu', open: open });
  }
  rIn.addEventListener('input', function () { if (asking.typing) return; if (replyFor) post({ type: 'draft', id: replyFor, text: rIn.value }); });
  /* Files dropped on the card or pasted from Finder are attachments: a chip each (the file's name, its path on hover, an x
     to take it off; Backspace in an empty field takes the last), opening the reply if need be. Sent, their paths follow
     your words, quoted when they have spaces. A reply's files are kept with its session, as its words are. */
  var repFiles = {}, repOn = false;
  function addPaths(list) {
    if (!list || !list.length) return;
    if (lastSt === 'ns') return nwPaths(list);
    if (lastSt === 'set') return fbPaths(list);
    if (lastSt !== 'open') return;
    if (dropping) dropped();
    /* an answer in your own words is words: a file goes in as its path */
    if (asking.typing) { rIn.value = withFiles(rIn.value.trim(), addFiles([], list)); setTimeout(function () { caretAt(rIn.value.length); }, 40); return; }
    if (fRep.style.display !== 'flex') { if (!q('.o-acts [data-act=reply]')) return; replyMenu(true); }
    repFiles[replyFor] = addFiles(repFiles[replyFor] || [], list); repAtt();
    setTimeout(function () { caretAt(rIn.value.length); }, 40);
  }
  function addFiles(had, list) { return had.concat(list.filter(function (x, i) { return had.indexOf(x) < 0 && list.indexOf(x) === i; })); }
  function withFiles(t, files) {
    var paths = (files || []).map(function (f) { return /[\s"']/.test(f) ? '"' + f.replace(/"/g, '\\"') + '"' : f; }).join(' ');
    return paths ? (t ? t + ' ' : '') + paths : t;
  }
  /* One line of chips, however many: more than fit scroll sideways, the edges fading where there is more, and the one
     just added scrolled into view. Each wears the file's own icon as Finder shows it, a picture a thumbnail of itself
     (Swift sends them a moment after the files, fileIcons); the design page has stand-ins by kind (file.png, ...). */
  var fileIcons = {};
  function fileIcon(f) {
    var ext = /\/$/.test(f) || !/\.[^./]+$/.test(f) ? 'folder' : f.split('.').pop().toLowerCase();
    return fileIcons[f] || icons['file.' + ext];
  }
  function attChips(box, files, drop) {
    var had = box.children.length;
    box.innerHTML = files.map(function (f, i) {
      var name = f.replace(/\/+$/, '').split('/').pop() || f, ic = fileIcon(f);
      return '<span class="att inline-flex h-[22px] max-w-[168px] flex-none items-center gap-1 rounded-md bg-white/[0.09] pl-1 pr-0.5 text-[12px] leading-4 text-foreground/90" title="' + esc(f) + '">' +
        (ic ? '<img class="size-4 flex-none rounded-[3px] object-cover" src="' + ic + '" alt="">' : svg('doc', 'size-3 flex-none text-muted-foreground')) +
        '<span dir="auto" class="min-w-0 truncate">' + esc(name) + '</span>' +
        '<button class="att-x grid size-4 flex-none cursor-pointer place-items-center rounded text-muted-foreground transition-colors hover:bg-white/[0.12] hover:text-foreground" data-i="' + i + '" aria-label="Remove ' + esc(name) + '">' + svg('x', 'size-2.5') + '</button></span>';
    }).join('');
    box.style.display = files.length ? 'flex' : 'none';
    box.querySelectorAll('.att-x').forEach(function (b) { b.onmousedown = function (e) { e.preventDefault(); }; b.onclick = function (e) { e.stopPropagation(); drop(+b.dataset.i); }; });
    if (files.length > had) box.scrollLeft = box.scrollWidth;
    attEdges(box); box.onscroll = function () { attEdges(box); };
  }
  function attEdges(box) {
    var l = box.scrollLeft > 1, r = box.scrollLeft + box.clientWidth < box.scrollWidth - 1;
    box.style.webkitMaskImage = box.style.maskImage = l || r ? 'linear-gradient(90deg, ' + (l ? 'transparent, #000 20px' : '#000, #000') + ', ' + (r ? '#000 calc(100% - 20px), transparent' : '#000') + ')' : '';
  }
  function repAtt() {
    var files = (replyFor && repFiles[replyFor]) || [];
    attChips(q('.r-att'), repOn ? files : [], function (i) { files.splice(i, 1); repAtt(); rIn.focus({ preventScroll: true }); });
    if (snap && lastSt === 'open') layout('open', snap);
  }
  /* Files dragged over the card (n of them; 0 when the drag goes away), the pointer at x, y in the page. The reply opens for them if
     it was closed, and closes again if they go elsewhere; its field lights up and says what a drop does, and more so with
     the file right on it; the character looks on wide-eyed, its eyes on the file as it moves. Dropped, it squints happily
     and hops. */
  var dropping = 0, dropOpened = false;
  function dragOver(n, x, y) {
    if (lastSt === 'ns') return nwDragOver(n, x, y);
    if (lastSt === 'set') return fbDragOver(n, x, y);
    if (lastSt !== 'open') return;
    if (n && !dropping) {
      if (fRep.style.display !== 'flex') { if (!q('.o-acts [data-act=reply]')) return; replyMenu(true, true); dropOpened = true; }
      cr.dataset.m = 'alert'; lookAt(rIn, 60);
    }
    var was = dropping; dropping = n;
    var r = rIn.getBoundingClientRect();
    var on = !!n && x != null && x >= r.left - 8 && x <= r.right + 8 && y >= r.top - 8 && y <= r.bottom + 8;
    rIn.classList.toggle('drop', !!n); rIn.classList.toggle('on', on);
    rIn.placeholder = !n ? replyHint() : (on ? 'Release to attach ' : 'Drop to attach ') + (n > 1 ? 'them' : 'it');
    if (!n && was) {
      if (dropOpened) { dropOpened = false; replyMenu(false, true); }
      if (snap) layout('open', snap);   /* its face goes back to the session's */
    }
  }
  function dropped() {
    dropping = 0; rIn.classList.remove('drop', 'on'); rIn.placeholder = replyHint();
    /* the reply it opened for the drag is yours now: Swift hears it is open, so keys go to it */
    if (dropOpened) { dropOpened = false; post({ type: 'replyMenu', open: true }); }
    var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop');
    setTimeout(function () { if (!dropping && snap && lastSt === 'open') layout('open', snap); }, 1100);
  }
  function replyHint() { var p = snap && snap.projects[snap.selected]; return p ? (asking.typing ? 'Your answer for ' : 'Reply to ') + agentShort(p.app || p.status.app) + '\u2026' : ''; }
  /* focus the field with the caret at i, the words scrolled so it shows */
  function caretAt(i) {
    rIn.focus({ preventScroll: true }); rIn.setSelectionRange(i, i);
    if (i >= rIn.value.length) rIn.scrollLeft = rIn.scrollWidth;
  }
  /* replying: the card shows the agent's own last message instead of the summary, and grows or shrinks to fit */
  var saidKey = '', saidLater = false;   /* a redraw held for a selection, made when it ends (selCheck) */
  function showSaid(open) {
    /* a first message with nothing said back yet opens it too, with only your words */
    var pane = q('.p-open'), p = snap && snap.projects[snap.selected], on = !!(open && p && (p.said || p.asked));
    var key = on ? [p.id, p.said, p.asked, !!p.askedLast].join('\u0001') : '', was = pane.dataset.rep === '1';
    if (was === on && key === saidKey) return;
    var box = q('.o-said-in'), sel = window.getSelection();
    /* it answered while the reply was open: drawn again in the new order, but never under words you are selecting */
    if (was && on && sel && !sel.isCollapsed && (box.contains(sel.anchorNode) || box.contains(sel.focusNode))) { saidLater = true; return; }
    /* drawn again in place: where your message was, and the words that were already there */
    var redraw = was && on && !STILL, mine = redraw && box.querySelector('.o-you'), from = mine && mine.getBoundingClientRect().top, before = redraw && box.textContent;
    saidKey = key; saidLater = false;
    pane.dataset.rep = on ? '1' : '';
    /* a long one opens at its end, where the question usually is, with a soft edge saying there is more above */
    if (on) { var you = p.asked ? '<div dir="auto" class="o-you' + (p.askedLast ? ' last' : '') + '">' + esc(p.asked) + '</div>' : '', said = p.said ? mdBlock(p.said) : '';
      /* sent and not answered yet: yours is the newest, so it goes below the agent's and is what the card opens on */
      box.innerHTML = p.askedLast ? said + you : you + said; box.parentNode.classList.toggle('ov', box.scrollHeight > box.clientHeight + 1); fitLastTable(box); box.scrollTop = box.scrollHeight; box.querySelectorAll('.md-tbl').forEach(tblEdge);
      /* the answer landed: your message glides to its new place and the answer comes in softly, as words do on the card */
      if (redraw && p.said && box.textContent !== before) [].forEach.call(box.children, function (el) {
        if (el.classList.contains('o-you')) { var dy = from != null ? from - el.getBoundingClientRect().top : 0; if (dy) el.animate([{ transform: 'translateY(' + dy + 'px)' }, { transform: 'none' }], { duration: 320, easing: 'cubic-bezier(.2,.9,.3,1)' }); }
        else el.animate([{ opacity: 0, filter: 'blur(2px)', transform: 'translateY(14px)' }, { opacity: 1, filter: 'blur(0)', transform: 'none' }], { duration: 340, delay: 60, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
      }); }
    if (snap && lastSt === 'open') layout('open', snap);
    if (on && !was && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches))
      q('.o-said').animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 260, easing: 'cubic-bezier(.2,.9,.3,1)' });
  }
  /* The message opens at its end, where the question is. A table just before it gives up rows of its window (down to
     three) so its header shows too; the rows it gave up are a scroll away in the table. */
  function fitLastTable(box) {
    var ws = box.querySelectorAll('.md-tbl'), w = ws[ws.length - 1]; if (!w) return;
    var b = box.getBoundingClientRect(), after = box.scrollHeight - (w.getBoundingClientRect().bottom - b.top + box.scrollTop);
    var room = Math.floor(box.clientHeight - after - 16);   /* clear of the message's soft top edge */
    if (room >= 86 && room < w.clientHeight) w.style.maxHeight = room + 'px';
  }
  /* a table bigger than its window fades at the sides it goes on (left, right, below; the header stays put above), and
     the fades follow as you scroll it */
  function tblEdge(w) {
    var set = function () {
      var x = w.scrollLeft, mx = w.scrollWidth - w.clientWidth, my = w.scrollHeight - w.clientHeight;
      var f = [x > 1 ? 'l' : '', x < mx - 1 ? 'r' : '', w.scrollTop < my - 1 ? 'b' : ''].join(' ').trim();
      if (f) w.parentNode.dataset.f = f; else delete w.parentNode.dataset.f;
    };
    set(); w.onscroll = set;
  }
  /* Preview: the agent's whole last message on the card, as tall as the panel lets it be, with no field under it. Space closes
     it again, as Quick Look does; the arrows and Page Up and Down scroll, Command+C copies it (or what you selected), R turns
     it into a reply and Esc goes back. */
  var previewOn = false, previewFrom = '';
  function canPreview(p) { return !!(p && p.said && !p.ask && !asking.typing); }
  /* `from` 'list': opened by Space in the list, so going back goes back there, on the same row */
  function previewMenu(open, quiet, from) {
    var pane = q('.p-open'), p = snap && snap.projects[snap.selected];
    if (open && (previewOn || repOn || !canPreview(p))) return;
    if (!open && !previewOn) return;
    previewOn = !!open; pane.dataset.prev = previewOn ? '1' : '';
    var back = !previewOn && !quiet && previewFrom === 'list'; previewFrom = previewOn ? from || '' : '';
    if (previewOn) {
      setWords(q('.o-pacts'), Act('ghost', 'Copy', '\u2318C', 'copy') + Act('ghost', 'Reply', 'R', 'reply') + Act('default', goLabel(p), ENTER, 'go'));
      footer(fPrev);
      if (pane.dataset.rep === '1') layout('open', snap); else showSaid(true);
      var sb = q('.o-said-in'); sb.scrollTop = sb.scrollHeight;   /* the end, as a chat opens: the latest words, Command+Up goes to the start */
    } else { footer(fMain); showSaid(false); }
    if (!quiet) post({ type: 'previewMenu', open: previewOn });
    if (back) post({ type: 'switcher' });
  }
  function previewCopy() {
    var p = snap && snap.projects[snap.selected], box = q('.o-said-in'), sel = window.getSelection();
    var picked = sel && !sel.isCollapsed && box.contains(sel.anchorNode) ? sel.toString() : '';
    var t = picked || (p && p.said) || ''; if (!t) return;
    post({ type: 'copy', text: t });
    /* it says so where you are: a selection brightens as Command+C does elsewhere, and the button reads Copied for a beat */
    if (picked) document.dispatchEvent(new Event('copy'));
    var b = q('.o-pacts [data-act=copy] span'), l = b && b.firstChild; if (!l) return;
    l.nodeValue = 'Copied'; clearTimeout(previewCopy.t); previewCopy.t = setTimeout(function () { l.nodeValue = 'Copy'; }, 1400);
    /* and the character smiles for a beat, with a small nudge: fine, not a show */
    var was = cr.dataset.m; if (was === 'awake' || was === 'happy') {
      cr.dataset.m = 'happy'; clearTimeout(previewCopy.m); previewCopy.m = setTimeout(function () { if (cr.dataset.m === 'happy') cr.dataset.m = 'awake'; }, 1600);
    }
  }
  function previewKey(k) {
    if (!previewOn) return;
    var box = q('.o-said-in'), page = Math.max(57, box.clientHeight - 38);
    if (k === 'close') previewMenu(false);
    else if (k === 'reply') replyMenu(true);
    else if (k === 'copy') previewCopy();
    else if (k === 'end' || k === 'top') saidScroll(k === 'end' ? 1e6 : -1e6, box);   /* the message's ends, past any table */
    else saidScroll({ pageDown: page, pageUp: -page, down: 57, up: -57 }[k] || 0);
  }
  /* the summary opens Preview (as does the footer's Preview); dragging over the words to select them does not */
  q('.p-open').addEventListener('click', function (e) {
    if (!e.target.closest('.o-h, .o-c')) return;
    var sel = window.getSelection(); if (sel && !sel.isCollapsed) return;
    previewMenu(true);
  });
  q('.x-pvback').onclick = function () { previewMenu(false); };
  function sendReply() {
    if (asking.typing) { otherSend(); return; }
    var files = repFiles[replyFor] || [], t = withFiles(rIn.value.trim(), files); if (!t) return;
    var p = snap && snap.projects[snap.selected];
    /* a terminal session takes it right here: the card clears and the words go off into the notch */
    if (p && p.via && sendFly(t)) { delete repFiles[replyFor]; post({ type: 'reply', text: t, close: SEND_CLOSE }); return; }
    /* without Accessibility Perch asks for it first; your words stay here and go out once it is on */
    if (snap.canSend === false && !(p && p.via)) { if (!snap.allowing) post({ type: 'reply', text: t }); rIn.focus({ preventScroll: true }); return; }
    delete repFiles[replyFor]; replyMenu(false, true); post({ type: 'reply', text: t });
  }
  /* Sent to a terminal. Everything above the field clears first, nearest first, so only your words are moving; then they
     shoot up into the notch as a bubble, stretching as they go, and the notch swallows them with a green ripple. The
     character watches and hops; the glow turns green. The card closes 0.3 s after you send (Swift waits for it). */
  var SEND_CLOSE = .3;
  function sendFly(text) {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return false;
    var pane = q('.p-open'), pr = pane.getBoundingClientRect(), fr = rIn.getBoundingClientRect();
    var foot = fRep.parentNode, rows = [].slice.call(foot.parentNode.children).filter(function (el) { return el !== foot && el.offsetHeight; }).reverse();
    var gone = rows.map(function (el, i) { return el.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateY(-6px)', filter: 'blur(3px)' }], { duration: 200, delay: i * 25, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' }); });
    gone.push(fRep.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 160, delay: 40, fill: 'forwards' }));
    rIn.value = '';
    var b = document.createElement('div'); b.className = 'fly'; b.textContent = text; pane.appendChild(b);
    b.style.left = (fr.left - pr.left + 8) + 'px'; b.style.top = (fr.top - pr.top + (fr.height - b.offsetHeight) / 2) + 'px';
    var dx = CARD_W / 2 - (fr.left - pr.left + 8 + b.offsetWidth / 2), dy = 2 - (fr.top - pr.top + fr.height / 2);
    b.animate([{ transform: 'none', opacity: 1 }, { transform: 'translate(' + (dx * .15) + 'px, 6px) scale(1.06, .9)', opacity: 1, offset: .25 },
      { transform: 'translate(' + (dx * .85) + 'px,' + (dy * .8) + 'px) scale(.5, 1.25)', opacity: 1, offset: .8 }, { transform: 'translate(' + dx + 'px,' + dy + 'px) scale(.1, .4)', opacity: 0 }],
      { duration: 360, delay: 40, easing: 'cubic-bezier(.6,0,.4,1)', fill: 'both' });
    var ring = document.createElement('div'); ring.className = 'fly-ring'; ring.style.left = (CARD_W / 2 - 30) + 'px'; ring.style.top = '-28px'; ring.style.animationDelay = '370ms'; pane.appendChild(ring);
    /* the character follows it with its eyes, then hops with a smile when it lands */
    look(2.8, -1.6);
    setTimeout(function () { var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); look(0, 0); }, 400);
    n.dataset.g = 'status'; n.style.setProperty('--glow', '140,207,164'); n.style.setProperty('--glow-hi', '196,234,210');
    /* once the card has closed, put it back as it was for next time */
    setTimeout(function () { gone.forEach(function (x) { x.cancel(); }); b.remove(); ring.remove(); replyMenu(false, true); }, SEND_CLOSE * 1000 + 600);
    return true;
  }
  q('.x-send').onclick = sendReply;
  q('.x-rclose').onclick = function () { replyMenu(false); };
  /* Eased by hand, frame by frame, toward where the keys want it; a held key keeps adding to the same glide. */
  var glide = { el: null, to: 0, at: 0, raf: 0 };
  function saidScroll(d, to) {
    var el = to || saidTarget(q('.o-said-in'), d);
    if (glide.el !== el) { cancelAnimationFrame(glide.raf); glide.raf = 0; glide.el = el; }
    var max = Math.max(0, el.scrollHeight - el.clientHeight);
    if (!glide.raf) glide.at = glide.to = el.scrollTop;   /* start from wherever a trackpad left it */
    glide.to = Math.max(0, Math.min(max, glide.to + d));
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) { el.scrollTop = glide.to; return; }
    if (glide.raf) return;
    var step = function () {
      glide.at += (glide.to - glide.at) * 0.18;
      if (Math.abs(glide.to - glide.at) < 0.4) glide.at = glide.to;
      el.scrollTop = glide.at;
      glide.raf = glide.at === glide.to ? 0 : requestAnimationFrame(step);
    };
    glide.raf = requestAnimationFrame(step);
  }
  /* The keys scroll the message, but a tall table on the way, with rows still to show, takes them until it has shown
     them: going down once the message has reached its top (or can go no further), going up once it has reached its foot. */
  function saidTarget(box, d) {
    var b = box.getBoundingClientRect(), rest = d > 0 ? box.scrollHeight - box.clientHeight - box.scrollTop : box.scrollTop, hit = null;
    [].forEach.call(box.querySelectorAll('.md-tbl'), function (w) {
      var r = w.getBoundingClientRect(), left = d > 0 ? w.scrollHeight - w.clientHeight - w.scrollTop : w.scrollTop;
      if (hit || left < 1 || r.bottom <= b.top || r.top >= b.bottom) return;
      if (rest < 1 || (d > 0 ? r.top <= b.top + 8 : r.bottom >= b.bottom - 8)) hit = w;
    });
    return hit || box;
  }
  rIn.addEventListener('keydown', function (e) {
    var rf = repFiles[replyFor];
    if (e.key === 'Backspace' && rf && rf.length && !rIn.selectionStart && !rIn.selectionEnd) { e.preventDefault(); rf.pop(); repAtt(); }
    else if (e.key === 'Enter') { e.preventDefault(); sendReply(); }
    else if (e.key === 'Escape') { e.preventDefault(); replyMenu(false); }
    /* up and down read the message above, a few lines at a time, while the words you are typing stay put */
    else if ((e.key === 'ArrowUp' || e.key === 'ArrowDown') && q('.p-open').dataset.rep === '1') {
      e.preventDefault(); saidScroll((e.key === 'ArrowDown' ? 1 : -1) * 57);
    }
    e.stopPropagation();
  });
  [['.x-s1', '30m'], ['.x-s2', '2h'], ['.x-s3', 'tomorrow']].forEach(function (b) { q(b[0]).onclick = function () { snoozeMenu(false, true); post({ type: 'snooze', when: b[1] }); }; });
  scene.querySelectorAll('.x-back').forEach(function (b) { b.onclick = function () { post({ type: 'back' }); }; });
  scene.querySelectorAll('.x-list').forEach(function (b) { b.onclick = function () { post({ type: 'switcher' }); }; });
  scene.querySelectorAll('.x-gear').forEach(function (b) { b.onclick = function () { post({ type: 'settings' }); }; });
  q('.x-new').onclick = function () { post({ type: 'newSession' }); };
  scene.querySelectorAll('.x-close').forEach(function (b) { b.onclick = function () { post({ type: 'dismiss' }); }; });

  /* ---- render ---- */
  var last = { phase: null, token: null };
  var snap = null;

  /* Questions, one at a time: a number answers and moves on, Back returns, the last one sends them all together. */
  var asking = { key: '', step: 0, picks: [], own: [], typing: false, p: null };
  function questionCard(p, a) {
    var key = p.id + '|' + a.subject + '|' + a.questions.length;
    if (asking.key !== key) { if (asking.typing) otherMenu(false); asking = { key: key, step: 0, picks: a.questions.map(function () { return []; }), own: a.questions.map(function () { return ''; }), typing: false, p: p }; }
    asking.p = p;
    var n = a.questions.length, qn = a.questions[asking.step], picks = asking.picks[asking.step];
    var own = asking.own[asking.step], ownOn = !!own && picks.indexOf(own) >= 0;
    status({ t: n > 1 ? 'Question ' + (asking.step + 1) + ' of ' + n : 'Asked you something', c: COLORS.attention });
    var h = q('.o-h'); setWords(h, esc(qn.text) + (qn.multi ? ' <span class="text-muted-foreground">Choose any</span>' : '')); h.title = qn.text; h.classList.add('line-clamp-2');
    h.style.marginTop = '6px';   /* the tallest card there is: every point goes to the choices */
    var c = q('.o-c'); setWords(c, ''); c.style.display = 'none';
    /* the choices stand a little apart, so two picked ones read as two; each number sits level with its choice */
    /* the pointer's choice is one highlight that slides from choice to choice, as on the list (chPill); a note is said in full */
    setWords(q('.o-ask'), '<div class="ch-box relative -mx-2 mt-1.5 flex flex-col gap-0.5">' + qn.options.map(function (o, i) {
      var on = picks.indexOf(o) >= 0, rec = /\s*\(recommended\)\s*$/i, label = o.replace(rec, ''), note = qn.notes[i] || '';
      return '<button data-act="pick" data-i="' + i + '" class="relative flex w-full cursor-pointer items-start gap-2.5 rounded-lg px-2 py-[3px] text-left transition-colors ' + (on ? 'bg-white/[0.1]' : '') + '">' +
        Kbd(String(i + 1)) + '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">' + esc(label) + (rec.test(o) ? '<span class="ml-1.5 text-xs text-muted-foreground">Recommended</span>' : '') + '</span>' +
        (note ? '<span class="block text-[11.5px] leading-[14px] text-muted-foreground">' + esc(note) + '</span>' : '') + '</span>' +
        (qn.multi ? '<span class="flex-none self-center ' + (on ? 'text-[#8CCFA4]' : 'text-transparent') + '">' + svg('check', 'size-3') + '</span>' : '') + '</button>';
    }).join('') + otherRow(qn, own, ownOn) + '</div>');
    q('.o-nx').style.display = 'none';
    var last = asking.step === n - 1, ready = qn.multi && picks.length;
    setWords(q('.o-acts'), (asking.step ? Act('ghost', 'Back', '\u2190', 'qback') : Flip()) +
      (ready ? Act('default', last ? 'Send' : 'Next', ENTER, 'qnext') : Act(asking.step ? 'ghost' : 'default', goLabel(p), ENTER, 'go')));
  }
  /* The choice under the pointer: one highlight that slides from choice to choice, put where the pointer is (not from enter
     and leave, which a card hovered open gets played late and out of order, so two choices lit at once or one stayed lit). */
  var chPill = document.createElement('div'); chPill.className = 'sel-pill ch-pill'; chPill.setAttribute('aria-hidden', 'true');
  function markChoice() {
    var box = q('.o-ask .ch-box');
    if (!box || !box.offsetParent) { chPill.classList.remove('on'); chPill.at = null; return; }
    if (chPill.parentNode !== box) { box.insertBefore(chPill, box.firstChild); chPill.at = null; chPill.classList.remove('on'); }
    var e = ptrAt[0] >= 0 ? document.elementFromPoint(ptrAt[0], ptrAt[1]) : null, b = e && e.closest && e.closest('.ch-box > button');
    if (!b || b.parentNode !== box) { chPill.classList.remove('on'); return; }
    var at = b.offsetTop + ':' + b.offsetHeight; if (at === chPill.at && chPill.classList.contains('on')) return;
    var first = !chPill.classList.contains('on'); chPill.at = at;
    if (first) chPill.classList.add('snap');
    chPill.style.transform = 'translateY(' + b.offsetTop + 'px)'; chPill.style.height = b.offsetHeight + 'px';
    if (first) { void chPill.offsetWidth; chPill.classList.remove('snap'); }
    chPill.classList.add('on');
  }
  /* Other: the choice after the agent's own, for an answer in your own words. It opens the card's reply field with the
     question still above it and the agent's choices dimmed; Return answers with what you typed (on a question that takes
     several, it is one more pick). What you typed stays on the row, so Esc and Other again bring it back. */
  function otherRow(qn, own, ownOn) {
    if (qn.options.length >= 9) return '';   /* the number keys end at 9 */
    return '<button data-act="other" data-i="' + qn.options.length + '" class="o-other relative flex w-full cursor-pointer items-start gap-2.5 rounded-lg px-2 py-[3px] text-left transition-colors ' + (ownOn || asking.typing ? 'bg-white/[0.1]' : '') + '">' +
      Kbd(String(qn.options.length + 1)) + '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">Other</span>' +
      '<span dir="auto" class="block truncate text-[11.5px] leading-[14px] ' + (own ? 'text-foreground/75">\u201c' + esc(own) + '\u201d' : 'text-muted-foreground">Answer in your own words') + '</span></span>' +
      (qn.multi ? '<span class="flex-none self-center ' + (ownOn ? 'text-[#8CCFA4]' : 'text-transparent') + '">' + svg('check', 'size-3') + '</span>' : '') + '</button>';
  }
  function otherMenu(open, quiet) {
    var a = asking.p && asking.p.ask, qn = a && a.questions && a.questions[asking.step];
    if (open && !qn) return;
    if (asking.typing === open) { if (open) caretAt(rIn.value.length); return; }
    if (!open) keepOwn();
    asking.typing = open;
    q('.p-open').dataset.oth = open ? '1' : '';
    footer(open ? fRep : fMain);
    if (open) {
      var last = asking.step === a.questions.length - 1;
      rIn.value = asking.own[asking.step] || '';
      q('.x-send-l').textContent = qn.multi ? 'Add' : last ? 'Send' : 'Next';
      setTimeout(function () { caretAt(rIn.value.length); }, 30);
    } else { rIn.value = ''; rIn.blur(); q('.x-send-l').textContent = 'Send'; }
    rIn.placeholder = replyHint();
    if (!quiet) post({ type: 'replyMenu', open: open });
    /* the Other row lights (or goes back), the agent's choices dim: only while the card still shows this question */
    var p = snap && snap.projects[snap.selected];
    if (lastSt === 'open' && p && p.id === asking.p.id) { cardMove = 'live'; questionCard(asking.p, a); cardMove = ''; layout(lastSt, snap); }
  }
  /* the words in the field stay this question's own answer when it closes; already picked, the pick changes with them
     (emptied, it is taken back) */
  function keepOwn() {
    var t = rIn.value.trim(), was = asking.own[asking.step], picks = asking.picks[asking.step] || [], at = picks.indexOf(was);
    if (t === was) return;
    if (at >= 0) { if (t) picks[at] = t; else picks.splice(at, 1); }
    asking.own[asking.step] = t;
  }
  /* Return in the field: the words answer this question (a question that takes several gets them as one more pick) */
  function otherSend() {
    var t = rIn.value.trim(), a = asking.p && asking.p.ask; if (!a) return;
    var qn = a.questions[asking.step], picks = asking.picks[asking.step];
    if (!t && !qn.multi) return;
    otherMenu(false);
    if (!qn.multi) { asking.picks[asking.step] = [t]; askKey('forward'); }
    else if (t && picks.indexOf(t) < 0) { picks.push(t); askKey('redraw'); drawCheck(qn.options.length, true); }
  }
  /* A question Perch cannot answer (no hooks, or read from the transcript): its first question and its choices, to read.
     Nothing on it is pressable: a message sent while a question is open dismisses it, so the only way on is the app itself. */
  function readQuestion(p, a) {
    var n = a.questions.length, qn = a.questions[0];
    status({ t: n > 1 ? 'Question 1 of ' + n : 'Asked you something', c: COLORS.attention });
    var h = q('.o-h'); setWords(h, esc(qn.text) + (qn.multi ? ' <span class="text-muted-foreground">Choose any</span>' : '')); h.title = qn.text; h.classList.add('line-clamp-2');
    h.style.marginTop = '6px';
    var c = q('.o-c'); setWords(c, ''); c.style.display = 'none';
    /* four choices with their notes and the reason would not fit the panel: past three, the labels alone */
    var terse = qn.options.length > 3;
    setWords(q('.o-ask'), '<div class="-mx-2 mt-1.5 flex flex-col">' + qn.options.map(function (o, i) {
      var rec = /\s*\(recommended\)\s*$/i, label = o.replace(rec, ''), note = terse ? '' : qn.notes[i] || '';
      return '<div class="flex w-full items-start gap-2.5 px-2 py-[3px]"><span class="grid size-4 flex-none place-items-center"><span class="size-1.5 rounded-full bg-white/25"></span></span>' +
        '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">' + esc(label) + (rec.test(o) ? '<span class="ml-1.5 text-xs text-muted-foreground">Recommended</span>' : '') + '</span>' +
        (note ? '<span class="block truncate text-[11.5px] leading-[14px] text-muted-foreground">' + esc(note) + '</span>' : '') + '</span></div>';
    }).join('') + '</div>' + (a.why ? '<div class="mt-3 text-[11px] leading-[14px] text-muted-foreground/70">' + esc(a.why).replace('Settings', '<span data-act="live" role="link" class="cursor-pointer underline underline-offset-2 hover:text-foreground">Settings</span>') + '</div>' : ''));
    q('.o-nx').style.display = 'none';
    setWords(q('.o-acts'), Flip() + Act('default', goLabel(p), ENTER, 'go'));
  }
  function drawCheck(i, on) {
    var b = q('.o-ask [data-i="' + i + '"]'), mark = b && b.lastElementChild, path = mark && mark.querySelector('path');
    if (STILL || !path || !path.getTotalLength) return;
    var len = String(Math.ceil(path.getTotalLength()) + 1);
    if (on) path.animate([{ strokeDasharray: len, strokeDashoffset: len }, { strokeDasharray: len, strokeDashoffset: '0' }], { duration: 350, easing: SMOOTH });
    else {
      mark.animate([{ color: COLORS.done }, { color: COLORS.done }], { duration: 150 });   /* already drawn clear: keep it green while it goes */
      path.animate([{ strokeDasharray: len, strokeDashoffset: '0' }, { strokeDasharray: len, strokeDashoffset: len }], { duration: 150, easing: SMOOTH });
    }
  }
  function askKey(k) {
    var a = asking.p && asking.p.ask; if (!a || !a.questions || !a.questions.length) return;
    var n = a.questions.length, qn = a.questions[asking.step], picks = asking.picks[asking.step];
    /* the next (or the last) question cross-blurs into place and its count changes only its number; a pick on a question
       with several answers draws its check in (transitions.dev checkbox check), or wipes it away */
    var redraw = function (how, pick, on) {
      var pane = q('.p-open'), seen = how === 'step' && !STILL ? crossSeen(pane, ['.o-h', '.o-ask']) : [];
      cardMove = 'live'; questionCard(asking.p, a); cardMove = '';
      if (snap) layout(lastSt, snap);
      markChoice();
      crossIn(pane, seen);
      if (how === 'pick' && pick != null) drawCheck(pick, on);
    };
    var forward = function () {
      if (asking.step < n - 1) { asking.step++; redraw('step'); return; }
      var answers = {}; a.questions.forEach(function (x, i) { answers[x.text] = asking.picks[i].join(', '); });
      post({ type: 'answer', answers: answers });
    };
    if (k === 'redraw') { redraw('pick'); return; }
    if (k === 'forward') { forward(); return; }
    if (/^[1-9]$/.test(k) && +k === qn.options.length + 1) { otherMenu(true); return; }
    if (/^[1-9]$/.test(k)) {
      var o = qn.options[+k - 1]; if (!o) return;
      if (qn.multi) { var at = picks.indexOf(o); if (at >= 0) picks.splice(at, 1); else picks.push(o); redraw('pick', +k - 1, at < 0); }
      else { asking.picks[asking.step] = [o]; forward(); }
    } else if (k === 'back' || k === 'left') {
      /* Left on the first question goes to All sessions, as the footer says; Backspace there stays put */
      if (asking.step) { asking.step--; redraw('step'); } else if (k === 'left') post({ type: 'switcher' });
    }
    else if (k === 'next') { if (picks.length) forward(); }
    else if (k === 'enter') { if (qn.multi && picks.length) forward(); else post({ type: 'confirm' }); }
  }

  /* The card's edge springs to a new height (input.css, .n), but the words inside reflow at once, so what sits below
     them would jump. Each block glides from where it was on the same spring instead. On another session's card, each piece
     that changed cross-blurs: the old words fade out where they were while the new ones fade in (crossIn), and a new app's
     icon shrinks away as the other grows in. The buttons stay put. */
  var cardId = null, iconKey = '';
  var CARD_WORDS = ['.o-app', '.o-name', '.o-sub', '.o-st', '.o-h', '.o-c', '.o-ask', '.o-x'];
  function settleCard(change, fresh) {
    var pane = q('.p-open'), els = [].slice.call(pane.querySelectorAll('.rv')), was = els.map(function (el) { return el.offsetParent ? el.getBoundingClientRect().top : null; });
    var seen = fresh && !STILL ? crossSeen(pane, CARD_WORDS) : [];
    change();
    if (STILL) return;
    crossIn(pane, seen, q('.o-app'));
    els.forEach(function (el, i) {
      if (!el.offsetParent) return;
      var dy = was[i] == null ? 0 : was[i] - el.getBoundingClientRect().top;
      if (Math.abs(dy) > .5) el.animate([{ transform: 'translateY(' + dy + 'px)' }, { transform: 'none' }], { duration: 600, delay: 50, easing: 'cubic-bezier(.3,1.5,.45,1)', fill: 'backwards' });
    });
  }

  /* the card's status (a phrase: words, colour, spinner); its spinner is drawn again only when it changes, so it keeps turning.
     On a card that stays open (cardMove 'live') a change moves: the spinner shrinks away or grows in, the words swap, and
     "Question 1 of 3" to "2 of 3" changes only its number. Opening, or another session's card, puts it in at once. */
  var cardMove = '';
  function status(ph, title) {
    var st = q('.o-st');
    if (!st._built) { st.innerHTML = '<span class="st-ic t-ic"></span><span class="st-t t-swap"></span>'; st._built = true; }
    var ic = st.firstChild, w = st.lastChild, still = cardMove !== 'live';
    if (still) ic.style.transition = 'none';
    ic.classList.toggle('has', !!ph.spin);
    if (still) { void ic.offsetWidth; ic.style.transition = ''; }
    iconSwap(ic, ph.spin ? Spinner('size-3', glow(COLORS.running)) : '', still);
    w.classList.toggle('text-muted-foreground', !ph.c);
    var count = /^Question \d+ of \d+$/;
    if (!still && count.test(w._t || '') && count.test(ph.t) && w._c === ph.c) morphText(w, ph.t);
    else swapText(w, ph.t, ph.c, still);
    st.title = title || '';
  }
  /* Words are put in only when they change: the snapshot comes again every refresh, and new nodes would drop a selection
     you are making in them. Written by anything else meanwhile (a question's card), they are put in again. */
  function setWords(el, html) {
    if (el._put === html && unHv(el.innerHTML) === el._was) return;
    el.innerHTML = html; el._put = html; el._was = unHv(el.innerHTML);
  }
  /* The pointer's mark (hoverAt) is not a change: a button under the pointer is the last thing to draw again. */
  function unHv(h) { return h.replace(/ class="([^"]*)"/g, function (m, c) { c = c.split(/\s+/).filter(function (x) { return x && x !== 'hv'; }).join(' '); return c ? ' class="' + c + '"' : ''; }); }
  function fill(p) {
    var a = p.ask, ph = phrase(p), h = q('.o-h'), c = q('.o-c'), box = q('.o-ask');
    /* drawn again only when it changes: a new image blinks while it decodes */
    var ik = p.app + '|' + (p.via || p.opens || '') + '|' + !!icons[p.via || p.opens || p.app];
    if (ik !== iconKey) { q('.o-app').innerHTML = AppOf(p, 'size-[34px]'); iconKey = ik; }
    /* a chat started without a project is named by its title alone */
    q('.o-name').textContent = p.topic || p.name; q('.o-name').title = p.topic || p.name;
    /* a question card says its own status (Question 1 of 3); setting the phrase first would swap the words back and forth on every refresh */
    var asks = a && a.kind === 'question' && a.questions && a.questions.length && (a.answerable || a.questions[0].options.length);
    if (!asks) status(ph, p.status.text);
    h.classList.remove('line-clamp-2'); h.title = ''; h.style.display = ''; h.style.marginTop = '';
    /* the grey line: the project, then (on a plain card) what you were doing */
    /* no project name (a worktree of nothing, a Claude task without a folder): the grey line starts with what it was doing */
    var sub = q('.o-sub'), proj = p.topic && p.name ? '<span class="text-foreground/70">' + esc(p.name) + '</span>' : '';
    setWords(sub, proj); sub.title = p.topic ? p.name : ''; sub.style.display = proj ? '' : 'none';
    var pre = q('.o-pr'), pl = prsOf(p), pc = pl ? PRMark(pl, 'size-4') : ''; if (pre.dataset.h !== pc) { pre.innerHTML = pc; pre.dataset.h = pc; } pre._prs = pl; prHover(pre); prStale(pre);
    /* an open reply follows the snapshot (its answer arriving, your message moving up), a question card or not */
    if (repOn) showSaid(true);
    /* Preview too, read from where you were rather than from its end */
    else if (previewOn) { var top = q('.o-said-in').scrollTop; showSaid(true); q('.o-said-in').scrollTop = top; }
    if (a && a.kind === 'question' && a.answerable && a.questions && a.questions.length) { questionCard(p, a); return; }
    if (a && a.kind === 'question' && a.questions && a.questions.length && a.questions[0].options.length) { readQuestion(p, a); return; }
    if (a) {
      /* what the agent is asking, and the means to answer it right here */
      setWords(h, esc(a.kind === 'question' ? a.subject : a.title));
      setWords(c, a.kind === 'plan' ? esc(a.subject) : '');
      setWords(box, a.kind === 'permission' && a.subject
        ? '<div dir="auto" class="mt-2 line-clamp-2 break-all rounded-md bg-white/[0.07] px-2.5 py-1.5 font-mono text-xs leading-[18px] text-foreground/90">' + esc(a.subject) + '</div>'
        : '');
    } else {
      /* "You were creating a database." becomes the grey line under the title, "Creating a database"; a headline that only
         repeats the title is left out. What happened is the body, in white, two lines at most. */
      var norm = function (t) { return String(t || '').replace(/[.\u2026\s]+$/, '').toLowerCase().slice(0, 60); };
      var was = String(p.headline || '').replace(/^\s*you were\s+/i, '').replace(/[.\s]+$/, '');
      var did = String(p.context || '').replace(/^\s*the assistant\s+/i, '');
      var said = !(norm(p.headline) === norm(p.topic || p.name)) && was;
      if (said) { setWords(sub, proj + (proj ? ' \u00b7 ' : '') + esc(was.charAt(0).toUpperCase() + was.slice(1))); sub.title = (p.topic ? p.name + ': ' : '') + p.headline; sub.style.display = ''; }
      /* your own words quoted back (You said: / You asked:): the label is grey, so what is quoted reads first */
      var you = /^(You said|You asked):\s*/.exec(did);
      if (did) { setWords(h, you ? '<span class="text-muted-foreground">' + esc(you[1]) + '</span> ' + md(did.slice(you[0].length)) : md(did.charAt(0).toUpperCase() + did.slice(1))); h.classList.add('line-clamp-2'); }
      else setWords(h, said ? '' : md(p.headline));
      setWords(c, ''); setWords(box, '');
    }
    c.style.display = c.innerHTML ? '' : 'none'; h.style.display = h.innerHTML ? '' : 'none';
    /* last line of defence: git housekeeping is never shown as a next step, whatever produced it (old cache included) */
    var nx = a || /^\W*(next:\s*)?(commit|push|merge|rebase|stage)\b(?! notification)|\b(pull request|uncommitted|git (add|commit|push|merge|rebase))\b|\bopen (a|the) pr\b/i.test(p.next || '') ? '' : (p.next || '');
    nx = nx.replace(/^\s*next\s*[:,-]\s*/i, '');   /* the row is already labelled Next (old cache, model output) */
    /* while it works, the same row says what it is doing right now */
    var now = !a && p.status.kind === 'running' && p.now;
    if (now) nx = now;
    q('.o-nl').textContent = 'Next'; q('.o-nl').style.display = now ? 'none' : '';   /* while it works the shimmer says so; no label */
    orbFor(now);
    q('.o-nx').classList.toggle('live', !!now);   /* kept in the reply too */
    q('.o-x').classList.toggle('truncate', !!now);   /* the step changes every few seconds: one line, never a jump in height */
    q('.o-x').classList.toggle('shimmer', !!now);    /* grey with a passing light: it is happening, not yours to do */
    q('.o-x').classList.toggle('line-clamp-2', !now);   /* the step is one line; the next step may take two */
    setWords(q('.o-x'), md(nx) + (now ? '<span class="shine" aria-hidden="true">' + md(nx) + '</span>' : ''));   /* the light's copy of the words, markup and all */
    q('.o-nx').style.display = nx ? '' : 'none';
    setWords(q('.o-acts'), a && a.answerable && a.kind === 'permission' ? Act('ghost', 'Deny', 'D', 'deny') + Act('ghost', goLabel(p), ENTER, 'go') + Act('default', 'Allow', 'A', 'allow')
      : a ? Flip() + Act('default', goLabel(p), ENTER, 'go')
      : Act('ghost', 'Reply', 'R', 'reply') + (canPreview(p) ? Act('ghost', 'Preview', 'space', 'preview') : Flip()) + Act('default', goLabel(p), ENTER, 'go'));
  }
  /* Beside the step a working session is on, a Thinking Orb (orbs.js) in the character's colour, its state from the step:
     searching for a search or a read, background for a helper, compacting, retrying, otherwise working. It is made only while
     the card shows a step and taken down after, so nothing keeps running behind a closed card. */
  var orb = { el: null, state: '' };
  function orbState(t) {
    return /^(Searching|Looking for|Reading)\b/.test(t) ? 'searching' : /^(Helper:|Working with a helper)/.test(t) ? 'background'
      : /compact/i.test(t) ? 'compacting' : /\b(retry|retrying|overloaded|rate limit)/i.test(t) ? 'retrying' : /^(Thinking|Planning)\b/.test(t) ? 'reasoning' : 'working';
  }
  function orbFor(step) {
    var box = q('.o-orb'), st = step && window.ThinkingOrbs ? orbState(step) : '';
    box.classList.toggle('hidden', !st);
    if (st === orb.state) return;
    if (orb.el) { orb.el.destroy(); orb.el = null; }
    orb.state = st;
    if (st) orb.el = window.ThinkingOrbs.mountOrb(box.querySelector('svg'), { state: st, size: 18 });
  }
  /* About five rows show at a time, with their section headers; the rest scroll, with a soft edge where there is more. */
  var sl = q('.s-l'), listSig = '', lastSel = -1;
  /* a row the pointer chose lights at once and waits for Swift to agree (pend); the list never scrolls for it (ptrPick) */
  var pend = -1, pendT = 0, ptrPick = -1;
  function edges() {
    var up = sl.scrollTop > 1, down = sl.scrollTop + sl.clientHeight < sl.scrollHeight - 1;
    sl.style.webkitMaskImage = sl.style.maskImage = up || down ? 'linear-gradient(' + (up ? 'transparent, #000 24px' : '#000, #000') + ', ' + (down ? '#000 calc(100% - 24px), transparent' : '#000') + ')' : '';
    sbar(false);
  }
  sl.addEventListener('scroll', function () { edges(); sbar(true); }, { passive: true });
  /* A thin scrollbar that shows only while you scroll, reach for it near the right edge, or drag it; it fades a moment after. */
  var sb = q('.s-bar'), sbT = 0, sbDrag = null;
  function sbar(wake) {
    var h = sl.clientHeight, all = sl.scrollHeight, track = sb.clientHeight;
    if (all <= h + 1) { sb.classList.remove('on'); return; }
    var th = Math.max(18, track * h / all), y = (track - th) * sl.scrollTop / (all - h);
    sb.firstChild.style.height = th + 'px'; sb.firstChild.style.transform = 'translateY(' + y + 'px)';
    if (!wake) return;
    sb.classList.add('on'); clearTimeout(sbT);
    sbT = setTimeout(function () { if (!sbDrag && !sb.matches(':hover')) sb.classList.remove('on'); }, 900);
  }
  sl.parentNode.addEventListener('mousemove', function (e) {
    var r = sl.getBoundingClientRect(); if (e.clientX > r.right - 16) sbar(true);
  });
  sb.addEventListener('mouseleave', function () { if (!sbDrag) sbar(true); });
  /* drag the thumb, or press the track to jump there */
  sb.addEventListener('pointerdown', function (e) {
    var t = sb.firstChild.getBoundingClientRect(), track = sb.getBoundingClientRect();
    if (e.target !== sb.firstChild) sl.scrollTop = (e.clientY - track.top - t.height / 2) / (track.height - t.height) * (sl.scrollHeight - sl.clientHeight);
    sbDrag = { y: e.clientY, top: sl.scrollTop }; sb.classList.add('drag'); sb.setPointerCapture(e.pointerId); e.preventDefault();
  });
  sb.addEventListener('pointermove', function (e) {
    if (!sbDrag) return;
    var th = sb.firstChild.offsetHeight, room = sb.clientHeight - th;
    sl.scrollTop = sbDrag.top + (e.clientY - sbDrag.y) / Math.max(1, room) * (sl.scrollHeight - sl.clientHeight);
  });
  function sbUp() { if (!sbDrag) return; sbDrag = null; sb.classList.remove('drag'); sbar(true); }
  sb.addEventListener('pointerup', sbUp); sb.addEventListener('pointercancel', sbUp);
  /* A session started from the list is a row from the moment you press Return: your words as its title, and where the
     project goes, how it is going (`pending`): Starting with a spinner, Started with the paper plane once Perch sees the
     session, Didn't start in orange if it never comes. It cannot be opened until it is a real session. */
  var listPend = {};
  function pendWord(k, app) { return { confirm: 'Confirm in ' + agentShort(app), starting: 'Starting\u2026', started: 'Started' }[k] || 'Didn\u2019t start'; }
  function pendHtml(k, app) {
    var w = '<span class="pw-t">' + esc(pendWord(k, app)) + '</span>', small = function (m) { return m.replace('size-4', 'size-[13px]'); };
    if (k === 'confirm') return '<span class="pw flex flex-none items-center gap-1.5 text-xs" style="color:' + COLORS.attention + '">' + w + small(Ring('need')) + '</span>';
    /* starting, the shimmering title already says it is on its way: the word alone, no spinner */
    return k === 'starting' ? '<span class="pw flex flex-none items-center gap-1.5 text-xs text-muted-foreground">' + w + '</span>'
      : k === 'started' ? '<span class="pw flex flex-none items-center gap-1.5 text-xs text-foreground/90">' + w + SentMark().replace('size-[15px]', 'size-[13px]') + '</span>'
      : '<span class="pw flex flex-none items-center gap-1.5 text-xs" style="color:' + COLORS.attention + '">' + w + small(Ring('need')) + '</span>';
  }
  /* the word changes in place, keeping the letters it shares (Starting to Started, transitions.dev text morph), and the colour
     follows; its mark arrives as the notch line's do (renderSent): the plane flies in from below left, a failure's ring pops */
  function pendIn(el, k, from, app) {
    if (STILL || !el || !el.animate) return;
    var t = el.querySelector('.pw-t');
    if (t && from) { t.textContent = pendWord(from, app); t._t = null; morphText(t, pendWord(k, app)); }
    if (from) el.animate([{ color: from === 'starting' ? 'rgb(161, 161, 170)' : COLORS.attention }, { color: getComputedStyle(el).color }], { duration: 180, easing: SMOOTH });
    var mark = el.querySelector('svg'); if (!mark || k === 'starting') return;
    if (k === 'failed' || k === 'confirm') mark.animate([{ opacity: 0, transform: 'scale(.4)' }, { opacity: 1, transform: 'scale(1.18)', offset: .6 }, { opacity: 1, transform: 'none' }], { duration: 420, delay: 60, easing: 'cubic-bezier(.3,1.4,.5,1)', fill: 'backwards' });
    else mark.animate([{ opacity: 0, transform: 'translate(-7px, 7px) scale(.75)' }, { opacity: 1, transform: 'translate(1px, -1px)', offset: .7 }, { opacity: 1, transform: 'none' }], { duration: 480, delay: 60, easing: 'cubic-bezier(.2,.8,.3,1)', fill: 'backwards' });
  }
  /* a row that goes folds shut through a grid row (transitions.dev accordion): the list is laid out at the start and the end,
     not on every frame as a height would be */
  function foldAway(r) {
    var wrap = document.createElement('div'), inner = document.createElement('div');
    wrap.style.cssText = 'display:grid;grid-template-rows:1fr;transition:grid-template-rows .25s ' + SMOOTH;
    inner.style.cssText = 'min-height:0;overflow:hidden;transition:opacity .25s ' + SMOOTH + ',filter .25s ' + SMOOTH;
    r.parentNode.insertBefore(wrap, r); wrap.appendChild(inner); inner.appendChild(r);
    void wrap.offsetHeight;
    wrap.style.gridTemplateRows = '0fr'; inner.style.opacity = '0'; inner.style.filter = 'blur(2px)';
  }
  /* the list's choice: one highlight slides from row to row (transitions.dev tabs sliding); opening the list puts it in place */
  var listTyped = '', listKeys = [];
  function selPill(row, still) {
    var el = selPill.el;
    if (!row) { el.classList.remove('on'); return; }
    var at = row.offsetTop + ':' + row.offsetHeight; if (at === selPill.at && !still) return;
    var first = !selPill.at || still || !el.classList.contains('on');
    selPill.at = at;
    if (first) el.classList.add('snap');
    el.style.transform = 'translateY(' + row.offsetTop + 'px)'; el.style.height = row.offsetHeight + 'px';
    if (first) { void el.offsetWidth; el.classList.remove('snap'); }
    el.classList.add('on');
  }
  selPill.el = document.createElement('div'); selPill.el.className = 'sel-pill'; selPill.el.setAttribute('aria-hidden', 'true');
  /* the typed words are a field: a caret anywhere in them, or a selection (Swift counts in characters) */
  function typedHtml(typed, caret, anchor) {
    var cs = window.Intl && Intl.Segmenter ? Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(typed), function (g) { return g.segment; }) : Array.from(typed);
    caret = caret == null ? cs.length : Math.min(caret, cs.length); anchor = anchor == null ? caret : Math.min(anchor, cs.length);
    var a = Math.min(caret, anchor), b = Math.max(caret, anchor), part = function (x, y, c) { var t = cs.slice(x, y).join(''); return t ? '<span dir="auto"' + (c ? ' class="s-sel"' : '') + '>' + esc(t) + '</span>' : ''; };
    return part(0, a) + (a === b ? '<i class="s-caret' + (b < cs.length ? ' mid' : '') + '"></i>' : part(a, b, true)) + part(b, cs.length);
  }
  function list(s) {
    var empty = !s.projects.length, typed = s.query || '', rows = s.shown || s.projects.map(function (p, k) { return k; });
    /* opening: from the top, and no pointer pick from the last time it was open (it would keep its row from being scrolled to) */
    var opening = lastSt !== 'switch';
    if (opening) { ptrPick = -1; pend = -1; sl.scrollTop = 0; }
    q('.s-ft').style.display = empty ? 'none' : '';
    /* what you typed replaces the title, with a caret; the right side counts what is left */
    q('.s-h').innerHTML = typed ? typedHtml(typed, s.queryCaret, s.queryAnchor) : 'Jump back in';
    var reading = switchFx === 'watch' && typed !== fxTyped && !!typed; fxTyped = typed;
    if (reading) { var caret = q('.s-h .s-caret'); if (caret) setTimeout(function () { lookAt(caret, 0); }, 0); }
    q('.s-n').textContent = typed ? rows.length + ' of ' + s.projects.length : (s.projects.length > 1 ? 'Type to filter' : '');
    if (!empty && !rows.length) {
      listSig = ''; marquee(null);
      sl.innerHTML = '<div class="flex items-baseline gap-2 px-2.5 pb-3 pt-1 text-[13px] leading-[18px] text-muted-foreground">No sessions match</div>';
      edges(); return;
    }
    if (empty) {
      listSig = ''; marquee(null);
      /* asked for before the first scan finished, or nothing in the last two weeks: say so instead of showing nothing */
      sl.innerHTML = '<div class="flex flex-col gap-0.5 px-2.5 pb-3 pt-1 text-[13px] leading-[18px]">' +
        (s.scanning ? '<span class="flex items-center gap-2 text-muted-foreground">' + Spinner('size-3') + 'Looking for your sessions\u2026</span>'
          : '<span class="text-foreground">Nothing to pick up yet</span><span class="text-muted-foreground">Sessions from your agents in the last two weeks show up here.</span><span class="mt-2 flex items-baseline gap-1.5 text-xs text-muted-foreground">' + Kbd('\u2325\u2318N') + 'Start a new session</span>') + '</div>';
      edges(); return;
    }
    /* Rows are drawn again only when they change, so a row that is reading itself out is not cut short. Swift sends them
       in order, by section (what needs you, today, earlier), and a small header starts each. A row leads with the
       session's title and how long ago; at the right, its mark (rowMark) and its project in grey. */
    var sec = '';
    var html = rows.map(function (k) {
      var p = s.projects[k], first = p.topic || p.name, second = p.topic ? p.name : '', name = sectionOf(p), head = '';
      if (p.pending) first = p.topic;
      var still = p.pending === 'starting' || p.pending === 'confirm';
      if (name !== sec) { head = '<div class="s-sec' + (sec ? '' : ' first') + '" data-k="s:' + esc(name) + '">' + esc(name) + '</div>'; sec = name; }
      return head + '<div class="row flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors" data-i="' + k + '" data-k="' + esc(p.id) + '">' +
        AppOf(p) +
        /* title and project each truncate on their own, so a Hebrew title loses its end, not its start */
        '<span class="flex min-w-0 flex-1 items-center gap-2"><span dir="auto" class="mq nm fade min-w-0 text-left font-medium' + (still ? ' shimmer' : '') + '"><span class="mq-in">' + esc(first) + '</span>' + (still ? '<span class="shine" aria-hidden="true"><span class="mq-in">' + esc(first) + '</span></span>' : '') + '</span>' +
        '<span class="pr flex-none"></span><span class="tm flex-none text-xs tabular-nums text-muted-foreground"></span></span>' +
        (p.pending && p.pending !== 'gone' ? pendHtml(p.pending, p.app) : p.pending ? '' :
        '<span class="flex min-w-0 max-w-[38%] flex-none items-center justify-end gap-2"><span class="rk t-ic grid size-4 flex-none place-items-center"></span>' +
        (second ? '<span dir="auto" class="mq tp fade min-w-0 text-xs text-muted-foreground"><span class="mq-in">' + esc(second) + '</span></span>' : '') + '</span>') + '</div>';
    }).join('');
    /* The list stays open and sorts itself again (a session starts needing you): the rows glide to their new places and a new
       section header fades in, and each row keeps its mark so a change of mark still moves (no transitions.dev recipe: its
       timing for a change of place). Typing, or a row coming or going, just redraws. */
    var live = lastSt === 'switch' && !STILL, keys = rows.map(function (k) { return s.projects[k].id; }), glide = null, marks = {};
    if (html !== listSig) {
      if (live && typed === listTyped && keys.slice().sort().join('\n') === listKeys.slice().sort().join('\n') && keys.join('\n') !== listKeys.join('\n')) {
        glide = {}; sl.querySelectorAll('[data-k]').forEach(function (e) { glide[e.dataset.k] = e.getBoundingClientRect().top; });
      }
      if (live) sl.querySelectorAll('.row .rk').forEach(function (rk) { if (rk.dataset.m != null) marks[rk.closest('.row').dataset.k] = rk.dataset.m; });
      listSig = html; hovered = null; lastSel = -1; marquee(null); sl.innerHTML = html; keyPtr = ptrAt.slice();   /* redrawn rows under a still pointer are not a choice */
      sl.insertBefore(selPill.el, sl.firstChild); selPill.at = null;
      sl.querySelectorAll('.row .rk').forEach(function (rk) { var m = marks[rk.closest('.row').dataset.k]; if (m != null) { iconSwap(rk, m, true); rk.dataset.m = m; } });
      if (glide) sl.querySelectorAll('[data-k]').forEach(function (e) {
        var was = glide[e.dataset.k], dy = was == null ? 0 : was - e.getBoundingClientRect().top;
        if (was == null) e.animate([{ opacity: 0, filter: 'blur(2px)' }, { opacity: 1, filter: 'blur(0)' }], { duration: 250, delay: 120, easing: SMOOTH, fill: 'backwards' });
        else if (Math.abs(dy) > .5) e.animate([{ transform: 'translateY(' + dy + 'px)' }, { transform: 'none' }], { duration: 300, easing: SMOOTH });
      });
      /* a row shows that session's card in the notch; Return (or the card's Open) opens it */
      sl.querySelectorAll('.row').forEach(function (r) {
        var starting = !!s.projects[+r.dataset.i].pending;   /* not `pend`: that is the pointer's pick, above */
        r.onclick = function () { if (!starting) post({ type: 'details', index: +r.dataset.i }); };
        r.ondblclick = function () { if (!starting) post({ type: 'choose', index: +r.dataset.i }); };
        r.onmouseenter = function () {
          hovered = r; marquee(r);
          var i = +r.dataset.i;
          if (!ptrMoved()) return;
          listKb = false; markList();
          if (i === (pend >= 0 ? pend : lastSel)) return;
          pend = ptrPick = i; clearTimeout(pendT); pendT = setTimeout(function () { pend = -1; }, 800);
          sl.querySelectorAll('.row').forEach(function (x) { x.classList.toggle('bg-accent', x === r); });
          selPill(r);
          post({ type: 'pick', index: i });
        };
        r.onmouseleave = function () { hovered = null; marquee(sl.querySelector('.row.bg-accent')); markList(); };
      });
    }
    var sel = null, cs = pend >= 0 && s.selected !== pend ? pend : s.selected;
    if (s.selected === pend) pend = -1;
    if (cs !== ptrPick) ptrPick = -1;
    sl.querySelectorAll('.row').forEach(function (r) {
      var on = +r.dataset.i === cs; r.classList.toggle('bg-accent', on); if (on) sel = r;
      var p = s.projects[+r.dataset.i], tm = r.querySelector('.tm'), rk = r.querySelector('.rk'), t = p.status.kind === 'running' ? '' : String(p.away || '').split(' ')[0], m = rowMark(p);
      if (p.pending) t = '';
      if (tm.textContent !== t) tm.textContent = t;
      var pe = r.querySelector('.pr'); if (pe) { var pl = prsOf(p), pm = pl ? PRMark(pl, 'size-3.5 block') : ''; if (pe.dataset.m !== pm) { pe.innerHTML = pm; pe.dataset.m = pm; } pe._prs = pl; prHover(pe); prStale(pe); }
      /* compared with what it was given, not innerHTML: its copy never reads back the same, and a redrawn spinner restarts its
         turn. On an open list the old mark shrinks away as the new one grows in (transitions.dev icon swap). */
      if (rk && rk.dataset.m !== m) { iconSwap(rk, m, !live || rk.dataset.m == null); rk.dataset.m = m; }
    });
    selPill(sel, !live);
    listTyped = typed; listKeys = keys;
    /* the chosen row stays in view, clear of the edge fades, as the arrows move past the fifth */
    if (sel && cs !== ptrPick) {
      var top = sel.offsetParent === sl ? sel.offsetTop : sel.offsetTop - sl.offsetTop, pad = 20;
      if (top - pad < sl.scrollTop) sl.scrollTop = top - pad;
      else if (top + sel.offsetHeight > sl.scrollTop + sl.clientHeight - pad) sl.scrollTop = top + sel.offsetHeight - sl.clientHeight + pad;
    }
    /* Opened again after the card folded to the notch, WebKit could keep showing the list where it was scrolled last time
       while the page had moved it to the top: the choice sat out of sight and the arrows seemed to do nothing. Once the card
       has grown, the scrolling area is made again (off and on) and told where it is, so what shows is where the page put it. */
    if (opening) {
      [60, 320].forEach(function (ms) { setTimeout(function () {
        if (lastSt !== 'switch') return;
        var at = sl.scrollTop;   /* the page's own idea, the true one */
        sl.style.overflowY = 'hidden'; void sl.offsetHeight; sl.style.overflowY = '';
        sl.scrollTop = at + (at > 0 ? -1 : 1); sl.scrollTop = at;
      }, ms); });
    }
    /* a started row: it slides in once; each new state says itself; once real, its spinner and project fade in; gone, it folds away */
    s.projects.forEach(function (p, k) {
      var was = listPend[p.id], now = p.pending || (was && was !== 'real' ? 'real' : was);
      if (!now || now === was) return;
      listPend[p.id] = now;
      var r = sl.querySelector('.row[data-i="' + k + '"]'); if (!r || STILL || !r.animate) return;
      if (now === 'started' || now === 'failed' || now === 'confirm') pendIn(r.querySelector('.pw'), now, was, p.app);
      if (now === 'real') r.lastChild.animate([{ opacity: 0, filter: 'blur(2px)' }, { opacity: 1, filter: 'none' }], { duration: 320, easing: 'ease-out' });
      if (now === 'gone') foldAway(r);
    });
    edges();
    /* whichever moved last reads out: the arrows' choice, or the row under the pointer */
    /* after layout has set its face */
    if (sel && cs !== lastSel && !reading) { var row = sel; setTimeout(function () { switched(s.projects[cs], row); }, 0); }
    if (cs !== lastSel && lastSel >= 0 && cs !== ptrPick) { listKb = true; markList(); }   /* chosen by the keys: its row shows again */
    if (cs !== lastSel && lastSel >= 0) keyPtr = ptrAt.slice();   /* chosen by the keys (or the pointer: the same spot): a row sliding under a still pointer must not take it back */
    if (cs !== lastSel || !hovered) { lastSel = cs; marquee(sel); }
  }
  /* the design page's sample data has no section from Swift: worked out the same way */
  function sectionOf(p) { return p.section || (p.attention ? 'Needs you' : /^\d+[mh]/.test(p.away || '') ? 'Today' : 'Earlier'); }
  /* a row's status in words when it is news or needs you, and how long ago at the right edge. Working has no age: it sits at the edge itself. */
  /* A row's status: the spinner while it works, else a ring (Ring) when it finished and you have not seen it or when
     it waits on you. Seen and idle sessions get none. */
  function rowMark(p) {
    var k = p.status.kind, a = p.ask;
    /* the glow rides on the spinner itself, on its own layer, so it turns as one piece instead of being redrawn (and wobbling) every frame */
    if (k === 'running' && !a) return Spinner('size-3.5', glow(COLORS.running));
    var g = a ? (RING[a.kind] ? a.kind : 'need') : k === 'attention' ? 'need' : k === 'done' && p.fresh !== false ? 'done' : '';
    if (!g) return '';
    return Ring(g, phrase(p, true).t);
  }
  /* A row cut short reads itself out: after a second on it (hovered or chosen), its text glides left to the end, rests, and comes back. */
  var mq = { el: null, t: 0, anims: [] }, hovered = null;
  /* The list's choice shows only while the pointer is on a row or the keys made it: a pointer that has left leaves no row lit
     (the choice itself stays, for Return, until the keys or the pointer move it). */
  var listKb = true;
  var listShown = true;
  /* from where the pointer is, not from enter and leave: a pointer that WebKit never reported moving (a list hovered open) gets
     its leave events played by the page (hoverAt), and a late leave from the row it came from can arrive after the next row's enter */
  function overRow() { var e = ptrAt[0] >= 0 ? document.elementFromPoint(ptrAt[0], ptrAt[1]) : null; return !!(e && e.closest && e.closest('.p-switch .row')); }
  function markList() {
    var pn = q('.p-switch'), lit = listKb || overRow();
    if (pn) pn.classList.toggle('nomark', !lit);
    if (lit !== listShown) { listShown = lit; post({ type: 'marked', on: lit }); }   /* Return, Right and Tab open nothing while no row is lit */
  }
  function marquee(row) {
    if (row && mq.el === row) return;
    clearTimeout(mq.t); mq.anims.forEach(function (a) { a.cancel(); });
    if (mq.el) mq.el.querySelectorAll('.mq-on').forEach(function (b) { b.classList.remove('mq-on', 'mq-rtl'); });
    mq = { el: row, t: 0, anims: [] };
    if (!row || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) return;
    mq.t = setTimeout(function () {
      /* the title if it is cut short, else the name; a right-to-left title glides the other way */
      var box = [row.querySelector('.nm'), row.querySelector('.tp')].filter(function (b) { return b && b.scrollWidth - b.clientWidth >= 4; })[0];
      if (!box || mq.el !== row) return;
      /* a shimmering title has a second copy of its words on top (the shine): both read out together, or they come apart */
      var inners = box.querySelectorAll('.mq-in'), rtl = getComputedStyle(box).direction === 'rtl';
      var over = box.scrollWidth - box.clientWidth + 14;   /* clear of the fade at the far edge */
      box.classList.add('mq-on'); if (rtl) box.classList.add('mq-rtl');
      var go = over / 45 * 1000, rest = 1600, back = 600, wait = 1400, all = go + rest + back + wait;
      var at = function (ms) { return ms / all; };
      var x = function (v) { return { transform: 'translateX(' + (rtl ? -v : v) + 'px)' }; };
      inners.forEach(function (inner) { mq.anims.push(inner.animate([
        Object.assign(x(0), { offset: 0, easing: 'cubic-bezier(.45,0,.55,1)' }), Object.assign(x(-over), { offset: at(go) }),
        Object.assign(x(-over), { offset: at(go + rest), easing: 'cubic-bezier(.4,0,.2,1)' }), Object.assign(x(0), { offset: at(go + rest + back) }), Object.assign(x(0), { offset: 1 })
      ], { duration: all, iterations: Infinity })); });
      /* the left edge fades in only while the text is away from its start */
      mq.anims.push(box.animate([
        { '--mql': '0px', offset: 0 }, { '--mql': '12px', offset: at(Math.min(300, go)) }, { '--mql': '12px', offset: at(go + rest) },
        { '--mql': '0px', offset: at(go + rest + back) }, { '--mql': '0px', offset: 1 }
      ], { duration: all, iterations: Infinity }));
    }, 1000);
  }
  /* ---- a new session (Command+Option+N, from anywhere; or the list's New button): which agent, which folder or none, then what to ask ----
     Three steps on one card, each a short list like the session list, so the keys are the same: Up and Down choose, Return
     (or Right) goes on, Esc (or Left) goes back a step. The choices you made sit along the top as chips; press one to change
     it. Swift sends the agents found on this Mac and the folders sessions ran in, newest first, and what to start on: the
     agent and folder of the session you are looking at (the row you were on in the list; from anywhere else, the session
     in front of you, youAreIn), else the ones you started with last. Return starts it and leaves you where you are; Command+Return starts it and
     takes you there. Your words are a draft until they go: closing keeps them, and the next Command+Option+N opens on them. */
  var nw = { on: false, step: 'app', app: 0, proj: 0, q: '', aq: '', text: '', last: '', files: [], lastFiles: [], o: null };
  var NW_STEPS = ['app', 'project', 'prompt'], nwSlide = 0, nwDrawn = '';
  /* what a row says while a file is over it (nwDropRow) */
  var NW_DZ = '<span class="nw-dz hidden flex-none items-center text-xs font-medium text-foreground">Drop to start</span>';
  function nwApps() { return (nw.o && nw.o.apps) || []; }
  /* the folders, narrowed by what you typed; No project first and Choose a folder last stay whatever you type */
  function nwRows() {
    var words = nw.q.toLowerCase().split(/\s+/).filter(Boolean), all = (nw.o && nw.o.projects) || [];
    var hit = all.filter(function (p) { var hay = (p.name + ' ' + (p.label || p.path)).toLowerCase(); return words.every(function (w) { return hay.indexOf(w) >= 0; }); });
    return (words.length ? [] : [{ none: true }]).concat(hit).concat([{ pick: true }]);
  }
  /* the agents, narrowed by what you typed on that step (by name or where it opens) */
  function nwAppList() {
    var words = nw.aq.toLowerCase().split(/\s+/).filter(Boolean);
    return nwApps().filter(function (a) { var hay = (a.name + ' ' + nwWhere(a)).toLowerCase(); return words.every(function (w) { return hay.indexOf(w) >= 0; }); });
  }
  function nwAgent() { return nwAppList()[nw.app] || nwApps()[nw.app] || { app: 'claude', name: 'Claude' }; }
  function nwFolder() { var r = nwRows()[nw.proj]; return r && !r.pick ? r : { none: true }; }
  function nwTile(ic) { return '<span class="grid size-5 flex-none place-items-center rounded-[5px] bg-white/[0.08] text-muted-foreground" aria-hidden="true">' + svg(ic, 'size-3') + '</span>'; }
  /* No project, as each agent takes it. The Claude app cannot be asked for a chat without a folder: given none, it uses
     the folder picked in its own new-session screen (and makes the session a worktree there), so its row says that. */
  function nwNone(a) { return !a.via && a.app === 'claude' ? ['Let Claude choose', 'The folder picked in Claude', 'Claude chooses'] : ['No project', a.via ? 'Starts in your home folder' : 'A chat with no folder', 'No project']; }
  function nwWhere(a) { return a.via ? TERMS[a.via] || 'Terminal' : agentShort(a.app) + ' app'; }
  function newApply(o, entering) {
    /* While it is open, what you are choosing holds still: a scan that finds activity elsewhere (another folder moving to
       the top, an agent found) would move the rows under you, change the folder chosen, or redraw the field and its caret
       as you type. Only a list that was empty (the first scan not yet done) is filled in. */
    if (!entering) {
      var had = (nw.o && nw.o.projects) || [];
      if (had.length || !(o.projects || []).length) return;
      nw.o = o;
      if (nw.step === 'app') { var fi = nwRows().findIndex(function (r) { return !r.none && !r.pick && r.name === o.project; }); nw.proj = fi < 0 ? 0 : fi; }
      return newRender();
    }
    nw.o = o;
    if (entering) {
      /* a draft waiting comes back with the agent and folder it was written for, not the defaults of where you are now */
      var kept = (nw.text || nw.files.length) && nw.kept, agent = kept ? kept.app : o.agent;
      var ai = nwApps().findIndex(function (a) { return a.id === agent; });
      nw.on = true; nw.app = ai < 0 ? 0 : ai; nw.q = ''; nw.aq = '';
      var pi = nwRows().findIndex(function (r) { return kept ? (kept.none ? r.none : !r.none && !r.pick && r.path === kept.path) : !r.none && !r.pick && r.name === o.project; });
      if (pi < 0 && kept) pi = nwRows().findIndex(function (r) { return !r.none && !r.pick && r.name === o.project; });
      nw.proj = pi < 0 ? 0 : pi;
      /* a draft waiting: straight back to it, as you left it */
      nw.step = nw.text || nw.files.length ? 'prompt' : 'app';
    }
    newRender(entering);
  }
  function nwChip(step, inner) { return '<button class="nw-chip flex h-6 min-w-0 flex-none cursor-pointer items-center gap-1.5 rounded-md bg-white/[0.07] px-1.5 text-[12.5px] font-medium transition-colors hover:bg-white/[0.12]" data-go="' + step + '">' + inner + '</button>'; }
  function nwSep() { return '<svg class="size-3 flex-none text-muted-foreground/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>'; }
  function newRender(entering) {
    var box = q('.nw'), a = nwAgent(), f = nwFolder(), html = '', at = NW_STEPS.indexOf(nw.step);
    /* along the top: the choices made so far as chips, then this step's question (or what you typed to narrow the folders) */
    var crumbs = '';
    if (at > 0) crumbs += nwChip('app', AppOf(a, 'size-3.5') + '<span class="truncate">' + esc(a.name) + '</span>') + nwSep();
    if (at > 1) crumbs += nwChip('project', svg(f.none ? 'chat' : 'folder', 'size-3 flex-none text-muted-foreground') + '<span class="truncate">' + esc(f.none ? nwNone(a)[2] : f.name) + '</span>');
    var ask = nw.step === 'app' ? (nw.aq ? '<span dir="auto">' + esc(nw.aq) + '</span><i class="s-caret"></i>' : 'New session') : nw.step === 'project' ? (nw.q ? '<span dir="auto">' + esc(nw.q) + '</span><i class="s-caret"></i>' : 'Which folder?') : '';
    var right = nw.step === 'app' ? (nw.aq ? nwAppList().length + ' of ' + nwApps().length : 'Which agent?') : nw.step === 'project' ? (nw.q ? (nwRows().length - 1) + ' of ' + ((nw.o.projects || []).length) : 'Type to filter') : nw.step === 'prompt' ? 'Opens in ' + nwWhere(a) : '';
    html += '<div class="flex h-9 items-center gap-1.5 pl-4 pr-4"><div class="flex min-w-0 flex-1 items-center gap-1.5">' + crumbs +
      (ask ? '<span class="nw-ask min-w-0 truncate text-sm font-medium leading-4' + (at ? ' pl-0.5' : '') + '">' + ask + '</span>' : '') + '</div>' +
      (right ? '<span class="nw-right flex-none text-xs text-muted-foreground">' + esc(right) + '</span>' : '') +
      (nw.step !== 'prompt' ? '<span class="nw-dhint hidden flex-none text-xs font-medium text-foreground">Drop on ' + (nw.step === 'app' ? 'an agent' : 'a folder') + ' to start</span>' : '') + '</div>';
    if (nw.step === 'app') {
      var apps = nwAppList();
      html += '<div class="nw-l relative max-h-[196px] overflow-y-auto px-1.5 pb-1">' + (apps.length ? '' : '<div class="px-2.5 pb-2 pt-1 text-[13px] leading-[18px] text-muted-foreground">No agent matches</div>') + apps.map(function (x, i) {
        return '<div class="nrow flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors' + (i === nw.app ? ' bg-accent' : '') + '" data-i="' + i + '">' + AppOf(x) +
          '<span class="nm min-w-0 flex-1 truncate font-medium">' + esc(x.name) + '</span><span class="nw-rt flex flex-none items-center gap-2"><span class="text-xs text-muted-foreground">' + esc(nwWhere(x)) + '</span>' + (i < 9 ? Kbd(String(i + 1)) : '') + '</span>' + NW_DZ + '</div>';
      }).join('') + '</div>' + nwHints(['\u2191\u2193', 'Choose'], [ENTER, 'Next'], ['\u2190', 'Back']);
    } else if (nw.step === 'project') {
      var rows = nwRows();
      html += '<div class="nw-l relative max-h-[196px] overflow-y-auto px-1.5 pb-1">' + rows.map(function (r, i) {
        var on = i === nw.proj ? ' bg-accent' : '';
        if (r.none) return '<div class="nrow flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors' + on + '" data-i="' + i + '">' + nwTile('chat') +
          '<span class="nm min-w-0 flex-1 truncate font-medium">' + nwNone(a)[0] + '</span><span class="nw-rt flex-none text-xs text-muted-foreground">' + nwNone(a)[1] + '</span>' + NW_DZ + '</div>';
        if (r.pick) return '<div class="nrow flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors' + on + '" data-i="' + i + '">' + nwTile('folderPlus') +
          '<span class="nm min-w-0 flex-1 truncate text-muted-foreground">Choose a folder\u2026</span>' + Kbd('\u2318O') + '</div>';
        return '<div class="nrow flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors' + on + '" data-i="' + i + '">' + nwTile('folder') +
          '<span class="flex min-w-0 flex-1 items-center gap-2"><span class="nm min-w-0 truncate font-medium">' + esc(r.name) + '</span><span class="flex-none text-xs tabular-nums text-muted-foreground">' + esc(r.away || '') + '</span></span>' +
          '<span dir="ltr" class="nw-rt min-w-0 max-w-[45%] flex-none truncate text-xs text-muted-foreground">' + esc(r.label || r.path) + '</span>' + NW_DZ + '</div>';
      }).join('') + '</div>' + nwHints(['\u2191\u2193', 'Choose'], [ENTER, 'Next'], ['\u2190', 'Back']);
    } else {
      /* the field is a box: the files attached along its top (nwPaths), then your words */
      html += '<div class="px-2.5"><div class="nw-box rounded-lg bg-white/[0.1] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] transition-[background-color,box-shadow] duration-200 focus-within:bg-white/[0.13] focus-within:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]">' +
        '<div class="nw-att mx-2 hidden gap-1 overflow-x-auto pt-2"></div>' +
        '<textarea class="nw-in block cursor-text max-h-[124px] min-h-[68px] w-full resize-none bg-transparent px-2.5 py-[7px] text-[13px] leading-[19px] text-foreground caret-white outline-none placeholder:text-white/35" rows="1" spellcheck="false" placeholder="What should ' + esc(agentShort(a.app)) + ' do?" aria-label="Prompt"></textarea></div></div>' +
        '<div class="mt-1.5 flex h-9 items-end gap-1 px-2.5 pb-2"><button aria-label="Back" title="Back (Esc)" class="nw-back flex h-7 flex-none cursor-pointer items-center rounded-md px-0.5 opacity-75 transition-opacity hover:opacity-100">' + Kbd('esc') + '</button>' +
        '<span class="flex-1"></span>' + Button('ghost', 'Start and go', Kbd('\u2318' + '\u21a9'), 'nw-go') + Button('default', 'Start', Kbd(svg('enter', 'size-2'), 1), 'nw-start pr-0.5') + '</div>';
    }
    /* a step forward slides in from the right, a step back from the left, the old one going the other way (transitions.dev
       page side by side) */
    var by = nwSlide; nwSlide = 0;   /* taken once: a draw again from inside this one (an answer to what it posts) does not slide */
    /* a refresh that changes nothing here leaves the card alone: drawn again, the prompt would lose what you selected in it
       (a double or triple click, Command+A) and its caret would jump to the end */
    if (!entering && !by && html === nwDrawn && box.firstChild) return;
    nwDrawn = html;
    var slid = by && !STILL ? crossSeen(q('.p-ns'), ['.nw'])[0] : null;
    box.innerHTML = html;
    if (slid && slid.g) {
      var dx = by > 0 ? 8 : -8, g = slid.g, gone = function () { g.remove(); };
      q('.p-ns').appendChild(g);
      g.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateX(' + (-dx) + 'px)', filter: 'blur(3px)' }], { duration: 250, easing: SMOOTH, fill: 'forwards' }).onfinish = gone;
      setTimeout(gone, 370);   /* the timer finishes it even when animations are paused */
      box.animate([{ opacity: 0, transform: 'translateX(' + dx + 'px)', filter: 'blur(3px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], { duration: 250, easing: SMOOTH });
    }
    var l = q('.nw-l'); if (l) { l.onscroll = function () { nwEdges(l); }; setTimeout(function () { nwEdges(l); }, 0); }
    box.querySelectorAll('.nw-chip').forEach(function (c) { c.onclick = function () { nwTo(c.dataset.go); }; });
    box.querySelectorAll('.nrow').forEach(function (r) {
      r.onclick = function () { nwPick(+r.dataset.i); nwNext(); };
      r.onmouseenter = function () { if (!ptrMoved() || nwDrop) return; nwPick(+r.dataset.i, true); };   /* a file dragged across the rows chooses nothing */
    });
    var ta = q('.nw-in');
    if (ta) {
      ta.value = nw.text; nwAtt();
      ta.oninput = function () { nw.text = ta.value; nwGrow(ta); };
      ta.onkeydown = function (e) {
        if (e.key === 'Backspace' && nw.files.length && !ta.selectionStart && !ta.selectionEnd) { e.preventDefault(); nw.files.pop(); nwAtt(); }
        else if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); e.stopPropagation(); nwStart(e.metaKey); }
        else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); nwBack(); }
      };
      q('.nw-start').onclick = function () { nwStart(false); };
      q('.nw-go').onclick = function () { nwStart(true); };
      q('.nw-back').onclick = nwBack;
      setTimeout(function () { ta.focus({ preventScroll: true }); var e = ta.value.length; ta.setSelectionRange(e, e); }, entering ? 260 : 0);
    }
    if (snap) layout('ns', snap);
    nwShow(); nwSeen();
  }
  function nwHints() { return '<div class="flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground">' + [].map.call(arguments, function (h) { return '<span class="flex items-baseline gap-1.5">' + (h[0] === '\u2191\u2193' ? Keys('\u2191', '\u2193') : Kbd(h[0])) + h[1] + '</span>'; }).join('') + '</div>'; }
  /* the chosen row stays in view, clear of the edge fades */
  function nwShow() {
    var sel = q('.nw .nrow.bg-accent'), l = q('.nw-l'), pad = 20; if (!sel || !l) return;
    if (sel.offsetTop - pad < l.scrollTop) l.scrollTop = sel.offsetTop - pad;
    else if (sel.offsetTop + sel.offsetHeight > l.scrollTop + l.clientHeight - pad) l.scrollTop = sel.offsetTop + sel.offsetHeight - l.clientHeight + pad;
  }
  function nwEdges(l) {
    var up = l.scrollTop > 1, down = l.scrollTop + l.clientHeight < l.scrollHeight - 1;
    l.style.webkitMaskImage = l.style.maskImage = up || down ? 'linear-gradient(' + (up ? 'transparent, #000 24px' : '#000, #000') + ', ' + (down ? '#000 calc(100% - 24px), transparent' : '#000') + ')' : '';
  }
  /* three lines to write in; two with files over them, so the field is about the same height either way */
  function nwGrow(ta) { var min = nw.files.length ? 44 : 68; ta.style.minHeight = min + 'px'; ta.style.height = 'auto'; ta.style.height = Math.min(124, Math.max(min, ta.scrollHeight)) + 'px'; if (snap && nw.on) layout('ns', snap); }
  /* the character's eyes go to what you are choosing */
  function nwSeen() { var el = q('.nw .nrow.bg-accent .nm') || q('.nw-in') || q('.nw-ask'); if (el) lookAt(el, 40); }
  function nwPick(i, quiet) {
    if (nw.step === 'app') nw.app = i; else nw.proj = i;
    q('.nw').querySelectorAll('.nrow').forEach(function (r) { r.classList.toggle('bg-accent', +r.dataset.i === i); });
    if (!quiet) nwShow();
    nwSeen();
  }
  function nwTo(step) {
    /* leaving the agents: the one you chose keeps its place in the whole list */
    if (nw.step === 'app' && step !== 'app' && nw.aq) { var a = nwAgent(); nw.aq = ''; nw.app = Math.max(0, nwApps().indexOf(a)); }
    /* and leaving the folders: the one you chose keeps its place too, rather than whatever row the narrowed one sat at
       (it was No project, then the app's own choice: a typed "perch" started in another folder) */
    if (nw.step === 'project' && step !== 'project' && nw.q) { var f = nwRows()[nw.proj]; nw.q = ''; var fi = nwRows().indexOf(f); nw.proj = fi < 0 ? 0 : fi; }
    nwSlide = NW_STEPS.indexOf(step) - NW_STEPS.indexOf(nw.step);
    nw.step = step; if (step !== 'project') nw.q = ''; newRender(); blinkEl(cr);
  }
  function nwNext() {
    if (nw.step === 'app') { if (!nwAppList().length) return; return nwTo('project'); }
    if (nw.step === 'project') { if (nwRows()[nw.proj].pick) { post({ type: 'newSession', action: 'chooseFolder' }); return; } return nwTo('prompt'); }
  }
  function nwBack() {
    if (nw.step === 'prompt') return nwTo('project');
    if (nw.step === 'project') return nwTo('app');
    post({ type: 'back' });
  }
  /* Return starts it and leaves you where you are: the words fly into the notch like a reply to a terminal, and the new
     session shows in the list, working. Command+Return starts it and takes you there. */
  function nwStart(go) {
    var words = nw.text.trim(), t = withFiles(words, nw.files), ta = q('.nw-in'); if (!t) { if (ta) ta.focus(); return; }
    var a = nwAgent(), f = nwFolder(), from = (nw.o && nw.o.from) || 'list';
    nw.last = nw.text; nw.text = ''; nw.lastFiles = nw.files; nw.files = [];
    /* from anywhere the words fly into the notch; from the list it is simply back, the new row already there and shimmering */
    if (!go && from !== 'list') newFly(words || nw.lastFiles.map(function (x) { return x.split('/').pop(); }).join(' '));
    /* opened from anywhere, the card folds into one line, like a reply's Sent: Starting until Perch sees the new session (started) */
    if (!go && from !== 'list') sentNext = { p: nwLineP(a, f), words: 'Starting', at: Date.now(), pending: true };
    post({ type: 'newSession', action: 'start', agent: a.id, folder: f.none ? '' : f.path, prompt: t, title: words || nw.lastFiles.map(function (x) { return x.replace(/\/+$/, '').split('/').pop(); }).join(', '), go: !!go, from: from, close: SEND_CLOSE });
  }
  function nwLineP(a, f) { return { id: 'new-session', name: f.none ? nwNone(a)[2] : f.name, topic: '', app: a.app, via: a.via, status: { kind: 'running', text: 'Starting', app: a.app } }; }
  /* Swift: the new session is there (its transcript or process seen), or it never came. On the one line the words change in
     place; in the list, the header says it and the row slides in. A session that did not start leaves your words as the draft. */
  function nwStarted(ok, app) {
    /* the app asks you to trust the folder first: the line says to confirm there, and waits */
    if (ok === 'confirm') {
      if (act.mode === 'sent' && act.p && act.p.id === 'new-session') { sentShow(act.p, 'Confirm in ' + app, true, false, '', true, true); return; }
      /* asked before the card had folded into its line: the line, when it comes, says it */
      if (sentNext && sentNext.p.id === 'new-session') { sentNext.words = 'Confirm in ' + app; sentNext.asks = true; return; }
      /* started from the list: the app has the keyboard now, so the list (Swift closes it next) folds into that same line */
      var pr = lastSt === 'switch' && snap && snap.projects.filter(function (x) { return x.pending === 'starting' || x.pending === 'confirm'; })[0];
      if (pr) sentNext = { p: { id: 'new-session', name: pr.name, topic: '', app: pr.app, via: pr.via, status: { kind: 'running', text: 'Starting', app: pr.app } }, words: 'Confirm in ' + app, at: Date.now(), pending: true, asks: true };
      return;
    }
    if (!ok && (nw.last || nw.lastFiles.length)) { nw.text = nw.last; nw.files = nw.lastFiles; }
    nw.last = ''; nw.lastFiles = [];
    if (act.mode === 'sent' && act.p && act.p.id === 'new-session') { if (ok) sentShow(act.p, 'Started'); else sentShow(act.p, '', false, false, 'Didn\u2019t start'); }
  }
  function newFly(text) {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var pane = q('.p-ns'), ta = q('.nw-in'), pr = pane.getBoundingClientRect(), fr = ta.getBoundingClientRect();
    var rows = [].slice.call(q('.nw').children).reverse();
    var gone = rows.map(function (el, i) { return el.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateY(-6px)', filter: 'blur(3px)' }], { duration: 200, delay: i * 25, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' }); });
    var b = document.createElement('div'); b.className = 'fly'; b.textContent = text; pane.appendChild(b);
    var x0 = fr.left - pr.left + 8, y0 = fr.top - pr.top + 6;
    b.style.left = x0 + 'px'; b.style.top = y0 + 'px';
    var dx = CARD_W / 2 - (x0 + b.offsetWidth / 2), dy = 2 - (y0 + b.offsetHeight / 2);
    b.animate([{ transform: 'none', opacity: 1 }, { transform: 'translate(' + (dx * .15) + 'px, 6px) scale(1.06, .9)', opacity: 1, offset: .25 },
      { transform: 'translate(' + (dx * .85) + 'px,' + (dy * .8) + 'px) scale(.5, 1.25)', opacity: 1, offset: .8 }, { transform: 'translate(' + dx + 'px,' + dy + 'px) scale(.1, .4)', opacity: 0 }],
      { duration: 360, delay: 40, easing: 'cubic-bezier(.6,0,.4,1)', fill: 'both' });
    var ring = document.createElement('div'); ring.className = 'fly-ring'; ring.style.left = (CARD_W / 2 - 30) + 'px'; ring.style.top = '-28px'; ring.style.animationDelay = '370ms'; pane.appendChild(ring);
    look(2.8, -1.6);
    setTimeout(function () { var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); look(0, 0); }, 400);
    n.dataset.g = 'status'; n.style.setProperty('--glow', '140,207,164'); n.style.setProperty('--glow-hi', '196,234,210');
    setTimeout(function () { gone.forEach(function (x) { x.cancel(); }); b.remove(); ring.remove(); }, SEND_CLOSE * 1000 + 600);
  }
  document.addEventListener('keydown', function (e) {
    if (!NATIVE || !snap || snap.phase !== 'newSession' || (e.target && e.target.classList && e.target.classList.contains('nw-in'))) return;
    if (newKey(e)) e.preventDefault();
  });
  /* Swift: the folder chosen in the Mac's picker. It becomes the session's, and on to the prompt. */
  function nwPicked(name, path) {
    var o = nw.o || {}; o.projects = (o.projects || []).filter(function (p) { return p.path !== path; });
    o.projects.unshift({ name: name, path: path, away: '' }); nw.o = o; nw.q = ''; nw.proj = 1; nwTo('prompt');
  }
  /* Files dropped on the card or pasted from Finder go into the prompt as their paths, as on a reply. Dropped while the
     agent or the folder is still being chosen, the card goes on to the prompt with what is chosen so far (the chips
     change it). Over the card the field lights up, more so with the file right on it, and the character watches. */
  var nwDrop = 0, nwHint = '', nwDropWas = null;
  function nwPaths(list) {
    nwDropWas = null;   /* dropped on a row: that row is the choice */
    if (nwDrop) nwDragOver(0);
    if (nw.step !== 'prompt') nwTo('prompt');
    var ta = q('.nw-in'); if (!ta) return;
    nw.files = addFiles(nw.files, list); nwAtt();
    setTimeout(function () { var e = ta.value.length; ta.focus({ preventScroll: true }); ta.setSelectionRange(e, e); }, 40);
    var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop');
    setTimeout(function () { if (!nwDrop && snap && lastSt === 'ns') layout('ns', snap); }, 1100);
  }
  function nwAtt() {
    var box = q('.nw-att'); if (!box) return;
    attChips(box, nw.files, function (i) { nw.files.splice(i, 1); nwAtt(); var ta = q('.nw-in'); if (ta) ta.focus({ preventScroll: true }); });
    var ta = q('.nw-in'); if (ta) nwGrow(ta);
  }
  /* A file over the agents or the folders: the row under it lights up and says Drop to start, and a drop there picks it
     and goes on to the prompt with the file attached. Off the rows (or gone), the row you had chosen comes back.
     Choose a folder... takes no file. */
  function nwDropRow(x, y) {
    var el = x == null ? null : document.elementFromPoint(x, y), row = el && el.closest ? el.closest('.nw .nrow') : null, i = row ? +row.dataset.i : -1;
    if (i >= 0 && nw.step === 'project' && (nwRows()[i] || {}).pick) i = -1;
    var cur = nw.step === 'app' ? nw.app : nw.proj;
    if (x != null && nwDropWas == null) nwDropWas = cur;
    var to = i >= 0 ? i : nwDropWas;
    if (to != null && to !== cur) nwPick(to, true);
    q('.nw').querySelectorAll('.nrow').forEach(function (r) { r.classList.toggle('dz', +r.dataset.i === i); });
    q('.nw').classList.toggle('dropping', x != null);
    if (x == null) nwDropWas = null;
  }
  function nwDragOver(n, x, y) {
    var ta = q('.nw-in'), fb = q('.nw-box'), was = nwDrop; nwDrop = n;
    if (n && !was) { cr.dataset.m = 'alert'; if (ta) nwHint = ta.placeholder; }
    if (n) lookAt(ta || q('.nw'), 60);
    if (nw.step !== 'prompt') nwDropRow(n ? x : null, y);
    if (ta) {
      var r = fb.getBoundingClientRect(), on = !!n && x != null && x >= r.left - 8 && x <= r.right + 8 && y >= r.top - 8 && y <= r.bottom + 8;
      fb.classList.toggle('drop', !!n); fb.classList.toggle('on', on);
      ta.placeholder = !n ? nwHint || ta.placeholder : (on ? 'Release to attach ' : 'Drop to attach ') + (n > 1 ? 'them' : 'it');
    }
    if (!n && was && snap) layout('ns', snap);   /* its face goes back */
  }
  /* the keys while it shows (the prompt's own field takes its keys itself); true when one was used */
  function newKey(e) {
    if (nw.step === 'prompt') { if (e.key === 'Escape') { nwBack(); return true; } return false; }
    var max = nw.step === 'app' ? nwAppList().length : nwRows().length, cur = nw.step === 'app' ? nw.app : nw.proj;
    if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && max) { nwPick((cur + (e.key === 'ArrowDown' ? 1 : -1) + max) % max); return true; }
    if (e.key === 'Enter' || e.key === 'ArrowRight') { nwNext(); return true; }
    if (e.key === 'Escape') { if (nw.q) { nw.q = ''; nw.proj = 0; newRender(); } else if (nw.aq) { nw.aq = ''; nw.app = 0; newRender(); } else nwBack(); return true; }
    if (e.key === 'ArrowLeft') { nwBack(); return true; }
    if (nw.step === 'app' && /^[1-9]$/.test(e.key) && +e.key <= max) { nwPick(+e.key - 1); setTimeout(nwNext, 140); return true; }
    if (nw.step === 'project' && e.metaKey && (e.key === 'o' || e.key === 'O')) { nw.proj = nwRows().length - 1; nwNext(); return true; }
    /* typing narrows the agents too (a number still picks one) */
    if (nw.step === 'app' && (e.key === 'Backspace' || (e.key.length === 1 && !/[0-9]/.test(e.key) && !e.metaKey && !e.ctrlKey && !(e.key === ' ' && !nw.aq)))) {
      nw.aq = e.key === 'Backspace' ? nw.aq.slice(0, -1) : nw.aq + e.key; nw.app = 0; newRender(); return true;
    }
    if (nw.step === 'project' && (e.key === 'Backspace' || (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !(e.key === ' ' && !nw.q)))) {
      nw.q = e.key === 'Backspace' ? nw.q.slice(0, -1) : nw.q + e.key;
      /* typing narrows to folders (No project steps aside) and lands on the first that matches */
      nw.proj = 0;
      newRender(); return true;
    }
    return false;
  }
  /* the auto-dismiss countdown: the glow slowly settles, nothing else on the card moves */
  function bar(on) {
    var g = q('.glow'); g.style.transition = 'none'; g.style.opacity = '';
    if (on) { void g.offsetWidth; g.style.transition = 'opacity 9s linear'; g.style.opacity = '.3'; }
    else g.style.transition = '';
  }
  /* The resting notch's outline. A photo of a 14-inch MacBook Pro with the full reported size (185 x 32) in magenta showed the
     hardware about 1.5 to 2 pt narrower on each side and about 1.5 pt shorter, with bottom corners near 10 pt. So it is drawn
     2.5 pt in at the sides and 1.5 pt up from the bottom, with smooth corners (a superellipse), and can only hide behind the
     hardware, never show past it. */
  function notchPath(w, h) {
    var ix = 2.5, iy = 1.5, r = 12, e = 2 / 2.6, pts = [], k, t, x0 = w - ix - r, y0 = h - iy - r, N = 14;
    pts.push([ix, -2], [w - ix, -2]);
    for (k = 0; k <= N; k++) { t = k / N * Math.PI / 2; pts.push([x0 + r * Math.pow(Math.cos(t), e), y0 + r * Math.pow(Math.sin(t), e)]); }
    for (k = 0; k <= N; k++) { t = k / N * Math.PI / 2; pts.push([ix + r - r * Math.pow(Math.sin(t), e), y0 + r * Math.pow(Math.cos(t), e)]); }
    return 'path("M' + pts.map(function (p) { return p[0].toFixed(2) + ' ' + p[1].toFixed(2); }).join(' L') + ' Z")';
  }
  var crHideT = 0;
  /* A question taller than the panel (four choices with long notes, and Other): its choices scroll, so the buttons below
     stay on the card. One that fits is left as it is. */
  function fitAsk(pane) {
    var box = pane.querySelector('.o-ask .ch-box'); if (!box) return;
    box.style.maxHeight = ''; box.classList.remove('fit');
    var over = pane.querySelector('.inner').offsetHeight - CARD_MAX_H;
    if (over > 0 && box.offsetHeight) { box.style.maxHeight = Math.max(120, box.offsetHeight - over) + 'px'; box.classList.add('fit'); }
  }
  /* Preview takes the height the panel has left; a message that fits shows whole */
  function fitPreview(pane) {
    var box = pane.querySelector('.o-said-in');
    if (pane.dataset.prev !== '1') { box.style.maxHeight = ''; return; }
    var at = box.scrollTop, end = at >= box.scrollHeight - box.clientHeight - 1;   /* measuring lets it grow whole, which would put it back at the top */
    box.style.maxHeight = 'none';
    var over = pane.querySelector('.inner').offsetHeight - CARD_MAX_H;
    box.style.maxHeight = over > 0 ? Math.max(120, box.offsetHeight - over) + 'px' : 'none';
    box.scrollTop = end ? box.scrollHeight : at;
    box.parentNode.classList.toggle('ov', box.scrollHeight > box.clientHeight + 1);
  }
  function layout(st, s) {
    /* No hardware notch (an external display): nothing is drawn at rest. The live activity and the card grow from the top centre; the box keeps a size to grow from. */
    var scr = s.screen, virt = !scr.hasNotch, idleW = virt ? 148 : scr.notchW, idleH = virt ? Math.min(scr.notchH || 24, 28) : scr.notchH;
    var w = st === 'idle' ? idleW : CARD_W, h = idleH;
    if (st !== 'idle') { var pane = q('.p-' + st); if (st === 'open') { fitAsk(pane); fitPreview(pane); } h = pane.querySelector('.inner').offsetHeight; }
    else if (act.mode) { var sz = actSize(idleW, idleH); w = sz[0]; h = sz[1]; placeAct(idleW, idleH, w); }
    n.dataset.act = st === 'idle' ? act.mode : '';
    n.style.width = w + 'px'; n.style.marginLeft = (-w / 2) + 'px'; n.style.height = h + 'px';
    n.style.opacity = 1;
    n.dataset.virt = virt ? '1' : '';
    var shaped = st === 'idle' && !act.mode && !virt;
    if (shaped) n.style.setProperty('--np', notchPath(idleW, idleH));
    n.dataset.shape = shaped ? '1' : '';
    document.documentElement.dataset.guide = s.guide || '';
    n.dataset.hide = virt && st === 'idle' && !act.mode ? '1' : '';
    n.dataset.s = st;
    curH = h;
    if (st === 'idle') {
      var d = 18; cr.style.width = cr.style.height = d + 'px';
      /* beside the notch, or beside the live activity when it has widened the notch */
      idleXf = 'translate(' + (-w / 2 - d - 6) + 'px,' + ((idleH - d) / 2) + 'px)'; idleD = d;
      cr.style.transform = idleXf;
      if (helloNext) { helloNext = false; sayHello(); }
    } else if (!celebrating) {
      cr.style.width = cr.style.height = '20px';
      cr.style.transform = 'translate(' + (-CARD_W / 2 + 16) + 'px,' + ((idleH - 20) / 2) + 'px)';
    }
    /* idle: nothing beside the notch. What needs you is said by the notch itself (the live activity below). */
    var news = false;
    /* on the character page the big preview is the character, so the small one steps out of its corner, and comes back after */
    var choosing = st === 'onb' && (onbStep === 0 || onbStep === 1) && !celebrating;
    if (choosing) cr.style.transform += ' translateY(-6px) scale(.3)';
    var crHide = (st === 'idle' && !news && !hello) || choosing;
    /* Put away with the card: it fades where it stands and only then takes its place beside the notch, unseen. Moving while
       it faded, it slid off sideways, half there. */
    if (crHide && st === 'idle' && cr.style.opacity !== '0' && !STILL) {
      cr.style.transition = 'transform 0s .26s, width 0s .26s, height 0s .26s, opacity .24s'; clearTimeout(crHideT);
      crHideT = setTimeout(function () { crHideT = 0; if (cr.style.transition !== 'none') cr.style.transition = ''; }, 320);
    } else if (!crHide && crHideT) { clearTimeout(crHideT); crHideT = 0; cr.style.transition = ''; }   /* back before it settled: it moves as always */
    cr.style.opacity = crHide ? 0 : 1;
    cr.dataset.news = news ? '1' : '';
    /* its face says how things are: wide-eyed when something needs you, happy when something finished */
    var cp = st === 'open' || (st === 'switch' && switchFx === 'watch') ? s.projects[s.selected] : null;
    if (!celebrating && !hello && !dropping && !crPlay) cr.dataset.m = st === 'idle' ? (news ? 'alert' : 'sleep')
      : st === 'new' || (st === 'set' && fbGlow.k === 'done' && Date.now() - fbGlow.at < 2600) ? 'happy' : (cp && cp.status.kind === 'attention' ? 'alert' : (cp && cp.status.kind === 'done' && cp.fresh ? 'happy' : 'awake'));
    post({ type: 'size', width: w, height: h });
    /* Swift needs the shape to let clicks through to it, and the keys to listen for while it shows */
    var mode = st === 'idle' ? act.mode : '', keys = !mode || mode === 'sent' || (act.p && (act.p.update || act.p.access)) ? [] : mode === 'full' ? act.keys : act.keys.filter(function (k) { return k !== 'reply'; });   /* an update, and Accessibility gone, have buttons for the mouse only */
    /* a question or a finish on the row (a question in the wings too): the shortcut that opens Perch opens it on its card instead */
    var toCard = (mode === 'full' || mode === 'wings') && act.keys.indexOf('card') >= 0;
    var sig = [mode, w, h, act.p ? act.p.id : '', keys.join(), toCard].join('|');
    if (sig !== actSent.sig) { actSent = { sig: sig }; post({ type: 'activity', mode: mode, width: w, height: h, keys: keys, card: toCard }); }
    if (st === 'open') markChoice();
  }

  /* ---- the live activity ----
     In a session you are not looking at, an answer or a request arrives, and the notch says so. It grows to the sides:
     the app and the session's name on the left, what happened on the right, a check when it finished. Below, a row of
     buttons for what you would do next, each with a Command+Option key so a stray press never answers anything: Pick up
     or Reply when it finished, Allow or Deny, a question's choices. A request also shows what it wants (the command, the
     question). A finish folds away after a few seconds; a request folds to small wings, the app and a mark, that stay
     until you answer. Resting the pointer on it holds it open. During a call or a presentation it skips straight to the
     wings. When you come back from a break, the welcome card says all this instead. */
  var act = { mode: '', p: null, kind: '', keys: [] }, actKnown = null, actTimer = 0, actSent = { mode: '' }, actEl = q('.act'), actGone = {}, actHeld = false, actMore = null, actMoreT = 0;
  var CMDOPT = '\u2318\u2325';
  var actNoKeys = [];   /* row keys Swift could not take (window.perch.actNoKeys): their buttons show no key */
  var MARK = {
    done: Ring('done'), ask: Ring('question'), run: Ring('permission'), plan: Ring('plan'), need: Ring('need')
  };
  function actKind(p) {
    if (p.update) return 'update';
    if (p.access) return 'access';
    if (p.ask) return { permission: 'run', question: 'ask', plan: 'plan' }[p.ask.kind] || 'need';
    return p.status.kind === 'attention' ? 'need' : 'done';
  }
  function actKey(p) { return p.update ? 'update|' + p.update.version + '|' + p.update.phase + '|' + (p.update.nudge || 0) : p.access ? 'access|' + p.access.phase + '|' + (p.access.since || 0) : p.id + '|' + actKind(p) + '|' + (p.ask ? p.ask.subject : p.status.text); }
  /* what you can do from here, as [action, label, key]; the first one is the main one */
  function actButtons(p, k) {
    var a = p.ask;
    if (k === 'done') return [['pick', goLabel(p), '\u21a9'], ['reply', 'Reply', 'R']];
    if (a && a.answerable && a.kind === 'permission') return [['allow', 'Allow', 'A'], ['deny', 'Deny', 'X']];
    var qn = a && a.answerable && a.kind === 'question' && a.questions && a.questions.length === 1 && a.questions[0];
    if (qn && !qn.multi && qn.options.length <= 3) return qn.options.map(function (o, i) { return ['pick' + (i + 1), o.replace(/\s*\(recommended\)\s*$/i, ''), String(i + 1), /\(recommended\)\s*$/i.test(o)]; });
    if (a && a.answerable) return [['open', 'Answer', '\u21a9']];
    return [['pick', goLabel(p), '\u21a9']];
  }
  function actWords(p, k) {
    if (p.ci && !p.ask) return String(p.status.text).replace(/ on #\d+$/, '').replace('Changes requested', 'Changes asked');   /* a pull request is why: "Checks failing", short enough for the notch's wing */
    return k === 'done' ? 'Finished' : k === 'run' ? 'Needs your OK' : k === 'ask' ? 'Asked you' : k === 'plan' ? 'Has a plan' : phrase(p, true).t;
  }
  /* Hovering a choice says its title and note below everything else: only what is under the pointer, and nothing that
     is already there moves (the pointer would lose it). */
  function actExtra(p, k) {
    if (actMore && actMore.pv && act.mode === 'full' && k === 'done') return '<div class="act-ex">Click to preview</div>';
    if (!actMore || act.mode !== 'full' || k !== 'ask') return '';
    var qs = p.ask && p.ask.questions && p.ask.questions[0]; if (!qs) return '';
    if (actMore.c != null) {
      var o = qs.options[actMore.c]; if (o == null) return '';
      return '<div class="act-ex"><b>' + esc(o.replace(/\s*\(recommended\)\s*$/i, '')) + (/\(recommended\)\s*$/i.test(o) ? '<i class="act-rec">Recommended</i>' : '') + '</b>' + esc((qs.notes && qs.notes[actMore.c]) || '') + '</div>';
    }
    /* the question hovered: a click shows it all on the card, and where Open Claude has no button, its key */
    if (actMore.q) return '<div class="act-ex">Click to see it all' + (act.keys.indexOf('app') >= 0 && !actEl.querySelector('.act-o') && actNoKeys.indexOf('app') < 0 ? ' \u00b7 ' + CMDOPT + 'O opens ' + esc(goLabel(p).replace(/^Open /, '')) : '') + '</div>';
    return '';
  }
  function renderAct() {
    actEl.dataset.mode = act.mode;
    /* what was there stays while it fades; shown again, its names are measured again */
    if (!act.mode) { actGlideFor = ''; return; }
    if (act.mode === 'sent') { renderSent(act.p); actGlide(); return; }
    actEl.classList.remove('chose');
    var p = act.p, k = act.kind, a = p.ask, body = '', bodyCls = '';
    if (act.mode !== 'full' || (k !== 'ask' && !(k === 'done' && actMore && actMore.pv))) actMore = null;
    if (k === 'update') { renderUpd(p.update); return; }
    if (k === 'access') { renderAccess(p.access); return; }
    if (k === 'run') body = '<span class="act-cmd">' + esc(a.brief || a.subject || 'a command') + '</span>';   /* the command without its output plumbing (Ask.brief); the card shows it all */
    else if (k === 'ask') { bodyCls = ' askq'; body = '<span dir="auto" class="act-q" data-a="card" title="Show it all">' + esc((a.questions && a.questions[0] && a.questions[0].text) || a.subject || 'Asked you something') + '</span>'; }   /* a question is said in full: it wraps */
    else if (k === 'plan' && a.subject) body = '<span dir="auto" class="act-t">' + esc(a.subject) + '</span>';
    var bs = actButtons(p, k);
    /* Open Claude at the right of the row opens the session in its app, on Command+Option+O on every row ('app'), unless a
       button already does (then a cross at the left puts it away); three choices need the room, so there it is the key alone. Command+Option+. puts it
       away either way. Clicking the question opens the whole of it on the card ('card'). */
    var toApp = !bs.some(function (b) { return b[0] === 'pick'; }), opener = toApp && !(/^pick\d$/.test(bs[0][0]) && bs.length >= 3);   /* three choices: the key alone */
    var pv = k === 'done' && canPreview(p);   /* a finish: its title, clicked, previews the whole message on the card */
    act.keys = ['gone'].concat(toApp ? ['app'] : [], k === 'ask' || k === 'done' ? ['card'] : [], pv ? ['preview'] : [], bs.map(function (b) { return b[0]; }));
    /* the cross to put it away at the left; actions at the right, the main one at the edge. A question's choices keep
       their order, 1 to 3, and shrink to fit; the recommended one, if any, is the bright one. */
    var choices = /^pick\d$/.test(bs[0][0]), list = choices ? bs : bs.slice().reverse();
    /* choices share one Command+Option, said once, so each keeps room for its words */
    /* The short project sits beside the camera; the session's longer title has the row below, before the buttons. A small
       cross at the left of the row puts it away (Command+Option+. does too). A chat with no project is named by its title
       alone, on top. */
    var split = p.topic && p.name !== p.topic;
    /* no key when Command+Option+O is Perch's own shortcut or another app holds it (Swift says, actNoKeys) */
    var openKey = actNoKeys.indexOf('app') < 0;
    var openB = opener ? '<button class="act-b act-o' + (openKey ? '' : ' nk') + '" data-a="app" title="' + esc(goLabel(p)) + '"><span class="act-bl">' + esc(goLabel(p)) + '</span>' + (openKey ? '<kbd>' + CMDOPT + 'O</kbd>' : '') + '</button>' : '';
    var btns = (!bs.some(function (b) { return b[0] === 'pick'; }) ? '' : '<button class="act-b act-x" data-a="gone" aria-label="Dismiss" title="Dismiss (\u2318\u2325.)">' + svg('x', 'size-3') + '</button>') +
      (choices ? '<span class="act-mod">' + CMDOPT + '</span>' : split ? '<span dir="auto" class="act-p' + (pv ? ' act-pv" data-a="preview' : '') + '"><span class="mq-in">' + esc(p.topic) + '</span></span>' : '<span class="act-gap"></span>') +
      list.map(function (b, i) {
        var main = choices ? !!b[3] : i === list.length - 1;
        /* a choice leads with its number, as on the card; an action ends with its keys */
        var label = '<span class="act-bl">' + esc(b[1]) + '</span>', key = '<kbd>' + (choices ? '' : b[0] === 'reply' ? '\u2318' : CMDOPT) + b[2] + '</kbd>';
        return '<button class="act-b' + (main ? ' go' : '') + (choices ? ' ch' : '') + '" data-a="' + b[0] + '" title="' + esc(b[1]) + '">' + (choices ? key + label : label + key) + '</button>';
      }).join('');
    /* after the choices at the right edge; before the actions, whose main one keeps the edge */
    if (openB) btns = choices ? btns + openB : btns.replace(/(<button class="act-b(?! act-x)[^"]*" data-a="(?:allow|deny|open|pick\d)")/, openB + '$1');
    var html = '<span class="act-l">' + AppOf(p, 'size-[15px]') + '<span dir="auto" class="act-n' + (pv && !split ? ' act-pv" data-a="preview' : '') + '"><span class="mq-in">' + esc(split ? p.name : p.topic || p.name) + '</span></span></span>' +
      '<span class="act-r"><span class="act-s' + (k === 'done' ? ' ok' : '') + '">' + esc(actWords(p, k)) + '</span>' + MARK[k] + '</span>' +
      (body ? '<div class="act-body' + bodyCls + '">' + body + '</div>' : '') + '<div class="act-btns">' + btns + '</div>';
    /* drawn again only when it changes, so a name gliding along is not cut short by a refresh */
    if (actEl._h !== html) { actEl.innerHTML = html; actEl._h = html; }
    /* what a hovered choice says comes and goes on its own: drawing the row again would replay the buttons' entrance, the
       row would slide under the pointer, and the choice it passed would open it again */
    var ex = actExtra(p, k), had = actEl.querySelector('.act-ex');
    if (!ex) { if (had) had.remove(); }
    else if (!had || had._h !== ex) {
      var t = document.createElement('div'); t.innerHTML = ex; var el = t.firstChild; el._h = ex; el.style.transition = 'none';
      if (had) actEl.replaceChild(el, had); else actEl.insertBefore(el, actEl.querySelector('.act-body, .act-btns'));
    }
    actEl._for = p.id;
    markAct();
    actGlide();
  }
  /* An update of Perch itself, in the same notch. It downloads in the background: only the character beside the camera and a ring that
     fills on the other side. When it is ready and you are busy it waits there, the ring a green check (Settings has Restart to update).
     When it restarts, the row says Updating. Back on the new version the character pops out and says so, then the notch tells you
     the headline of what is new. All of it folds away by itself. */
  function haze(c) { return glow(c); }   /* apply() has its own `glow` */
  var UPD_C = 59.7;   /* the ring's circumference, 2 pi r with r 9.5 */
  function updRing(frac, c) {
    c = c || 'size-4';
    return '<svg class="' + c + ' flex-none" viewBox="0 0 24 24" fill="none" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="' + glow(COLORS.running) + '"><circle cx="12" cy="12" r="9.5" stroke="rgba(255,255,255,.14)"/>' +
      '<circle class="upd-arc" cx="12" cy="12" r="9.5" stroke="' + COLORS.running + '" stroke-dasharray="' + UPD_C + '" stroke-dashoffset="' + UPD_C * (1 - frac) + '" transform="rotate(-90 12 12)"/>' +
      '<path d="M12 7.8v6.6M9.2 11.8l2.8 2.8 2.8-2.8" stroke="' + COLORS.running + '"/></svg>';
  }
  function renderUpd(u) {
    var ph = u.phase, notes = !!u.notesOpen, bullets = u.bullets || [];
    var words = { checking: 'Checking', available: 'Available', downloading: 'Downloading', ready: 'Ready to restart', restarting: 'Updating', updated: 'Updated', current: 'Up to date', failed: u.during === 'update' ? 'Couldn\u2019t update' : 'Couldn\u2019t check' }[ph];
    var mark = ph === 'restarting' || ph === 'checking' ? Spinner('size-4', glow(COLORS.running)) : ph === 'downloading' ? updRing(u.progress || 0) : ph === 'available' ? Ring('down') : ph === 'failed' ? Ring('need') : Ring('done');
    /* the headline of what is new; What's new opens the few lines behind it, right here in the notch */
    var body = '';
    if (ph === 'available' && (u.notes || bullets.length)) {
      body = notes && bullets.length
        ? '<div class="act-body tall" data-h="' + (Math.min(bullets.length, 6) * 19 + 8) + '" style="height:' + (Math.min(bullets.length, 6) * 19 + 8) + 'px">' + bullets.map(function (b) { return '<span dir="auto" class="act-li"><i></i>' + esc(b) + '</span>'; }).join('') + '</div>'
        : '<div class="act-body"><span dir="auto" class="act-t">' + esc(u.notes) + '</span></div>';
    }
    /* it could not: one line on why and what to do, and the way to do it */
    if (ph === 'failed' && u.problem) body = '<div class="act-body fail" data-h="32"><span dir="auto" class="act-t">' + esc(u.problem) + '</span></div>';
    /* buttons are for the mouse: the notch never takes the keyboard when it opens by itself, so no keys to learn */
    var btn = function (a, label, main) { return '<button class="act-b' + (main ? ' go' : '') + ' nk" data-a="' + a + '"><span class="act-bl">' + label + '</span></button>'; };
    var btns = '', keys = ['gone'];
    if (ph === 'available') { keys = ['gone', 'notes', 'install']; btns = (notes ? '' : btn('notes', 'What\u2019s new')) + '<span class="act-gap"></span>' + btn('gone', 'Later') + btn('install', 'Update', true); }
    if (ph === 'failed' && u.problem) { keys = u.fix === 'none' ? ['gone'] : ['gone', u.fix === 'move' ? 'reveal' : 'retry']; btns = '<span class="act-gap"></span>' + (u.fix === 'none' ? btn('gone', 'Okay', true) : btn('gone', 'Later') + (u.fix === 'move' ? btn('reveal', 'Show in Finder', true) : btn('retry', 'Try again', true))); }
    act.keys = keys;
    /* the peek: Update available on one side, the version beside its mark on the other; no character */
    var peeking = act.mode === 'peek';
    if (peeking) { words = esc(u.version); body = ''; btns = ''; }
    var html = '<span class="act-l">' + (peeking ? '' : crHtml('', 15, shapeOf(charNow.shape), ph === 'restarting' ? 'sleep' : 'awake')) + '<span class="act-n"><span class="mq-in">' + (peeking ? 'Update available' : 'Perch ' + esc(u.version)) + '</span></span></span>' +
      '<span class="act-r"><span class="act-s ' + (peeking ? 'said' : ph === 'updated' || ph === 'current' ? 'ok' : 'mu') + '">' + words + '</span>' + mark + '</span>' + body + (btns ? '<div class="act-btns">' + btns + '</div>' : '');
    var key = html.replace(/stroke-dashoffset="[^"]*"/, '');   /* the ring moves in place, so it eases instead of snapping */
    if (actEl._h !== key) { actEl.innerHTML = html; actEl._h = key; }
    var arc = actEl.querySelector('.upd-arc'); if (arc) arc.style.strokeDashoffset = String(UPD_C * (1 - (u.progress || 0)));
    actGlide();
  }
  /* Accessibility Perch had, gone: an update signed another way (macOS ties the grant to the signature) or a switch turned off
     in System Settings. The notch says it once, at a quiet moment, in the same row as an update: the character, Needs access
     in orange, one line on what waits, and Allow for the mouse (it opens by itself, so no keys). Allow clears the stale switch
     and opens System Settings; the row waits there until the switch is on, says Allowed and folds away. */
  function accP(a) { return { id: 'perch-access', name: 'Perch', topic: 'Perch', app: 'perch', access: a, status: { kind: 'idle', text: 'Accessibility', app: 'perch' } }; }
  function renderAccess(a) {
    var ph = a.phase;
    var words = { lost: 'Needs access', asked: 'Turn it on', granted: 'Allowed' }[ph];
    var mark = ph === 'granted' ? Ring('done') : ph === 'asked' ? Spinner('size-4', glow(COLORS.running)) : Ring('need');
    var line = ph === 'lost' ? (a.afterUpdate ? 'macOS asks again after an update. Command+Option and replies wait.' : 'Accessibility is off. Command+Option and replies wait until it is on.')
      : ph === 'asked' ? 'In macOS\u2019s prompt, choose Open System Settings.' : '';
    var btn = function (x, label, main) { return '<button class="act-b' + (main ? ' go' : '') + ' nk" data-a="' + x + '"><span class="act-bl">' + label + '</span></button>'; };
    var btns = '', keys = ['gone'];
    if (ph === 'lost') { keys = ['gone', 'axallow']; btns = '<span class="act-gap"></span>' + btn('gone', 'Later') + btn('axallow', 'Allow', true); }
    if (ph === 'asked') { keys = ['gone', 'axallow']; btns = '<span class="act-gap"></span>' + btn('gone', 'Later') + btn('axallow', 'Open System Settings'); }
    act.keys = keys;
    var html = '<span class="act-l">' + crHtml('', 15, shapeOf(charNow.shape), 'awake') + '<span class="act-n"><span class="mq-in">Perch</span></span></span>' +
      '<span class="act-r"><span class="act-s' + (ph === 'granted' ? ' ok' : ph === 'asked' ? ' mu' : '') + '">' + words + '</span>' + mark + '</span>' +
      (line ? '<div class="act-body fail" data-h="32"><span dir="auto" class="act-t">' + esc(line) + '</span></div>' : '') + (btns ? '<div class="act-btns">' + btns + '</div>' : '');
    if (actEl._h !== html) { actEl.innerHTML = html; actEl._h = html; }
    actGlide();
  }
  /* A name that does not fit, beside the camera or on the row below, reads itself out as a list row does: after a moment it
     glides to its end, rests, and comes back. Started again only when the words change, so a refresh does not restart it. */
  var actGlides = [], actGlideFor = '';
  function actGlide() {
    var key = act.mode + '|' + actEl._h;
    if (key === actGlideFor && actGlides.length) return;
    actGlides.forEach(function (a) { a.cancel(); }); actGlides = []; actGlideFor = key;
    actEl.querySelectorAll('.mq-on').forEach(function (b) { b.classList.remove('mq-on', 'mq-rtl'); });
    if (act.mode !== 'full' || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) return;
    var tries = 0, was = '';
    setTimeout(function start() {
      if (actGlideFor !== key) return;
      /* measured once the notch has stopped growing: mid-grow a box is a sliver, and a glide sized to it runs the
         whole name out of sight. Two readings in a row that agree mean it has settled. */
      var boxes = actEl.querySelectorAll('.act-n, .act-p'), now = [].map.call(boxes, function (b) { return b.clientWidth; }).join();
      var settled = now === was && [].every.call(boxes, function (b) { return b.clientWidth > 40; });
      was = now;
      if (!settled) { if (++tries < 12) setTimeout(start, 200); return; }
      actEl.querySelectorAll('.act-n, .act-p').forEach(function (box) {
        var inner = box.querySelector('.mq-in'), over = box.scrollWidth - box.clientWidth;
        if (!inner || over < 4) return;
        var rtl = getComputedStyle(box).direction === 'rtl'; over += 14;   /* clear of the fade at the far edge */
        box.classList.add('mq-on'); if (rtl) box.classList.add('mq-rtl');
        var lead = 500, go = over / 45 * 1000, rest = 1600, back = 600, wait = 1400, all = lead + go + rest + back + wait;
        var at = function (ms) { return ms / all; }, x = function (v) { return { transform: 'translateX(' + (rtl ? -v : v) + 'px)' }; };
        actGlides.push(inner.animate([
          Object.assign(x(0), { offset: 0 }), Object.assign(x(0), { offset: at(lead), easing: 'cubic-bezier(.45,0,.55,1)' }), Object.assign(x(-over), { offset: at(lead + go) }),
          Object.assign(x(-over), { offset: at(lead + go + rest), easing: 'cubic-bezier(.4,0,.2,1)' }), Object.assign(x(0), { offset: at(lead + go + rest + back) }), Object.assign(x(0), { offset: 1 })
        ], { duration: all, iterations: Infinity }));
        actGlides.push(box.animate([
          { '--mql': '0px', offset: 0 }, { '--mql': '0px', offset: at(lead) }, { '--mql': '12px', offset: at(lead + Math.min(300, go)) },
          { '--mql': '12px', offset: at(lead + go + rest) }, { '--mql': '0px', offset: at(lead + go + rest + back) }, { '--mql': '0px', offset: 1 }
        ], { duration: all, iterations: Infinity }));
      });
    }, 900);   /* the notch grows for about this long */
  }
  /* the size follows what it says: both sides as wide as the wider one, so the camera stays in the middle */
  function actSize(idleW, idleH) {
    if (act.mode === 'wings') return [idleW + 56, idleH];
    actEl.style.setProperty('--aw', '999px');   /* measured at full length, before anything is cut short */
    var l = actEl.querySelector('.act-l'), r = actEl.querySelector('.act-r'), bb = actEl.querySelector('.act-btns');
    var side = Math.max(l ? l.scrollWidth : 0, r ? r.scrollWidth : 0) + 26;
    if (act.mode === 'sent') return [Math.ceil(Math.min(480, Math.max(idleW + 2 * side, idleW + 150)) / 2) * 2, idleH];   /* one line: what it was about, and that it went; as wide as the panel at most, so Confirm in Claude fits */
    if (act.mode === 'peek') return [Math.ceil(Math.max(idleW + 2 * side, idleW + 120) / 2) * 2, idleH];   /* an update found by itself: one line, as wide as the version */
    var bw = 0; if (bb) { bb.style.width = 'max-content'; bw = bb.offsetWidth + 28; bb.style.width = ''; }
    /* an even width: centred in the panel, an odd one puts everything in it on a half pixel, and a turning spinner wobbles there */
    var even = function (x) { return Math.ceil(x / 2) * 2; };
    var w = even(Math.min(460, Math.max(idleW + 2 * side, idleW + 150, bw)));   /* the panel is 480 wide */
    if (!actEl.querySelector('.act-btns')) return [even(Math.min(460, Math.max(idleW + 2 * side, idleW + 150))), idleH];   /* an update restarting: just the row */
    var bd = actEl.querySelector('.act-body');
    if (bd && bd.classList.contains('askq')) {
      /* as tall as the question is at this width (a line is 18px), up to five lines; past that it scrolls */
      var mq = bd.cloneNode(true); mq.style.cssText = 'position:absolute;visibility:hidden;left:0;top:0;height:auto;transform:none;width:' + (w - 26) + 'px';
      actEl.appendChild(mq); var qh = Math.min(96, Math.max(24, mq.offsetHeight + 4)); actEl.removeChild(mq);
      bd.dataset.h = String(qh); bd.style.height = (qh - 2) + 'px';
    }
    var base = idleH + (bd ? +bd.dataset.h || 24 : 0) + 44, ex = actEl.querySelector('.act-ex');
    /* the buttons hang from the top while there is more below them, so the notch growing does not carry them down */
    bb.style.bottom = 'auto'; bb.style.top = (base - 35) + 'px';   /* always from the top: a note going away does not carry them up and back on the spring */
    if (ex) {
      /* as tall as its words are at this width, up to a point */
      var m = ex.cloneNode(true); m.style.cssText = 'position:absolute;visibility:hidden;left:0;top:0;width:' + (w - 26) + 'px';
      actEl.appendChild(m); var eh = Math.min(96, m.offsetHeight); actEl.removeChild(m);
      ex.style.top = (base - 3) + 'px'; ex.style.maxHeight = eh + 'px';
      return [w, base + eh + 6];
    }
    return [w, base];
  }
  /* in the wings the icon and the mark sit centred beside the camera; open, the words reach to the edges */
  function placeAct(idleW, idleH, w) {
    var wing = (w - idleW) / 2, side = act.mode === 'wings' ? Math.round(wing / 2 - 7.5) : 13;
    /* each side's words (with the icon or mark, 22px) end 8px short of the camera, never under it */
    actEl.style.setProperty('--as', side + 'px'); actEl.style.setProperty('--ah', idleH + 'px'); actEl.style.setProperty('--aw', Math.max(0, wing - 13 - 8 - 22) + 'px');
  }
  function setAct(mode, p, quiet) {
    var kind = p ? actKind(p) : '', next = p ? mode : '';
    var same = act.mode === next && act.p && p && act.p.id === p.id && act.kind === kind && JSON.stringify(act.p) === JSON.stringify(p);
    act = { mode: next, p: p || act.p, kind: kind || act.kind, keys: act.keys };
    if (!same) renderAct();
    if (!next) actHeld = false;
    if (!quiet && snap) layout(lastSt, snap);
  }
  /* the session you are in, or one of the sessions that may be it when Swift cannot tell which one of an app's is in front */
  function inside(s, id) { return s.activeId === id || (s.activeIds || []).indexOf(id) >= 0; }
  /* a session that stopped on an error has nothing to answer: it says so once, and does not stay as wings */
  function actErr(p) { return !p.ask && p.status.kind === 'attention' && /error/.test(p.status.text); }
  /* a build that is not a release says so: a narrow black tab hangs under the notch (or the card) with TEST BUILD, the branch and
     the commit. Only while the notch is hovered or open or the character peeks out (input.css decides); the rest of the time it is away. */
  n.insertAdjacentHTML('beforeend', '<div class="tb" aria-hidden="true"><b>TEST BUILD</b><span></span></div>');   /* inside the notch: it grows and shrinks with it */
  var tbEl = q('.tb'), tbText = '';
  function testTag(s) {
    var t = s.testBuild || '';
    if (t !== tbText) { tbText = t; tbEl.children[1].textContent = t.replace(/^claude\//, ''); }
    tbEl.hidden = !t;
  }
  /* A question that goes unanswered does not wait in the wings for ever: it said its piece (nine seconds in full, then a minute
     as wings) and goes away. It stays in the list and on its card; only the notch stops pointing at it. The same for a session
     Perch only guesses is waiting on you (its last message ends in a question, no request open): nothing is stopped on it, and an
     hour-old guess would hang there as a ! for ever. A command that needs your OK, or a plan, still waits until answered: the agent
     is stopped on it. */
  var actSeen = {}, actExpTimer = 0, ACT_Q_MS = 69000;   /* nine seconds in full, then the setting's seconds as wings (Swift sends it as questionSeconds) */
  /* Settings > Notify me about: the kinds the notch may announce. Turning one off only stops the live activity (the full row and the
     wings); the list, the cards, the status rings and the welcome card keep saying everything. Swift sends the kinds that are off. */
  var NOTIFY = [['done', 'Finished'], ['run', 'Needs your OK'], ['ask', 'Asked you something'], ['plan', 'Has a plan'], ['error', 'Stopped on an error']];
  /* the row's own marks, Lucide icons as they are (lucide.dev, ISC), each in a colour of its own */
  var NMARK = {
    done: ['<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>', COLORS.done],
    run: ['<path d="m7 11 2-2-2-2"/><path d="M11 13h4"/><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/>', COLORS.attention],
    ask: ['<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>', COLORS.attention],
    plan: ['<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M12 11h4"/><path d="M12 16h4"/><path d="M8 11h.01"/><path d="M8 16h.01"/>', '#B7A3F0'],
    error: ['<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>', '#F08A8A'],
    ci: [PRI.open, COLORS.attention]
  };
  /* Checks failing is a moment only while PR checks is on: nothing else knows when a check fails */
  function notifyList(o) { return NOTIFY.concat([['ci', 'Checks failing']]); }
  function ciOff(o) { return !(o.prs === 'on' && o.showPRs !== false); }
  /* the same marks in the text colour, for the icon group: one quiet colour instead of six */
  function nCol(k) { return '<svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="' + NMARK[k][1] + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + NMARK[k][0] + '</svg>'; }
  function nMark(k) {
    var m = NMARK[k];
    return '<svg class="size-4 flex-none" viewBox="0 0 24 24" fill="none" stroke="' + m[1] + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="' + glow(m[1]) + '" aria-hidden="true">' + m[0] + '</svg>';
  }
  function notifyKind(p) { var k = actKind(p); return p.ci && !p.ask ? 'ci' : actErr(p) ? 'error' : k === 'need' ? 'ask' : k; }   /* a guessed wait, with no request open, is a question */
  function muted(s, p) { return (s.notifyOff || []).indexOf(notifyKind(p)) >= 0; }
  function blocking(p) { return !!p.ask && (p.ask.kind === 'permission' || p.ask.kind === 'plan'); }
  function actExpired(p) {
    if (blocking(p)) return false;
    var k = actKey(p), t = actSeen[k] || (actSeen[k] = Date.now());
    return Date.now() - t > ACT_Q_MS;
  }
  function waiting(s) {
    var list = s.projects.filter(function (p) { return !inside(s, p.id) && p.attention && !actErr(p) && !actGone[actKey(p)] && !muted(s, p) && !actExpired(p); });
    /* wake when the soonest question runs out, so the wings go without waiting for the next snapshot */
    var left = list.filter(function (p) { return !blocking(p); }).map(function (p) { return ACT_Q_MS - (Date.now() - actSeen[actKey(p)]); });
    clearTimeout(actExpTimer);
    if (left.length) actExpTimer = setTimeout(function () { if (act.mode === 'wings' && snap) actSettle(); }, Math.min.apply(null, left) + 50);
    return list;
  }
  var updTok = 0;
  var updNotes = false;   /* What's new open */
  var updOpen = false;    /* the peek was clicked open into the row */
  function updP(u) { return { id: 'perch-update', name: 'Perch', topic: 'Perch ' + u.version, app: 'perch', update: Object.assign({}, u, { notesOpen: updNotes }), status: { kind: 'idle', text: 'Perch ' + u.version, app: 'perch' } }; }
  function actLater(ms) { clearTimeout(actTimer); actTimer = setTimeout(function () { if (!actHeld) actSettle(); }, ms); }
  function activity(s, st) {
    ACT_Q_MS = 9000 + 1000 * (s.questionSeconds || 60);
    var others = s.projects.filter(function (p) { return !inside(s, p.id); });
    var need = waiting(s), done = others.filter(function (p) { return p.status.kind === 'done' && p.fresh && !actGone[actKey(p)] && !muted(s, p); });
    var errs = others.filter(function (p) { return actErr(p) && !actGone[actKey(p)] && !muted(s, p); }), heard = need.concat(errs);
    /* What is remembered does not depend on which sessions you are in: that guess can flicker (a reading goes stale while a card is
       up), and a finish that dropped out of the list for a moment would land again. Only what is said is left out for the ones you are in. */
    /* A request answered or put away stays away while it stands. Once it is settled (that session has moved on), the same
       request asked again is news: the same command a second time must not pass in silence. Finishes and errors keep theirs. */
    Object.keys(actGone).forEach(function (k) {
      var bits = k.split('|'); if (['run', 'ask', 'plan'].indexOf(bits[1]) < 0) return;
      var p = s.projects.filter(function (x) { return x.id === bits[0]; })[0];
      if (p && actKey(p) !== k) delete actGone[k];
    });
    /* the same for when a question was first seen, which runs out its time on the notch (actExpired) */
    Object.keys(actSeen).forEach(function (k) {
      var id = k.split('|')[0], p = id !== 'update' && s.projects.filter(function (x) { return x.id === id; })[0];
      if (p && actKey(p) !== k) delete actSeen[k];
    });
    var everyDone = s.projects.filter(function (p) { return p.status.kind === 'done' && p.fresh && !actGone[actKey(p)]; });
    var everyHeard = s.projects.filter(function (p) { return ((p.attention && !actErr(p)) || actErr(p)) && !actGone[actKey(p)]; });
    var now = { need: everyHeard.map(actKey), done: everyDone.map(function (p) { return p.id; }) };
    var known = actKnown; actKnown = now;
    if (st !== 'idle') { clearTimeout(actTimer); clearTimeout(sentT); sent = null; sentBase = null; setAct('', null, true); return; }   /* the card is up: it says all of this */
    /* an answer just given on the card: the card closes into the line that says it went */
    if (sentNext && Date.now() - sentNext.at < 3000) { var sn = sentNext; sentNext = null; actGone[actKey(sn.p)] = 1; sentBase = known; sentShow(sn.p, sn.words, true, true, '', sn.pending, sn.asks); return; }
    sentNext = null;
    if (actPressing) return;   /* the choice you pressed is lighting up: the row folds in a moment, nothing else moves it */
    /* Perch's own update: downloading or waiting to restart it is only wings (and gives way to a session that needs you); restarting
       and arriving say their piece in the row */
    var u = s.update, up = u && updP(u), ukey = up && actKey(up);
    if (!u || u.phase !== 'available') updOpen = false;
    /* found by itself and peeked already (this version, or a Not now holds): the notch says nothing, the list's Update says it */
    var updList = !!(u && u.phase === 'available' && u.peek && u.listOnly && !updOpen);
    /* the timer of the phase before (the offer folding away) must not fold this one */
    if (u && act.p && act.p.update && act.p.update.phase !== u.phase) clearTimeout(actTimer);
    if (up && !s.quiet && !actGone[ukey] && !updList) {
      var showing = act.mode === 'full' && act.p && act.p.update && act.p.update.phase === u.phase && (u.phase !== 'failed' || act.p.update.problem === u.problem);   /* a failure that says something else is a new one */
      /* downloading: only the character and the ring. Downloaded: nothing on the notch, it restarts at a quiet moment (the list and Settings have Restart). */
      if (u.phase === 'downloading' && !need.length) { setAct('wings', up, true); return; }
      if (u.phase === 'restarting' || u.phase === 'checking') { clearTimeout(actTimer); setAct('full', up, true); return; }
      /* found by itself (a check on the schedule): it peeks first, one line for four seconds, and opens to the row only when you click
         it. A session waiting on you goes first: the peek waits until the notch is free. Once it folds, the list's Update says the rest. */
      if (u.phase === 'available' && u.peek && !updOpen) {
        if (!need.length) {
          var peeking = act.mode === 'peek' && act.p && act.p.update; setAct('peek', up, true);
          if (!peeking) { actLater(4000); post({ type: 'update', action: 'peeked' }); }   /* once per version: Swift remembers it */
          return;
        }
      } else if (u.phase === 'available') { setAct('full', up, true); if (!showing && !up.update.notesOpen) actLater(9000); return; }
      /* a small row that says it and goes: updated, up to date, could not check */
      if (u.phase === 'updated' || u.phase === 'current' || u.phase === 'failed') { setAct('full', up, true); if (!showing) actLater(u.phase === 'failed' ? (u.problem ? 9000 : 4500) : 3500); return; }
    }
    if (act.p && act.p.update && !(up && !s.quiet && !actGone[ukey] && !updList && u.phase !== 'ready')) { setAct('', null, true); }
    var arrived = known && heard.filter(function (p) { return known.need.indexOf(actKey(p)) < 0; })[0];
    var landed = known && done.filter(function (p) { return known.done.indexOf(p.id) < 0; })[0];
    /* it is saying an answer went: it says it to the end; what arrives meanwhile is said after it (sentDone) */
    if (act.mode === 'sent') return;
    /* Accessibility gone: said when nothing else is on the notch, and a session's news goes first. Once said (it folded, or
       Later) Swift stops sending it until it is lost again. Waiting for the switch it stays; Allowed folds away. */
    var ax = s.access, ap = ax && accP(ax), akey = ap && actKey(ap);
    var axShowing = act.mode === 'full' && act.p && act.p.access;
    if (ap && !s.quiet && !actGone[akey] && !arrived && !landed && (axShowing || !need.length) && (axShowing || act.mode !== 'full')) {
      var same = axShowing && act.p.access.phase === ax.phase;
      setAct('full', ap, true);
      if (!same) { clearTimeout(actTimer); if (ax.phase === 'lost') actLater(12000); else if (ax.phase === 'granted') actLater(3500); }
      return;
    }
    if (axShowing) { clearTimeout(actTimer); setAct(need.length ? 'wings' : '', need[0], true); }
    var full = act.mode === 'full' && act.p;
    /* you went to that session while it showed: it is the one you are in now, so it goes */
    if (full && inside(s, act.p.id)) {
      clearTimeout(actTimer); if (act.kind === 'done') post({ type: 'activitySeen', id: act.p.id });
      setAct(need.length ? 'wings' : '', need[0], true); return;
    }
    if ((arrived || landed) && !s.quiet) {
      setAct('full', arrived || landed, true); actLater(arrived ? 9000 : 6000);
    } else if (full && act.kind !== 'done' && !heard.some(function (p) { return p.id === act.p.id; })) {
      clearTimeout(actTimer); setAct(need.length ? 'wings' : '', need[0], true);   /* answered somewhere else while it showed */
    } else if (full) {
      var fresh = s.projects.filter(function (p) { return p.id === act.p.id; })[0]; if (fresh) setAct('full', fresh, true);
    } else setAct(need.length ? 'wings' : '', need[0], true);
  }
  /* it has said its piece: whatever still waits on you stays as wings */
  function actSettle() {
    if (!snap) return;
    if (act.p && act.p.access && act.p.access.phase === 'lost') post({ type: 'access', action: 'said' });
    if (act.p && (actErr(act.p) || act.p.update || act.p.access)) actGone[actKey(act.p)] = 1;   /* said once */
    var n2 = waiting(snap); setAct(n2.length ? 'wings' : '', n2[0]); }
  function actDo(a) {
    var p = act.p; if (!p || !act.mode || act.keys.indexOf(a) < 0) return;
    if (a === 'gone') {
      if (p.update) { updNotes = false; post({ type: 'update', action: 'later' }); }
      if (p.access) post({ type: 'access', action: 'said' });
      actGone[actKey(p)] = 1; clearTimeout(actTimer);
      if (act.kind === 'done') post({ type: 'activitySeen', id: p.id });
      actSettle(); return;
    }
    if (a === 'notes') { updNotes = !updNotes; clearTimeout(actTimer); if (snap && snap.update) setAct('full', updP(snap.update)); return; }
    if (a === 'reveal' || a === 'retry') { post({ type: 'update', action: a === 'reveal' ? 'reveal' : 'check' }); actGone[actKey(p)] = 1; clearTimeout(actTimer); setAct('', null); return; }
    if (a === 'axallow') { clearTimeout(actTimer); post({ type: 'access', action: 'allow' }); return; }   /* the row stays: it waits for the switch */
    if (a === 'install') { updNotes = false; post({ type: 'update', action: 'install' }); actGone[actKey(p)] = 1; clearTimeout(actTimer); setAct('', null); return; }
    var m = null;
    if (a === 'allow' || a === 'deny') m = { type: 'activityAnswer', id: p.id, choice: a };
    else if (/^pick\d$/.test(a)) { var qn = p.ask.questions[0], ans = {}; ans[qn.text] = qn.options[+a.slice(4) - 1]; m = { type: 'activityAnswer', id: p.id, answers: ans }; }
    else post({ type: a === 'pick' || a === 'app' ? 'activityPick' : 'activityOpen', id: p.id, reply: a === 'reply', preview: a === 'preview' });
    actGone[actKey(p)] = 1; clearTimeout(actTimer);
    if (!m) { setAct('', null); return; }
    /* an answer: the button you chose lights for a beat, then the row folds into the line that says it went */
    var b = actEl.querySelector('.act-btns [data-a="' + a + '"]'), calm = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    act.keys = []; actPressing = !!b && !calm; delete sentLate[p.id]; sentBase = actKnown;
    if (actPressing) { actEl.classList.add('chose'); b.classList.add('on'); }
    post(m);
    setTimeout(function () { actPressing = false; sentShow(p, sentWords(m)); }, actPressing ? 170 : 0);
  }
  /* An answer given from Perch says it went. The row folds to one line, the session on the left and what you chose on the
     right with a check, and goes after a moment (whatever still waits on you stays as wings). An answer on the card says
     the same as the card closes (sentNext). */
  var sent = null, sentNext = null, sentT = 0, SENT_MS = 2400, actPressing = false, sentN = 0;
  function sentWords() { return 'Sent'; }   /* a choice, several, Allow or Deny: the line says one thing, that it went */
  /* the mark that says it went: a paper plane, slightly tilted, in the blue the update ring uses. Lucide's send as it is
     (lucide.dev, ISC), no ring. It flies in from the lower left as if just thrown, overshoots a touch and settles. */
  var SENT_PLANE = '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/>';
  function SentMark() {
    return '<svg class="size-[15px] flex-none" viewBox="0 0 24 24" fill="none" stroke="' + COLORS.running + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="' + glow(COLORS.running) + '" aria-label="Sent">' + SENT_PLANE + '</svg>';
  }
  /* an answer on the card (here, or A and D, which Swift takes): once the card closes, the notch says it went (activity) */
  function noteAnswer(m) {
    var p = snap && snap.projects[snap.selected]; if (!p) return;
    delete sentLate[p.id]; sentNext = { p: p, words: sentWords(m), at: Date.now() };
  }
  /* Swift: a reply is on its way to the session in the background (typed into its terminal, or Claude's composer took it).
     Like an answer, the card closes into the line that says it went. */
  function replying(id) {
    var p = snap && snap.projects.filter(function (x) { return x.id === id; })[0]; if (!p) return;
    delete sentLate[p.id]; sentNext = { p: p, words: 'Sent', at: Date.now() };
  }
  /* Swift: it could not go in the background, so the session comes forward with the words to paste. The line was early:
     it goes without a word (the session in front, or Reply copied, says the rest). */
  function replyHanded(id) {
    if (sentNext && sentNext.p.id === id) sentNext = null;
    if (act.mode === 'sent' && act.p && act.p.id === id) { clearTimeout(sentT); sentDone(); }
  }
  /* Swift: that answer reached nothing (the request was settled or let go a moment before). The line says so, however far it got. */
  var sentLate = {};
  function notSent(id) {
    sentLate[id] = Date.now();
    if (act.mode === 'sent' && act.p && act.p.id === id && sent && sent.ok) sentShow(act.p, '', false);
  }
  function sentShow(p, words, ok, quiet, failWords, pending, asks) {
    if (ok !== false && Date.now() - (sentLate[p.id] || 0) < 3000) ok = false;
    if (ok === false) words = failWords || 'Didn\u2019t send';
    /* each answer is a line of its own (`n`), even for the same session with the same words; it folds out of the row only
       when that row is what shows now (`fold`), otherwise (a card closing, a row already put away) it is drawn afresh */
    sent = { words: words, ok: ok !== false, pending: !!pending && ok !== false, asks: !!asks, n: ++sentN, fold: (act.mode === 'full' || act.mode === 'sent') && !!act.p && act.p.id === p.id };
    clearTimeout(actTimer); clearTimeout(sentT);
    setAct('sent', p, quiet);
    /* already the line for this session: setAct leaves it be, so its words change here (renderSent draws each line once) */
    if (act.mode === 'sent') renderSent(act.p);
    /* a line still waiting (Starting) stays until it is told how it went; never longer than 20 s */
    sentT = setTimeout(sentDone, sent.asks ? 150000 : sent.pending ? 20000 : sent.ok ? SENT_MS : 4500);
  }
  /* The line has said its piece. Anything that arrived while it showed, or while the button lit before it (`sentBase` is what
     had been said when the answer was given), is said now, in full; whatever still waits on you stays as wings. */
  var sentBase = null;
  function sentDone() {
    sent = null; if (act.mode !== 'sent' || !snap) { sentBase = null; return; }
    if (sentBase) actKnown = sentBase;
    sentBase = null; setAct('', null, true); activity(snap, lastSt); layout(lastSt, snap);
  }
  function renderSent(p) {
    var right = '<span dir="auto" class="act-s' + (sent.asks ? '' : sent.pending ? ' mu' : sent.ok ? ' said' : '') + '">' + esc(sent.words) + '</span>' + (sent.asks ? Ring('need') : sent.pending ? Spinner('size-[15px]', glow(COLORS.running)) : sent.ok ? SentMark() : Ring('need'));
    var key = 'sent|' + sent.n;
    if (actEl._h === key) return;
    var r = actEl.querySelector('.act-r'), calm = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    /* the row it answered is still there: it folds in place, and only the right side changes. From a card that is closing,
       the notch is still shrinking to one line: the session fades in as it lands, and the words and the plane wait until it
       has settled (`lag`), or the plane would fly while nothing can be seen. */
    var lag = 0;
    if (sent.fold && r && actEl._for === p.id) r.innerHTML = right;
    else {
      actEl.innerHTML = '<span class="act-l">' + AppOf(p, 'size-[15px]') + '<span dir="auto" class="act-n"><span class="mq-in">' + esc(p.topic && p.name !== p.topic ? p.name : p.topic || p.name) + '</span></span></span><span class="act-r">' + right + '</span>';
      if (!calm) actEl.firstChild.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220, delay: 180, easing: 'ease-out', fill: 'backwards' });
      r = actEl.querySelector('.act-r'); lag = 300;
    }
    actEl._h = key; actEl._for = p.id; actEl.classList.remove('chose');
    if (calm) return;
    var w = r.querySelector('.act-s'), mark = r.querySelector('svg');
    if (w) w.animate([{ opacity: 0, transform: 'translateX(5px)', filter: 'blur(2px)' }, { opacity: 1, transform: 'none', filter: 'none' }], { duration: 260, delay: 140 + lag, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
    if (sent.pending && !sent.asks) return;
    if (!sent.ok || sent.asks) { mark.animate([{ opacity: 0, transform: 'scale(.4)' }, { opacity: 1, transform: 'scale(1.18)', offset: .6 }, { opacity: 1, transform: 'none' }], { duration: 420, delay: 200 + lag, easing: 'cubic-bezier(.3,1.4,.5,1)', fill: 'backwards' }); return; }
    mark.animate([{ opacity: 0, transform: 'translate(-7px, 7px) scale(.75)' }, { opacity: 1, transform: 'translate(1px, -1px)', offset: .7 }, { opacity: 1, transform: 'none' }], { duration: 480, delay: 200 + lag, easing: 'cubic-bezier(.2,.8,.3,1)', fill: 'backwards' });
  }
  actEl.addEventListener('click', function (e) {
    /* the peek opens into the update's row, with its headline and buttons */
    if (act.mode === 'peek' && act.p && act.p.update && snap && snap.update) { updOpen = true; clearTimeout(actTimer); setAct('full', updP(snap.update)); actLater(9000); return; }
    if (act.mode !== 'full') return;
    var b = e.target.closest('[data-a]'); if (b) actDo(b.dataset.a);
  });
  /* --activity: plays the three moments over your real sessions, in the real notch. Updates from Swift wait until it ends. */
  var actDemoOn = false, actDemoLast = null;
  function actDemo(tries) {
    if (actDemoOn) return;
    var s0 = snap, ps = s0 ? s0.projects.filter(function (p) { return !inside(s0, p.id); }) : [];
    /* right after launch the first scan may not be in yet */
    if (!ps.length || s0.phase !== 'idle') { if ((tries || 0) < 40) setTimeout(function () { actDemo((tries || 0) + 1); }, 500); return; }
    post({ type: 'log', text: 'activity demo over ' + ps.length + ' sessions' });
    actDemoOn = true; known = null;   /* no All clear for the request the demo starts after */
    var a = ps[0], b = ps[1] || a, c = ps[2] || a;
    var calm = s0.projects.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'running' ? x.status : { kind: 'idle', text: 'Finished', app: x.app } }); });
    var show = function (id, o) { apply(Object.assign({}, s0, { phase: 'idle', demo: true, quiet: false, projects: calm.map(function (x) { return x.id === id ? Object.assign({}, x, o) : x; }) })); };
    var ask = function (o) { return Object.assign({ status: { kind: 'attention', text: 'Claude needs you', app: 'claude' }, attention: true }, o); };
    show('', {});
    setTimeout(function () { show(a.id, { status: { kind: 'done', text: 'Claude finished', app: a.app }, fresh: true }); }, 800);
    setTimeout(function () { show(b.id, ask({ ask: { kind: 'permission', title: 'Claude wants to run a command', subject: 'npm run build && npm test', options: [], answerable: true } })); }, 8500);
    setTimeout(function () { show(c.id, ask({ ask: { kind: 'question', title: 'Claude asked you something', subject: 'Which layout should the hero use?', answerable: true,
      questions: [{ text: 'Which layout should the hero use?', header: 'Layout', multi: false, options: ['Centered', 'Split (Recommended)', 'Full bleed'], notes: ['', '', ''] }] } })); }, 21000);
    setTimeout(function () { actDemoOn = false; actKnown = null; known = null; actGone = {}; apply(actDemoLast || s0); actDemoLast = null; }, 33000);   /* no All clear for a pretend request */
  }
  /* The button (or question) under the pointer, from where the pointer is, as the list's row: WebKit's own hover stays on a
     button the pointer left when the panel was never clicked, so two lit at once. */
  function markAct() {
    var e = ptrAt[0] >= 0 && act.mode === 'full' ? document.elementFromPoint(ptrAt[0], ptrAt[1]) : null, t = e && e.closest && e.closest('.act-b, .act-q, .act-pv');
    if (t && !actEl.contains(t)) t = null;
    [].forEach.call(actEl.querySelectorAll('.pt'), function (x) { if (x !== t) x.classList.remove('pt'); });
    if (t) t.classList.add('pt');
  }
  /* resting the pointer on it holds it open; leaving gives it a moment more */
  actEl.addEventListener('mouseenter', function () { if (act.mode === 'full' || act.mode === 'peek') { actHeld = true; clearTimeout(actTimer); } });
  actEl.addEventListener('mouseleave', function () { if (actHeld) { actHeld = false; actLater(2500); } actMoreSet(null); [].forEach.call(actEl.querySelectorAll('.pt'), function (x) { x.classList.remove('pt'); }); });
  /* the pointer's moves reach here from WebKit, or from the page's own replay of them */
  actEl.addEventListener('mousemove', function (e) {
    if (act.mode === 'full' && act.kind === 'done' && e.target.closest) { actMoreSet(e.target.closest('.act-pv') ? { pv: 1 } : null); return; }
    if (act.mode !== 'full' || act.kind !== 'ask' || !e.target.closest) return;
    var qs = act.p.ask && act.p.ask.questions && act.p.ask.questions[0], ch = e.target.closest('.act-b.ch');
    if (e.target.closest('.act-q')) actMoreSet({ q: 1 });
    else if (ch && qs) {
      var i = +ch.dataset.a.replace('pick', '') - 1, l = ch.querySelector('.act-bl');
      if ((qs.notes && qs.notes[i]) || (l && l.scrollWidth > l.clientWidth + 1)) actMoreSet({ c: i }); else actMoreSet(null);
    } else actMoreSet(null);
  });
  /* it goes away a moment after the pointer leaves what it speaks for, so crossing from one choice to the next does not flicker */
  function actMoreSet(v) {
    clearTimeout(actMoreT);
    if (!v) { if (actMore) actMoreT = setTimeout(function () { actMore = null; renderAct(); if (snap) layout(lastSt, snap); }, 160); return; }
    if (actMore && JSON.stringify(actMore) === JSON.stringify(v)) return;
    actMore = v; renderAct(); if (snap) layout(lastSt, snap);
  }

  /* While the list or a card is open the notch cannot say it, so the update waits at the top left, beside the character (the right has the
     hardware notch's neighbour, Settings and the close, with no room): Update, a ring while it downloads, Restart when it is ready. */
  /* where the update stands, as one small thing for Settings' Updates row: Check for updates when there is nothing to say, then what is
     happening, then the button for what comes next */
  /* left of the row, only when the right is a button (or nothing): what the button is about. While it works or has answered, the right says it. */
  function updSub(s) {
    var u = s.update, ph = u ? u.phase : '', v = u ? esc(u.version) : '';
    return ph === 'available' ? v + ' is available' : ph === 'ready' ? v + ' is ready' : ph === 'failed' ? '<span style="color:' + COLORS.attention + '">' + esc(u.short || (u.during === 'update' ? 'couldn\u2019t update' : 'couldn\u2019t check')) + '</span>' : '';
  }
  function updSlot(s) {
    var u = s.update, ph = u ? u.phase : '';
    var chipB = function (label, tip) { return '<button title="' + esc(tip) + '" class="s-upd h-[22px] cursor-pointer rounded-md px-2 text-[11.5px] font-medium tracking-[-0.005em] transition-colors">' + label + '</button>'; };
    /* a mark and a few words, on the right, in the colour of what they say */
    var note = function (inner, words, c) { return '<span class="flex h-[22px] items-center justify-end gap-1.5 text-[12px]" style="color:' + c + '"><span class="grid size-4 flex-none place-items-center">' + inner + '</span>' + words + '</span>'; };
    if (ph === 'available') return chipB('Update', 'Perch ' + u.version + ' is available');
    if (ph === 'ready') return chipB('Restart to update', 'Perch ' + u.version + ' is downloaded. It installs and restarts Perch');
    if (ph === 'checking') return note(Spinner('size-3.5', haze(COLORS.running)), 'Checking', COLORS.running);
    if (ph === 'current') return note(Ring('done'), 'You have the latest version', COLORS.done);
    if (ph === 'downloading') return note(updRing(u.progress || 0, 'size-4'), 'Downloading ' + esc(u.version), COLORS.running);
    if (ph === 'restarting') return note(Spinner('size-3.5', haze(COLORS.running)), 'Updating', COLORS.running);
    /* the reason is said on the left (updSub): here only what to do about it */
    if (ph === 'failed' && u.fix === 'none') return '';
    if (ph === 'failed') return u.fix === 'move' ? Button('ghost', 'Show in Finder', '', 's-rev s-gr') : Button('ghost', 'Try again', '', 's-chk s-gr');
    return Button('ghost', 'Check for updates', '', 's-chk s-gr" title="Look for a newer version of Perch');
  }
  function bindUpdSlot(root, s) {
    var ph = s.update ? s.update.phase : '';
    var ub = root.querySelector('.s-upd'); if (ub) ub.onclick = function () { post({ type: 'update', action: ph === 'ready' ? 'restart' : 'install' }); };
    var cb = root.querySelector('.s-chk'); if (cb) cb.onclick = function () { post({ type: 'update', action: 'check' }); };
    var rb = root.querySelector('.s-rev'); if (rb) rb.onclick = function () { post({ type: 'update', action: 'reveal' }); };
  }
  var chipSig = '';
  function updChip(s, st) {
    var u = s.update, ph = u && u.phase, on = (st === 'open' || st === 'switch') && (ph === 'available' || ph === 'downloading' || ph === 'ready'), sig = on ? ph + Math.round((u.progress || 0) * 20) : '';
    if (sig === chipSig) return; chipSig = sig;
    document.querySelectorAll('.upd-chip').forEach(function (b) {
      b.classList.toggle('hidden', !on); b.classList.toggle('flex', on);
      if (!on) return;
      b.dataset.p = ph; b.title = ph === 'available' ? 'Perch ' + u.version + ' is available. Update now' : ph === 'ready' ? 'Perch ' + u.version + ' is downloaded. Restart to install it' : 'Downloading Perch ' + u.version;
      b.innerHTML = ph === 'downloading' ? updRing(u.progress || 0, 'size-[15px]') : (ph === 'available' ? 'Update' : 'Restart');
      b.style.cursor = ph === 'downloading' ? 'default' : '';
      b.onclick = function () { if (ph !== 'downloading') post({ type: 'update', action: ph === 'ready' ? 'restart' : 'install' }); };
    });
  }
  /* What is new, after an update. The card says it once: Perch and its version, the headline, then the few lines behind it (six show,
     the rest scroll). It opens by itself, so it takes no keys; Got it goes on to the list. */
  var wnSig = '';
  /* Got it. WebKit sometimes never turns a press and release into a click on this card, which opens by itself, often under
     a pointer resting on the notch; so Swift also passes on each release over the card (wnUp) and the page checks what is there. */
  /* Allow on the card, once however it arrives (a click, a release Swift passes on, or both) */
  var wnAxAt = 0;
  function wnAllow() { if (Date.now() - wnAxAt < 1500) return; wnAxAt = Date.now(); post({ type: 'access', action: 'allow' }); }
  q('.wn').addEventListener('click', function (e) { if (e.target.closest('.wn-ok')) post({ type: 'whatsnew', action: 'done' }); else if (e.target.closest('.wn-ax')) wnAllow(); });
  function wnUp(x, y) { var el = lastSt === 'new' && document.elementFromPoint(x, y); if (el && el.closest('.wn-ok')) post({ type: 'whatsnew', action: 'done' }); else if (el && el.closest('.wn-ax')) wnAllow(); }
  /* The update that lost Accessibility (a build signed another way) says so on its own What's new card, under the lines: one row
     with the orange ring, what waits, and Allow. Pressed, it waits for the switch in System Settings; on, it turns green. Got it
     stays the card's main button either way: Settings keeps the row for later. */
  function wnAccess(ax) {
    if (!ax) return '';
    var on = ax === 'granted', asked = ax === 'asked';
    var mark = on ? Ring('done') : asked ? Spinner('size-4', glow(COLORS.running)) : Ring('need');
    var title = on ? 'Accessibility is on' : asked ? 'Turn Perch on in System Settings' : 'Allow Accessibility again';
    var sub = on ? 'Command+Option and replies work again.' : asked ? 'Choose Open System Settings in macOS\u2019s prompt, then switch Perch on.' : 'macOS asks once more after this update. Until then Command+Option and replies wait.';
    return '<div class="wn-a rv mx-4 mt-2 flex items-center gap-2.5 rounded-lg bg-black/[0.18] py-2 pl-3 pr-2" style="--i:3">' + mark +
      '<div class="min-w-0 flex-1"><div class="text-[12.5px] font-medium leading-[17px]">' + title + '</div><div class="text-xs leading-4 text-muted-foreground">' + sub + '</div></div>' +
      (on ? '' : Button('ghost', asked ? 'Open' : 'Allow', '', 'wn-ax flex-none bg-white/[0.08] text-foreground')) + '</div>';
  }
  function whatsNew(w) {
    if (!w) return;
    var sig = JSON.stringify(w); if (sig === wnSig) return;
    /* only the Accessibility row changed (Allow pressed, the switch turned on): that row alone, the list keeps its scroll */
    var was = wnSig; wnSig = sig;
    var a0 = q('.wn-a'), bare = function (x) { var o = JSON.parse(x); delete o.access; return JSON.stringify(o); };
    if (was && a0 && w.access && bare(was) === bare(sig)) { a0.outerHTML = wnAccess(w.access); return; }
    var bl = w.bullets || [], rows = bl.filter(function (b) { return b !== w.headline; });
    /* the fade sits on a still wrapper, not on the list that scrolls: a mask on the scroller itself makes WebKit repaint it
       every frame of a scroll, and the lines judder behind the trackpad */
    var list = rows.length ? '<div class="wn-lw rv mx-4 mt-1.5 overflow-hidden rounded-lg bg-black/[0.18]" style="--i:2"><div class="wn-l o-said-in max-h-[150px] overflow-y-auto px-3 py-1.5">' + rows.map(function (b) {
      return '<div dir="auto" class="flex items-start gap-2 py-[3px] text-[12.5px] leading-[18px] text-foreground/80"><i class="mt-[8px] size-[3px] flex-none rounded-full bg-zinc-500"></i><span class="min-w-0">' + esc(b) + '</span></div>';
    }).join('') + '</div></div>' : '';
    q('.wn').innerHTML =
      header('<div class="truncate text-sm font-medium leading-4">What\u2019s new in Perch</div>', '<span class="flex-none text-xs tabular-nums text-muted-foreground">' + esc(w.version) + '</span>') +
      '<div dir="auto" class="rv px-4 pb-0.5 pt-1 text-[13.5px] font-medium leading-[19px] tracking-[-0.01em]" style="--i:1">' + esc(w.headline || 'Perch ' + w.version) + '</div>' + list + wnAccess(w.access) +
      '<div class="rv flex h-9 items-end justify-end px-2.5 pt-1" style="--i:' + (w.access ? 4 : 3) + '">' + Button('default', 'Got it', Kbd(CMDOPT + svg('enter', 'size-2'), 1), 'wn-ok h-7 rounded-lg pl-3 pr-1.5') + '</div>';
    var box = q('.wn-l'); if (box) box.parentNode.classList.toggle('ov', box.scrollHeight > box.clientHeight + 1);   /* a list that scrolls fades at its edges, as the expanded reply does */
  }
  function apply(s) {
    if (actDemoOn && !s.demo) { actDemoLast = s; return; }
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', onboarding: 'onb', settings: 'set', whatsnew: 'new', newSession: 'ns' }[s.phase];
    updChip(s, st);
    var p = s.projects[s.selected];
    if (st !== 'open') { snoozeMenu(false, true); replyMenu(false, true); previewMenu(false, true); }
    else if (previewOn && !canPreview(p)) previewMenu(false);
    /* a reply belongs to its session: if the card moved to another one under it, the reply closes (its words stay a draft) */
    else if (replyFor && p && p.id !== replyFor) replyMenu(false);
    else if (asking.typing && !(p && p.ask && asking.p && p.id === asking.p.id)) otherMenu(false);
    if (st !== 'open' && dropping) { dropping = 0; dropOpened = false; rIn.classList.remove('drop', 'on'); }
    if (p && !dropping) rIn.placeholder = replyHint();
    if (Date.now() - pickedAt > 1000) applyCharacter(s.character);
    if (st === 'onb') onb(s.onboarding); else { onbStep = -1; onbSig = ''; }
    if (st === 'new') whatsNew(s.whatsNew); else wnSig = '';
    if (st === 'set') {
      if (liveNext) { setPage = 'agents'; setSig = ''; }
      settingsApply(s.settings);
      if (liveNext) { liveNext = false; var lr = q('.set .s-sw[data-k=live]'); setFocus = [].indexOf.call(q('.set').querySelectorAll('.s-row'), lr && lr.closest('.s-row')); setKb = true; paintFocus(); setTimeout(flashLive, 300); }
    } else {
      /* the character picker and the shortcut recorder come back to the page and row they opened from; anywhere else,
         Settings starts again at the top of the list */
      if (st !== 'onb') { setPage = ''; setFocus = setRootAt = 0; if (fbState === 'sent') fbState = ''; }
      setSig = ''; setKb = true; setHot = -1;
    }
    var flipped = st === 'open' && lastSt === 'open' && p && cardId && p.id !== cardId;
    cardMove = st === 'open' && lastSt === 'open' && p ? (p.id !== cardId ? 'flip' : 'live') : '';
    if (p) { if (st === 'open' && lastSt === 'open') settleCard(function () { fill(p); }, p.id !== cardId); else fill(p); }
    cardMove = '';
    if (st !== 'open') orbFor('');
    if (flipped) setTimeout(function () { switched(p); }, 0);   /* after layout sets its face */
    cardId = st === 'open' && p ? p.id : null;
    moments(s, st);
    activity(s, st);
    testTag(s);
    if (st === 'switch') list(s); else { marquee(null); lastSel = -1; }
    if (st === 'ns') newApply(s.newSession || {}, !nw.on); else { if (nw.on) { var ka = nwAgent(), kf = nwFolder(); nw.kept = { app: ka.id, path: kf.path, none: !!kf.none }; } nw.on = false; nwDrop = 0; }
    /* Without Accessibility Perch cannot type for you: Send asks for it, then sends once it is on.
       A terminal session takes a reply without Accessibility: Perch types it into its tab. */
    var canSend = s.canSend !== false || !!(p && p.via);
    q('.x-send-l').textContent = canSend ? 'Send' : s.allowing ? 'Waiting for access' : 'Allow and send';
    /* while it waits there is nothing to press: no Return on it, and it steps back */
    q('.x-send kbd').style.display = !canSend && s.allowing ? 'none' : '';
    q('.x-send').style.opacity = !canSend && s.allowing ? '.6' : '';
    q('.x-send').title = canSend ? '' : s.allowing ? 'Choose Open System Settings in macOS\u2019s prompt, then switch Perch on. Your reply goes out as soon as it is on.'
      : 'Perch needs Accessibility to send for you. Allow it once and this reply goes out.';
    /* green only while a finished session is news, blue while it works; one you have already seen glows in the character's colour */
    var glow = { attention: ['233,168,119', '244,210,180'], done: ['140,207,164', '196,234,210'], running: ['141,200,232', '198,228,246'] };
    var gk = st === 'set' && Date.now() - fbGlow.at < 2600 ? glow[fbGlow.k] : st === 'open' && p && glow[p.status.kind] && !(p.status.kind === 'done' && p.fresh === false) ? glow[p.status.kind] : null, g = gk || ['245,184,59', '255,222,140'];
    n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    n.dataset.g = gk ? 'status' : 'char';
    n.dataset.run = st === 'open' && p && p.status.kind === 'running' ? '1' : '';   /* working: the light breathes (input.css) */
    var allDone = st === 'onb' && s.onboarding && s.onboarding.step === s.onboarding.total - 1;
    n.style.setProperty('--gcol', allDone ? COLORS.done : (st === 'onb' && introGlow) || charNow.color);
    var was = lastSt;
    if (st === 'idle' && was !== 'idle') hand(false);
    lastSt = st;
    /* the notch closed, or another session's card took its place, under a pointer resting on a PR mark: no leave comes, so its label would float on alone */
    var cardId = s.projects && s.projects[s.selected] ? s.projects[s.selected].id : null;
    if (st !== was || (st === 'open' && cardId !== prCard)) prNow();
    prCard = cardId;
    if (selOn || st !== 'open') selCheck();
    if (st === 'switch' && was !== 'switch') { listKb = true; keyPtr = ptrAt.slice(); ptrFresh = true; markList(); }   /* opened (by the hotkey too): the first row is lit, and a pointer resting over a row of it has not chosen that row */
    /* The panel moved to another display: it is there at once, at that display's size. Nothing grows or shrinks from the
       other display's notch, and nothing lingers on one that shows nothing at rest. A card opening there grows from its notch. */
    var sk = [s.screen.hasNotch, s.screen.notchW, s.screen.notchH].join('|');
    if (screenKey && sk !== screenKey) {
      scene.dataset.moved = '1';
      layout(was === 'idle' ? 'idle' : st, s);
      void n.offsetWidth; getComputedStyle(n, '::after').opacity;
      scene.dataset.moved = '';
    }
    screenKey = sk;
    layout(st, s);
    if (was !== st) drill(was, st, s);
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
    /* turning happy, it gives a little bounce as the smile comes up */
    if (m === 'happy' && wasMood !== 'happy' && !celebrating && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) {
      var up = 'cubic-bezier(.2,.8,.4,1)'; inner.style.transformOrigin = '50% 100%';
      inner.animate([{ transform: 'none', easing: up }, { transform: 'scale(1.1,.9)', offset: .22, easing: up }, { transform: 'translateY(-2.5px) scale(.95,1.07)', offset: .5, easing: 'cubic-bezier(.6,0,.8,.4)' },
        { transform: 'scale(1.04,.97)', offset: .76, easing: up }, { transform: 'none' }], { duration: 560 });
    }
    if (m !== 'peek') wasMood = m;
  }).observe(cr, { attributes: true, attributeFilter: ['data-m'] });
  /* ---- the character watches you move between sessions. In the list its eyes go to the row you are on, and when you stop there it blinks.
     Its face is that session's: wide-eyed if it needs you, with a start as you arrive, a happy squint if it finished.
     Typing a filter, it reads along; flipping cards, its eyes go to the new title. A held arrow only moves its eyes. ---- */
  var fxPlay = 0, switchFx = 'watch', fxAt = 0, fxBlink = 0, fxMood = '', fxTyped = '';
  /* Measured in the card, from where the character sits in its corner (layout), so it aims right even while the card
     and the character are still moving into place. */
  function lookAt(el, along) {
    var pane = el.closest('.pane'); if (!pane || !snap) return;
    var scr = snap.screen, idleH = !scr.hasNotch ? Math.min(scr.notchH || 24, 28) : scr.notchH;
    var r = el.getBoundingClientRect(), pr = pane.getBoundingClientRect(), dx = r.left - pr.left + Math.min(along, r.width / 2) - 26,
        dy = r.top - pr.top + r.height / 2 - idleH / 2, d = Math.max(1, Math.hypot(dx, dy));
    tracking = true; clearTimeout(trackTimer); trackTimer = setTimeout(function () { tracking = false; }, 1600);
    look(dx / d * 2.6, dy / d * 2.2);
  }
  function switched(p, row) {
    if (switchFx !== 'watch' || celebrating || hello) return;
    var now = Date.now(), held = now - fxAt < 380; fxAt = now;
    var at = row ? row.querySelector('.nm') || row : q('.o-name');
    if (at) lookAt(at, 40);
    clearTimeout(fxBlink); fxBlink = setTimeout(function () { cr.classList.add('blink'); setTimeout(function () { cr.classList.remove('blink'); }, 110); }, 260);
    /* layout has already given it the session's face; arriving at one that needs you startles it */
    var mood = cr.dataset.m, startle = mood === 'alert' && fxMood !== 'alert'; fxMood = mood;
    if (startle && !held && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) {
      var ci = cr.querySelector('.cr-in'), up = 'cubic-bezier(.2,.8,.4,1)'; ci.style.transformOrigin = '50% 100%';
      ci.animate([{ transform: 'none', easing: up }, { transform: 'translateY(-4px) scale(.88,1.16)', offset: .24, easing: 'cubic-bezier(.6,0,.8,.4)' },
        { transform: 'scale(1.09,.92)', offset: .52, easing: up }, { transform: 'translateY(-1px) scale(.98,1.02)', offset: .76, easing: up }, { transform: 'none' }], { duration: 540 });
    }
  }

  /* ---- into a session's card from the list (Right, or a click on its row) and back (Left): the character leans in to
     look at the card, and leans back to the list. The panes keep their own quiet fade. ---- */
  var drillFx = true;
  function drill(from, to, s) {
    var going = from === 'switch' && to === 'open', back = from === 'open' && to === 'switch';
    if (!drillFx || celebrating || hello || (!going && !back)) return;
    var ci = cr.querySelector('.cr-in'), up = 'cubic-bezier(.2,.8,.4,1)', down = 'cubic-bezier(.6,0,.8,.4)';
    /* its eyes go first: to the card's title going in, to the row you came from going back */
    var at = going ? q('.o-name') : q('.p-switch .row[data-i="' + s.selected + '"] .nm');
    setTimeout(function () { if (at) lookAt(at, 40); }, 60);
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    ci.style.transformOrigin = '50% 100%';
    if (going) ci.animate([{ transform: 'none', easing: up }, { transform: 'translateY(1px) scale(1.1,.88)', offset: .18, easing: up },
      { transform: 'translate(1.5px,-3px) scale(.93,1.1) rotate(7deg)', offset: .48, easing: down },
      { transform: 'translateX(.5px) scale(1.05,.95) rotate(-2deg)', offset: .74, easing: up }, { transform: 'none' }], { duration: 640 });
    else ci.animate([{ transform: 'none', easing: up }, { transform: 'translate(-1px,-1px) scale(.95,1.06) rotate(-6deg)', offset: .36, easing: up },
      { transform: 'scale(1.04,.97) rotate(1.5deg)', offset: .7, easing: up }, { transform: 'none' }], { duration: 520 });
    setTimeout(function () { cr.classList.add('blink'); setTimeout(function () { cr.classList.remove('blink'); }, 110); }, going ? 560 : 440);
  }
  /* cursor position in page coordinates, sent by Swift from anywhere on screen */
  var trackTimer = null;
  /* A card opened by hovering gets no pointer moves from WebKit until it is clicked: the pointer was already over it.
     Swift sends where the pointer is anyway (cursor, below). While no real moves arrive, what is under it is marked .hv,
     which every hover style also answers to, and mouseenter and mouseleave play as a real pointer would make them. */
  var hvEls = [], realMoveAt = 0;
  /* Where the pointer is, and where it was at the last arrow key. A row that slides or is redrawn under a still pointer gets a
     mouseenter too (here and from WebKit); that must not pull the keyboard's choice back to the pointer. Only a pointer that moved does. */
  var ptrAt = [-1, -1], keyPtr = null;
  /* Just opened: where the pointer was is from the last time anything showed, so the first place it is reported is where it
     rests, not a move. Without this, a list opening under a resting pointer lit the row beneath it instead of the top one. */
  var ptrFresh = false;
  function ptrSeen(x, y) { if (ptrFresh) { ptrFresh = false; keyPtr = [x, y]; } ptrAt = [x, y]; }
  function ptrMoved() { return !keyPtr || keyPtr[0] !== ptrAt[0] || keyPtr[1] !== ptrAt[1]; }
  /* The pointer is sampled, not followed: a quick pass skips rows, and a skipped row never gets its mouseenter. Walk the
     line from the last sample to this one and give each list or settings row it crossed a brief flash (.crossed, in input.css),
     on in a frame and fading out, so every row the pointer went over shows it. Only looks; the choice stays with the row it stops on. */
  var swAt = null, swT = 0;
  function sweep(x, y) {
    var p = swAt, now = Date.now(); swAt = [x, y];
    if (!p || now - swT > 120) { swT = now; return; }
    swT = now;
    var dx = x - p[0], dy = y - p[1], n = Math.floor(Math.hypot(dx, dy) / 6), last = null;
    for (var i = 1; i < n; i++) {
      var el = document.elementFromPoint(p[0] + dx * i / n, p[1] + dy * i / n), r = el && el.closest && el.closest('.row, .s-row');
      if (r) last = r;
      if (r && !r.classList.contains('crossed')) { r.classList.add('crossed'); setTimeout(function (r) { r.classList.remove('crossed'); }.bind(null, r), 30); }
    }
    /* A pointer that leaves the rows within one step (out of the card, or up to the notch) never entered the last row it
       crossed: its choice would stay on an earlier one. The last row it went over is the one it left from. */
    var end = document.elementFromPoint(x, y);
    if (last && !(end && end.closest && end.closest('.row, .s-row'))) last.dispatchEvent(new MouseEvent('mouseenter'));
  }
  document.addEventListener('mousemove', function (e) { if (e.isTrusted) { ptrSeen(e.clientX, e.clientY); sweep(e.clientX, e.clientY); if (lastSt === 'switch') markList(); if (lastSt === 'open') markChoice(); if (act.mode) markAct(); realMoveAt = Date.now(); if (hvEls.length) hoverAt(-1, -1); } }, true);
  function hoverAt(x, y) {
    var el = x < 0 ? null : document.elementFromPoint(x, y), chain = [];
    for (var c = el; c && c !== document.documentElement; c = c.parentElement) chain.push(c);
    hvEls.forEach(function (c) { if (chain.indexOf(c) < 0) { c.classList.remove('hv'); c.dispatchEvent(new MouseEvent('mouseleave')); } });
    chain.slice().reverse().forEach(function (c) { if (hvEls.indexOf(c) < 0) { c.classList.add('hv'); c.dispatchEvent(new MouseEvent('mouseenter')); } });
    hvEls = chain;
    if (el) el.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: x, clientY: y }));
    var cur = el ? getComputedStyle(el).cursor : '';
    hand(cur === 'pointer', cur === 'text');
  }
  /* WebKit shows the hand only on a card with the keyboard; on one without, Swift shows it when the page says */
  var handOn = false, beamOn = false;
  function hand(on, text) { text = !on && !!text; if (on !== handOn || text !== beamOn) { handOn = on; beamOn = text; post({ type: 'hand', on: on, text: text }); } }
  /* Words selected on the card: Swift keeps the card open while they are (it would close as the pointer leaves, or when its
     time is up) and sends Command+C to them. A selection on words no longer showing (the reply closed) or in the reply
     field does not count, and goes when the card closes. */
  var selOn = false;
  function selCheck() {
    var s = window.getSelection(), node = s && s.rangeCount && !s.isCollapsed ? s.anchorNode : null;
    var el = node && (node.nodeType === 1 ? node : node.parentElement);
    var on = !!(el && lastSt === 'open' && document.activeElement !== rIn && q('.p-open').contains(el) && el.getClientRects().length && String(s).trim());
    if (!on && node && (lastSt !== 'open' || !el.getClientRects().length)) s.removeAllRanges();
    if (on !== selOn) { selOn = on; post({ type: 'selected', on: on }); }
    hlDraw();
    if (saidLater && (!s || s.isCollapsed) && repOn) showSaid(true);
  }
  document.addEventListener('selectionchange', selCheck);
  document.addEventListener('mouseleave', function () { chPill.classList.remove('on'); });
  /* The selection, drawn (input.css .hl): one rounded piece per line, from the selected words' own boxes, cut to what shows of
     them (the reply's scroll, a table's window, a clamped line), fading in as a drag reaches each line. The system's
     highlight stays underneath, hidden, and is what gets copied. */
  var hlLayer = document.createElement('div'); hlLayer.className = 'hl'; hlLayer.setAttribute('aria-hidden', 'true'); q('.p-open').appendChild(hlLayer);
  function hlDraw() {
    var s = window.getSelection(), lines = [];
    if (selOn && document.documentElement.dataset.hl !== 'native' && s.rangeCount) {
      var r = s.getRangeAt(0), pr = q('.p-open').getBoundingClientRect(), clips = new Map();
      var clip = function (el) {
        if (clips.has(el)) return clips.get(el);
        var c = el.classList.contains('p-open') || !el.parentElement ? { l: -1e4, t: -1e4, r: 1e4, b: 1e4 } : clip(el.parentElement), cs = getComputedStyle(el);
        if (cs.overflowX !== 'visible' || cs.overflowY !== 'visible') { var b = el.getBoundingClientRect(); c = { l: Math.max(c.l, b.left), t: Math.max(c.t, b.top), r: Math.min(c.r, b.right), b: Math.min(c.b, b.bottom) }; }
        clips.set(el, c); return c;
      };
      var root = r.commonAncestorContainer, w = document.createTreeWalker(root.nodeType === 1 ? root : root.parentNode, NodeFilter.SHOW_TEXT), t;
      while ((t = w.nextNode())) {
        if (!r.intersectsNode(t) || !t.parentElement.closest('.p-open') || t.parentElement.closest('.shine, button, .md-mk')) continue;   /* a list's marker is copied, not lit */
        var sr = document.createRange(); sr.selectNodeContents(t);
        if (t === r.startContainer) sr.setStart(t, r.startOffset);
        if (t === r.endContainer) sr.setEnd(t, r.endOffset);
        var c = clip(t.parentElement);
        [].forEach.call(sr.getClientRects(), function (b) {
          var x = { l: Math.max(b.left - 2, c.l), t: Math.max(b.top, c.t), r: Math.min(b.right + 2, c.r), b: Math.min(b.bottom, c.b) };
          if (b.width > 1 && x.r - x.l > 2 && x.b - x.t > 2) lines.push(x);
        });
      }
      /* pieces on the same line (a word in code, a bold one) become one */
      lines.sort(function (a, b) { return a.t - b.t || a.l - b.l; });
      lines = lines.reduce(function (out, x) {
        var y = out[out.length - 1];
        if (y && Math.min(y.b, x.b) - Math.max(y.t, x.t) > Math.min(y.b - y.t, x.b - x.t) / 2) { y.l = Math.min(y.l, x.l); y.r = Math.max(y.r, x.r); y.t = Math.min(y.t, x.t); y.b = Math.max(y.b, x.b); }
        else out.push(x);
        return out;
      }, []);
      lines.forEach(function (x) { x.l -= pr.left; x.r -= pr.left; x.t -= pr.top; x.b -= pr.top; });
    }
    var have = hlLayer.children;
    while (have.length > lines.length) hlLayer.removeChild(have[have.length - 1]);
    lines.forEach(function (x, i) {
      var el = have[i];
      if (!el) { el = document.createElement('i'); el.className = 'in'; hlLayer.appendChild(el); requestAnimationFrame(function () { el.classList.remove('in'); }); }
      el.style.cssText = 'left:' + x.l + 'px;top:' + x.t + 'px;width:' + (x.r - x.l) + 'px;height:' + (x.b - x.t) + 'px';
    });
  }
  document.addEventListener('scroll', function () { if (selOn) hlDraw(); }, true);
  /* copied (Command+C, or Copy from the menu): the highlight brightens for a beat, so you know it went */
  document.addEventListener('copy', function () {
    if (!selOn) return;
    hlLayer.classList.remove('copied'); void hlLayer.offsetWidth; hlLayer.classList.add('copied');
  });
  hlLayer.addEventListener('animationend', function () { hlLayer.classList.remove('copied'); });
  /* Selecting in the message above took the caret from the reply: what you type next goes back into the field. */
  document.addEventListener('keydown', function (e) {
    if (fRep.style.display !== 'flex' || document.activeElement === rIn || (document.activeElement && document.activeElement.tagName === 'INPUT') || e.metaKey || e.ctrlKey || !(e.key.length === 1 || e.key === 'Backspace')) return;
    caretAt(rIn.selectionEnd == null ? rIn.value.length : rIn.selectionEnd);
  }, true);
  function cursor(x, y) {
    ptrSeen(x, y); sweep(x, y); if (lastSt === 'switch') markList(); if (lastSt === 'open') markChoice(); if (act.mode) markAct();
    if (Date.now() - realMoveAt > 400) hoverAt(x, y);
    if (cr.dataset.m !== 'awake' && cr.dataset.m !== 'alert') return;
    var r = cr.getBoundingClientRect(), dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height / 2);
    var d = Math.max(1, Math.hypot(dx, dy)), k = Math.min(1, d / 40);
    tracking = true; look((dx / d) * 3.1 * k, (dy / d) * 2.2 * k);
    /* measured from its box, which stays put while the character itself squashes and hops */
    var pv = q('.cr-pv') || q('.cr-hi'); if (pv) { var pr = pv.parentNode.getBoundingClientRect(), w = pv.offsetWidth, px = x - (pr.left + pr.width / 2), py = y - (pr.top + pr.height / 2), pd = Math.max(1, Math.hypot(px, py)), pk = Math.min(1, pd / 60); eyesTo(pv, (px / pd) * w * .1 * pk, (py / pd) * w * .075 * pk); }
    clearTimeout(trackTimer); trackTimer = setTimeout(function () { tracking = false; }, 1600);
  }
  /* The big character's eyes (and, a little, its body) move on a spring run here rather than a CSS transition. The app reads
     the pointer 30 times a second, and a transition started again at each reading moves in stops and starts. */
  function eyesTo(el, x, y) {
    var s = el._eyes || (el._eyes = { x: 0, y: 0, vx: 0, vy: 0, t: 0, on: false });
    s.tx = x; s.ty = y;
    if (STILL) { s.x = x; s.y = y; } else if (!s.on) { s.on = true; s.t = 0; requestAnimationFrame(step); }
    put();
    function put() { el.style.setProperty('--lx', s.x.toFixed(2) + 'px'); el.style.setProperty('--ly', s.y.toFixed(2) + 'px'); }
    function step(now) {
      if (!el.isConnected) { s.on = false; return; }
      /* stiff enough to settle in about a third of a second, damped to the faintest overshoot */
      var dt = s.t ? Math.min(.034, (now - s.t) / 1000) : .016, k = 380, c = 26; s.t = now;
      s.vx += (k * (s.tx - s.x) - c * s.vx) * dt; s.vy += (k * (s.ty - s.y) - c * s.vy) * dt;
      s.x += s.vx * dt; s.y += s.vy * dt;
      var rest = Math.abs(s.tx - s.x) < .02 && Math.abs(s.ty - s.y) < .02 && Math.abs(s.vx) + Math.abs(s.vy) < .1;
      if (rest) { s.x = s.tx; s.y = s.ty; s.vx = s.vy = 0; s.on = false; }
      put();
      if (!rest) requestAnimationFrame(step);
    }
  }
  /* the real pointer only: hoverAt's own mousemove (for the page's hover handlers) would come back here and loop, and the
     design page's pretend pointer calls cursor itself */
  if (!NATIVE) scene.addEventListener('mousemove', function (e) { if (e.isTrusted) cursor(e.clientX, e.clientY); });
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
    /* an octopus, after the emoji: a tall round head with a waist, and six tentacles splaying out under it, their tips curling */
    ['octo', 'Octopus', 'M12 1.4C16.3 1.4 18.9 4.5 18.9 8.3C18.9 11.1 17.6 12.7 16.5 13.7C18 14.6 20.3 14.9 21.8 14.2C22.8 13.7 23.8 14.6 23.2 15.6C22.6 16.6 21 16.9 19.6 16.8C18.9 16.8 18.4 17 18.2 17.4C18.4 18.6 19.7 19.6 20.6 20.4C21.4 21.1 20.9 22.2 19.9 21.9C18.3 21.4 16.8 20.2 15.9 19.1C15.8 20.3 16.1 21.6 16 22.3C15.9 23.1 14.8 23.3 14.3 22.6C13.6 21.6 13.1 19.9 12 19.2C10.9 19.9 10.4 21.6 9.7 22.6C9.2 23.3 8.1 23.1 8 22.3C7.9 21.6 8.2 20.3 8.1 19.1C7.2 20.2 5.7 21.4 4.1 21.9C3.1 22.2 2.6 21.1 3.4 20.4C4.3 19.6 5.6 18.6 5.8 17.4C5.6 17 5.1 16.8 4.4 16.8C3 16.9 1.4 16.6 0.8 15.6C0.2 14.6 1.2 13.7 2.2 14.2C3.7 14.9 6 14.6 7.5 13.7C6.4 12.7 5.1 11.1 5.1 8.3C5.1 4.5 7.7 1.4 12 1.4Z', '30%', '32%', '54%', '13%'],
    /* a bao, after the Bun mascot: broad and soft with a rounded top and pleats */
    ['bun', 'Bun', 'M12 4.2C15.4 4.2 18.4 6.6 20.4 9.6C21.9 11.9 22.7 13.9 22.7 16.1C22.7 19.6 18.2 21.6 12 21.6S1.3 19.6 1.3 16.1C1.3 13.9 2.1 11.9 3.6 9.6C5.6 6.6 8.6 4.2 12 4.2Z', '54%', '31%', '55%', '14%',
      'M9.4 9Q10.3 6.8 11.5 5.8M12.1 9.2Q12.3 7.1 12.4 5.5M14.6 8.9Q14.2 6.9 13.3 5.7'],
    /* a small robot: an antenna on a rounded tile */
    ['tile', 'Tile', 'M7 3h10a4 4 0 0 1 4 4v10a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4z', '40%', '', '', '', 'M12 3.2V1.6', 'M12 .3a1.15 1.15 0 1 1 0 2.3a1.15 1.15 0 1 1 0-2.3z'],
    /* an onigiri: a soft rice triangle with its band of nori */
    ['peak', 'Onigiri', 'M10.2 3.6Q12 .9 13.8 3.6L22 17.2Q23.8 21 19.6 21H4.4Q.2 21 2 17.2Z', '40%', '33%', '55%', '12%', '', 'M8.2 17.2h7.6v3.8H8.2z']
  ];
  var PALETTE = [['Saffron', '#F5B83D'], ['Peach', '#FF9E7A'], ['Rose', '#F48FB1'], ['Lilac', '#B9A2F5'], ['Sky', '#7DC4F5'], ['Mint', '#7FD9A8'], ['Cream', '#F2EAD3']];
  var charNow = { shape: 'ears', color: '#F5B83D' };
  function shapeOf(k) { if (k === 'arch') k = 'bun'; /* Arch became Bun */ if (k === 'dome') k = 'octo'; /* the Ghost became the Octopus */ for (var i = 0; i < SHAPES.length; i++) if (SHAPES[i][0] === k) return SHAPES[i]; return SHAPES[0]; }
  function applyCharacter(c) {
    if (!c) return;
    charNow = { shape: shapeOf(c.shape)[0], color: c.color };   /* an old name (Ghost, Arch) counts as the shape that replaced it */
    var sh = shapeOf(c.shape);
    scene.querySelectorAll('.cr:not(.cr-mini) .f path:not(.pl):not(.fd)').forEach(function (p) { p.setAttribute('d', sh[2]); });
    scene.querySelectorAll('.cr:not(.cr-mini) .f path.fd').forEach(function (p) { p.setAttribute('d', sh[8] || ''); });
    scene.querySelectorAll('.cr:not(.cr-mini) .f path.pl').forEach(function (p) { p.setAttribute('d', sh[7] || ''); });
    scene.querySelectorAll('.cr:not(.cr-mini)').forEach(function (e) { e.style.setProperty('--et', sh[3]); e.style.setProperty('--el', sh[4] || '30%'); e.style.setProperty('--er', sh[5] || '56%'); e.style.setProperty('--ew', sh[6] || '14%'); e.dataset.shape = sh[0]; });
    document.documentElement.style.setProperty('--cr', c.color);
    menuIcon(sh);
    if (n && !(onbLast && onbStep === onbLast.total - 1 && n.dataset.s === 'onb')) n.style.setProperty('--gcol', c.color);
  }
  /* The menu bar icon is your character: its silhouette with the eyes cut out, drawn here and handed to the app as a template image. */
  var iconShape = '';
  function menuIcon(sh) {
    if (!NATIVE || iconShape === sh[0] || !window.Path2D) return;
    iconShape = sh[0];
    var cv = document.createElement('canvas'), g = cv.getContext('2d'), u = 34 / 24;
    cv.width = cv.height = 36; g.translate(1, 1); g.scale(u, u);
    g.fillStyle = g.strokeStyle = '#000';
    var body = new Path2D(sh[2]);
    g.fill(body); if (sh[8]) g.fill(new Path2D(sh[8]));
    if (sh[7]) {
      /* line details: cut in as slits where they cross the body (whiskers, pleats), drawn where they stick out (an antenna) */
      var lines = new Path2D(sh[7]), outside = new Path2D(); outside.rect(-2, -2, 28, 28); outside.addPath(body);
      g.lineCap = 'round';
      g.save(); g.clip(body); g.globalCompositeOperation = 'destination-out'; g.lineWidth = .9; g.stroke(lines); g.restore();
      g.save(); g.clip(outside, 'evenodd'); g.lineWidth = 1.3; g.stroke(lines); g.restore();
    }
    /* the eyes, a touch bigger than on screen so they read at menu bar size */
    g.globalCompositeOperation = 'destination-out';
    var top = parseFloat(sh[3]) * .24, w = parseFloat(sh[6] || '14%') * .24 * 1.15, h = 24 * .26;
    [sh[4] || '30%', sh[5] || '56%'].forEach(function (l) { var x = parseFloat(l) * .24 + parseFloat(sh[6] || '14%') * .12; g.beginPath(); g.ellipse(x, top + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2); g.fill(); });
    post({ type: 'menuIcon', png: cv.toDataURL('image/png') });
  }
  function crHtml(cls, size, sh, mood) {
    return '<div class="cr ' + cls + '" data-shape="' + sh[0] + '" data-m="' + (mood || 'awake') + '" style="position:relative;left:auto;top:auto;width:' + size + 'px;height:' + size + 'px;transform:none;--et:' + sh[3] + ';--el:' + (sh[4] || '30%') + ';--er:' + (sh[5] || '56%') + ';--ew:' + (sh[6] || '14%') + '"><div class="cr-in"><i class="f"><svg viewBox="0 0 24 24"><g class="coat"><path d="' + sh[2] + '"/><path class="pl" d="' + (sh[7] || '') + '"/><path class="fd" d="' + (sh[8] || '') + '"/></g></svg></i><i class="ey l"></i><i class="ey r"></i></div></div>';
  }

  /* ---- onboarding: six short steps inside the notch ---- */

  /* ---- moments: the party at the end of onboarding, and the first hello beside the notch ---- */
  var celebrating = false, hello = false, helloNext = false, curH = 232, idleXf = '', idleD = 18, lastSt = 'idle', screenKey = '';
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
    var host = q('.p-onb'), cols = [COLORS.done, '#B7E4C7', charNow.color, '#FDE68A', '#FFFFFF'], k, html = '';
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
    hello = true; scene.dataset.peek = '1';
    var ci = cr.querySelector('.cr-in'), say = cr.querySelector('.say');
    say.textContent = text || ''; cr.dataset.say = text ? '1' : '';
    cr.style.transform = idleXf; cr.style.opacity = 1; cr.dataset.m = 'awake';
    ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive');
    setTimeout(function () { ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); cr.dataset.m = mood; }, 420);
    setTimeout(function () { runHome(function () { hello = false; scene.dataset.peek = ''; if (snap) layout(lastSt, snap); }); }, ms);
  }
  /* While you are at the Mac, rare and small: a session you are not in finished, or the last thing waiting on you was answered. */
  var known = null;
  function moments(s, st) {
    if (st !== 'idle') return;
    var done = s.projects.filter(function (p) { return p.status.kind === 'done' && p.fresh && !inside(s, p.id); }).map(function (p) { return p.id; });
    var need = s.projects.filter(function (p) { return p.attention && !inside(s, p.id); }).length;
    /* a finish, or the last thing waiting on you being answered, is the live activity's to say; the character stays in */
    known = { done: done, need: need };
  }
  /* After setup the character peeks out beside the notch, says hi, and tucks back in. */
  function sayHello() {
    hello = true; scene.dataset.peek = '1';
    var ci = cr.querySelector('.cr-in');
    cr.style.opacity = 1; cr.dataset.m = 'awake';
    ci.classList.remove('arrive'); void ci.offsetWidth; ci.classList.add('arrive');
    setTimeout(function () { ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); cr.dataset.m = 'happy'; }, 700);
    setTimeout(function () { cr.dataset.m = 'awake'; blinkEl(cr); }, 1500);
    setTimeout(function () { runHome(function () { hello = false; scene.dataset.peek = ''; if (snap) layout(lastSt, snap); }); }, 2500);
  }
  /* It lives behind the notch: a little wind-up, leaning back with its eyes on the notch, then a dash in under the notch's edge. */
  function runHome(done) {
    var ci = cr.querySelector('.cr-in');
    cr.dataset.say = '';
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) { cr.style.opacity = 0; setTimeout(done, 350); return; }
    cr.style.setProperty('--run', (idleD + 24) + 'px');
    cr.dataset.m = 'awake'; look(2.6, 0);
    cr.classList.add('running'); ci.classList.remove('run'); void ci.offsetWidth; ci.classList.add('run');
    /* as it ducks in under the notch, the notch gulps it: a ripple in its colour where it went in, a bump down and a nudge
       the way it ran, then it settles */
    setTimeout(function () {
      var ring = document.createElement('i'); ring.className = 'gulp'; ring.style.left = (240 - n.offsetWidth / 2 - 22) + 'px'; ring.style.top = (n.offsetHeight / 2 - 22) + 'px';
      scene.appendChild(ring); setTimeout(function () { ring.remove(); }, 700);
      n.style.transformOrigin = '50% 0';
      n.animate([{ transform: 'none' }, { transform: 'translateX(1.5px) scale(1.02, 1.16)', offset: .28 }, { transform: 'translateX(-.6px) scale(.995, .95)', offset: .6 }, { transform: 'none' }],
        { duration: 480, easing: 'cubic-bezier(.3,.7,.4,1)' }).onfinish = function () { n.style.transformOrigin = ''; };
    }, 620);
    setTimeout(function () {
      cr.style.transition = 'none'; cr.style.opacity = 0;
      ci.classList.remove('run'); cr.classList.remove('running'); look(0, 0);
      void cr.offsetWidth; cr.style.transition = '';
      done();
    }, 1000);
  }

  /* ---- a click on the small character beside the card: it reacts, a different way each time ---- */
  var CLICKS = ['giggle', 'hops', 'dash', 'wink', 'startle', 'nap'], lastClick = '', crPlay = 0;
  var STAR = '<svg viewBox="0 0 10 10"><path d="M5 0Q5.6 4.4 10 5Q5.6 5.6 5 10Q4.4 5.6 0 5Q4.4 4.4 5 0Z"/></svg>';
  function crClick(only) {
    if (crPlay || hello || celebrating || cr.style.opacity === '0') return;
    var pick = only || CLICKS.filter(function (t) { return t !== lastClick; })[Math.floor(Math.random() * (CLICKS.length - 1))];
    var ci = cr.querySelector('.cr-in'), ms = 1400, T = setTimeout, mood = function (m) { cr.dataset.m = m; };
    var still = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    var play = function (cls) { ci.classList.remove(cls); void ci.offsetWidth; ci.classList.add(cls); };
    var fx = function (cls, html, delay) { T(function () { var e = document.createElement('i'); e.className = 'fx ' + cls; e.innerHTML = html; cr.appendChild(e); T(function () { e.remove(); }, 1300); }, delay || 0); };
    lastClick = pick; crPlay = 1;
    if (still) { mood('happy'); ms = 900; }
    else if (pick === 'giggle') { mood('happy'); play('giggle'); T(function () { mood('awake'); }, 1050); ms = 1500; }
    else if (pick === 'hops') { mood('happy'); play('hops'); look(0, .5); T(function () { look(0, 0); mood('awake'); }, 800); ms = 950; }
    else if (pick === 'dash') {
      /* it runs right along the top, under the notch's edge, and a moment later pops out there and trots home */
      var nw = snap && snap.screen && snap.screen.hasNotch ? snap.screen.notchW : 148;
      cr.style.setProperty('--run', Math.max(40, Math.round(CARD_W / 2 - 30 - nw / 2)) + 'px');
      look(2.6, 0); cr.classList.add('dashing'); play('dash');
      T(function () { cr.classList.remove('dashing'); ci.classList.remove('dash'); play('dashback'); look(-1.4, 0); mood('alert'); }, 1250);
      T(function () { look(0, 0); mood('happy'); }, 1700);
      T(function () { mood('awake'); }, 2200); ms = 2350;
    }
    else if (pick === 'wink') { play('tilt'); T(function () { cr.classList.add('wink'); }, 120); fx('star', STAR, 160); T(function () { cr.classList.remove('wink'); }, 1000); ms = 1250; }
    else if (pick === 'startle') { mood('alert'); look(-1.2, -.4); play('startle'); T(function () { look(0, 0); mood('awake'); }, 800); ms = 1000; }
    else { mood('sleep'); look(0, 0); fx('z', 'z', 250); fx('z z2', 'z', 750); T(function () { mood('awake'); play('hop'); }, 1900); ms = 2500; }
    T(function () {
      ['giggle', 'hops', 'dash', 'dashback', 'tilt', 'startle', 'hop'].forEach(function (c) { ci.classList.remove(c); });
      cr.classList.remove('wink', 'dashing'); crPlay = 0; look(0, 0);
      if (snap) layout(lastSt, snap);
    }, ms);
  }
  scene.addEventListener('click', function (e) { if (e.target.closest('.cr') === cr) crClick(); });

  /* ---- the shortcut that opens and closes Perch: shown in Settings and in onboarding, recorded by the app ---- */
  var SC0 = { keys: ['\u2318', '\u2325'], kind: 'tap', custom: false, recording: false, error: '', tried: false, saved: false, works: true, why: '', attempt: [], refusals: 0, pending: [], picks: 0 };
  function scOf(sc) { return sc || SC0; }
  function scKeysHtml(sc, tint, gap) { return '<span class="inline-flex items-baseline ' + (gap || 'gap-[3px]') + '">' + scOf(sc).keys.map(function (k) { var h = Kbd(k); return tint ? h.replace('<kbd class="', '<kbd style="color:' + tint + '" class="') : h; }).join('') + '</span>'; }
  function scWords(sc) { return scOf(sc).kind === 'tap' ? 'Tap both to open or close Perch' : 'Open or close Perch'; }
  /* what the recorder asks for, or why it refused the last try (it keeps listening) */
  function scPrompt(sc) { return sc.error ? '<span style="color:' + COLORS.attention + '">' + sc.error + '</span>' : '<span class="sc-live" data-t="Press your shortcut\u2026">Press your shortcut\u2026</span>'; }
  function shortcutStep(o) {
    var sc = scOf(o.shortcut), needsAx = sc.kind === 'tap' && !o.accessibility, big = sc.keys.map(function (k) {
      return '<button class="kcap' + (sc.tried || sc.saved ? ' ok' : sc.works ? ' on' : ' off') + '" data-k="' + k + '" aria-label="' + k + '">' + k + '</button>';
    }).join('');
    var broken = !sc.works && !sc.recording ? '<span style="color:' + COLORS.attention + '">' + sc.why + '</span>' : '';
    /* while it listens the keys are drawn as you hold them, each its own key (scHeldApply); until one is held, an empty key */
    /* no separate recording look: while it listens the card shows the shortcut you have now, plain grey, and says it is listening */
    var chosen = sc.recording && sc.pending && sc.pending.length;
    var current = (chosen ? sc.pending : sc.keys).map(function (k) { return '<span class="kcap' + (chosen ? ' ok' : '') + '" data-k="' + k + '" style="cursor:default;pointer-events:none">' + k + '</span>'; }).join('');
    var tried = sc.recording && sc.error && sc.attempt && sc.attempt.length ? sc.attempt.map(function (k) { return '<span class="kcap bad" data-k="' + k + '" style="cursor:default">' + k + '</span>'; }).join('') : current;
    scRest = tried;
    var shown = sc.recording ? tried : big, ask = sc.pending && sc.pending.length ? 'Press Return to save it, or press another shortcut.' : 'Listening for your new shortcut\u2026',
      listening = sc.error ? '<span style="color:' + COLORS.attention + '">' + sc.error + '</span>' : ask;
    if (o.only) {
      /* opened from Settings: the whole card is the recorder. It listens from the start; Done goes back to Settings. */
      var note = sc.recording ? listening
          : broken ? broken
          : sc.tried ? '<span style="color:' + COLORS.done + '">That\u2019s it. This is your shortcut.</span>'
          : sc.saved ? 'Saved.'
          : needsAx ? 'A tap needs Accessibility. Record a key combo instead, or allow it in Settings.' : 'Press Record again to change it.';
      return otitle(o, sc.which === 'new' ? 'Start a new session with' : 'Open Perch with', 'Press the shortcut you want. Esc goes back.') +
        oi(3, '<div class="o-sc-big mt-4 flex justify-center gap-1.5"' + (sc.recording ? ' data-rec="1"' : '') + '>' + shown + '</div>') +
        oi(4, '<p class="o-sc-hint mt-3 px-4 text-center text-xs leading-4 text-muted-foreground">' + note + '</p>') +
        ofoot(5, false, '', 'Done', 'next', (sc.recording ? '' : Button('ghost', 'Record again', Kbd('C'), 'o-sc" data-a="record')) + (sc.custom ? Button('ghost', 'Reset', '', 'o-scr') : ''));
    }
    var hint = sc.recording ? listening
      : broken ? broken
      : sc.tried ? '<span style="color:' + COLORS.done + '">That\u2019s it. You\u2019ll tap this a lot.</span>'
      : sc.saved ? 'Saved.'
      : needsAx ? 'A tap needs Accessibility. Go back to allow it, or record a key combo.'
      : sc.kind === 'tap' ? 'Try it now. Tap both keys together.' : 'Try it now. Press it.';
    return otitle(o, 'This is how you use Perch', 'Open and close it any time with this.') +
      oi(3, '<div class="o-sc-big mt-4 flex justify-center gap-1.5"' + (sc.recording ? ' data-rec="1"' : '') + '>' + shown + '</div>') +
      oi(4, '<p class="o-sc-hint mt-3 px-4 text-center text-xs leading-4 text-muted-foreground">' + hint + '</p>') +
      ofoot(5, true, Button('ghost', sc.recording ? 'Cancel' : 'Use another shortcut', Kbd(sc.recording ? 'esc' : 'C'), 'o-sc" data-a="' + (sc.recording ? 'cancel' : 'record')), 'Next', 'next');
  }
  /* the big keys: they press like keys, light up while you hold the real ones, and when you try it they spring and the character cheers */
  var scHeldNow = [], scWasTried = '', scHeldShown = '', scPendingNow = [], scPendSeen = '', scFresh = false, scPeak = [];
  var scRest = '', scRef = 0;
  function scHeldApply() {
    document.querySelectorAll('.o-sc-big[data-rec]').forEach(function (b) {
      /* a key pressed on top of held modifiers shows at once, as a pressed key beside them, until you let go */
      if (!scHeldNow.length) scFresh = false;
      /* letting go one key at a time must not show fewer keys for a moment: the row keeps the most that was held until all are up */
      if (!scHeldNow.length) scPeak = []; else if (scHeldNow.length >= scPeak.length) scPeak = scHeldNow.slice();
      var fresh = scFresh && scPendingNow.length ? scPendingNow : null, keys = fresh || scPeak, sig = keys.join('') + (fresh ? '+' : '');
      if (b.dataset.held === sig) return;
      /* what was held is remembered here, not on the row: the card redraws now and then and a fresh row must not replay the press */
      var before = sig.indexOf(scHeldShown) === 0 ? scHeldShown.length : 0; b.dataset.held = sig; var same = scHeldShown === sig; scHeldShown = sig;
      b.innerHTML = keys.length ? keys.map(function (k) { return '<span class="kcap' + (fresh ? ' ok' : '') + ' down" data-k="' + k + '" style="cursor:default">' + k + '</span>'; }).join('') : scRest;
      if (!STILL) b.querySelectorAll('.kcap.down').forEach(function (c, i) { if (c.animate && !same && i >= before && keys.length) c.animate([{ transform: 'translateY(-5px) scale(.9)', opacity: .5 }, { transform: 'translateY(2px) scale(.97)', opacity: 1 }], { duration: 180, easing: 'cubic-bezier(.3,1.4,.5,1)' }); });
    });
    document.querySelectorAll('.o-sc-big:not([data-rec]) .kcap[data-k]').forEach(function (c) { c.classList.toggle('down', scHeldNow.indexOf(c.dataset.k) >= 0); });
    document.querySelectorAll('.sc-live').forEach(function (e) { e.textContent = scHeldNow.length ? scHeldNow.join(' ') : e.dataset.t; });
  }
  function scAfter(o) {
    var sc = scOf(o && o.shortcut);
    var pend = sc.recording && sc.pending && sc.pending.length ? sc.pending.join('') : '';
    scPendingNow = pend ? sc.pending : [];
    var pick = pend ? pend + '#' + (sc.picks || 0) : '';
    if (pick !== scPendSeen) { scPendSeen = pick; scFresh = !!pend && scHeldNow.length > 0; }
    var mark = sc.tried ? 'tried' : sc.saved ? 'saved' : '';
    if (mark && mark !== scWasTried) {
      document.querySelectorAll('.o-sc-big .kcap').forEach(function (c, i) {
        if (!c.animate || STILL) return;
        c.animate([{ transform: 'translateY(2px) scale(.96)' }, { transform: 'translateY(-5px) scale(1.12)', offset: .45 }, { transform: 'translateY(0) scale(1)' }], { duration: 520, delay: i * 70, easing: 'cubic-bezier(.3,1.4,.5,1)' });
      });
      var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop');
      setTimeout(function () { if (cr.dataset.m === 'happy' && onbStep === 3) cr.dataset.m = 'awake'; }, 1800);
    }
    scWasTried = mark;
    /* the bottom of the card glows orange for a refusal and green once it is saved, and a refusal shakes the keys */
    var bad = sc.recording && !!sc.error, good = sc.recording ? !sc.error && !!(sc.pending && sc.pending.length) : (sc.saved || sc.tried);
    introGlow = bad ? COLORS.attention : good ? COLORS.done : ''; n.style.setProperty('--gcol', introGlow || charNow.color);
    if (bad && sc.refusals !== scRef && !STILL) {
      var row = document.querySelector('.o-sc-big');
      if (row && row.animate) row.animate([{ transform: 'translateX(0)' }, { transform: 'translateX(-8px)' }, { transform: 'translateX(7px)' }, { transform: 'translateX(-5px)' }, { transform: 'translateX(4px)' }, { transform: 'translateX(-2px)' }, { transform: 'translateX(0)' }], { duration: 460, easing: 'ease-out' });
    }
    scRef = sc.refusals || 0;
    scHeldApply();
  }
  var onbStep = -1, onbSig = '', onbLast = null, onbOpenG = '';   /* onbOpenG: the group open on the apps step */
  function oi(i, inner) { return '<div class="o-i" style="--i:' + i + '">' + inner + '</div>'; }
  function otitle(o, title, sub) {
    /* the hello is not a step of the setup: the count starts after it */
    return (o.only ? '' : oi(0, '<div class="px-4 pt-0.5 text-xs tabular-nums text-muted-foreground">' + o.step + ' of ' + (o.total - 1) + '</div>')) +
      oi(1, '<p class="' + (o.only ? 'pt-0.5' : 'mt-1') + ' px-4 text-[15px] font-semibold leading-5 tracking-[-0.02em]">' + title + '</p>') +
      oi(2, '<p class="mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground">' + sub + '</p>');
  }
  /* `left` sits where Back would be: the keyboard hints on the character step */
  function ofoot(i, back, mid, label, action, left) { return oi(i, ofootIn(back, mid, label, action, left)); }
  function ofootIn(back, mid, label, action, left) {
    return '<div class="o-foot mt-3 flex h-9 items-end gap-1 px-2.5">' + (back ? Button('ghost', 'Back', Kbd('\u2190'), 'o-back') : (left || '')) + '<span class="flex-1"></span>' + (mid || '') +
      Button('default', label, Kbd(svg('enter', 'size-2'), 1), 'o-primary pr-0.5" data-a="' + action) + '</div>';
  }
  /* a tile's second line on the apps step: one quiet word while the first scan runs, then what it found */
  /* chats are named by count only: their titles can be personal, and the tile is seen before you choose */
  function liveNote(on) { return on ? 'Codex may ask you once to trust the new hook.' : 'Adds a small hook to each agent. You can remove it in Settings.'; }
  /* off: Turn on, or Skip; on: Next */
  function liveFoot(on) { return ofootIn(true, on ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), on ? 'Next' : 'Turn on', on ? 'next' : 'hooks'); }
  function prsNote(on) { return on ? 'A failing check puts the session under Needs you. Change it in Settings.' : 'Read only: Perch never writes to GitHub. You can switch it off in Settings.'; }
  function prsFoot(on) { return ofootIn(true, on ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), on ? 'Next' : 'Turn on', on ? 'next' : 'prs'); }
  function tick(done) { return done ? Ring('done') : '<span class="size-4 flex-none rounded-full border border-muted-foreground/40"></span>'; }
  function orow(icon, label, right) { return '<div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]">' + icon + '<span class="flex-1">' + label + '</span><span class="text-muted-foreground">' + right + '</span></div>'; }
  function ohint(left, text) { return '<div class="flex items-baseline gap-3"><span class="flex w-[4.5rem] flex-none">' + left + '</span><span class="text-muted-foreground">' + text + '</span></div>'; }
  function onbDo(a) {
    if (a === 'finish') helloNext = true;
    if (a === 'hooks') post({ type: 'hooks', on: true }); else if (a === 'prs') post({ type: 'setting', key: 'pullRequests', value: true }); else post({ type: 'onb', action: a });
  }
  var pickedAt = 0;   /* apply() leaves the character alone just after a pick: a snapshot sent before the app heard of it still has the old one */
  function pickCharacter(c) {
    if (shapeOf(c.shape)[0] === charNow.shape && c.color === charNow.color) return;   /* already this one */
    var shapeChanged = shapeOf(c.shape)[0] !== charNow.shape, box = q('.onb'), pv = q('.cr-pv');
    pickedAt = Date.now();
    post({ type: 'character', shape: c.shape, color: c.color });
    charNow = { shape: shapeOf(c.shape)[0], color: c.color };   /* an old name (Ghost, Arch) counts as the shape that replaced it */
    if (!pv) applyCharacter(charNow);
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
    if (!pv) return;
    pv._busy = Date.now() + 1500;
    /* One motion for the whole character, eyes and all: down into a squash, up with a little stretch, a soft landing. A new
       shape and its happy face come in together at the lowest point. A pick made mid-motion carries on from wherever the
       character is, so going through the shapes quickly never snaps it back to the start. */
    var settle = function () { clearTimeout(pv._t); pv._t = setTimeout(function () { pv.dataset.m = 'awake'; }, 850); };
    if (!shapeChanged) { pv.dataset.m = 'happy'; settle(); if (!pv._swap) applyCharacter(charNow); }
    else if (!pv._swap) pv._swap = setTimeout(function () { pv._swap = 0; reshape(pv, function () { applyCharacter(charNow); pv.dataset.m = 'happy'; }); settle(); }, STILL ? 0 : 110);
    if (STILL) return;
    var from = getComputedStyle(pv).transform, up = 'cubic-bezier(.2,.8,.4,1)';
    if (pv._pop) pv._pop.cancel();
    pv._pop = pv.animate([{ transform: from, easing: 'cubic-bezier(.3,0,.5,1)' }, { transform: 'scale(1.12,.86)', offset: .2, easing: up },
      { transform: 'translateY(-3px) scale(.95,1.07)', offset: .5, easing: 'cubic-bezier(.5,0,.7,.4)' }, { transform: 'scale(1.04,.97)', offset: .74, easing: up }, { transform: 'none' }], { duration: 560 });
  }
  /* the shape and the face change in one frame, without their usual glide, so the eyes land with the new body instead of sliding across it */
  function reshape(el, fn) { el.classList.add('reshape'); fn(); void el.offsetWidth; el.classList.remove('reshape'); }
  /* the preview and the little shape tiles are alive: they blink and glance about while you choose */
  function blinkEl(el) { el.classList.add('blink'); setTimeout(function () { el.classList.remove('blink'); }, 150); }
  /* while you choose, the big preview plays: a jump, a wiggle, a squish, a short nap, a happy bounce. Never the same twice in a row. */
  var TRICKS = ['jump', 'wiggle', 'squish', 'nap', 'happy'], lastTrick = '';
  function trick(pv, only) {
    var ci = pv.querySelector('.cr-in'), pick = only || TRICKS.filter(function (t) { return t !== lastTrick; })[Math.floor(Math.random() * (TRICKS.length - 1))];
    lastTrick = pick; pv._busy = Date.now() + 1800;
    var play = function (cls, ms) { ci.classList.remove(cls); void ci.offsetWidth; ci.classList.add(cls); setTimeout(function () { ci.classList.remove(cls); }, ms); };
    if (pick === 'nap') {
      pv.dataset.m = 'sleep'; eyesTo(pv, 0, 0);
      setTimeout(function () { if (pv.dataset.m === 'sleep') { pv.dataset.m = 'awake'; play('hop', 600); } }, 1500);
    } else if (pick === 'jump') {
      /* its eyes drop as it crouches, go up as it leaves the ground, and come back as it lands */
      play('jump', 1000); eyesTo(pv, 0, 1.2);
      setTimeout(function () { eyesTo(pv, 0, -1.8); }, 200);
      setTimeout(function () { eyesTo(pv, 0, 0); }, 620);
    } else if (pick === 'happy') {
      pv.dataset.m = 'happy'; play('hop', 600);
      setTimeout(function () { if (pv.dataset.m === 'happy') pv.dataset.m = 'awake'; }, 900);
    } else play(pick, 950);
  }
  /* clicked while you choose it: tickled. Its eyes squeeze shut and it squirms and giggles */
  function tickle(pv) {
    var ci = pv.querySelector('.cr-in'); pv._busy = Date.now() + 1900; clearTimeout(pv._tk); clearTimeout(pv._tk2);
    pv.dataset.m = 'happy';
    ci.classList.remove('giggle'); void ci.offsetWidth; ci.classList.add('giggle');
    /* the eyes open again as the wobble settles; the classes go once everything has come to rest */
    pv._tk = setTimeout(function () { if (pv.dataset.m === 'happy') pv.dataset.m = 'awake'; }, 1050);
    pv._tk2 = setTimeout(function () { ci.classList.remove('giggle'); }, 1500);
  }
  scene.addEventListener('click', function (e) { var pv = e.target.closest('.cr-pv'); if (pv) tickle(pv); });
  /* A shape or a colour is picked on the press. A snapshot that draws the card again between press and release replaces
     the swatch under the pointer, and the browser then sends no click at all. The click that follows is the same pick
     again, which pickCharacter ignores. */
  scene.addEventListener('pointerdown', function (e) {
    var b = e.button === 0 && e.target.closest('.o-shape, .o-color'); if (!b) return;
    pickCharacter(b.dataset.k ? { shape: b.dataset.k, color: charNow.color } : { shape: charNow.shape, color: b.dataset.c });
  });
  (function previewLife() {
    var pv = q('.cr-pv');
    if (pv && pv.dataset.m === 'awake' && !(pv._busy > Date.now()) && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) && Math.random() < 0.4) trick(pv);
    else if (pv && pv.dataset.m === 'awake' && !(pv._busy > Date.now())) {
      blinkEl(pv); if (Math.random() < 0.3) setTimeout(function () { blinkEl(pv); }, 280);
      eyesTo(pv, (Math.random() - 0.5) * 5, (Math.random() - 0.5) * 3);
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
            '<p class="hi-sub mt-2 text-[13px] leading-[18px] text-muted-foreground">I live on your notch and watch your coding agents. When one finishes or needs your OK, I\u2019ll tell you. Answer it here, or jump straight back in.</p></div></div>') +
        oi(1, '<div class="hi-demo pointer-events-none mx-2.5 mt-3 flex select-none flex-col rounded-lg bg-white/[0.04] py-0.5" aria-hidden="true">' + introRow(0, 'claude', 'Hero spacing', 'Website') + introRow(1, 'codex', 'Install guide', 'Docs') + '</div>') +
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
          '<span class="flex items-center gap-3.5 pl-1.5 text-xs text-muted-foreground"><span class="flex items-baseline gap-1.5">' + Keys('\u2190', '\u2192') + 'Shape</span><span class="flex items-baseline gap-1.5">' + Keys('\u2191', '\u2193') + 'Colour</span></span>');
    } else if (st === 2) {
      h = otitle(o, 'Let Perch reply for you', 'Perch pastes and sends your replies, and listens for its shortcut. macOS asks you to allow it once.') +
        oi(3, '<div class="mt-3 px-4">' + orow(tick(g), 'Accessibility', g ? 'Allowed' : 'Waiting for you\u2026') + '</div>') +
        oi(4, g ? '' : '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">macOS asks next: choose Open System Settings there, then switch Perch on. Switched it on but nothing changes? <button class="o-restart cursor-pointer underline underline-offset-2 hover:text-foreground">Restart Perch</button></p>') +
        ofoot(5, true, g ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), g ? 'Next' : 'Open System Settings', g ? 'next' : 'accessibility');
    } else if (st === 3) {
      h = shortcutStep(o);
    } else if (st === 4) {
      /* Three tiles, one for each way agents are used (GROUPS), each with its agents in a row of small checks that opens
         under it; a tile's own check ticks all of them. The places Perch follows a session into are named inside the
         group they belong to: nothing to choose there, Perch finds them by itself. */
      var grs = groupsOf(o.sources, o.places);
      var tiles = grs.map(function (gr) {
        var open = onbOpenG === gr.g.id, n = gr.list.length, on = gr.list.filter(function (x) { return x.enabled; }).length;
        var names = gr.list.map(function (x) { return x.name; }), line = o.scanning ? 'Scanning\u2026' : names.slice(0, 3).join(', ') + (n > 3 ? ', +' + (n - 3) : '');
        var chips = gr.list.map(function (x) {
          return '<button role="switch" aria-checked="' + x.enabled + '" aria-label="Include ' + esc(x.name) + '" data-id="' + x.id + '" class="o-sw og-chip">' + App(x.id, 'size-3.5') + '<span>' + esc(x.name) + '</span>' + svg('check', 'og-tk size-3') + '</button>';
        }).join('');
        var pl = gr.places.map(function (x) { return '<span class="flex items-center gap-1.5">' + App(x.id, 'size-3.5') + '<span>' + esc(x.name) + '</span></span>'; }).join('');
        return '<div class="og rounded-lg bg-white/[0.06]' + (open ? ' open' : '') + '" data-g="' + gr.g.id + '">' +
          '<div class="og-h flex h-11 cursor-pointer items-center gap-2.5 px-3" aria-expanded="' + open + '"><span class="og-gl grid size-7 flex-none place-items-center rounded-lg bg-white/[0.08] text-foreground/80 transition-opacity' + (on ? '' : ' opacity-50') + '">' + svg(gr.g.ic, 'size-3.5') + '</span>' +
          '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] font-medium leading-4">' + gr.g.name + '</span><span class="o-line block truncate text-xs leading-4 text-muted-foreground' + (o.scanning ? ' opacity-60' : '') + '">' + esc(line) + '</span></span>' +
          '<button role="checkbox" aria-checked="' + (on === n ? 'true' : on ? 'mixed' : 'false') + '" aria-label="Include ' + gr.g.name + '" class="og-ck">' + svg('check', 'og-c size-3') + '<i></i></button>' +
          svg('chevD', 'og-chev size-3 flex-none text-muted-foreground/70') + '</div>' +
          '<div class="og-b' + (open ? '' : ' hidden') + ' px-3 pb-2.5 pt-0.5"><div class="flex flex-wrap gap-1.5">' + chips + '</div>' +
          (pl ? '<p class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs leading-4 text-muted-foreground"><span>Also works in</span>' + pl + '</p>' : '') + '</div></div>';
      }).join('');
      h = otitle(o, 'Choose your apps', 'Perch only reads the ones you tick. You can change this later from the menu bar.') +
        oi(3, '<div class="mt-3 flex flex-col gap-1.5 px-4">' + tiles + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">macOS may ask to let Perch see a project folder. Choose Allow.</p>') +
        ofoot(5, true, '', 'Next', 'next');
    } else if (st === 5) {
      var live = o.live === 'on';
      h = otitle(o, 'Know the moment they need you', 'Your agents tell Perch when they finish or need your OK, and you can answer from the notch.') +
        oi(3, '<div class="mt-3 px-4"><div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]"><span class="flex-1">Live status</span>' +
          '<button role="switch" aria-checked="' + live + '" aria-label="Live status" class="o-live sw"><i></i></button></div></div>') +
        oi(4, '<p class="o-note mt-2 px-4 text-xs leading-4 text-muted-foreground">' + liveNote(live) + '</p>') +
        oi(5, liveFoot(live));
    } else if (st === 6 && o.total === 8) {
      var pon = o.prs === 'on';
      h = otitle(o, 'Know when a pull request needs you', 'Perch asks GitHub, with the gh login you already have, whether checks fail or a review wants changes.') +
        oi(3, '<div class="mt-3 px-4"><div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]">' + svg('pr', 'size-4 flex-none text-muted-foreground') + '<span class="flex-1">PR checks</span>' +
          '<button role="switch" aria-checked="' + pon + '" aria-label="PR checks" class="o-prsw sw"><i></i></button></div></div>') +
        oi(4, '<p class="o-note mt-2 px-4 text-xs leading-4 text-muted-foreground">' + prsNote(pon) + '</p>') +
        oi(5, prsFoot(pon));
    } else {
      h = otitle(o, 'You\u2019re all set!', 'Here is how to reach Perch.') +
        oi(3, '<div class="mt-3 flex flex-col gap-2 px-4 text-[13px]">' + ohint(scKeysHtml(o.shortcut), scWords(o.shortcut)) + ohint(Kbd('\u2303\u2325P'), 'The welcome card') + ohint(Kbd('\u2303\u2325L'), 'Other projects') + ohint('<span class="text-xs text-muted-foreground">Hover</span>', 'Rest on the notch to peek') + '</div>') +
        ofoot(4, true, '', 'Done', 'finish');
    }
    box.className = 'onb' + (animate ? ' go' : '');
    box.innerHTML = h;
    introToken++; introGlow = '';
    if (st === 0) introduce(animate);
    onbBind(box);
  }
  function onbBind(box) {
    box.querySelectorAll('.o-primary').forEach(function (b) { b.onclick = function () { onbDo(b.dataset.a); }; });
    box.querySelectorAll('.o-skip').forEach(function (b) { b.onclick = function () { onbDo('next'); }; });
    box.querySelectorAll('.o-back').forEach(function (b) { b.onclick = function () { onbDo('back'); }; });
    box.querySelectorAll('.o-scr').forEach(function (b) { b.onclick = function () { post({ type: 'shortcut', action: 'reset' }); }; });
    box.querySelectorAll('.o-sc').forEach(function (b) { b.onclick = function () { post({ type: 'shortcut', action: b.dataset.a }); }; });
    box.querySelectorAll('.o-sc-big .kcap').forEach(function (b) { b.onclick = function () { post({ type: 'shortcut', action: 'try' }); }; });
    if (onbStep === 3) scAfter(onbLast);
    box.querySelectorAll('.o-restart').forEach(function (b) { b.onclick = function () { onbDo('restart'); }; });
    /* a click on a group opens it; its own check ticks or clears all of it (a dash means some: it ticks the rest) */
    box.querySelectorAll('.og-h').forEach(function (h) { h.onclick = function (e) { if (e.target.closest('.og-ck')) return; var og = h.parentNode; ogOpen(og, !og.classList.contains('open')); }; });
    box.querySelectorAll('.og-ck').forEach(function (b) { b.onclick = function () {
      var og = b.closest('.og'), on = b.getAttribute('aria-checked') !== 'true';
      og.querySelectorAll('.og-chip').forEach(function (c) { if (c.getAttribute('aria-checked') !== String(on)) { setSw(c, on); post({ type: 'source', id: c.dataset.id, enabled: on }); } });
      ogSync(og);
    }; });
    box.querySelectorAll('.og-chip').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setSw(b, on); ogSync(b.closest('.og')); post({ type: 'source', id: b.dataset.id, enabled: on }); }; });
    box.querySelectorAll('.o-prsw').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setSw(b, on); post({ type: 'setting', key: 'pullRequests', value: on }); }; });
    box.querySelectorAll('.o-live').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setSw(b, on); post({ type: 'hooks', on: on }); }; });
    box.querySelectorAll('.o-shape').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: b.dataset.k, color: charNow.color }); }; });
    box.querySelectorAll('.o-color').forEach(function (b) { b.onclick = function () { pickCharacter({ shape: charNow.shape, color: b.dataset.c }); }; });
  }
  /* ---- the introduction: Perch says who it is (names start with intro: `hello` is the hello beside the notch after setup) ---- */
  var introToken = 0, introGlow = '';
  /* A sample session, drawn like a row of the list: its title and how long ago, and at the right its mark and its project
     in grey. Only a picture: the frame around the two takes no pointer. */
  function introRow(i, app, title, project) {
    return '<div class="hi-row flex h-9 items-center gap-2 px-1.5 text-sm" data-i="' + i + '">' + App(app) +
      '<span class="flex min-w-0 flex-1 items-center gap-2"><span class="min-w-0 truncate font-medium">' + title + '</span><span class="hi-tm flex-none text-xs tabular-nums text-muted-foreground"></span></span>' +
      '<span class="flex flex-none items-center gap-2"><span class="hi-st grid size-4 flex-none place-items-center">' + Spinner('size-3.5', glow(COLORS.running)) + '</span><span class="text-xs text-muted-foreground">' + project + '</span></span></div>';
  }
  function introduce(animate) {
    var tok = introToken, box = q('.onb'), hi = box.querySelector('.cr-hi'), ci = hi.querySelector('.cr-in');
    var say = box.querySelector('.hi-t'), ghost = box.querySelector('.hi-ghost'), bubble = box.querySelector('.hi-say'), sub = box.querySelector('.hi-sub'), rows = box.querySelectorAll('.hi-row');
    var words = 'Hi, I\u2019m Perch.', reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    var at = function (ms, fn) { setTimeout(function () { if (tok === introToken && onbStep === 0) fn(); }, ms); };
    var play = function (cls, ms) { ci.classList.remove(cls); void ci.offsetWidth; ci.classList.add(cls); setTimeout(function () { ci.classList.remove(cls); }, ms); };
    /* the spinner gives way to the row's mark, as in the list: a check when it finished, the prompt for a command waiting for your OK */
    var mark = function (i, k, label) { rows[i].querySelector('.hi-st').innerHTML = Ring(k, label); rows[i].querySelector('.hi-tm').textContent = '1m'; };
    var status = function (i, k, label, mood, glow) {
      mark(i, k, label);
      if (!reduce) rows[i].querySelector('.hi-st').animate([{ opacity: 0, transform: 'scale(.5)' }, { opacity: 1, transform: 'none' }], { duration: 320, easing: 'cubic-bezier(.3,1.4,.5,1)' });
      hi.dataset.m = mood; play('hop', 600);
      introGlow = glow; n.style.setProperty('--gcol', glow || charNow.color);
    };
    var finished = function () { status(0, 'done', 'Finished', 'happy', COLORS.done); };
    var needs = function () { status(1, 'permission', 'Needs your OK', 'alert', COLORS.attention); };
    if (reduce || !animate) {
      say.textContent = words; ghost.textContent = ''; hi.dataset.m = 'awake';
      mark(0, 'done', 'Finished'); mark(1, 'permission', 'Needs your OK');
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
      eyesTo(hi, 2.6, 2);
    });
  }
  function onb(o) {
    if (!o) return;
    /* What a step is drawn from; anything else changes in place. The scan (scanning, counts, names), the switches and live
       status arrive every half second or so: drawing the step again for them took the element under the pointer away
       mid-click and restarted the tiles. */
    var sig = [o.step, o.only, o.step === 2 || o.step === 3 ? o.accessibility : '', o.step === 3 ? JSON.stringify(o.shortcut) : '', o.step === 4 ? o.sources.map(function (x) { return x.id; }).join(',') + '|' + (o.places || []).map(function (x) { return x.id; }).join(',') + '|' + Object.keys(icons).length : ''].join('|');
    if (sig === onbSig) {
      var was = onbLast; onbLast = o;
      if (o.step === 4) onbSources(o);
      if (o.step === 5 && (!was || was.live !== o.live)) onbLive(o);
      if (o.step === 6 && o.total === 8 && (!was || was.prs !== o.prs)) onbPrs(o);
      return;
    }
    /* the introduction uses none of this data: a scan finishing must not cut it short */
    if (o.step === 0 && onbStep === 0 && onbSig && o.only === (onbLast && onbLast.only)) { onbSig = sig; onbLast = o; return; }
    var animate = o.step !== onbStep; if (animate) scWasTried = ''; onbStep = o.step; onbSig = sig; onbRender(o, animate);
    if (animate && o.step === o.total - 1) setTimeout(celebrate, 60);
  }
  /* the apps step, in place: a switch slides, a tile's line fades to what the scan found */
  /* a group's check and icons follow its small checks: all ticked, some (a dash), or none */
  function ogSync(og) {
    var cs = og.querySelectorAll('.og-chip'), on = [].filter.call(cs, function (b) { return b.getAttribute('aria-checked') === 'true'; }).length;
    og.querySelector('.og-ck').setAttribute('aria-checked', on === cs.length ? 'true' : on ? 'mixed' : 'false');
    og.querySelector('.og-gl').classList.toggle('opacity-50', !on);
    [].forEach.call(og.querySelectorAll('.og-f'), function (f, i) { f.classList.toggle('off', cs[i].getAttribute('aria-checked') !== 'true'); });
  }
  /* a group opens under its tile (one at a time) and the card grows to hold it */
  function ogOpen(og, open) {
    var box = q('.onb');
    box.querySelectorAll('.og.open').forEach(function (x) { if (x !== og || !open) { x.classList.remove('open'); x.querySelector('.og-b').classList.add('hidden'); x.querySelector('.og-h').setAttribute('aria-expanded', 'false'); } });
    var b = og.querySelector('.og-b');
    og.classList.toggle('open', open); b.classList.toggle('hidden', !open); og.querySelector('.og-h').setAttribute('aria-expanded', String(open));
    onbOpenG = open ? og.dataset.g : '';
    if (open && !STILL) b.animate([{ opacity: 0, transform: 'translateY(-4px)' }, { opacity: 1, transform: 'none' }], { duration: 220, easing: 'ease-out' });
    if (snap && lastSt === 'onb') layout('onb', snap);
  }
  /* the apps step, in place: a check slides, a tile's line fades to what the scan found */
  function onbSources(o) {
    var src = function (id) { return o.sources.filter(function (y) { return y.id === id; })[0]; };
    q('.onb').querySelectorAll('.og-chip').forEach(function (b) { var x = src(b.dataset.id); if (x && b.getAttribute('aria-checked') !== String(x.enabled)) setSw(b, x.enabled); });
    q('.onb').querySelectorAll('.og').forEach(function (og) {
      ogSync(og);
      var gr = groupsOf(o.sources, o.places).filter(function (y) { return y.g.id === og.dataset.g; })[0], sub = og.querySelector('.o-line'), line;
      if (!gr) return;
      var n = gr.list.length;
      line = o.scanning ? 'Scanning\u2026' : gr.list.map(function (x) { return x.name; }).slice(0, 3).join(', ') + (n > 3 ? ', +' + (n - 3) : '');
      if (sub.textContent === line) return;
      sub.textContent = line; sub.classList.toggle('opacity-60', !!o.scanning);
      if (!STILL) sub.animate([{ opacity: 0 }, { opacity: o.scanning ? .6 : 1 }], { duration: 280, easing: 'ease-out' });
    });
  }
  /* live status turned on or off: the switch slides, the note and the buttons follow */
  function onbLive(o) {
    var on = o.live === 'on', box = q('.onb'), b = box.querySelector('.o-live'), note = box.querySelector('.o-note'), foot = box.querySelector('.o-foot');
    if (b && b.getAttribute('aria-checked') !== String(on)) setSw(b, on);
    if (note) note.textContent = liveNote(on);
    if (foot) { foot.parentNode.innerHTML = liveFoot(on); onbBind(box); }
  }
  /* PR checks turned on or off on its step: the switch slides, the note and the buttons follow */
  function onbPrs(o) {
    var on = o.prs === 'on', box = q('.onb'), b = box.querySelector('.o-prsw'), note = box.querySelector('.o-note'), foot = box.querySelector('.o-foot');
    if (b && b.getAttribute('aria-checked') !== String(on)) setSw(b, on);
    if (note) note.textContent = prsNote(on);
    if (foot) { foot.parentNode.innerHTML = prsFoot(on); onbBind(box); }
  }
  /* Return and the arrow keys, forwarded from the app while the card has the keyboard. */
  function onbKey(k) {
    if (k === 'enter') { var b = q('.o-primary'); if (b) b.click(); return; }
    /* S skips a step that can be skipped; Left goes back, except on the character page where it changes the shape */
    if (k === 'skip') { var sk = q('.o-skip'); if (sk) sk.click(); return; }
    /* C changes the shortcut on its step */
    if (k === 'change') { var ch = q('.o-sc'); if (ch && ch.dataset.a === 'record') ch.click(); return; }
    if (k === 'left' && onbStep !== 1) { var bk = q('.o-back'); if (bk) bk.click(); return; }
    if (onbStep !== 1) return;
    /* left and right change the shape, up and down the colour (up goes right along the swatches); both wrap */
    var d = (k === 'right' || k === 'up') ? 1 : -1, i = 0;
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

  /* ---- settings, inside the notch ----
     A short list of categories, each saying what it is set to now. Right or Return opens one; Left or Esc comes back, and
     on the list itself goes back to where Settings came from. A category shows its settings inline, with no menus to drop
     down, so a page is only as tall as it needs. Character opens its picker; Send feedback is the last row. */
  var setLast = null, setSig = '', setPage = '', setSlide = 0, setRootAt = 0;
  var SET_PAGES = [['shortcuts', 'Shortcuts', 'keyboard'], ['agents', 'Agents', 'grid'], ['notify', 'Notifications', 'bell'], ['character', 'Character', 'cat'], ['general', 'General', 'gear']];
  var SET_TITLES = { shortcuts: 'Shortcuts', agents: 'Agents', notify: 'Notifications', general: 'General' };
  /* a switch changes in place so it slides, with a double settle (.sw.is-init); redrawing it would just snap to the new state */
  function setSw(b, on) {
    if (b.getAttribute('aria-checked') !== String(on)) b.classList.add('is-init');
    b.setAttribute('aria-checked', String(on));   /* .sw in input.css draws it from this */
  }
  /* the same setting as a plain check at the right, nothing while it is off (the look of the Notifications menu's moments):
     a click anywhere on its row flips it, as with a switch */
  function ckHtml(on, key, label) {
    return '<button role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-k="' + key + '" class="s-sw ck">' + svg('check', 'size-4') + '</button>';
  }
  function swHtml(on, key, label) {
    return '<button role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-k="' + key + '" class="s-sw sw"><i></i></button>';
  }
  /* Pull requests, one row, three choices: nothing, the mark (from the Claude app's own list), or the mark with checks (asks GitHub through
     the GitHub CLI's login). Checks is greyed while there is no CLI or no login, and the line says what to do. */
  function prsMode(o) { return o.showPRs === false ? 'off' : o.prs === 'on' ? 'checks' : 'marks'; }
  function prsDesc(o) {
    /* one line each: this page has no room for two */
    if (prsMode(o) === 'off') return 'No mark on any session';
    if (o.prs === 'nogh') return 'Marks only: Checks needs the GitHub CLI';
    if (o.prs === 'login') return 'Marks only: Checks needs gh auth login';
    return prsMode(o) === 'checks' ? 'Also asks GitHub if checks fail or changes are wanted' : 'A mark on a session that made a pull request';
  }
  function prsSeg(o) {
    var mode = prsMode(o), nocli = o.prs === 'nogh' || o.prs === 'login';
    return '<span class="flex rounded-md bg-white/[0.07] p-0.5">' + [['off', 'Off'], ['marks', 'Marks'], ['checks', 'Checks']].map(function (x) {
      var dis = x[0] === 'checks' && nocli;
      return '<button class="s-prm h-5 rounded px-2 text-xs transition-colors ' + (mode === x[0] ? 'bg-white/[0.16] text-foreground' : 'text-muted-foreground' + (dis ? ' opacity-40' : ' cursor-pointer hover:text-foreground')) + (dis ? '" disabled="' : '') + '" data-m="' + x[0] + '">' + x[1] + '</button>';
    }).join('') + '</span>';
  }
  function srow(left, right) { return '<div class="s-row mx-2 flex h-[30px] items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors">' + left + '<span class="flex-none">' + right + '</span></div>'; }
  /* a setting with a line under it saying what it does; the line runs under the whole row, past the control */
  function drow(left, desc, right) {
    /* the line is as tall as a segment (24 pt), so the control never reaches the words under it */
    return '<div class="s-row mx-2 flex flex-col justify-center rounded-md px-2 py-1 text-[13px] transition-colors"><span class="flex h-6 items-center gap-2.5">' + left + '<span class="flex-none">' + right + '</span></span>' +
      '<span class="block pl-[26px] pt-[3px] text-[11.5px] leading-[15px] text-muted-foreground">' + desc + '</span></div>';
  }
  /* a few words over a group of rows: not a row, the keys pass it by */
  function shead(t) { return '<div class="mx-2 px-2 pb-1 pt-2 text-[11.5px] font-medium text-muted-foreground/80">' + t + '</div>'; }
  /* each setting leads with its mark in a small quiet tile, so the rows tell apart at a glance ('-' keeps the room, empty) */
  function stile(ic) { return ic === '-' ? '<span class="size-[18px] flex-none" aria-hidden="true"></span>' : ic ? '<span class="grid size-[18px] flex-none place-items-center rounded-[5px] bg-white/[0.08] text-muted-foreground" aria-hidden="true">' + svg(ic, 'size-[11px]') + '</span>' : ''; }
  function slabel(t, sub, ic) {
    var txt = t + (sub ? ' <span class="text-muted-foreground">' + sub + '</span>' : '');
    return ic ? '<span class="flex min-w-0 flex-1 items-center gap-2">' + stile(ic) + '<span class="min-w-0 truncate">' + txt + '</span></span>' : '<span class="min-w-0 flex-1 truncate">' + txt + '</span>';
  }
  /* a row that is one thing (an agent, a moment, a screen): its mark first, dimmed while it is off */
  function sthing(mark, name, on, after) {
    return '<span class="flex min-w-0 flex-1 items-center gap-2"><span class="s-dim grid size-[18px] flex-none place-items-center transition-opacity' + (on ? '' : ' opacity-40') + '">' + mark + '</span><span class="min-w-0 truncate' + (on ? '' : ' text-muted-foreground') + '">' + name + '</span>' + (after || '') + '</span>';
  }
  /* a click anywhere on such a row switches or picks it */
  function stap(html, attrs) { return html.replace('<div class="', '<div ' + (attrs || '') + ' class="s-tap cursor-pointer '); }
  function setHints(l) { return '<span class="flex items-center gap-3.5 pl-1.5 text-xs text-muted-foreground">' + l.map(function (h) { return '<span class="flex items-baseline gap-1.5">' + (h[0] === '\u2191\u2193' ? Keys('\u2191', '\u2193') : Kbd(h[0])) + h[1] + '</span>'; }).join('') + '</span>'; }
  function showNow(o) { var all = showChoices(o), cur = o.showOn || 'mouse'; return all.filter(function (x) { return x.id === cur; })[0] || all[0]; }
  /* what each switch says, by its key, so a refresh slides only the ones that moved */
  function swVal(o, k) {
    if (k === 'login') return !!o.login;
    if (k === 'live') return o.live === 'on';
    if (k === 'hover') return !!o.hoverExternal;
    if (k === 'fbinfo') return fbInfo;
    if (/^src:/.test(k)) return o.sources.some(function (x) { return x.id === k.slice(4) && x.enabled; });
    if (/^ntf:/.test(k)) return notifyOn(k.slice(4));
    return false;
  }
  /* The moments the notch announces: one row with the lit ones as small coloured icons, opening a menu with a check for each. */
  var notifyMenuOpen = false, ntFocus = 0;
  /* the card is measured again after the menu opens or folds, so it has room for all of it */
  function ntRelayout() { if (snap && lastSt === 'set') layout('set', snap); }
  function notifyMoments(o) {
    var list = notifyList(o);
      /* one row: the lit moments as icons and a chevron; it opens a menu over the rows below, a check for each moment that is on */
      var faces = list.filter(function (x) { return notifyOn(x[0]) && !(x[0] === 'ci' && ciOff(o)); }).map(function (x) { return nCol(x[0]); }).join('');
      var items = list.map(function (x, i) {
        var y = notifyOn(x[0]), dis = x[0] === 'ci' && ciOff(o);
        return '<div class="' + (dis ? '' : 's-nt cursor-pointer ') + 'nt-it flex h-8 items-center gap-2.5 rounded-lg px-2.5 text-[13px] transition-colors' + (dis ? '' : ' hover:bg-white/[0.07]') + '" data-i="' + i + '" data-k="' + x[0] + '" aria-pressed="' + y + '">' +
          '<span class="grid flex-none transition-opacity ' + (y && !dis ? '' : dis ? 'opacity-25' : 'opacity-40') + '">' + nCol(x[0]) + '</span><span class="min-w-0 flex-1 truncate ' + (y && !dis ? '' : 'text-muted-foreground') + '">' + esc(x[1]) + '</span>' +
          (dis ? '<span class="flex-none text-xs text-muted-foreground/70">Needs Checks</span>' : '<span class="grid size-4 flex-none place-items-center text-foreground/80">' + (y ? svg('check', 'size-4') : '') + '</span>') + '</div>';
      }).join('');
      var menu = notifyMenuOpen ? '<div class="nt-menu absolute right-0 top-[34px] z-30 w-[250px] rounded-xl bg-[#1c1c1f] p-1 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.09),0_12px_32px_rgba(0,0,0,0.6)]">' + items + '</div>' : '';
      return '<div class="s-row s-menu relative mx-2 flex h-[30px] cursor-pointer items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors">' + slabel('Notify me about', '', 'bell') +
        '<span class="flex flex-none items-center gap-1.5 rounded-lg bg-white/[0.07] py-1 pl-2 pr-1.5">' + (faces ? '<span class="flex items-center gap-1.5">' + faces + '</span>' : '<span class="text-xs text-muted-foreground">Nothing</span>') + svg(notifyMenuOpen ? 'chevU' : 'chevD', 'size-3 flex-none text-muted-foreground') + '</span>' + menu + '</div>';
  }
  var scSetSaved = '';
  var axAsked = false;   /* Allow was clicked: if it is still not working, the switch in System Settings is stale */
  function settingsRender(o) {
    setLast = o;
    if (o.accessibility) axAsked = false;   /* on now: if it is ever lost again, the row starts over at Allow */
    var sc = scOf(o.shortcut), chev = svg('chevR', 'size-3 flex-none text-muted-foreground/60');
    var small = function (t, c) { return '<span class="min-w-0 truncate text-xs' + (c ? '' : ' text-muted-foreground') + '"' + (c ? ' style="color:' + c + '"' : '') + '>' + t + '</span>'; };
    /* nothing to do when it is allowed, so the row only shows while it is not: what is wrong in orange, and Allow, the one thing to do here */
    var axRow = o.accessibility ? '' : srow(slabel('Reply and shortcuts', axAsked ? 'turn on in System Settings' : '<span style="color:' + COLORS.attention + '">' + (o.accessWas ? 'needs access again' : 'needs access') + '</span>', 'access'), Button('ghost', axAsked ? 'Open' : 'Allow', '', 's-ax s-gr bg-white/[0.08] text-foreground" title="Opens Accessibility in System Settings with a fresh switch for this build of Perch. Turn it on there.'));
    var html, by = setSlide; setSlide = 0;
    if (setPage === 'feedback') html = fbHtml();
    else {
      var rows, foot;
      if (!setPage) {
        var sh = shapeOf(charNow.shape), colorName = ''; PALETTE.forEach(function (c) { if (c[1] === charNow.color) colorName = c[0].toLowerCase(); });
        var on = o.sources.filter(function (x) { return x.enabled; }), marks = notifyList(o).filter(function (x) { return notifyOn(x[0]) && !(x[0] === 'ci' && ciOff(o)); });
        var faces = function (l) { return '<span class="flex flex-none gap-[3px]">' + l.join('') + '</span>'; };
        /* each category says what it is set to now, so the list alone answers most questions */
        var sum = {
          shortcuts: scKeysHtml(sc, sc.works ? '' : COLORS.attention),
          agents: (o.live === 'on' ? '' : small('Live status off')) + (on.length ? faces(on.map(function (x) { return App(x.id, 'size-4'); })) : small('None')),
          notify: marks.length ? faces(marks.map(function (x) { return nMark(x[0]); })) : small('Nothing'),
          character: small(esc(sh[1]) + ', ' + colorName),
          general: small(esc(showNow(o).name))
        };
        var go = function (id, label, ic, right) { return srow(slabel(label, '', ic), '<span class="flex items-center gap-2">' + right + chev + '</span>').replace('<div class="', '<div data-go="' + id + '" class="s-go cursor-pointer ' + (id === 'character' ? 's-char ' : '')); };
        /* which build this is, and on the right where its update stands: Check for updates when there is nothing to say,
           what is out with Update, a ring while it downloads, Restart to update, a failure in orange with what to do. A local
           test build has no updater: its version only, and no row when the notch already says it is a test build. */
        var ver = snap && !snap.testBuild && snap.version ? '<span class="tabular-nums">' + esc(snap.version) + '</span>' : '';
        var upd = snap && snap.canUpdate ? srow(slabel('Version', ver, 'tag'), '<span class="flex items-center gap-2"><span class="s-updsub min-w-0 truncate text-xs text-muted-foreground">' + updSub(snap) + '</span><span class="s-updslot flex h-6 items-center gap-1.5">' + updSlot(snap) + '</span></span>')
          : ver ? srow(slabel('Version', ver, 'tag'), '') : '';
        rows = axRow + SET_PAGES.map(function (p) { return go(p[0], p[1], p[2], sum[p[0]]); }).join('') +
          upd + go('feedback', 'Send feedback', 'chat', '<span class="fb-st flex items-center text-xs"><span class="fb-ic t-ic"></span><span class="t-swap"></span></span>');
        foot = setHints([['\u2191\u2193', 'Choose'], ['\u2192', 'Open']]) + '<span class="flex-1"></span>' + Button('ghost', 'Quit Perch', '', 's-quit') + Button('default', o.back ? 'Back' : 'Done', Kbd('esc', 1), 's-done');
      } else {
        /* the page says which it is under the notch's line (beside the notch there is room only for Settings), with Left as
           its way back, drawn as the key, as Raycast does */
        rows = '<div class="mx-2 flex h-7 items-center gap-2 px-1.5"><button aria-label="Back" title="Back (\u2190)" class="s-back -my-1 flex h-6 flex-none cursor-pointer items-center rounded-md px-0.5 opacity-75 transition-opacity hover:opacity-100">' + Kbd('\u2190') + '</button>' +
          '<span class="truncate text-[13px] font-medium">' + SET_TITLES[setPage] + '</span></div>' + pageRows(o, sc, axRow);
        foot = '<span class="flex flex-1 justify-center">' + setHints([['\u2191\u2193', 'Choose'], [ENTER, 'Change'], ['\u2190', 'Back']]) + '</span>';
      }
      /* the keys, like the list's: every setting can be changed without the mouse */
      html = '<div>' + rows + '</div><div class="mt-1 flex h-9 items-end gap-1 px-2.5">' + foot + '</div>';
    }
    /* inside a category, Settings steps back and is a way back */
    var title = setPage ? '<button class="s-crumb cursor-pointer rounded text-muted-foreground transition-colors hover:text-foreground" title="Back (\u2190)">Settings</button>' : 'Settings';
    /* a category opens from the right and comes back from the left, the old page going the other way (transitions.dev page side by side) */
    var pane = q('.p-set'), slid = by && !STILL ? crossSeen(pane, ['.set']) : [];
    var box = q('.set');
    box.innerHTML = html; q('.s-title').innerHTML = title;
    /* the moments' menu opens over the rows below: the card keeps room for all of it, and the footer under it */
    box.style.minHeight = setPage === 'notify' && notifyMenuOpen ? (34 + notifyList(o).length * 32 + 20 + 36) + 'px' : '';
    slid.forEach(function (x) {
      if (!x.g) return;
      var dx = by > 0 ? 8 : -8, g = x.g, gone = function () { g.remove(); };
      pane.appendChild(g);
      g.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateX(' + (-dx) + 'px)', filter: 'blur(3px)' }], { duration: 250, easing: SMOOTH, fill: 'forwards' }).onfinish = gone;
      setTimeout(gone, 370);   /* the timer finishes it even when animations are paused */
      x.el.animate([{ opacity: 0, transform: 'translateX(' + dx + 'px)', filter: 'blur(3px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], { duration: 250, easing: SMOOTH });
    });
    var crumb = q('.s-crumb'); if (crumb) crumb.onclick = function () { setGo(''); };
    if (setPage === 'feedback') { fbBind(box); return; }
    box.querySelectorAll('.s-row').forEach(function (r, i) { r.addEventListener('mouseenter', function () { if (ptrMoved()) { setFocus = i; setHot = i; setKb = false; paintFocus(); } }); r.addEventListener('mouseleave', function () { if (setHot === i) { setHot = -1; paintFocus(); } }); });
    paintFocus();
    box.querySelectorAll('.s-go').forEach(function (r) { r.onclick = function () { setGo(r.dataset.go); }; });
    box.querySelectorAll('.s-grp').forEach(function (r) { r.onclick = function () { setGroup = setGroup === r.dataset.g ? '' : r.dataset.g; setSig = ''; settingsApply(setLast); ntRelayout(); }; });
    box.querySelectorAll('.s-tap').forEach(function (r) { r.onclick = function (e) {
      if (e.target.closest('.s-sw')) return;
      if (r.dataset.show) { post({ type: 'setting', key: 'showOn', value: r.dataset.show }); return; }
      var c = r.querySelector('.s-sw'); if (c) c.click();
    }; });
    box.querySelectorAll('.s-sw').forEach(function (b) { b.onclick = function () {
      var on = b.getAttribute('aria-checked') !== 'true', k = b.dataset.k, r = b.closest('.s-row'), dm = r && r.querySelector('.s-dim');
      setSw(b, on);   /* slide now; the app confirms (or puts it back) a moment later */
      if (dm) { dm.classList.toggle('opacity-40', !on); dm.nextSibling.classList.toggle('text-muted-foreground', !on); }
      if (k === 'login') post({ type: 'setting', key: k, value: on });
      else if (k === 'live') post({ type: 'hooks', on: on });
      else if (k === 'hover') post({ type: 'setting', key: 'hoverExternal', value: on });
      else if (/^src:/.test(k)) post({ type: 'source', id: k.slice(4), enabled: on });
      else if (/^ntf:/.test(k)) post({ type: 'notify', kind: k.slice(4), enabled: on });
    }; });
    bindUpdSlot(box, snap); fbRow(true);
    /* a shortcut you just recorded: its keys spring once, so it never lands without a word */
    var chip = box.querySelector('button.s-sc');
    if (chip && sc.saved && !sc.recording && scSetSaved !== sc.keys.join('')) { if (chip.animate && !STILL) chip.animate([{ transform: 'scale(.9)' }, { transform: 'scale(1.14)', offset: .5 }, { transform: 'scale(1)' }], { duration: 480, easing: 'cubic-bezier(.3,1.4,.5,1)' }); }
    scSetSaved = sc.saved ? sc.keys.join('') : '';
    var row = box.querySelector('.s-char');
    if (row) { row.onmouseenter = function () { if (cr.dataset.m === 'awake') { cr.dataset.m = 'happy'; look(-1.2, 1.6); } }; row.onmouseleave = function () { if (cr.dataset.m === 'happy') cr.dataset.m = 'awake'; }; }
    box.querySelectorAll('.s-seg').forEach(function (b) { b.onclick = function () { post({ type: 'setting', key: b.dataset.key, value: +b.dataset.m }); }; });
    box.querySelectorAll('.s-nt').forEach(function (b) {
      b.onclick = function (e) { if (e) e.stopPropagation(); post({ type: 'notify', kind: b.dataset.k, enabled: b.getAttribute('aria-pressed') !== 'true' }); };
      var ln = box.querySelector('.s-ntl'), was = ln && ln.innerHTML;
      if (ln && b.dataset.name) { b.onmouseenter = function () { ln.textContent = b.dataset.name + ' \u00b7 ' + (b.getAttribute('aria-pressed') === 'true' ? 'on' : 'off'); }; b.onmouseleave = function () { ln.innerHTML = was; }; }
    });
    box.querySelectorAll('.s-menu').forEach(function (r) { r.onclick = function (e) { if (e.target.closest('.nt-menu')) return; notifyMenuOpen = !notifyMenuOpen; ntFocus = 0; setSig = ''; settingsApply(setLast); ntRelayout(); }; });
    box.onclick = function (e) { if (notifyMenuOpen && !e.target.closest('.s-menu')) { notifyMenuOpen = false; setSig = ''; settingsApply(setLast); ntRelayout(); } };
    box.querySelectorAll('.s-prm').forEach(function (b) { b.onclick = function () {
      var m = b.dataset.m; post({ type: 'setting', key: 'showPullRequests', value: m !== 'off' }); post({ type: 'setting', key: 'pullRequests', value: m === 'checks' });
    }; });
    var on2 = function (sel, fn) { box.querySelectorAll(sel).forEach(function (b) { b.onclick = fn; }); };
    on2('.s-sc', function () { post({ type: 'onbOpen', step: 3, only: true }); });
    on2('.s-scr', function () { post({ type: 'shortcut', action: 'reset' }); });
    on2('.s-nsc', function () { post({ type: 'onbOpen', step: 3, only: true, which: 'new' }); });
    on2('.s-ax', function () { axAsked = true; post({ type: 'onb', action: 'accessibility' }); if (snap && snap.settings) settingsApply(snap.settings); });   /* the row says turn on in System Settings at once */
    on2('.s-quit', function () { post({ type: 'quit' }); });
    /* Esc and this button go back to the card or list Settings came from, or close it when it came from elsewhere */
    on2('.s-done', function () { post({ type: setLast && setLast.back ? 'back' : 'dismiss' }); });
    on2('.s-back', function () { setGo(''); });
  }
  /* a category's own rows */
  function pageRows(o, sc, axRow) {
    var gap = '<div class="h-1.5"></div>';
    if (setPage === 'shortcuts') {
      /* when it does not work the keys turn orange and the tooltip says why; the Accessibility row below carries the fix. The recorder page says it in words. */
      var scRow = srow('<span class="flex min-w-0 flex-1 items-center gap-2">' + stile('keyboard') + '<span class="truncate">Open Perch</span><button class="s-sc -my-0.5 cursor-pointer rounded-md px-0.5 py-0.5 transition hover:bg-white/10 active:scale-95" aria-label="Change the shortcut" title="' + (sc.works ? 'Change' : sc.why) + '">' + scKeysHtml(sc, sc.works ? '' : COLORS.attention) + '</button></span>', '<span class="s-gr flex items-center gap-1">' + Button('ghost', 'Change', '', 's-sc') + (sc.custom ? Button('ghost', 'Reset', '', 's-scr') : '') + '</span>');
      /* the shortcut that opens Perch straight on a new session (a global hotkey too; Finder takes the same keys for New Smart Folder, so it can change) */
      var nsc = o.newShortcut || { keys: ['\u2325', '\u2318', 'N'], custom: false };
      var newRow = srow('<span class="flex min-w-0 flex-1 items-center gap-2">' + stile('plus') + '<span class="truncate">New session</span><button class="s-nsc -my-0.5 cursor-pointer rounded-md px-0.5 py-0.5 transition hover:bg-white/10 active:scale-95" aria-label="Change the new session shortcut" title="Change">' + scKeysHtml({ keys: nsc.keys }) + '</button></span>', '<span class="s-gr flex items-center gap-1">' + Button('ghost', 'Change', '', 's-nsc') + '</span>');
      return scRow + newRow + axRow;
    }
    if (setPage === 'agents') {
      /* the agents by how you use them (GROUPS): three rows, one of which opens to show its agents, with a check for each.
         Closed, a group's icons say which are on. */
      return groupsOf(o.sources).map(function (gr) {
        var open = setGroup === gr.g.id;
        var head = '<div class="s-row s-grp mx-2 flex h-[30px] cursor-pointer items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors" data-g="' + gr.g.id + '" aria-expanded="' + open + '">' + slabel(gr.g.name, '', gr.g.ic) +
          '<span class="flex flex-none items-center gap-2">' + (open ? '' : faceStack(gr.list, 'size-4', true)) + svg(open ? 'chevU' : 'chevD', 'size-3 flex-none text-muted-foreground/60') + '</span></div>';
        /* an open group's agents sit two to a row, so even five of them leave room for what is under them */
        return head + (open ? '<div class="ml-7 mr-2 grid grid-cols-2">' + gr.list.map(function (x) {
          var cnt = x.count ? '<span class="flex-none text-xs tabular-nums text-muted-foreground">' + x.count + '</span>' : '';
          return stap(srow(sthing(App(x.id, 'size-4'), esc(x.name), x.enabled, cnt), ckHtml(x.enabled, 'src:' + x.id, x.name)).replace('s-row mx-2', 's-row'));
        }).join('') + '</div>' : '');
      }).join('') + gap +
        stap(drow(slabel('Live status', '', 'pulse'), 'A small hook in each agent tells Perch the moment it waits', swHtml(o.live === 'on', 'live', 'Live status'))) +
        gap + drow(slabel('Pull requests', '', 'pr'), prsDesc(o), prsSeg(o));
    }
    if (setPage === 'notify') {
      /* a small segmented choice: each button says which setting it is (data-key) and its value (data-m) */
      var segOf = function (key, vals, name) {
        return '<span class="flex rounded-md bg-white/[0.07] p-0.5">' + vals.map(function (m) {
          return '<button class="s-seg h-5 cursor-pointer rounded px-2 text-xs transition-colors ' + (o[key] === m ? 'bg-white/[0.16] text-foreground' : 'text-muted-foreground hover:text-foreground') + '" data-key="' + key + '" data-m="' + m + '">' + name(m) + '</button>';
        }).join('') + '</span>';
      };
      /* which moments the notch announces (the list and the cards say all of them) */
      return notifyMoments(o) + gap +
        /* the minutes are how long you are away, not a reminder after an agent replies */
        drow(slabel('Welcome back after', '', 'timer'), 'Away this long, and the card says where you left off', segOf('idleMinutes', [10, 20, 60], function (m) { return m === 60 ? '1 hour' : m + ' min'; })) +
        /* a question nobody answers leaves the notch after this long (it stays in the list) */
        drow(slabel('Questions stay for', '', 'hourglass'), 'Then they wait in the list', segOf('questionSeconds', [30, 60, 300], function (m) { return m === 300 ? '5 min' : m === 60 ? '1 min' : m + ' s'; }));
    }
    if (setPage === 'general') {
      /* Where the shortcut opens Perch and where it shows up by itself; hovering a screen's top still opens it on that screen.
         One check: the two ways of following you, then each display by name. A display you chose that is not connected
         stays listed, greyed, so the choice is still there to see; until it is back Perch follows the mouse. While a
         display without a notch is connected, Hover opens on external displays follows them. */
      var now = showNow(o), mark = { mouse: 'pointer', window: 'win' };
      var screens = showChoices(o).map(function (x) {
        var y = x.id === now.id;
        return stap(srow(sthing(svg(mark[x.id] || 'monitor', 'size-3.5 text-muted-foreground'), esc(x.name), x.on, x.on ? '' : '<span class="flex-none text-xs text-muted-foreground">Not connected</span>'),
          '<span class="flex size-4 items-center justify-center">' + (y ? svg('check', 'size-3.5') : '') + '</span>'), 'role="menuitemradio" aria-checked="' + y + '" data-show="' + x.id + '"');
      }).join('');
      var hover = o.hasExternal ? stap(drow(slabel('Hover opens on external displays', '', '-'), 'Rest the pointer on its top edge and Perch opens there', swHtml(!!o.hoverExternal, 'hover', 'Hover opens on external displays'))) : '';
      return srow(slabel('Open at login', '', 'login'), swHtml(o.login, 'login', 'Open at login')) + gap + shead('Show Perch on') + screens + hover;
    }
    return '';
  }
  /* a category, the list (''), Character's picker, or feedback; `still` opens it in place, without the slide */
  function setGo(id, still) {
    if (!setPage) setRootAt = setFocus;
    if (id === 'character') { post({ type: 'onbOpen', step: 1, only: true }); return; }
    if (id === setPage) return;
    var was = setPage;
    setSlide = still ? 0 : id ? 1 : -1;
    setPage = id; setGroup = ''; setFocus = id ? 0 : setRootAt; setKb = true; setHot = -1;
    /* the app gives Send feedback's fields the keys while it is open, and takes files dropped on the card */
    if (id === 'feedback' || was === 'feedback') post({ type: 'feedbackOpen', open: id === 'feedback' });
    if (id === 'feedback' && fbState === 'sent') fbState = '';
    if (!id) { var a = document.activeElement; if (a && a.blur) a.blur(); }
    setSig = ''; if (setLast) settingsApply(setLast);
    /* back on the list, on the row of the page you left */
    if (!id && was) { var rows = [].slice.call(q('.set').querySelectorAll('.s-row')), at = rows.indexOf(q('.set .s-go[data-go=' + was + ']')); if (at >= 0) { setFocus = at; paintFocus(); } }
    if (snap && lastSt === 'set') layout('set', snap);
  }

  /* ---- feedback, from Settings ----
     Your words, files dropped on the card, pasted or attached, and an email if you would like an answer. Return sends;
     Esc, or Left in an empty field, goes back and keeps what you wrote (the Send feedback row says Draft). Sent, your
     words fly into the notch and the list comes back, its Send feedback row saying how it is going. */
  var fbText = '', fbMail = '', fbFiles = [], fbInfo = true, fbState = '', fbFlying = false;   /* fbState: '', sending, sent, failed */
  var fbGlow = { at: 0, k: '' };   /* the card glows green for a moment when it goes, orange when it could not */
  function fbHas() { return !!(fbText.trim() || fbFiles.length); }
  function fbHtml() {
    var ver = (snap && snap.version) || '0.4.3', mac = (snap && snap.macOS) || '26.1';
    /* the title as a category's, with Esc as its way back: Left moves through your words here */
    return '<div class="mx-2 flex h-7 items-center gap-2 px-1.5"><button aria-label="Back" title="Back (Esc)" class="fb-back -my-1 flex h-6 flex-none cursor-pointer items-center rounded-md px-0.5 opacity-75 transition-opacity hover:opacity-100">' + Kbd('esc') + '</button>' +
      '<span class="truncate text-[13px] font-medium">Send feedback</span></div>' +
      '<div class="fb px-2.5">' +
      '<p class="px-1 pb-2 text-[12px] leading-4 text-muted-foreground">Bugs, ideas, anything. It goes straight to the maker of Perch.</p>' +
      /* the field is a box: the files attached along its top, then your words */
      '<div class="fb-box rounded-lg bg-white/[0.1] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] transition-[background-color,box-shadow] duration-200 focus-within:bg-white/[0.13] focus-within:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]">' +
        '<div class="fb-att mx-2 hidden gap-1 overflow-x-auto pt-2"></div>' +
        '<textarea class="fb-in block cursor-text max-h-[150px] min-h-[92px] w-full resize-none bg-transparent px-2.5 py-[7px] text-[13px] leading-[19px] text-foreground caret-white outline-none placeholder:text-white/35" rows="1" spellcheck="true" placeholder="What happened, or what you wish Perch did\u2026" aria-label="Feedback"></textarea></div>' +
      '<input class="fb-mail mt-1.5 block h-7 w-full cursor-text rounded-lg bg-white/[0.06] px-2.5 text-[13px] text-foreground caret-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)] outline-none transition-[background-color,box-shadow] duration-200 placeholder:text-white/35 focus:bg-white/[0.1] focus:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]" type="email" spellcheck="false" autocomplete="email" placeholder="Your email, if you\u2019d like an answer" aria-label="Your email">' +
      /* what else goes with it, said plainly; on by default, a click turns it off */
      '<div class="s-tap fb-inf mt-1.5 flex h-6 cursor-pointer items-center gap-2 px-1 text-[12px] text-muted-foreground">' + swHtml(fbInfo, 'fbinfo', 'Include version details') + '<span class="truncate">Include Perch ' + esc(ver) + ' and macOS ' + esc(mac) + '</span></div>' +
      /* what stands in the way, in orange, when something does: files over the limit, or a send that failed */
      '<p class="fb-err mt-1 hidden px-1 text-[12px] leading-4" style="color:' + COLORS.attention + '"></p>' +
      '</div>' +
      '<div class="mt-1 flex h-9 items-end gap-1 px-2.5">' +
        Button('ghost', svg('clip', 'size-3') + 'Attach', Kbd('\u2318O'), 'fb-attach -ml-1') + '<span class="flex-1"></span>' +
        /* the way round both: Mail, with a new message to the maker of Perch, your words and files in it */
        Button('ghost', 'Email it instead', '', 'fb-mailit hidden') +
        Button('default', '<span class="fb-send-l">Send</span>', Kbd(ENTER, 1), 'fb-send pr-0.5') +
      '</div>';
  }
  function fbBind(box) {
    var ta = box.querySelector('.fb-in'), mail = box.querySelector('.fb-mail');
    ta.value = fbText; mail.value = fbMail; fbAtt(); fbPaint(true);
    ta.oninput = function () { fbText = ta.value; if (fbState === 'failed') fbState = ''; fbGrow(ta); fbPaint(); };
    /* An email that does not look like one is said once you leave the field or press Send, never while you type; said,
       it goes away the moment the address is right (or the field is empty: an email is not needed) */
    mail.oninput = function () { fbMail = mail.value; if (fbMailSaid) { if (!fbMailBad()) fbMailSaid = false; fbPaint(); } };
    mail.onblur = function () { if (fbMailBad() && !fbMailSaid) { fbMailSaid = true; fbPaint(); } };
    var keys = function (e, el) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); e.stopPropagation(); fbSend(); }
      else if (e.metaKey && (e.key === 'o' || e.key === 'O')) { e.preventDefault(); e.stopPropagation(); post({ type: 'feedbackAttach' }); }   /* the app takes Command+O first */
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); setGo(''); }
      /* Left is Back here too, once there is nothing in the field for it to move through */
      else if (e.key === 'ArrowLeft' && !el.value && !(el === ta && fbFiles.length)) { e.preventDefault(); e.stopPropagation(); setGo(''); }
      else if (e.key === 'Backspace' && el === ta && fbFiles.length && !ta.selectionStart && !ta.selectionEnd) { e.preventDefault(); fbFiles.pop(); fbAtt(); fbPaint(); }
      else if (e.key === 'ArrowDown' && el === ta && ta.selectionStart === ta.value.length) { e.preventDefault(); mail.focus({ preventScroll: true }); }
      else if (e.key === 'ArrowUp' && el === mail) { e.preventDefault(); ta.focus({ preventScroll: true }); }
      else e.stopPropagation();   /* typing is the field's: the settings keys never see it */
    };
    ta.onkeydown = function (e) { keys(e, ta); }; mail.onkeydown = function (e) { keys(e, mail); };
    box.querySelector('.fb-send').onclick = fbSend;
    box.querySelector('.fb-back').onclick = function () { setGo(''); };
    box.querySelector('.fb-attach').onclick = function () { post({ type: 'feedbackAttach' }); };
    box.querySelector('.fb-mailit').onclick = fbMailIt;
    var inf = box.querySelector('.fb-inf'), isw = inf.querySelector('.s-sw');
    inf.onclick = function (e) { if (!e.target.closest('.s-sw')) isw.click(); };
    isw.onclick = function (e) { e.stopPropagation(); fbInfo = !fbInfo; setSw(isw, fbInfo); };
    /* focus without scrolling: the card is still growing, and a scroll to the field would shove the whole notch up */
    setTimeout(function () { if (setPage === 'feedback' && document.activeElement !== mail) { ta.focus({ preventScroll: true }); ta.setSelectionRange(ta.value.length, ta.value.length); } }, 40);
  }
  function fbGrow(ta) { var min = fbFiles.length ? 64 : 92; ta.style.minHeight = min + 'px'; ta.style.height = 'auto'; ta.style.height = Math.min(150, Math.max(min, ta.scrollHeight)) + 'px'; if (snap && lastSt === 'set') layout('set', snap); }
  function fbAtt() {
    var box = q('.set .fb-att'); if (!box) return;
    attChips(box, fbFiles, function (i) { fbFiles.splice(i, 1); fbAtt(); fbPaint(); var ta = q('.set .fb-in'); if (ta) ta.focus({ preventScroll: true }); });
    /* a file past the limit is orange and says its size */
    var big = fbBig();
    [].forEach.call(box.querySelectorAll('.att'), function (c, i) {
      if (big.indexOf(i) < 0) return;
      c.style.background = 'rgba(233,168,119,.16)'; c.style.color = COLORS.attention; c.title += ' (too big to send)';
      c.querySelector('.truncate').insertAdjacentHTML('afterend', '<span class="flex-none pl-1 text-[11px] tabular-nums opacity-80">' + fbMB(fileSizes[fbFiles[i]]) + '</span>');
    });
    if (big.length) { box.scrollLeft = box.scrollWidth; attEdges(box); }
    var ta = q('.set .fb-in'); if (ta) fbGrow(ta);
  }
  /* Perch sends 4 MB at most (a Vercel function takes 4.5): pictures go smaller first (the app sends their size after
     that), and a file that would take it past the limit is marked, in the order you added them */
  var FB_CAP = 4 * 1024 * 1024, fileSizes = {};
  function fbBig() { var sum = 0, out = []; fbFiles.forEach(function (f, i) { var b = fileSizes[f] || 0; if (sum + b > FB_CAP) out.push(i); else sum += b; }); return out; }
  function fbMB(b) { return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + ' MB'; }
  var fbMailSaid = false;
  function fbMailBad() { var m = fbMail.trim(); return !!m && !/^[^\s@]+@[^\s@]+\.[^\s@.]{2,}$/.test(m); }
  /* Send: faint until there is something to send, while a file is too big, and while the email is wrong; Try again after a
     failure (the words morph). The line above says what is wrong; Email it instead appears beside a file too big or a
     failure, the two it gets round. */
  function fbPaint(still) {
    var b = q('.set .fb-send'); if (!b) return;
    var go = fbState === 'sending', big = fbBig(), failed = fbState === 'failed', mailBad = fbMailSaid && fbMailBad();
    b.classList.toggle('opacity-50', !fbHas() || go || big.length > 0 || mailBad);
    morphText(b.querySelector('.fb-send-l'), go ? 'Sending' : failed && !big.length ? 'Try again' : 'Send', still);
    var err = big.length ? 'Too big to send, 4 MB at most. Remove ' + (big.length === 1 ? 'it' : 'them') + ', or email it instead.'
      : mailBad ? 'That email doesn\u2019t look right. Fix it, or leave it empty.'
      : failed ? 'Couldn\u2019t send. Your words are kept.' : '';
    var e = q('.set .fb-err'), had = !e.classList.contains('hidden');
    e.textContent = err; e.classList.toggle('hidden', !err);
    /* the field itself in orange too, so the eye goes to it */
    q('.set .fb-mail').style.boxShadow = mailBad ? 'inset 0 0 0 1px rgba(233,168,119,.75)' : '';
    q('.set .fb-mailit').classList.toggle('hidden', !(big.length || (failed && !mailBad)));
    q('.set .fb-in').readOnly = q('.set .fb-mail').readOnly = go;
    if (had !== !!err && snap && lastSt === 'set') layout('set', snap);
  }
  /* Mail takes it from here: a new message with everything in it, and Perch steps aside (the words are Mail's now) */
  function fbMailIt() {
    post({ type: 'feedbackMail', text: fbText.trim(), email: fbMail.trim(), files: fbFiles.slice(), info: fbInfo });
    fbText = ''; fbFiles = []; fbState = '';
  }
  function fbSend() {
    if (fbState === 'sending') return;
    var ta = q('.set .fb-in');
    var shake = function (el) { if (el && el.animate && !STILL) el.animate([{ transform: 'none' }, { transform: 'translateX(-3px)' }, { transform: 'translateX(3px)' }, { transform: 'translateX(-2px)' }, { transform: 'none' }], { duration: 280, easing: 'ease-out' }); };
    if (!fbHas()) { if (ta) { ta.focus({ preventScroll: true }); shake(q('.set .fb-box')); } return; }
    if (fbBig().length) { shake(q('.set .fb-err')); return; }
    if (fbMailBad()) { var m = q('.set .fb-mail'); fbMailSaid = true; fbPaint(); if (m) { m.focus({ preventScroll: true }); shake(m); } return; }
    fbState = 'sending';
    post({ type: 'feedback', text: fbText.trim(), email: fbMail.trim(), files: fbFiles.slice(), info: fbInfo });
    /* then the list again, coming in from the left, on the Send feedback row, which says Sending */
    var t = fbFly(); fbFlying = !!t;
    setTimeout(function () {
      fbFlying = false; if (setPage !== 'feedback') return;
      setGo('', true);
      if (t) q('.set').animate([{ opacity: 0, transform: 'translateX(-8px)', filter: 'blur(3px)' }, { opacity: 1, transform: 'none', filter: 'blur(0)' }], { duration: 250, easing: SMOOTH });
    }, t);
  }
  /* Your words go off into the notch the way a reply to a terminal does: the page clears, the field first, and the words
     rise as a bubble, stretching as they go; the notch swallows them with a green ripple, and the character watches and
     hops. Returns when the list may come back (0 with reduced motion: at once). */
  function fbFly() {
    var pane = q('.p-set'), box = q('.set'), ta = box.querySelector('.fb-in'); if (STILL || !ta) return 0;
    var pr = pane.getBoundingClientRect(), fr = ta.getBoundingClientRect();
    var words = fbText.trim().split('\n')[0] || fbFiles.map(function (x) { return x.replace(/\/+$/, '').split('/').pop(); }).join(', ');
    [box.querySelector('.fb-box'), box.querySelector('.fb p'), box.querySelector('.fb-mail'), box.querySelector('.fb-inf'), box.firstChild, box.lastChild].forEach(function (el, i) {
      if (el) el.animate([{ opacity: 1, transform: 'none', filter: 'blur(0)' }, { opacity: 0, transform: 'translateY(-6px)', filter: 'blur(3px)' }], { duration: 200, delay: i * 25, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' });
    });
    var b = document.createElement('div'); b.className = 'fly'; b.textContent = words; pane.appendChild(b);
    ta.style.color = 'transparent';   /* the words are the bubble now: they are not left behind in the field as well */
    var x0 = fr.left - pr.left + 8, y0 = fr.top - pr.top + 6;
    b.style.left = x0 + 'px'; b.style.top = y0 + 'px';
    var dx = CARD_W / 2 - (x0 + b.offsetWidth / 2), dy = 2 - (y0 + b.offsetHeight / 2);
    b.animate([{ transform: 'none', opacity: 1 }, { transform: 'translate(' + (dx * .15) + 'px, 6px) scale(1.06, .9)', opacity: 1, offset: .25 },
      { transform: 'translate(' + (dx * .85) + 'px,' + (dy * .8) + 'px) scale(.5, 1.25)', opacity: 1, offset: .8 }, { transform: 'translate(' + dx + 'px,' + dy + 'px) scale(.1, .4)', opacity: 0 }],
      { duration: 360, delay: 40, easing: 'cubic-bezier(.6,0,.4,1)', fill: 'both' });
    var ring = document.createElement('div'); ring.className = 'fly-ring'; ring.style.left = (CARD_W / 2 - 30) + 'px'; ring.style.top = '-28px'; ring.style.animationDelay = '370ms'; pane.appendChild(ring);
    look(2.8, -1.6);
    setTimeout(function () { var ci = cr.querySelector('.cr-in'); cr.dataset.m = 'happy'; ci.classList.remove('hop'); void ci.offsetWidth; ci.classList.add('hop'); look(0, 0); fbGlowNow('done'); }, 400);
    setTimeout(function () { b.remove(); ring.remove(); }, 1000);
    return 320;
  }
  function fbGlowNow(k) {
    fbGlow = { at: Date.now(), k: k };
    var g = k === 'done' ? ['140,207,164', '196,234,210'] : ['233,168,119', '244,210,180'];
    n.dataset.g = 'status'; n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    clearTimeout(fbGlowNow._t); fbGlowNow._t = setTimeout(function () { if (snap) apply(snap); }, 2700);   /* then it settles back into the character's colour */
  }
  /* The Send feedback row says how your message is doing, changing in place: Sending with a spinner, then a green check
     and thank you, or Couldn't send in orange (open it and everything is still there). Draft while words wait. */
  function fbRow(still) {
    var st = q('.set .fb-st'); if (!st) return;
    var ic = st.firstChild, tx = st.lastChild;
    var m = fbState === 'sending' ? [Spinner('size-3.5', glow(COLORS.running)), 'Sending', COLORS.running]
      : fbState === 'sent' ? [Ring('done'), 'Sent. Thank you', COLORS.done]
      : fbState === 'failed' ? [Ring('need'), 'Couldn\u2019t send', COLORS.attention]
      : ['', fbHas() ? 'Draft' : '', ''];
    ic.classList.toggle('has', !!m[0]);
    iconSwap(ic, m[0], still);
    tx.classList.toggle('text-muted-foreground', !m[2]);
    swapText(tx, m[1], m[2], still);
  }
  /* the app says how it went */
  function fbDone(ok) {
    if (fbState !== 'sending') return;
    fbState = ok ? 'sent' : 'failed';
    if (ok) { fbText = ''; fbFiles = []; }
    if (!fbFlying) {
      /* opened again while it went: a failure shows there, a success takes you back to the list */
      if (setPage === 'feedback') { if (ok) setGo(''); else fbPaint(); }
      else fbRow(false);
    }
    setTimeout(function () { fbGlowNow(ok ? 'done' : 'attention'); }, fbFlying ? 500 : 0);
  }
  /* Esc on Send feedback with neither field focused (they handle it themselves); in the app nothing else would see it */
  if (NATIVE) document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && lastSt === 'set' && setPage === 'feedback') { e.preventDefault(); setGo(''); } });
  function fbPaths(list) {
    if (setPage !== 'feedback') return;
    var b = q('.set .fb-box'); if (b) b.classList.remove('drop', 'on');
    fbFiles = addFiles(fbFiles, list); if (fbState === 'failed') fbState = '';
    fbAtt(); fbPaint();
    var ta = q('.set .fb-in'); if (ta) setTimeout(function () { ta.focus({ preventScroll: true }); }, 40);
  }
  /* a file over the card lights the field, more so right on it */
  function fbDragOver(nf, x, y) {
    var b = setPage === 'feedback' && q('.set .fb-box'); if (!b) return;
    if (!nf) { b.classList.remove('drop', 'on'); return; }
    var el = x == null ? null : document.elementFromPoint(x, y);
    b.classList.add('drop'); b.classList.toggle('on', !!(el && el.closest && el.closest('.fb-box')));
  }
  var DEV_DISPLAYS = [{ id: '1', name: 'Built-in Retina Display', connected: true }, { id: '2', name: 'LG UltraFine', connected: true }];
  var SHOW_WAYS = [['mouse', 'Screen with mouse'], ['window', 'Screen with active window']];
  function showChoices(o) {
    return SHOW_WAYS.map(function (w) { return { id: w[0], name: w[1], on: true }; })
      .concat((o.displays || []).map(function (x) { return { id: x.id, name: x.name, on: x.connected !== false, display: true }; }));
  }
  function notifyOn(k) { return ((snap && snap.notifyOff) || []).indexOf(k) < 0; }
  /* the highlighted row, moved with the arrow keys or the pointer */
  var setGroup = '';   /* the group open on Settings, Agents */
  var setFocus = 0, liveNext = false, setHot = -1, setKb = true;   /* a row is lit while the pointer is on it or the keys chose it */
  /* opened from a question's "Settings": Agents opens on Live status, and it lights up once so the eye lands on it */
  function flashLive() {
    var b = q('.set .s-sw[data-k=live]'), r = b && b.closest('.s-row');
    if (r && r.animate && !STILL) r.animate([{ backgroundColor: 'rgba(255,255,255,.2)' }, { backgroundColor: 'rgba(255,255,255,0)' }], { duration: 1800, easing: 'ease-out' });
  }
  function paintFocus() {
    var rows = q('.set').querySelectorAll('.s-row');
    setFocus = Math.max(0, Math.min(setFocus, rows.length - 1));
    rows.forEach(function (r, i) { r.classList.toggle('bg-accent', i === setFocus && (setKb || i === setHot)); });
    /* in the icon row, the icon the keys are on */
    q('.set').querySelectorAll('.s-nt[data-i]').forEach(function (b) {
      var inMenu = !!b.closest('.nt-menu'), on = setKb && (inMenu ? +b.dataset.i === ntFocus : rows[setFocus] && rows[setFocus].contains(b) && +b.dataset.i === ntFocus);
      if (inMenu) b.classList.toggle('bg-white/[0.09]', on); else { b.classList.toggle('ring-1', on); b.classList.toggle('ring-white/40', on); }
    });
  }
  /* arrows, Return and Space, forwarded from the app while Settings has the keyboard. Left is always Back. */
  function settingsKey(k) {
    keyPtr = ptrAt.slice(); setKb = true;
    if (setPage === 'feedback') { if (k === 'esc' || k === 'left') setGo(''); return; }   /* the fields take the keys; these come only when neither has focus */
    var rows = q('.set').querySelectorAll('.s-row'), row = rows[setFocus];
    /* with the moments' menu open the keys are its own: Up and Down choose, Return switches one, Left and Esc fold it away */
    if (notifyMenuOpen) {
      var its = q('.set').querySelectorAll('.nt-menu .s-nt');
      if (k === 'left' || k === 'esc') { notifyMenuOpen = false; setSig = ''; settingsApply(setLast); ntRelayout(); return; }
      if (k === 'down' || k === 'up') { ntFocus = (ntFocus + (k === 'down' ? 1 : -1) + its.length) % its.length; paintFocus(); return; }
      if (k === 'enter' && its[ntFocus]) its[ntFocus].click();
      return;
    }
    /* inside an open group Left folds it back to its row; on the row itself it is Back, as everywhere here */
    if (k === 'left' && setGroup && row && !row.classList.contains('s-grp')) { var gid = setGroup; setGroup = ''; setSig = ''; settingsApply(setLast); setFocus = [].indexOf.call(q('.set').querySelectorAll('.s-row'), q('.set .s-grp[data-g=' + gid + ']')); paintFocus(); ntRelayout(); return; }
    if (k === 'esc' || k === 'left') { if (setPage) setGo(''); else post({ type: 'back' }); return; }
    if (k === 'down' || k === 'up') { setFocus = (setFocus + (k === 'down' ? 1 : -1) + rows.length) % rows.length; ntFocus = 0; paintFocus(); return; }
    if (!row) return;
    if (row.dataset.go) { if (k === 'right' || k === 'enter') setGo(row.dataset.go); return; }
    if (row.classList.contains('s-grp')) { if (k === 'right' || k === 'enter') row.click(); return; }
    /* the moments' icons: Right moves along them, Return switches the one it is on; Left is Back, as everywhere here */
    if (row.classList.contains('s-menu')) { if (k === 'enter') row.click(); return; }
    var nts = row.querySelectorAll('.s-nt');
    if (nts.length) {
      if (k === 'right') { ntFocus = Math.min(ntFocus + 1, nts.length - 1); paintFocus(); return; }
      var cur = nts[Math.min(ntFocus, nts.length - 1)]; if (cur) cur.click(); return;
    }
    /* Pull requests: the same, over the choices that can be made (Checks needs the GitHub CLI) */
    if (row.querySelector('.s-prm') && setLast) {
      var pm = ['off', 'marks'].concat(setLast.prs === 'nogh' || setLast.prs === 'login' ? [] : ['checks']), pi = pm.indexOf(prsMode(setLast));
      if (k === 'right' && pi >= pm.length - 1) return;
      var to = pm[(pi + 1) % pm.length]; post({ type: 'setting', key: 'showPullRequests', value: to !== 'off' }); post({ type: 'setting', key: 'pullRequests', value: to === 'checks' }); return;
    }
    /* a segment: Right moves the choice along and stops at the end; Return comes round again from the start */
    var seg = row.querySelectorAll('.s-seg');
    if (seg.length && setLast) {
      var v = [].map.call(seg, function (b) { return +b.dataset.m; }), sk = seg[0].dataset.key, i = v.indexOf(setLast[sk]);
      if (k === 'right' && i >= v.length - 1) return;
      post({ type: 'setting', key: sk, value: v[(i + 1) % v.length] }); return;
    }
    if (k === 'right') return;
    /* Return or Space: flip the switch, pick the screen, or press the row's button */
    if (row.classList.contains('s-tap')) { row.click(); return; }
    var c = row.querySelector('.s-sw, button'); if (c) c.click();
  }
  function settingsApply(o) {
    if (!o) return;
    var box = q('.set'), upd = snap ? [snap.update, !!snap.canUpdate] : 0, sig = JSON.stringify([o, charNow, upd, snap && snap.notifyOff, axAsked, setPage, setGroup, fbState]); if (sig === setSig) return;
    /* feedback is drawn once when it opens: Swift sends Settings every half second while sessions are written, and a
       redraw would take your caret and selection */
    if (setSig && setPage === 'feedback' && box.querySelector('.fb-in')) { setSig = sig; setLast = o; return; }
    /* the list is drawn again whenever what it says changes; a category with the same rows and new values changes them in
       place, so switches and the segment animate */
    var shape = JSON.stringify([setPage, setGroup, o.shortcut, o.accessibility, o.accessWas, axAsked, !!o.hasExternal, o.sources.map(function (x) { return [x.id, x.count]; }), charNow, snap && snap.canUpdate, snap && snap.version, snap && snap.testBuild, o.showOn, o.displays, setPage === 'agents' ? [o.prs === 'on', o.prs === 'nogh' || o.prs === 'login', o.showPRs !== false] : setPage === 'notify' ? [o.prs, o.showPRs !== false, o.sources.length, notifyMenuOpen, snap && snap.notifyOff] : setPage ? 0 : [o, snap && snap.notifyOff]]);
    if (setSig && box.dataset.shape === shape) {
      setSig = sig; setLast = o;
      box.querySelectorAll('.s-sw').forEach(function (b) {
        var v = swVal(o, b.dataset.k), r = b.closest('.s-row'), dm = r && r.querySelector('.s-dim'); setSw(b, v);
        if (dm) { dm.classList.toggle('opacity-40', !v); dm.nextSibling.classList.toggle('text-muted-foreground', !v); }
      });
      var us = box.querySelector('.s-updslot');
      if (us && snap) {
        var html = updSlot(snap), key = html.replace(/stroke-dashoffset="[^"]*"/, '');
        if (us._k !== key) { us.innerHTML = html; us._k = key; bindUpdSlot(us, snap); }
        var sb = box.querySelector('.s-updsub'); if (sb) sb.textContent = ''; if (sb) sb.innerHTML = updSub(snap);
        var arc = us.querySelector('.upd-arc'); if (arc) arc.style.strokeDashoffset = String(UPD_C * (1 - (snap.update.progress || 0)));
      }
      fbRow(false);
      box.querySelectorAll('.s-seg').forEach(function (b) {
        var on = +b.dataset.m === o[b.dataset.key];
        ['bg-white/[0.16]', 'text-foreground'].forEach(function (c) { b.classList.toggle(c, on); });
        ['text-muted-foreground', 'hover:text-foreground'].forEach(function (c) { b.classList.toggle(c, !on); });
      });
      return;
    }
    setSig = sig; settingsRender(o); box.dataset.shape = shape;
  }

  /* A title that does not fit fades at its end (.fade, input.css); one that fits is left whole. Checked again whenever the notch's words change. */
  var fadeRaf = 0;
  function fadeSweep() {
    fadeRaf = 0;
    n.querySelectorAll('.fade').forEach(function (el) { el.classList.toggle('cut', el.scrollWidth - el.clientWidth > 1); });
  }
  new MutationObserver(function () { if (!fadeRaf) fadeRaf = requestAnimationFrame(fadeSweep); }).observe(n, { childList: true, subtree: true, characterData: true });
  window.addEventListener('resize', function () { if (!fadeRaf) fadeRaf = requestAnimationFrame(fadeSweep); });
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fadeSweep);
  window.perch = { held: function (list) { scHeldNow = list || []; scHeldApply(); }, hi: function () { if (lastSt === 'idle' && !hello && !celebrating) sayHello(); }, _icons: function (o) { icons = o; }, _snap: function () { return snap; }, actKey: actDo, actNoKeys: function (l) { l = l || []; if (l.join() === actNoKeys.join()) return; actNoKeys = l; actEl._h = ''; renderAct(); }, actDemo: actDemo, hot: function (on) { n.dataset.hot = on ? '1' : ''; }, onbKey: onbKey, setKey: settingsKey, setGo: setGo, feedbackSent: fbDone, askKey: askKey, newKey: function (k) { return newKey({ key: k }); }, newStarted: nwStarted, newPicked: nwPicked, answering: function (choice) { noteAnswer({ type: 'answer', choice: choice }); }, notSent: notSent, replying: replying, replyHanded: replyHanded, still: function () { still = true; cr.classList.remove('blink'); }, apply: apply, wnUp: wnUp, listKey: function () { listKb = true; markList(); }, cursor: cursor, snoozeMenu: function (o) { snoozeMenu(o); }, replyMenu: function (o) { if (o && !q('.o-acts [data-act=reply]')) return; replyMenu(o); }, previewMenu: function (o, from) { previewMenu(o, false, from); }, previewKey: previewKey, wnScroll: function (k) { var el = q('.wn-l'); if (!el) return; var page = Math.max(57, el.clientHeight - 38); saidScroll({ down: 57, up: -57, pageDown: page, pageUp: -page }[k] || 0, el); }, paths: addPaths, fileSizes: function (o) { Object.keys(o || {}).forEach(function (k) { fileSizes[k] = o[k]; }); fbAtt(); fbPaint(); }, fileIcons: function (o) { Object.keys(o || {}).forEach(function (k) { if (o[k]) fileIcons[k] = o[k]; }); repAtt(); nwAtt(); fbAtt(); }, dragOver: dragOver, say: function (t) { pop('awake', 2600, t); },
    /* Swift hid the panel to move it to another display: it shows it again once what goes there is on screen */
    painted: function (token) { requestAnimationFrame(function () { requestAnimationFrame(function () { post({ type: 'painted', token: token }); }); }); } };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', onboarding: 'onb', settings: 'set', whatsnew: 'new', newSession: 'ns' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (m.type === 'answer') noteAnswer(m);
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  var devFrom = '', devFbT = 0, devSc = Object.assign({}, SC0);
  /* New session's shortcut, as Settings shows it; while the recorder records it, devSc is its state and Open Perch's waits in devScOpen */
  var SCN0 = { keys: ['\u2325', '\u2318', 'N'], kind: 'combo', custom: false }, devScNew = Object.assign({}, SCN0), devScOpen = null;
  /* back from the recorder: what it recorded goes to its own shortcut, and devSc is Open Perch's again */
  function devScBack() {
    if (devSc.which !== 'new') return;
    devScNew = { keys: devSc.keys, kind: devSc.kind, custom: devSc.custom };
    devSc = devScOpen || Object.assign({}, SC0); devScOpen = null;
  }
  /* the recorder, as the app does it: Swift listens, decides and sends the result; here the browser's keys stand in */
  /* what Swift sends for "does it work": a tap hears nothing without Accessibility, a combo can be held by another app */
  function devScOut(ax) {
    var c = JSON.parse(JSON.stringify(devSc));
    if (c.taken) { c.works = false; c.why = 'Another app already uses this shortcut. Record a different one.'; }
    else if (c.kind === 'tap' && ax === false) { c.works = false; c.why = 'A tap needs Accessibility. Allow it, or record a key combo.'; }
    else { c.works = true; c.why = ''; }
    return c;
  }
  function devScSync(patch) {
    Object.assign(devSc, patch || {});
    if (!snap) return;
    var s = JSON.parse(JSON.stringify(snap));
    if (s.settings) s.settings.shortcut = devScOut(s.settings.accessibility);
    if (s.onboarding) s.onboarding.shortcut = devScOut(s.onboarding.accessibility);
    s.timerToken++; apply(s);
  }
  function dev(m) {
    /* Done with a choice waiting: it saves (the keys spring, the card glows green), then goes back to Settings */
    if (m.type === 'onb' && m.action === 'next' && snap && snap.onboarding && snap.onboarding.only && devSc.recording && devSc.pending && devSc.pending.length) {
      window.perchDev.saveChoice(); setTimeout(function () { if (snap && snap.phase === 'onboarding') dev(m); }, 900); return;
    }
    if (m.type === 'update') {
      if (m.action === 'install' || m.action === 'restart') window.perchDev.updRun(m.action === 'restart');
      if (m.action === 'check') { var D = window.perchDev, k = ++updTok; D.update('checking', { fresh: false, stay: true }); setTimeout(function () { if (k === updTok) D.update('current', { fresh: false, stay: true }); }, 1600); setTimeout(function () { if (k === updTok) D.update(null, { fresh: false, stay: true }); }, 5200); }
      return;
    }
    if (m.type === 'shortcut') {
      if (m.action === 'record') devScSync({ recording: true, error: '', attempt: [], pending: [], saved: false, tried: false });
      else if (m.action === 'cancel') devScSync({ recording: false, error: '', pending: [] });
      else if (m.action === 'reset') devScSync(Object.assign({}, SC0, devSc.which === 'new' ? SCN0 : {}, { which: devSc.which, saved: true }));
      else if (m.action === 'try' && !devSc.recording) devScSync({ tried: true, saved: false });
      return;
    }
    /* the drafts Swift keeps, kept here instead */
    if (m.type === 'draft') { base.drafts = base.drafts || {}; if (m.text) base.drafts[m.id] = m.text; else delete base.drafts[m.id]; if (snap) snap.drafts = base.drafts; return; }
    if (m.type === 'reply' && snap && snap.projects[snap.selected] && base.drafts) delete base.drafts[snap.projects[snap.selected].id];
    /* Esc while it waits for Accessibility: back to the card, and the wait is off */
    if (m.type === 'replyMenu' && !m.open && snap && snap.allowing) { var s0 = JSON.parse(JSON.stringify(snap)); s0.allowing = false; base.allowing = false; apply(s0); return; }
    if (m.type === 'newSession') { devNew(m); return; }
    if (m.type === 'whatsnew') { base.access = null; window.perchDev.show('switcher', false, false); return; }   /* Got it: on to the list */
    /* Allow: System Settings opens (here, a line says so), the switch is turned on a few seconds later */
    if (m.type === 'access') {
      var nowA = document.getElementById('now'), D2 = window.perchDev;
      if (m.action === 'said') { base.access = null; return; }
      if (m.action !== 'allow' || !snap) return;
      var k2 = ++updTok, onCard = snap.phase === 'whatsnew', set = function (ph) {
        if (k2 !== updTok) return;
        if (onCard) { if (!snap || snap.phase !== 'whatsnew') return; var c = JSON.parse(JSON.stringify(snap)); c.whatsNew.access = ph; c.timerToken = Math.random(); apply(c); }
        else { base.access = { phase: ph, afterUpdate: false, since: 1 }; D2.access(ph, { fresh: false }); }
      };
      set('asked'); if (nowA) nowA.textContent = 'System Settings opens on Accessibility, with a fresh switch for Perch';
      setTimeout(function () { if (k2 !== updTok) return; set('granted'); if (nowA) nowA.textContent = 'You turn Perch on'; }, 3800);
      if (!onCard) setTimeout(function () { if (k2 === updTok) base.access = null; }, 4000);
      return;
    }
    if (!snap || m.type === 'size' || m.type === 'log' || m.type === 'hand' || m.type === 'snoozeMenu' || m.type === 'replyMenu') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'flip') { s.selected = (s.selected + (m.dir || 1) + s.projects.length) % s.projects.length; s.timerToken++; apply(s); return; }
    /* a reply to a terminal session flies off first, then the card closes */
    if (m.type === 'reply' && snap.projects[snap.selected] && snap.projects[snap.selected].via) { replying(snap.projects[snap.selected].id); setTimeout(function () { var s2 = JSON.parse(JSON.stringify(snap)); s2.phase = 'idle'; s2.timerToken++; apply(s2); }, (m.close || .76) * 1000); return; }
    /* without Accessibility the card stays, waiting for it; the words stay in the field */
    if (m.type === 'reply' && snap.canSend === false) { s.allowing = true; s.timerToken++; apply(s); return; }
    if (m.type === 'reply' && snap.projects[snap.selected]) replying(snap.projects[snap.selected].id);   /* the Claude app takes it in the background */
    if (m.type === 'confirm' || m.type === 'dismiss' || m.type === 'snooze' || m.type === 'reply' || m.type === 'choose' || m.type === 'answer') s.phase = 'idle';
    if (m.type === 'answer' && s.projects[s.selected]) {
      /* the agent goes on: the request is settled and it is working again */
      s.projects[s.selected] = Object.assign({}, s.projects[s.selected], { ask: null, attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'Claude Code is working', app: 'claude' } });
      var nowEl = document.getElementById('now'); if (nowEl) nowEl.textContent = m.answers ? 'Sent: ' + Object.keys(m.answers).map(function (k) { return m.answers[k]; }).join(' / ') : (m.choice === 'deny' ? 'Denied. Claude is told no and goes on.' : 'Allowed. Claude runs it.');
    }
    if (m.type === 'hooks') { if (s.settings) s.settings.live = m.on ? 'on' : 'off'; if (s.onboarding) s.onboarding.live = m.on ? 'on' : 'off'; }
    if (m.type === 'character') { s.character = { shape: m.shape, color: m.color }; }
    /* a page opened from Settings: Done goes back there, whatever step it is */
    if (m.type === 'onb' && m.action === 'next' && s.onboarding && s.onboarding.only) { window.perchDev.settings(null, true); return; }
    if (m.type === 'onb' && s.onboarding) {
      var o = s.onboarding;
      if (m.action === 'next') o.step = Math.min(o.step + 1, o.total - 1);
      else if (m.action === 'back') o.step = Math.max(o.step - 1, 0);
      else if (m.action === 'finish') s.phase = 'idle';
      else if (m.action === 'accessibility') o.accessibility = true;
      if (o.step === 4 && m.action === 'next') { o.scanning = true; var held = JSON.parse(JSON.stringify(s)); held.timerToken++; apply(held); setTimeout(function () { var d2 = JSON.parse(JSON.stringify(held)); d2.onboarding.scanning = false; apply(d2); }, 1200); return; }
    }
    if (m.type === 'source' && s.onboarding) { s.onboarding.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'settings') { devFrom = snap.phase === 'open' || snap.phase === 'switcher' ? snap.phase : ''; s.phase = 'settings'; s.settings = s.settings || { sources: [], accessibility: true, idleMinutes: 20, questionSeconds: 60, login: false, live: 'on', prs: 'off', hasExternal: !s.screen.hasNotch, hoverExternal: false, showOn: 'mouse', displays: DEV_DISPLAYS, shortcut: devScOut(true) }; if (!s.settings.sources.length) s.settings.sources = [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }]; }
    /* the real app opens the pull request in the browser; the design page does the same in a new tab */
    if (m.type === 'openpr' && m.url) { window.open(m.url, '_blank', 'noopener'); return; }
    if (m.type === 'setting' && m.key === 'pullRequests') { if (s.settings) s.settings.prs = m.value ? 'on' : 'off'; if (s.onboarding) s.onboarding.prs = m.value ? 'on' : 'off'; }
    if (m.type === 'setting' && m.key === 'showPullRequests') { s.showPRs = m.value; if (s.settings) s.settings.showPRs = m.value; }
    if (m.type === 'setting' && s.settings && m.key !== 'pullRequests' && m.key !== 'showPullRequests') { s.settings[m.key] = m.value; if (m.key === 'questionSeconds') s.questionSeconds = m.value; }
    if (m.type === 'notify') { var off = (s.notifyOff || []).filter(function (k) { return k !== m.kind; }); if (!m.enabled) off.push(m.kind); s.notifyOff = off; }
    if (m.type === 'source' && s.settings) { s.settings.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'onbOpen') { window.perchDev.onboarding(m.step || 0, true, m.only, null, false, false, m.which); return; }
    if (m.type === 'onb' && m.action === 'next' && s.onboarding && s.onboarding.only) { window.perchDev.settings(null, true); return; }
    /* Allow in Settings: System Settings opens, the row says turn on in System Settings, and the switch comes on a few seconds later */
    if (m.type === 'onb' && !s.onboarding) {
      if (m.action !== 'accessibility' || !s.settings) return;
      var k3 = ++updTok; s.timerToken = Math.random(); apply(s);
      setTimeout(function () { if (k3 !== updTok || !snap || snap.phase !== 'settings') return; var s3 = JSON.parse(JSON.stringify(snap)); s3.settings.accessibility = true; s3.settings.shortcut = devScOut(true); s3.timerToken = Math.random(); apply(s3); }, 3800);
      return;
    }
    if (m.type === 'feedback') { clearTimeout(devFbT); if (!window.perchDev.fbHold) devFbT = setTimeout(function () { fbDone(!window.perchDev.fbFail); }, 1300); return; }
    if (m.type === 'feedbackMail') { var nm = document.getElementById('now'); if (nm) nm.textContent = 'Mail opens a new message to the maker of Perch with your words' + (m.files.length ? ' and ' + m.files.length + ' file' + (m.files.length === 1 ? '' : 's') : ''); s.phase = 'idle'; }
    if (m.type === 'feedbackAttach') { addPaths(['/Users/you/Desktop/Screenshot 2026-10-17 at 11.42.png']); return; }
    if (m.type === 'quit') { s.phase = 'idle'; }
    if (m.type === 'switcher') s.phase = 'switcher';
    /* answered from the notch: that session goes on, working again */
    if (m.type === 'activityAnswer') { s.projects = s.projects.map(function (x) { return x.id === m.id ? Object.assign({}, x, { ask: null, attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: x.app === 'codex' ? 'Codex is working' : 'Claude Code is working', app: x.app } }) : x; }); var nw = document.getElementById('now'); if (nw) nw.textContent = 'Sent from the notch: ' + (m.choice || Object.keys(m.answers).map(function (k) { return m.answers[k]; }).join(' / ')); }
    if (m.type === 'pick') { s.selected = m.index; if (typeof base !== 'undefined') base.selected = m.index; }
    if (m.type === 'details') { s.selected = m.index; s.phase = 'open'; s.autoCollapse = false; }
    if (m.type === 'activityOpen') { var oi = s.projects.findIndex(function (x) { return x.id === m.id; }); if (oi >= 0) { s.selected = oi; s.phase = 'open'; } }
    if (m.type === 'back') s.phase = snap.phase === 'settings' && devFrom ? devFrom : snap.phase === 'newSession' ? (snap.newSession && snap.newSession.from === 'list' ? 'switcher' : 'idle') : 'open';
    if (s.phase === 'settings' && s.settings) s.settings.back = !!devFrom;
    s.timerToken++; s.autoCollapse = s.phase === 'open'; apply(s);
    if (m.type === 'activityOpen' && m.preview) setTimeout(function () { previewMenu(true); }, 350);
  }
  if (!NATIVE) {
    var P = [
      { id: 'onboarding', name: 'Onboarding flow', branch: 'main', away: '4m', at: '11:32 AM', headline: 'You were fixing the permissions screen.', context: 'Swapped the sheet for a popover because it clipped on small windows.', next: '', topic: 'Permissions screen', app: 'claude', attention: true, fresh: true, line: 'Waiting on you for 4m', status: { kind: 'attention', text: 'Claude wants to run a command', app: 'claude' }, ask: { kind: 'permission', title: 'Claude wants to run a command', subject: 'npm run build && npm test -- --watch=false', options: [], answerable: true } },
      { id: 'website', name: 'Website', branch: 'feature/hero', away: '48m', at: '10:44 AM', headline: 'You were tightening the hero spacing.', context: 'The hero now fits at phone width. The full-bleed video is gone because it slowed the page.', next: 'Check the hero on a real phone',
        asked: 'Make the hero fit at phone width, the video is too heavy there.', said: 'Done. The hero now fits at phone width:\n\n- Padding drops from 96px to 48px under 640px\n- The headline wraps at 18ch instead of overflowing\n- The full-bleed video is gone; it cost 1.8s on 4G\n\nI left the poster image in its place so the fold still has something to look at.\n\nWant me to bring the video back for desktop only, behind `prefers-reduced-motion`?', topic: 'Hero spacing', app: 'claude', attention: false, fresh: true, line: 'Finished 12m after you left', status: { kind: 'done', text: 'Claude finished', app: 'claude' } },
      { id: 'docs', name: 'Docs', branch: 'main', away: '1m', at: '11:58 AM', headline: 'Rewriting the install guide.', context: 'Moving the setup steps above troubleshooting, then cutting the duplicate FAQ.', now: 'Editing install.md', next: '', topic: 'Install guide', app: 'codex', attention: false, fresh: true, line: 'Working now', status: { kind: 'running', text: 'Codex is working', app: 'codex' } },
      { id: 'finance', name: 'Finance', branch: '', away: '3d', at: 'Mon 3:40 PM', headline: 'You were reconciling September invoices.', context: 'Matched 41 of 43 invoices by vendor and amount; two are still open.', next: '', topic: 'September invoices',
        asked: 'Reconcile the September invoices against the bank export and tell me what is left open.', said: 'September is reconciled except two invoices. By vendor:\n\n| Vendor | Invoices | Total | Matched |\n|---|---|---|---|\n| Hetzner | 12 | $1,842.60 | 100% |\n| AWS | 9 | $20,000.00 | 100% |\n| Linear | 18 | $1,320.00 | 94% |\n| Figma | 4 | $540.00 | 75% |\n\nThe two still open are a Figma seat refund and a Linear credit note. Should I book them as credits against October?', app: 'claude', attention: false, fresh: false, line: '3d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      /* more than five: the list scrolls. Long topics read themselves out after a second on the row. */
      { id: 'planner', name: 'room-planner-prototype', branch: 'main', away: '5h', at: '10:12 AM', headline: 'You were measuring the missing areas of the apartment.', context: 'The camera saw more than the model kept; the walls now come from the depth pass.', next: '', topic: 'Video to 3D world with measured walls and the missing areas filled in', app: 'claude', attention: false, fresh: false, line: '5h ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      { id: 'repo', name: 'Fetch and review the Perch repo, then list what to fix first', branch: '', away: '6h', at: '9:40 AM', headline: 'You were reviewing the Perch repo.', context: 'Read the README and the provider; three fixes are listed.', next: '', topic: '', app: 'codex', attention: false, fresh: false, line: '6h ago', status: { kind: 'idle', text: 'Codex finished', app: 'codex' } },
      { id: 'lukatz', name: 'lukatz_website', branch: 'main', away: '1d', at: 'Yesterday', headline: 'You were adding the team to the town map.', context: 'Each team member walks the map as a small character.', next: '', topic: '\u05d4\u05d5\u05e1\u05e3 \u05d3\u05de\u05d5\u05d9\u05d5\u05ea NPC \u05e9\u05dc \u05d4\u05e6\u05d5\u05d5\u05ea \u05dc\u05de\u05e4\u05d4 \u05e9\u05dc \u05d4\u05e2\u05d9\u05e8 \u05d5\u05e2\u05d5\u05d3 \u05db\u05de\u05d4 \u05d3\u05d1\u05e8\u05d9\u05dd', app: 'claude', attention: false, fresh: false, line: '1d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      { id: 'api', name: 'api-server', branch: 'main', away: '1m', at: '12:01 PM', asked: 'Add a rate limiter to the public API, per key, with a burst allowance. Keep it simple, a token bucket is fine, and make sure the 429 tells clients when to retry.', said: 'The limiter is in: a token bucket per API key, 60 requests a minute with a burst of 20. Over the limit, the API answers `429` with a `Retry-After` header.\n\n```ts\napp.use(rateLimit({ perKey: 60, burst: 20 }))\n```\n\nI am running the test suite now.', headline: 'Rate limiter for the public API.', context: 'You said: \u201cadd a rate limiter to the public API, per key, with a burst allowance\u201d', now: 'Run the test suite', next: '', topic: 'Rate limiter for the public API', app: 'claude', via: 'ghostty', attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'Claude Code is working', app: 'claude' } },
      { id: 'fluid', name: 'FluidAgent', via: 'terminal', branch: 'main', away: '23h', at: 'Yesterday', headline: 'You were stopping a runaway tool loop.', context: 'The agent now stops after three identical calls.', next: '', topic: 'Stop it when the tool loop runs away', app: 'codex', attention: false, fresh: false, line: '23h ago', status: { kind: 'idle', text: 'Codex finished', app: 'codex' } },
      { id: 'gaps', name: 'spec-gap-finder', branch: 'main', away: '2d', at: 'Wed', headline: 'You were setting up the PDF gap finder.', context: 'It reads a spec and a supplier answer and lists what is missing.', next: '', topic: 'PDF gap analysis app and the supplier questionnaire', app: 'claude', attention: false, fresh: false, line: '2d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      /* the other agents: OpenCode at work in Ghostty, and pi in a herdr pane (herdr shown in Ghostty) */
      { id: 'tui', name: 'tui-kit', via: 'ghostty', branch: 'main', away: '2m', at: '12:03 PM', headline: 'Keyboard focus for the table.', context: 'Moving focus with the arrow keys, then making Tab leave the table.', now: 'Running `bun test`', next: '', topic: 'Keyboard focus for the table component', app: 'opencode', attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'OpenCode is working', app: 'opencode' },
        said: 'Arrow keys now move focus between cells, and Home and End jump to the ends of a row. I am running the tests before I touch Tab.' },
      { id: 'scraper', name: 'price-scraper', via: 'ghostty', host: 'herdr', branch: 'main', away: '12m', at: '11:52 AM', headline: 'You were retrying failed pages.', context: 'Failed pages now retry three times with backoff, and the run log lists the ones that never loaded.', next: 'Run it against the full catalogue', topic: 'Retry failed pages with backoff', app: 'pi', attention: false, fresh: true, line: 'Finished 12m ago', status: { kind: 'done', text: 'pi finished', app: 'pi' },
        said: 'Failed pages now retry three times, waiting 1, 4 and 16 seconds. Pages that still fail go to `failed.txt` with their status code.\n\nNext: run it against the full catalogue.' },
      /* a workspace in Conductor: Conductor's icon with the agent on its corner, and Open Conductor on the button */
      { id: 'phoenix', name: 'conductor-test', opens: 'conductor', branch: 'asafofer/ls-files', away: '6m', at: '1:30 PM', headline: 'Ls files.', context: 'The only tracked file in the workspace is `README.md`, which is 7 bytes.', next: '', topic: 'Ls files', app: 'claude', attention: false, fresh: true, line: 'Finished 6m ago', status: { kind: 'done', text: 'Claude Code replied', app: 'claude' },
        asked: 'Run `ls` with bash and tell me what files are here.', said: 'The only tracked file in the workspace is `README.md`, which is 7 bytes.' },
      /* a chat in Cursor: Cursor's own icon, and Open Cursor on the button. Pick up opens the chat itself through Cursor's chat link. */
      { id: 'cursorchat', name: 'api-server', branch: 'main', away: '8m', at: '11:58 AM', headline: 'You were adding retries to the sync job.', context: 'The sync job now retries three times with backoff and logs the pages that never loaded.', next: '', topic: 'Retry the sync job with backoff', app: 'cursor', attention: false, fresh: true, line: 'Finished 8m ago', status: { kind: 'done', text: 'Cursor replied', app: 'cursor' },
        asked: 'Make the sync job retry three times with backoff, and log what never loads.', said: 'The sync job now retries three times with backoff (1, 4 and 16 seconds) and logs the pages that never loaded.' },
      /* Muse Code in a terminal, like OpenCode and pi: Ghostty's icon with Muse's mark on its corner */
      { id: 'musecode', name: 'ledger-api', via: 'ghostty', branch: 'main', away: '5m', at: '12:00 PM', headline: 'You were splitting the ledger export.', context: 'The export now writes one file per account, and the tests cover the empty ones.', next: 'Run the export against the full ledger', topic: 'Split the ledger export by account', app: 'muse', attention: false, fresh: true, line: 'Finished 5m ago', status: { kind: 'done', text: 'Muse finished', app: 'muse' },
        asked: 'Split the ledger export into one file per account, and skip the empty ones.', said: 'The export now writes `ledger-<account>.csv` for each account that has entries. Empty accounts are skipped, and the tests cover them.\n\nNext: run it against the full ledger.' },
      /* Dots and Grok Bot work in the cloud, on a computer of their own: the session wears the agent's own icon, and Open Dots goes to it */
      { id: 'dotsbrief', name: 'Analytics', branch: '', away: '14m', at: '11:46 AM', headline: 'You asked for the weekly metrics brief.', context: 'It pulled the numbers from the dashboard and wrote the brief; two figures need your eye.', next: 'Check the churn figure before it goes out', topic: 'Weekly metrics brief for Monday', app: 'dots', attention: false, fresh: true, line: 'Finished 14m ago', status: { kind: 'done', text: 'Dots finished', app: 'dots' },
        asked: 'Every Monday, pull last week\u2019s numbers and write the metrics brief.', said: 'The brief is ready, and I put it in your drafts. Two figures look off: churn is up 2.1 points and the trial count dropped by a third.\n\nNext: check the churn figure before it goes out.' },
      { id: 'grokfix', name: 'checkout-service', branch: '', away: '3m', at: '12:02 PM', headline: 'Chasing a flaky checkout test.', context: 'It reproduced the failure one run in five and is bisecting the last ten commits.', now: 'Bisecting the last ten commits', next: '', topic: 'Fix the flaky checkout test', app: 'grokbot', attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'Grok Bot is working', app: 'grokbot' },
        asked: 'The checkout test fails one run in five. Find out why and fix it.', said: 'I can reproduce it: one run in five, always on the card step. I am bisecting the last ten commits now.' }
    ];
    /* sample pull requests: one of each state */
    var PR0 = 'asafofer/perch', DEMO_PR = { onboarding: [{ number: 452, url: 'https://github.com/asafofer/perch/pull/452', title: 'Per-chat audience override', repo: PR0, url: 'https://github.com/asafofer/perch/pull/452', state: 'open', checks: 'running' }],
      website: [{ number: 448, url: 'https://github.com/asafofer/perch/pull/448', title: 'Tighten the hero spacing at phone width', repo: PR0, state: 'open', checks: 'pass', review: 'approved' }],
      docs: [{ number: 455, url: 'https://github.com/asafofer/perch/pull/455', title: 'Rewrite the install guide', repo: PR0, state: 'draft' }],
      planner: [{ number: 431, url: 'https://github.com/asafofer/perch/pull/431', title: 'Video to 3D world with measured walls', repo: PR0, state: 'merged' }, { number: 436, url: 'https://github.com/asafofer/perch/pull/436', title: 'Fill the missing areas from the depth pass', repo: PR0, state: 'merged' }],
      lukatz: [{ number: 12, url: 'https://github.com/asafofer/perch/pull/12', title: 'Add the team to the town map', repo: PR0, state: 'closed' }],
      api: [{ number: 460, url: 'https://github.com/asafofer/perch/pull/460', title: 'Add a per-key rate limiter to the public API', repo: PR0, state: 'open', checks: 'fail' }, { number: 441, url: 'https://github.com/asafofer/perch/pull/441', title: 'Add a token bucket to the limiter', repo: PR0, state: 'merged' }],
      fluid: [{ number: 87, url: 'https://github.com/asafofer/perch/pull/87', title: 'Stop a runaway tool loop', repo: PR0, state: 'open', checks: 'pass', review: 'changes' }],
      gaps: [{ number: 23, url: 'https://github.com/asafofer/perch/pull/23', title: 'Set up the PDF gap finder', repo: PR0, state: 'open', conflict: true }],
      tui: [{ number: 9, url: 'https://github.com/asafofer/perch/pull/9', title: 'Keyboard focus for the table', repo: PR0, state: 'open', checks: 'pass' }, { number: 7, url: 'https://github.com/asafofer/perch/pull/7', title: 'Add Perch to the landing page', repo: 'asafofer/perch-landing', state: 'merged' }] };
    P.forEach(function (p) { if (DEMO_PR[p.id]) p.prs = DEMO_PR[p.id]; });
    /* this Mac's real app icons when ./scripts/run.sh --design-icons has written them; the stand-ins otherwise */
    fetch('icons.local.json', { cache: 'reload' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (o) {
      if (!o) return; icons = o; listSig = ''; if (snap) apply(Object.assign({}, snap, { timerToken: snap.timerToken }));
    }).catch(function () {});
    var hash = (location.hash || '#open').slice(1);
    var phase = { idle: 'idle', open: 'open', switcher: 'switcher', restoring: 'restoring' }[hash] || 'open';
    var sel = +(new URLSearchParams(location.search).get('i') || 0);
    document.body.style.background = '#16201e';
    function d0() { clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); }
    var base = { canUpdate: true, selected: sel, timerToken: 0, screen: { hasNotch: true, notchW: 185, notchH: 32 }, projects: P, version: '0.1.0 (198)' };
    apply(Object.assign({ phase: phase, autoCollapse: phase === 'open' }, base));
    var autoTimer, devQuery = '', devCaret = 0, devAnchor = 0;
    function devShown() {
      var words = devQuery.toLowerCase().split(/\s+/).filter(Boolean);
      var mins = function (p) { var m = /^(\d+)([mhd])/.exec(p.away || ''); return m ? +m[1] * { m: 1, h: 60, d: 1440 }[m[2]] : 1e9; };
      var rank = function (p) { return { 'Needs you': 0, Today: 1 }[sectionOf(p)] === undefined ? 2 : { 'Needs you': 0, Today: 1 }[sectionOf(p)]; };
      return P.map(function (p, k) { return k; }).filter(function (k) { var hay = (P[k].name + ' ' + P[k].topic).toLowerCase(); return words.every(function (w) { return hay.indexOf(w) >= 0; }); })
        .sort(function (a, b) { return rank(P[a]) - rank(P[b]) || mins(P[a]) - mins(P[b]) || a - b; });
    }
    /* the new session flow: the agents on this Mac and the folders sessions ran in, newest first */
    var NEW_APPS = [{ id: 'claude', app: 'claude', name: 'Claude' }, { id: 'claude-code', app: 'claude', via: 'ghostty', name: 'Claude Code' }, { id: 'codex', app: 'codex', name: 'Codex' },
      { id: 'opencode', app: 'opencode', via: 'ghostty', name: 'OpenCode' }, { id: 'pi', app: 'pi', via: 'ghostty', name: 'pi' }];
    var NEW_DIRS = [['api-server', '~/Code/api-server', '1m'], ['docs', '~/Code/docs', '1m'], ['tui-kit', '~/Code/tui-kit', '2m'], ['perch', '~/Documents/perch', '4m'], ['price-scraper', '~/Code/price-scraper', '12m'],
      ['website', '~/Code/website', '48m'], ['room-planner-prototype', '~/Documents/room-planner-prototype', '5h'], ['lukatz_website', '~/Code/lukatz_website', '1d'], ['spec-gap-finder', '~/Code/spec-gap-finder', '2d'], ['finance', '~/Documents/finance', '3d']]
      .map(function (x) { return { name: x[0], path: x[1], away: x[2] }; });
    /* it starts on the agent and folder of the session you are looking at: the row you were on, or the one in front of you */
    function newFrom(p) {
      var agent = !p ? 'claude' : p.app === 'claude' ? (p.via ? 'claude-code' : 'claude') : p.app;
      var dir = p && NEW_DIRS.filter(function (x) { return x.name === p.name.toLowerCase(); })[0];
      return { apps: NEW_APPS, projects: NEW_DIRS, agent: agent, project: dir ? dir.name : 'perch' };
    }
    var devNewRun = 0;
    function devNew(m) {
      var D = window.perchDev, nowEl = document.getElementById('now');
      if (!m.action) { D.newSession(m.from === 'anywhere' ? { from: 'anywhere' } : {}); return; }
      if (m.action === 'chooseFolder') {
        if (nowEl) nowEl.textContent = 'macOS\u2019s folder picker opens; you pick ~/Code/landing-page';
        setTimeout(function () {
          if (!snap || snap.phase !== 'newSession') return;
          var o = JSON.parse(JSON.stringify(snap.newSession)); o.projects.unshift({ name: 'landing-page', path: '~/Code/landing-page', away: '' });
          nw.q = ''; nw.proj = 1; nw.step = 'prompt'; apply(Object.assign({}, snap, { newSession: o, timerToken: Math.random() }));
        }, 1100);
        return;
      }
      if (m.action !== 'start') return;
      var a = NEW_APPS.filter(function (x) { return x.id === m.agent; })[0] || NEW_APPS[0];
      var name = m.folder ? m.folder.split('/').pop() : 'No project', fail = D.newFails, id = 'new-' + Date.now();
      var row = { id: id, name: name, via: a.via, branch: 'main', away: '0m', at: 'now', headline: '', context: '', now: 'Reading the code', next: '', topic: (m.title || m.prompt).length > 70 ? (m.title || m.prompt).slice(0, 68) + '\u2026' : (m.title || m.prompt), app: a.app, attention: false, fresh: true, line: 'Working now', status: { kind: 'running', text: agentName(a.app) + ' is working', app: a.app } };
      var later = function (ms, f) { var k = devNewRun; setTimeout(function () { if (k === devNewRun) f(); }, ms); };
      /* from the list it goes back to the list at once; from anywhere the card folds as the words go in (SEND_CLOSE, as a reply to a terminal does) */
      var close = (m.go || m.from === 'list' ? 0 : m.close) * 1000;
      if (m.go) { later(0, function () { apply(Object.assign({}, snap, { phase: 'idle', timerToken: Math.random() })); }); if (nowEl) nowEl.textContent = (a.via ? 'Ghostty' : agentShort(a.app)) + ' comes forward on the new session, your words sent'; return; }
      /* from the list: back to the list, where the new session is a row at once, Starting, then Started (or Didn't start) */
      if (m.from === 'list') {
        var keep = null, relist = function () { var sh = devShown(); base.selected = Math.max(0, P.indexOf(keep)); apply(Object.assign({}, base, { phase: 'switcher', character: charNow, autoCollapse: false, query: '', shown: sh, selected: base.selected, timerToken: Math.random() })); };
        var pend = Object.assign({}, row, { pending: 'starting', status: { kind: 'running', text: 'Starting', app: a.app }, fresh: false, now: '' });
        later(close, function () {
          D.show('switcher'); keep = P[base.selected]; P.unshift(pend); relist();
          if (nowEl) nowEl.textContent = 'Back in the list at once: the new session is already a row, Starting\u2026';
        });
        /* the app asks you to confirm the folder: it has the keyboard now, so the list folds into the line that says so */
        if (D.newConfirms) {
          later(close + 1200, function () {
            pend.pending = 'confirm'; relist(); nwStarted('confirm', agentShort(a.app));
            apply(Object.assign({}, snap, { phase: 'idle', timerToken: Math.random() }));
            if (nowEl) nowEl.textContent = agentShort(a.app) + ' asks you to trust the folder: the list folds into the line that says so';
          });
          later(close + 5200, function () {
            P[P.indexOf(pend)] = row; nwStarted(true);
            apply(Object.assign({}, snap, { projects: P, timerToken: Math.random() }));
            if (nowEl) nowEl.textContent = 'Confirmed there: Perch sees the session, Started';
          });
          return;
        }
        later(close + 1500, function () {
          pend.pending = fail ? 'failed' : 'started'; relist();
          if (fail) nwStarted(false); else nwStarted(true);
          if (nowEl) nowEl.textContent = fail ? 'It never came: Didn\u2019t start. Your words wait for the next Command+Option+N' : 'Perch sees it: Started, the plane flies in';
        });
        later(close + 1500 + SENT_MS, function () {
          if (fail) { pend.pending = 'gone'; relist(); later(360, function () { P.splice(P.indexOf(pend), 1); relist(); }); if (nowEl) nowEl.textContent = 'The row folds away'; return; }
          P[P.indexOf(pend)] = row; relist();
          if (nowEl) nowEl.textContent = 'An ordinary row now: working, in website';
        });
        return;
      }
      /* from anywhere: the card folds into one line, Starting, then Started (or Didn't start) */
      later(close, function () { apply(Object.assign({}, snap, { phase: 'idle', timerToken: Math.random() })); if (nowEl) nowEl.textContent = 'The card folds into one line: Starting\u2026'; });
      later(close + 1700, function () {
        if (!fail) P.unshift(row);
        nwStarted(!fail);
        if (nowEl) nowEl.textContent = fail ? 'It never came: Didn\u2019t start, and your words wait for the next Command+Option+N' : 'Started: Perch sees the new session';
      });
    }
    window.perchDev = {
      /* a pull request mark (or the mark of several) for a scenario's button on the design page */
      prIcon: function (specs) { return PRMark(specs.map(function (x) { return Object.assign({ number: 1, state: 'open' }, x); }), 'size-4'); },
      /* every pull request mark with its words and colour, for the design page's grid */
      prLegend: function () {
        return [['open', {}], ['open', { checks: 'running' }], ['open', { checks: 'pass', review: 'approved' }], ['open', { review: 'approved' }], ['open', { checks: 'fail' }], ['open', { review: 'changes' }], ['open', { conflict: true }], ['draft', {}], ['merged', {}], ['closed', {}]]
          .map(function (x) { var pr = Object.assign({ number: 452, state: x[0] }, x[1]), w = prWord(pr), c = w.c === COLORS.attention ? COLORS.attention : PRC[pr.state]; return { icon: PRIcon(pr, 'size-5'), word: w.t, color: prColor(pr) }; }).concat([{ icon: PRMark([{ number: 107, state: 'merged' }, { number: 109, state: 'merged' }], 'size-5'), word: 'Several', color: PRC.merged }]);
      },
      /* the list stays open while sessions change under it (the design page's Motion scenarios): `over` maps a session's
         index to what changes in it; the list sorts itself as the app's would. `sel` is the index of the row to choose. */
      listChange: function (over, sel) {
        clearTimeout(autoTimer);
        var keep = P; P = P.map(function (x, k) { return over && over[k] ? Object.assign({}, x, over[k]) : x; });
        var shown = devShown();
        apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'switcher', autoCollapse: false, shown: shown, selected: sel == null ? shown[0] : sel, timerToken: Math.random() }));
        P = keep;
      },
      /* the new session flow; o can set agent, project, step, text and q (what is typed to narrow the folders) */
      newSession: function (o) {
        o = o || {}; clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); nw.on = false;
        if (o.text !== undefined) nw.text = o.text;
        var front = P.filter(function (x) { return x.id === 'api'; })[0];
        var ns = Object.assign(newFrom(o.from === 'anywhere' ? front : P[base.selected]), { from: o.from === 'anywhere' ? 'anywhere' : 'list' }, o.agent ? { agent: o.agent } : {}, o.project ? { project: o.project } : {});
        apply(Object.assign({}, base, { phase: 'newSession', character: charNow, autoCollapse: false, newSession: ns, timerToken: Math.random() }));
        if (o.step || o.q) { nw.step = o.step || nw.step; nw.q = o.q || ''; if (o.q) nw.proj = 0; newRender(); }
      },
      /* a character as markup, for pages that draw it outside the notch (ui/install/background.html, the disk image's picture) */
      character: function (shape, size, mood) { return crHtml('', size, shapeOf(shape), mood); },
      /* open a group on the apps step or on Settings, Agents */
      openGroup: function (id) { var el = q('.onb .og[data-g=' + id + '] .og-h') || q('.set .s-grp[data-g=' + id + ']'); if (el) el.click(); },
      show: function (ph, quiet, mine) { if (ph === 'open' && P[base.selected] && P[base.selected].pending) return; clearTimeout(autoTimer); devQuery = ''; devCaret = devAnchor = 0; if (base.once) base.once = false; else { base.canSend = true; base.allowing = false; } snoozeMenu(false, true); replyMenu(false, true); if (ph === 'switcher') { var top = devShown()[0]; if (top !== undefined) base.selected = top; } var s = Object.assign({}, base, { character: charNow, projects: quiet ? P.map(function (x) { return Object.assign({}, x, { attention: false }); }) : P, phase: ph, autoCollapse: ph === 'open', proactive: ph === 'open' && !mine, shown: ph === 'switcher' ? devShown() : null, timerToken: Math.random() }); apply(s); },
      /* the selection's highlight: drawn by the page (the default) or the system's own, to compare them */
      hl: function (mode) { if (mode === 'native') document.documentElement.dataset.hl = 'native'; else delete document.documentElement.dataset.hl; hlDraw(); },
      tint: function (color) { applyCharacter({ shape: charNow.shape, color: color }); },
      setNotch: function (has) {
        base.screen = has ? { hasNotch: true, notchW: 185, notchH: 32 } : { hasNotch: false, notchW: 0, notchH: 24 };
        if (snap) apply(Object.assign({}, snap, { screen: base.screen, timerToken: Math.random() }));
      },
      shortcut: function (patch) { devScSync(patch); },
      settings: function (o, keep) {
        devScBack(); setGroup = o && o.group || '';
        if (!keep) { devSc = Object.assign({}, SC0, o && o.shortcut || {}); devScNew = Object.assign({}, SCN0); axAsked = false; }
        /* each scenario starts Settings afresh: the list, at the top, nothing written to send */
        if (!keep) { fbText = ''; fbMail = ''; fbFiles = []; fbState = ''; fbInfo = true; fbMailSaid = false; window.perchDev.fbFail = window.perchDev.fbHold = false; setPage = ''; setSig = ''; setFocus = setRootAt = 0; setKb = true; }
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        apply(Object.assign({}, base, { phase: 'settings', character: charNow, autoCollapse: false, timerToken: Math.random(), update: o && o.update ? o.update : null, notifyOff: o && o.notifyOff || [],
          settings: Object.assign({ sources: [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }], accessibility: true, idleMinutes: 20, questionSeconds: 60, login: false, live: 'on', prs: 'off', showPRs: true, hasExternal: !base.screen.hasNotch, hoverExternal: false, showOn: 'mouse', displays: DEV_DISPLAYS, shortcut: devScOut(!o || o.accessibility !== false), newShortcut: { keys: devScNew.keys, custom: devScNew.custom } }, o || {}) }));
        if (o && o.page) setGo(o.page, true); else if (!keep) setGo('', true);
      },
      /* `scan`: the first scan is still running when the step opens; it comes in, then the app keeps sending the same
         snapshot every half second, as it does while sessions are written */
      onboarding: function (step, accessibility, only, live, all, scan, which, gh) {
        devScBack();
        /* the recorder records the shortcut it was opened for: New session's from its row, otherwise the one that opens Perch */
        if (only && step === 3 && which === 'new') { devScOpen = devSc; devSc = Object.assign({}, SC0, devScNew, { which: 'new', recording: true }); }
        else devSc = only && step === 3 ? Object.assign({}, devSc, { which: 'open', recording: true, error: '', saved: false, tried: false }) : Object.assign({}, SC0);
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        var sources = [{ id: 'claude', name: 'Claude Code', count: 3, names: ['Website', 'Docs', 'Finance'], enabled: true }, { id: 'codex', name: 'Codex', count: 1, names: ['Onboarding flow'], enabled: true }];
        if (all) sources = sources.concat([{ id: 'opencode', name: 'OpenCode', count: 1, names: ['tui-kit'], enabled: true }, { id: 'pi', name: 'pi', count: 1, names: ['price-scraper'], enabled: true }, { id: 'cursor', name: 'Cursor', count: 2, names: ['api-server', 'website'], enabled: true }]);
        /* every agent Perch knows, to see the choice with the most it can hold; 'new' is only the three added last */
        if (all === 'full' || all === 'new') sources = sources.concat([{ id: 'muse', name: 'Muse', count: 1, names: ['ledger-api'], enabled: true }, { id: 'dots', name: 'Dots', count: 2, names: ['Weekly metrics brief', 'Inbox triage'], enabled: true }, { id: 'grokbot', name: 'Grok Bot', count: 1, names: ['Fix the flaky checkout test'], enabled: true }]);
        if (all === 'full') all = 'app';
        if (all === 'app') sources = sources.slice(0, 1).concat([{ id: 'cowork', name: 'Claude tasks', count: 2, names: ['Taxes', 'Inbox'], enabled: true }, { id: 'chat', name: 'Claude chats', count: 30, names: [], enabled: false }], sources.slice(1));
        var places = all === 'app' ? [{ id: 'conductor', name: 'Conductor' }, { id: 'herdr', name: 'herdr' }, { id: 'tmux', name: 'tmux' }, { id: 'cmux', name: 'cmux' }, { id: 'agterm', name: 'agterm' }] : [];
        var s0 = Object.assign({}, base, { phase: 'onboarding', character: charNow, autoCollapse: false, timerToken: Math.random(),
          onboarding: { step: step, total: gh ? 8 : 7, prs: gh === 'on' ? 'on' : 'off', shortcut: devScOut(!!accessibility), accessibility: !!accessibility, scanning: !!scan, sources: sources, places: places, only: !!only, live: live || 'off' } });
        apply(s0);
        if (!scan) return;
        var k = 0, again = function () {
          if (!snap || snap.phase !== 'onboarding' || snap.onboarding.step !== step) return;
          var s1 = JSON.parse(JSON.stringify(snap)); s1.onboarding.scanning = false; s1.timerToken = Math.random(); apply(s1);
          if (++k < 12) autoTimer = setTimeout(again, 500);
        };
        autoTimer = setTimeout(again, 1600);
      },
      variant: function (i, o) { clearTimeout(autoTimer); actGone = {}; snoozeMenu(false, true); replyMenu(false, true); base.canSend = true; apply(Object.assign({}, base, { character: charNow, selected: i, projects: P.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), phase: 'open', proactive: true, autoCollapse: true, timerToken: Math.random() })); },
      /* the list with one session changed, as variant does for the card */
      variantList: function (i, o) { clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true); apply(Object.assign({}, base, { character: charNow, selected: i, projects: P.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), phase: 'switcher', autoCollapse: false, timerToken: Math.random() })); },
      /* the next refresh of the same card, a reply left open as it is */
      refresh: function (i, o) { apply(Object.assign({}, base, { character: charNow, selected: i, projects: P.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), phase: 'open', timerToken: Math.random() })); },
      empty: function (scanning) { clearTimeout(autoTimer); apply(Object.assign({}, base, { character: charNow, projects: [], selected: 0, phase: 'switcher', autoCollapse: false, scanning: !!scanning, timerToken: Math.random() })); },
      /* the switching proposals: pick a style and watch it move through the list a few times */
      /* plays the character's part in moving between sessions: through the list, or into a card and back. Any other
         scenario stops it (fxStop). */
      fxStop: function () { fxPlay++; },
      fx: function (play) {
        fxMood = ''; window.perchDev.show('switcher');
        var me = ++fxPlay, go = function (i, f) { setTimeout(function () { if (me === fxPlay) f(); }, 900 + i * 850); };
        if (play === 'list') [1, 1, 1, -1, -1, -1].forEach(function (d, i) { go(i, function () { if (lastSt === 'switch') window.perchDev.step(d); }); });
        if (play === 'details') { go(0, function () { window.perchDev.step(1); }); go(1, function () { window.perchDev.show('open', false, true); }); go(3, function () { window.perchDev.show('switcher'); }); go(4, function () { window.perchDev.step(1); }); go(5, function () { window.perchDev.show('open', false, true); }); }
      },
      noAccess: function (waiting) { base.canSend = false; base.allowing = !!waiting; base.once = true; },
      /* a session you are not in finishes while you work: the character pops out, happy, and tucks back in */
      finish: function () { var q2 = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, status: x.id === 'docs' ? { kind: 'running', text: 'Codex is working', app: 'codex' } : x.status, fresh: false }); }); apply(Object.assign({}, base, { character: charNow, projects: q2, phase: 'idle', timerToken: Math.random() }));
        setTimeout(function () { q2 = q2.map(function (x) { return x.id === 'docs' ? Object.assign({}, x, { status: { kind: 'done', text: 'Codex finished', app: 'codex' }, fresh: true }) : x; }); apply(Object.assign({}, base, { character: charNow, projects: q2, phase: 'idle', timerToken: Math.random() })); }, 900); },
      /* the last thing waiting on you was answered */
      clear: function () { d0(); apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'idle', timerToken: Math.random() }));
        setTimeout(function () { apply(Object.assign({}, base, { character: charNow, projects: P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'attention' ? { kind: 'running', text: 'Claude Code is working', app: 'claude' } : x.status }); }), phase: 'idle', timerToken: Math.random() })); }, 1600); },
      say: function (t) { window.perch.say(t); },
      /* Perch's own update, at rest on the notch: phase is downloading, ready, restarting or updated (none: no update). `o.progress` is how far the download is. */
      update: function (phase, o) {
        o = o || {}; var LONG_NOTES = ['Record your own shortcut to open Perch', 'Shortcuts work on non-Latin keyboard layouts (Hebrew, Arabic, Cyrillic and more) by falling back to the key\u2019s position on a US keyboard', 'A notch that fits the hardware, on every display', 'Hover opens on the right screen when you have more than one', 'Perch updates itself, with a ring beside the camera while it downloads', 'Check for updates in the menu bar', 'The list shows what needs you first', 'Replies to a Claude app session go in without leaving what you were doing', 'A file dropped on the card goes in as its path', 'OpenCode and pi sessions show up beside Claude Code and Codex', 'herdr and cmux panes are found and brought back exactly', 'The character has a few more shapes and colours', 'Settings has a switch for opening at login', 'Many small fixes']; clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        if (o.fresh !== false && (o.fresh || !snap || !snap.update || snap.update.phase !== phase)) { actGone = {}; if (o.fresh) { updNotes = false; updOpen = false; } }
        var calm = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'attention' || x.status.kind === 'done' ? { kind: 'idle', text: 'Finished', app: x.app } : x.status }); });
        base.update = phase ? { version: phase === 'checking' ? '0.3.0' : '0.3.1', phase: phase, peek: !!o.peek, listOnly: !!o.listOnly, progress: o.progress || 0, notes: 'Record your own shortcut to open Perch', problem: o.problem || '', fix: o.fix || '', during: o.during || '', short: o.short || '',
          bullets: o.long ? LONG_NOTES : ['Record your own shortcut to open Perch', 'Shortcuts work on non-Latin keyboard layouts', 'A notch that fits the hardware, on every display'] } : null;
        if (o.view) { window.perchDev.show(o.view, false, o.view === 'open'); return; }
        /* in the list or on a card: the same snapshot with the update changed, the view stays */
        if (o.stay && snap && (snap.phase === 'switcher' || snap.phase === 'open' || snap.phase === 'settings')) { apply(Object.assign({}, snap, { update: base.update, timerToken: Math.random() })); return; }
        apply(Object.assign({}, base, { character: charNow, projects: o.busy ? P : calm, phase: 'idle', timerToken: Math.random(), update: base.update }));
      },
      /* the card that says what is new, on the first start after an update; `o.long` is a long list, `o.plain` a release with only a headline */
      whatsNew: function (o) {
        o = o || {}; d0(); window.perchDev.updStop(); actGone = {};
        var LONG = ['Lists and code read better in a reply', 'Bullet and numbered lists draw with their markers, nested as written, even with no blank line before them', 'Code in a reply takes your character\u2019s colour', 'Paragraphs and lists in a reply have a clearer gap between them', 'Another app\u2019s shortcut that shares Perch\u2019s modifiers no longer opens Perch', 'Warp sessions are found by reading each tab', 'A reply to a Claude app session goes in without leaving what you were doing', 'A file dropped on the card goes in as its path'];
        var bullets = o.long ? LONG : o.plain ? [] : ['Bullet and numbered lists in a reply draw with their markers, nested as written', 'Code in a reply takes your character\u2019s colour', 'Paragraphs and lists in a reply have a clearer gap between them', 'Another app\u2019s shortcut that shares Perch\u2019s modifiers no longer opens Perch'];
        apply(Object.assign({}, base, { character: charNow, projects: P, phase: 'whatsnew', autoCollapse: false, timerToken: Math.random(), update: null,
          whatsNew: { version: '0.3.10', headline: 'Lists and code read better in a reply', bullets: o.access ? bullets.slice(0, 2) : bullets, access: o.access || null } }));
      },
      /* Accessibility Perch had, gone: `phase` is lost, asked (Allow was pressed, System Settings is open) or granted; null takes it away.
         `o.afterUpdate`: an update brought it about (only when What's new did not say it already). */
      access: function (phase, o) {
        o = o || {}; d0(); if (o.fresh !== false) { window.perchDev.updStop(); actGone = {}; clearTimeout(actTimer); if (act.p && act.p.access) act.mode = ''; }   /* a fresh start runs its own clock */
        base.access = phase ? { phase: phase, afterUpdate: !!o.afterUpdate, since: 1 } : null;
        var calm = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'attention' || x.status.kind === 'done' ? { kind: 'idle', text: 'Finished', app: x.app } : x.status }); });
        apply(Object.assign({}, base, { character: charNow, projects: o.busy ? P : calm, phase: 'idle', timerToken: Math.random(), update: null, access: base.access }));
      },
      /* what Update (or Restart to update) does here: download, restart, come back on the new version. `ready`: it is downloaded already. */
      updRun: function (ready) {
        var me = ++updTok, at = function (ms, f) { setTimeout(function () { if (me === updTok) f(); }, ms); }, sc = document.getElementById('scene'), D = window.perchDev, t = 0;
        if (!ready) { D.update('downloading', { progress: 0.03, fresh: false, stay: true }); for (var k = 1; k <= 12; k++) (function (k) { at(k * 800, function () { D.update('downloading', { progress: Math.min(1, k / 12), fresh: false, stay: true }); }); })(k); t = 10200; at(t, function () { D.update('ready', { fresh: false, stay: true }); }); t += 900; }
        at(t, function () { D.update('restarting', { fresh: false }); });
        at(t + 2300, function () { sc.style.transition = 'opacity .25s'; sc.style.opacity = '0'; });
        at(t + 3700, function () { D.update(null); sc.style.opacity = '1'; });
        at(t + 4400, function () { D.whatsNew(); });
      },
      /* the snapshot as it is, with one session changed: something happening elsewhere while a scenario plays */
      also: function (i, o) { if (snap) apply(Object.assign({}, snap, { projects: snap.projects.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), timerToken: Math.random() })); },
      updStop: function () { updTok++; base.access = null; base.update = null; document.getElementById('scene').style.opacity = '1'; },
      /* how an answer from the notch says it went: 'answer' (one line, your answer and a check) or 'check' (the wings, the app and a check) */
      /* an answer that came too late (answered in the app already, or Perch had let the question go): the line says it did not send */
      sentFail: function (a) {
        var p = act.p, b = actEl.querySelector('.act-btns [data-a="' + a + '"]'); if (!p) return;
        clearTimeout(actTimer); act.keys = []; actPressing = true; sentBase = actKnown; if (b) { actEl.classList.add('chose'); b.classList.add('on'); }
        notSent(p.id);   /* as Swift says it: a moment after the press, before the row has folded */
        setTimeout(function () { actPressing = false; sentShow(p, 'Sent'); }, 170);
      },
      /* a click on the small character beside the card: one reaction, or (no name) the next in turn */
      mascot: function (name) { crPlay = 0; crClick(name); },
      /* the character step, the preview playing one trick again and again; another scenario stops it (fxStop) */
      trick: function (name) {
        window.perchDev.onboarding(1);
        var me = ++fxPlay;
        (function again(ms) { setTimeout(function () { var pv = q('.cr-pv'); if (me !== fxPlay || !pv) return; pv._busy = Date.now() + 99999; trick(pv, name); again(2400); }, ms); })(900);
      },
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
      /* the notch at rest, then one session changes: what the live activity does when an answer or a request arrives */
      /* `off`: the kinds Settings > Notify me about has switched off */
      arrive: function (i, o, off) {
        d0(); base.selected = 0; actGone = {}; actSeen = {};   /* a scenario played again arrives again, answered or not */
        var calm = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'running' ? x.status : { kind: 'idle', text: 'Finished', app: x.app } }); });
        apply(Object.assign({}, base, { character: charNow, projects: calm, phase: 'idle', notifyOff: off || [], timerToken: Math.random() }));
        autoTimer = setTimeout(function () { apply(Object.assign({}, base, { character: charNow, projects: calm.map(function (x, k) { return k === i ? Object.assign({}, x, o) : x; }), phase: 'idle', notifyOff: off || [], timerToken: Math.random() })); }, 900);
      },
      play: function () { var d = window.perchDev; d.show('idle'); autoTimer = setTimeout(function () { d.show('open'); }, 1200); },
      project: function (i) { base.selected = i; },
      /* each scenario starts with no replies left typed */
      clearDrafts: function () { base.drafts = {}; if (snap) snap.drafts = base.drafts; nw.text = ''; nw.last = ''; nw.files = []; nw.lastFiles = []; nw.kept = null; repFiles = {}; devNewRun++; window.perchDev.newFails = false; window.perchDev.newConfirms = false; for (var k = P.length - 1; k >= 0; k--) if (/^(new|app)-/.test(P[k].id)) { P.splice(k, 1); base.selected = 0; } },
      /* Claude tasks and chats join the sample sessions for one scenario (the next scenario takes them out); returns their places */
      claudeApp: function () {
        var at = P.length;
        P.push({ id: 'app-cowork', name: 'Taxes', branch: '', away: '25m', at: '11:35 AM', headline: 'Sorting this year\u2019s receipts.', context: 'Filed 38 receipts by month into Taxes/2026. Three have no date and wait in Unsorted.', next: '', topic: 'Sort this year\u2019s receipts by month', app: 'cowork', attention: false, fresh: true, line: 'Finished 25m ago', status: { kind: 'done', text: 'Claude replied', app: 'cowork' },
          asked: 'Sort the receipts in my Taxes folder by month and tell me which ones you could not place.', said: 'Filed 38 receipts by month into Taxes/2026.\n\nThree have no date on them, so they wait in **Unsorted**: two from Hetzner and a photo of a till slip.' },
          { id: 'app-cowork2', name: 'Inbox', branch: '', away: '2h', at: '10:05 AM', headline: 'Not opened on this Mac yet', context: '', next: '', topic: 'Sort the inbox into folders', app: 'cowork', attention: false, fresh: true, line: 'Finished 2h ago', status: { kind: 'done', text: 'Claude replied', app: 'cowork' } },
          { id: 'app-chat', name: '', branch: '', away: '1h', at: '11:02 AM', headline: '', context: 'Three quiet places near Marylebone with a table for two on Saturday: Trishna, Orrery and The Ninth.', next: '', topic: 'Anniversary dinner ideas', app: 'chat', attention: false, fresh: true, line: 'Replied 1h ago', status: { kind: 'done', text: 'Claude replied', app: 'chat' },
            asked: 'somewhere quiet for an anniversary dinner on saturday, near marylebone, not too formal', said: 'Three quiet places near Marylebone with a table for two on Saturday:\n\n- **Trishna**: modern Indian, softly lit, about \u00a375 a head\n- **Orrery**: French, looks over the church garden, the most romantic of the three\n- **The Ninth**: small plates, relaxed, the least formal\n\nOrrery is the one I would book if you want it to feel like an occasion.' },
          { id: 'app-chat2', name: 'financials', branch: '', away: '3h', at: '9:14 AM', headline: '', context: 'September is up to date. Rent and the two card payments are in; the business balance is \u20aa2,140 short of the bank.', next: '', topic: 'Planning an overdue update', app: 'chat', attention: false, fresh: false, line: '3h ago', status: { kind: 'idle', text: 'Claude replied', app: 'chat' },
            asked: 'update the sheet with the september statements', said: 'September is up to date. Rent and the two card payments are in; the business balance is \u20aa2,140 short of the bank, which is the Deeto transfer that has not cleared yet.' });
        return at;
      },
      step: function (d) {
        var shown = devShown(), at = shown.indexOf(base.selected);
        if (!shown.length) return;
        base.selected = at < 0 ? shown[0] : shown[(at + d + shown.length) % shown.length];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, queryCaret: devCaret, queryAnchor: devAnchor, shown: shown, timerToken: Math.random() }));
      },
      /* the same narrowing as ListFilter in Swift: every word must appear in the name or the title */
      type: function (t) {
        devQuery = t; devCaret = devAnchor = t.length; var shown = devShown(); if (shown.length) base.selected = shown[0];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, queryCaret: devCaret, queryAnchor: devAnchor, shown: shown, timerToken: Math.random() }));
      },
      /* the typed words as a field: caret anywhere, a selection, edits at the caret (Perch's FilterField) */
      edit: function (e) {
        var lo = Math.min(devCaret, devAnchor), hi = Math.max(devCaret, devAnchor), k = e.key;
        var word = function (i, d) { var j = i; if (d < 0) { while (j > 0 && /\s/.test(devQuery[j - 1])) j--; while (j > 0 && !/\s/.test(devQuery[j - 1])) j--; } else { while (j < devQuery.length && /\s/.test(devQuery[j])) j++; while (j < devQuery.length && !/\s/.test(devQuery[j])) j++; } return j; };
        var set = function (t, c) { devQuery = t; devCaret = devAnchor = c; var shown = devShown(); if (shown.length) base.selected = shown[0]; draw(shown); }, draw = function (shown) { apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, queryCaret: devCaret, queryAnchor: devAnchor, shown: shown || devShown(), timerToken: Math.random() })); };
        if (k === 'ArrowLeft' || k === 'ArrowRight') {
          var d = k === 'ArrowLeft' ? -1 : 1, to = e.metaKey ? (d < 0 ? 0 : devQuery.length) : e.altKey ? word(devCaret, d) : lo !== hi && !e.shiftKey ? (d < 0 ? lo : hi) : Math.min(Math.max(devCaret + d, 0), devQuery.length);
          devCaret = to; if (!e.shiftKey) devAnchor = to; draw(); return;
        }
        if (e.metaKey && k.toLowerCase() === 'a') { devAnchor = 0; devCaret = devQuery.length; draw(); return; }
        if (e.metaKey && k.toLowerCase() === 'c') { if (lo !== hi && navigator.clipboard) navigator.clipboard.writeText(devQuery.slice(lo, hi)); return; }
        if (k === 'Backspace' || k === 'Delete') {
          if (lo === hi) { if (k === 'Backspace') { if (!lo) return; lo = e.altKey ? word(lo, -1) : lo - 1; } else { if (hi >= devQuery.length) return; hi++; } }
          set(devQuery.slice(0, lo) + devQuery.slice(hi), lo); return;
        }
        set(devQuery.slice(0, lo) + k + devQuery.slice(hi), lo + k.length);
      }
    };
    /* recording and trying the shortcut with the browser's own keys (capture phase, before anything else sees them) */
    var scMods = [], scKey = false, SC_GLYPH = [['ctrlKey', '\u2303'], ['altKey', '\u2325'], ['shiftKey', '\u21E7'], ['metaKey', '\u2318']];
    var scHeld = function (e) { return SC_GLYPH.filter(function (g) { return e[g[0]]; }).map(function (g) { return g[1]; }); };
    var scTaken = { '\u2303\u2325P': 'the welcome card', '\u2303\u2325L': 'the project list', '\u2303\u2325Q': 'Quit Perch', '\u2318Q': 'Quit in every app', '\u2318W': 'Close in every app', '\u2318C': 'Copy', '\u2318V': 'Paste', '\u2318Space': 'Spotlight' };
    /* what you press is only a choice; Return alone saves it, another try replaces it */
    var scDone = function (keys, kind) { devScSync({ pending: keys, pendKind: kind, error: '', attempt: [], picks: (devSc.picks || 0) + 1 }); };
    var scSave = function () {
      var std = devSc.which === 'new' ? SCN0 : SC0, keys = devSc.pending, kind = devSc.pendKind, same = keys.join('') === std.keys.join('') && kind === std.kind;
      devScSync({ keys: keys, kind: kind, custom: !same, recording: false, error: '', attempt: [], pending: [], tried: false, saved: true });
    };
    window.perchDev.saveChoice = scSave;
    document.addEventListener('keydown', function (e) {
      if (snap && (snap.phase === 'settings' || snap.phase === 'onboarding')) window.perch.held(scHeld(e));
      if (!snap || !(snap.phase === 'settings' || snap.phase === 'onboarding') || e.repeat) return;
      var isMod = /^(Control|Alt|Shift|Meta)$/.test(e.key), held = scHeld(e);
      if (isMod) { if (held.length >= scMods.length) scMods = held; scKey = false; if (devSc.recording) { e.preventDefault(); e.stopImmediatePropagation(); } return; }
      if (!devSc.recording) {
        if (snap.phase === 'onboarding' && snap.onboarding.step === 3 && devSc.kind === 'combo' && held.concat([e.key === ' ' ? 'Space' : e.key.toUpperCase()]).join('') === devSc.keys.join('')) { e.preventDefault(); devScSync({ tried: true }); }
        scKey = true; return;
      }
      e.preventDefault(); e.stopImmediatePropagation(); scKey = true;
      if (e.key === 'Escape') { devScSync({ recording: false, error: '', pending: [] }); if (snap.onboarding && snap.onboarding.only) dev({ type: 'onb', action: 'next' }); return; }
      var name = { ' ': 'Space', ArrowUp: '\u2191', ArrowDown: '\u2193', ArrowLeft: '\u2190', ArrowRight: '\u2192', Enter: '\u21A9', Tab: '\u21E5' }[e.key] || (e.key.length === 1 ? e.key.toUpperCase() : e.key);
      if (e.key === 'Enter' && !held.length && devSc.pending && devSc.pending.length) { scSave(); return; }
      if (!held.length) { devScSync({ error: 'Hold \u2318, \u2325, \u2303 or \u21E7 too', attempt: [name], refusals: (devSc.refusals || 0) + 1 }); return; }
      var combo = held.join('') + name;
      if (scTaken[combo]) { devScSync({ error: combo + ' is ' + scTaken[combo], attempt: held.concat([name]), refusals: (devSc.refusals || 0) + 1 }); return; }
      scDone(held.concat([name]), 'combo');
    }, true);
    document.addEventListener('keyup', function (e) {
      if (!snap || !(snap.phase === 'settings' || snap.phase === 'onboarding')) return;
      window.perch.held(scHeld(e));
      if (scHeld(e).length) return;
      var mods = scMods, only = !scKey; scMods = []; scKey = false;
      if (!only || !mods.length) return;
      if (devSc.recording) {
        e.preventDefault(); e.stopImmediatePropagation();
        if (devSc.which === 'new') { devScSync({ error: 'New session needs a key too, like \u2325\u2318N.', attempt: mods, refusals: (devSc.refusals || 0) + 1 }); return; }
        if (mods.length < 2) { devScSync({ error: 'A tap needs two or more modifier keys', attempt: mods, refusals: (devSc.refusals || 0) + 1 }); return; }
        var tap = mods.join('');
        if (scTaken[tap]) { devScSync({ error: tap + ' is ' + scTaken[tap], attempt: mods, refusals: (devSc.refusals || 0) + 1 }); return; }
        scDone(mods.slice().sort(function (a, b) { return '\u2303\u2325\u21E7\u2318'.indexOf(a) - '\u2303\u2325\u21E7\u2318'.indexOf(b); }), 'tap');
      } else if (snap.phase === 'onboarding' && snap.onboarding.step === 3 && devSc.kind === 'tap' && mods.slice().sort().join('') === devSc.keys.slice().sort().join('')) devScSync({ tried: true });
    }, true);
    /* Command+Option+N from anywhere, even with nothing open: a new session */
    document.addEventListener('keydown', function (e) {
      if (e.metaKey && e.altKey && e.code === 'KeyN' && snap && snap.phase !== 'onboarding' && snap.phase !== 'settings') { e.preventDefault(); e.stopImmediatePropagation(); post({ type: 'newSession', from: snap.phase === 'switcher' ? 'list' : 'anywhere' }); }
    }, true);
    document.addEventListener('keydown', function (e) {
      var ph = snap && snap.phase; if (!ph || ph === 'idle') return;
      if (ph === 'newSession') { if (e.target && e.target.classList && e.target.classList.contains('nw-in')) return; if (newKey(e)) e.preventDefault(); return; }
      /* Got it on the what's new card: Command+Option+Return, a key that never types into anything behind the card (the app registers it only while the card shows) */
      if (ph === 'whatsnew' && e.metaKey && e.altKey && e.key === 'Enter') { e.preventDefault(); post({ type: 'whatsnew', action: 'done' }); return; }
      var arrows = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' };
      if (ph === 'onboarding' && !(devSc && devSc.recording) && (e.key === 'c' || e.key === 'C') && onbStep === 3) { e.preventDefault(); onbKey('change'); return; }
      if (ph === 'onboarding' && (arrows[e.key] || e.key === 'Enter' || e.key === 's' || e.key === 'S')) { e.preventDefault(); onbKey(arrows[e.key] || (e.key === 'Enter' ? 'enter' : 'skip')); return; }
      if (ph === 'settings' && (arrows[e.key] || e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); settingsKey(arrows[e.key] || 'enter'); return; }
      /* the same keys as the app when the card asks something: A allows, D denies; for questions a number, Return, Left and Right */
      var ask = ph === 'open' && snap.projects[snap.selected] && snap.projects[snap.selected].ask;
      if (ask && ask.answerable && fRep.style.display !== 'flex') {
        var k = e.key.toLowerCase();
        if (ask.kind === 'permission' && (k === 'a' || k === 'd')) { post({ type: 'answer', choice: k === 'a' ? 'allow' : 'deny' }); return; }
        if (ask.kind === 'question') { var m2 = { Enter: 'enter', Backspace: 'back', ArrowLeft: 'left', ArrowRight: 'next' }[e.key] || (/^[1-9]$/.test(k) ? k : null); if (m2) { e.preventDefault(); askKey(m2); return; } }
      }
      /* What's new: the arrows and Page Up and Down scroll its list, as in the app once the pointer is on it */
      if (ph === 'new' && { ArrowDown: 'down', ArrowUp: 'up', PageDown: 'pageDown', PageUp: 'pageUp' }[e.key]) { e.preventDefault(); window.perch.wnScroll({ ArrowDown: 'down', ArrowUp: 'up', PageDown: 'pageDown', PageUp: 'pageUp' }[e.key]); return; }
      if (previewOn && ph === 'open') {
        var rk = e.key === 'Escape' || e.key === 'ArrowLeft' || e.key === ' ' ? 'close' : e.key === 'PageDown' ? 'pageDown' : e.key === 'PageUp' ? 'pageUp' : e.key === 'ArrowDown' ? (e.metaKey ? 'end' : 'down') : e.key === 'ArrowUp' ? (e.metaKey ? 'top' : 'up') : e.metaKey && e.key === 'c' ? 'copy' : !e.metaKey && (e.key === 'r' || e.key === 'R') ? 'reply' : '';
        if (rk) { e.preventDefault(); previewKey(rk); return; }
      }
      if (e.key === ' ' && ph === 'switcher' && !devQuery) { e.preventDefault(); window.perchDev.show('open', false, true); previewMenu(true, false, 'list'); return; }
      if (e.key === ' ' && ph === 'open' && fRep.style.display !== 'flex') { e.preventDefault(); previewMenu(true); return; }
      if (e.key === 'Escape' && ph === 'switcher' && devQuery) { window.perchDev.type(''); return; }
      if (e.key === 'Escape' && ph === 'settings') { settingsKey('esc'); return; }
      if (e.key === 'Escape') { if (fSnz.style.display === 'flex') snoozeMenu(false, true); else if (fRep.style.display === 'flex') replyMenu(false); else window.perchDev.show('idle'); }
      else if (e.key === 'Enter' && (ph === 'open' || ph === 'switcher')) window.perchDev.show('idle');
      else if (e.key === 'Tab' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.key === 'Tab' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open'); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'switcher') { e.preventDefault(); window.perchDev.step(e.key === 'ArrowDown' ? 1 : -1); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'open') { e.preventDefault(); dev({ type: 'flip', dir: e.key === 'ArrowDown' ? 1 : -1 }); }
      else if (ph === 'switcher' && devQuery && (e.key === 'ArrowLeft' || (e.key === 'ArrowRight' && (devCaret < devQuery.length || devCaret !== devAnchor || e.shiftKey)) || (e.metaKey && /^[ac]$/i.test(e.key)))) { e.preventDefault(); window.perchDev.edit(e); }
      else if (e.key === 'ArrowRight' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open', false, true); }
      else if (e.key === 'ArrowLeft' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.metaKey && e.key === ',') { e.preventDefault(); window.perchDev.settings(); }
      else if (ph === 'switcher' && (e.key === 'Backspace' || e.key === 'Delete' || (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !(e.key === ' ' && !devQuery)))) { e.preventDefault(); window.perchDev.edit(e); }
      else if ((e.key === 'n' || e.key === 'N') && ph === 'open') snoozeMenu(fSnz.style.display !== 'flex', true);
      else if (fSnz.style.display === 'flex' && /^[123]$/.test(e.key)) { snoozeMenu(false, true); window.perchDev.show('idle'); }

    });
  }
})();

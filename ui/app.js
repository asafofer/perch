/* Perch notch UI. Swift owns the state machine and calls window.perch.apply(snapshot);
   this file only draws and reports user actions back through the "perch" message handler. */
(function () {
  var NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.perch);
  var CARD_W = 400;
  var COLORS = { attention: '#E9A877', done: '#8CCFA4', idle: '#71717A', running: '#8DC8E8' };
  var DOME = { d: 'M2 19V13A10 10 0 0 1 5.4 5.5L5.2 2.6Q5 1.4 6 1.9L9.6 3.7A10 10 0 0 1 14.4 3.7L18.2 1.9Q19.2 1.4 18.8 2.6L18.6 5.5A10 10 0 0 1 22 13v6a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z', et: '44%' };

  /* ---- shadcn recipes ---- */
  var ICON = {
    enter: '<polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    chev: '<path d="m6 9 6 6 6-6"/>',
    list: '<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>',
    load: '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
    win: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/>',
    file: '<path d="M10 12.5 8 15l2 2.5"/><path d="m14 12.5 2 2.5-2 2.5"/><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    down: '<path d="M12 4.5v11"/><path d="M7.5 11.5l4.5 4.5 4.5-4.5"/><path d="M5 19.5h14"/>',
    restart: '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4.5v4h-4"/>',
    gear: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
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
  var AGENTS = { claude: ['Claude Code', 'Claude'], codex: ['Codex', 'Codex'], opencode: ['OpenCode', 'OpenCode'], pi: ['pi', 'pi'] };
  function agentName(k) { return (AGENTS[k] || AGENTS.claude)[0]; }
  function agentShort(k) { return (AGENTS[k] || AGENTS.claude)[1]; }
  /* Codex's own mark, the icon its app ships (icon-codex-light.png), for when Codex is only a command on this Mac and for
     the design page. The app itself now wears ChatGPT's icon; Swift sends this same mark from inside it. */
  var MARKS = { codex: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAOFElEQVR42u1bW2wc5RU+/z+zN1/jS0icOHHixCQpJCGFJIQmEBVIqasikKjoA+ItlUgfaJ8q3qhUFdEn+gB9iNRKfQIV2grRBBqCzEVNQoFEDRSnuZBLc/V1vfZ6d2dn/p7zX3b+Xez1jmOnleo/OprZGc/Mf75zznfO+WcCsDAWxsJYGAvj/3ewm72BEIJns9mlsVisA6XN9/0mPJxAcVH4HM0zQCmi5B3HGfM8bwjlal1d3TXGWPBfAaBQKGzHyTzBOd+NP9cgEItwMuxWWA2fJfBRo7h7FqUPwXg9Ho8fuyUug4pvCYLgzzgHT0wx8Ny8SZXh0ZxobvOt/D58WPpWKDtLYNIYgvui6FRzjKKb/Rxj/GXcbcIHkRv+zxCZNZ8mDMmXaa5zygFkea08IOI3z7rMTHzuwUAA5Dafz/84mUy+ctMAjIyMbGlubv4ASadhtsobagwEAagUp2M0Vz4PYBAI6BHj6XT6/paWluPV/tapdvL555/nDz300H5k+ztnozwpyZiA8UkGwxmA4TSDkVGUMQ5j4wATeDzvKTPEYyFQcxESCELcdd1OnPurfX19YlYeMDQ0tAMR/JCAMgCYTEcPqZb1OCo+WQC4dIPB+CgHL4uJ3FdeYJ7K0ANiWC0k6wAaFwXQ0SYgFcd70x9INzEaMTwmtOewEv+Y/cp5aABo10cP3tXW1nZkunm61QBIpVJP4s0dZNaym0+1X+6CAKPjAj4/5YAYY1D0lLLM0VYm/UCJh7hOpAHSQxyGRwWs7gxkWBR9pZTrCoijJGPqvkHw9edPNQ8yGFrfIR3w55HIIYDuH9+9e/cvEMmlURifFBzPCThy1AE2hBbC+o2R5VBR5odbML/1vpdDGWeQwfC4+m8Gly8xuHKFwbVrHAbRgzI5BVx9qrrnVXIB/m0ScfgdhoEfKQSOHDmyatu2bSfwJs22B8yMgID3PuDgX+WQSuhEy9SDJCfw8qcStoEmyGKgwsQXSooonq+8hHy1vhmgc0UAm9YG6BWsKnGS0ZADaJs+duzYXTt27DgfKQQ6OjqWIXpN5Eq1eoCD/nTuEsDgaQ7LcbJkfcFKYVxifgOI3OpQp62j44JrMefo2hyG0fXrADcwVAaHAb691ZcgBFWmRnMnHUgX/BkNAMz77VTb18r+SjEBX37OoV4WThU+pgEQ2guMR5Tmr5UlxYVWvgSC+a2B+BIBdhGtB7cHIcLTZwNGukQmQXSfxmpEV57jBQxgers6wGFi1IE6VDBXCNMaswDg2gvkfkUQCqsekKEhrNqBLGoIFD3t+OcOdHUIuH0lhkswPQC2LpEAIPKYie3J5ScmAT7t53D9ggP+ECqFbj/JQra3HEApj+JwCwzrb0z2I30kB5AnCS10DM8HXJ1HfOHjExy6O4t42dR8YKXsZGQA8CK3qvI4keExAW/2uTB8gUOioHK6yzXvMcu6IlTY0WKAKAPBqhiN8gWtbAHPFbgiRpkh8VkXr3AYQD5Y0jZ1JWnVC25kACh2qrl9FlPda++4cPkshzqyDt7JKaq8yllF/GsAzDnHBkIDxplVMlseYJT3uBKfKwAoLxXyANew0FraLqrWdNV0cWstLW3l6XaHjnLoP4WpjsDASbm+VlArQ3FLaY2s7PCw9SRxKr3BAkBeC0pBmQapKNIABI4CIIAwRabHQiKt9NZa6gU3ivIGgCsDAB9+5sh9aRWdww1T0xVLbwPo6QY4dQZT14BS1KQ1bgFlgGAWCEKHgQTBWJwrUCUHmDqhqLxLtcMzz33WHlDuTgI+Q9LLZJksdAKLsSXguI3j8d7vAKzoAFi/DuC3r2FWmNShYOV3E/vcChsOYZnsa+YPNPkR+8t9oZifIzM21Imb6iQjA+AhM51G0nNRSRbTSAdh7yLBcJQC46h0eyvA3XcBHP4bPqyixykVQXo/zIVKSZP65CFHFVaBAYcAQIklhQTPnyUAvJYQCFdcBJIfsn+GSQA4AuBg98ZpH7eg97M4m6Mn1fXU7m7bBNDWrmI5METGdWwzleKI7PKoUA5lEq/Pacmj0jmUfIEWORTx5XEOBZQMAvyXj2KQmRCy7bbnWuuqVeRla69IwqTitnBrm0gBnLwAcHlAWbIOf3/rm9ozXC3WfuBaoEAoMv/r/oCeW/BodQr3UYooAcqJLzgc/MiV7fe8eEC5OygOoDKUowKOa0ksFPIOUvbolyo8aF1gUw/AyuX4m4ogV3kPgUVbGUoGFEcTHbfiX6dFSYIo1Jv5RRVOAu/9Hnael2/ocnw+ACi5FP5L4KQXNQjVhOgen08hCQThHDYvZ66oGKeqcfudeM4obwCLh7/pnAHH3jI37CrL+lhNvEODDInZQS9QZBRl0ZZHSYO0S4sT3ct9KObDY8Kq480+DUqN10bUXClnN9ZpJR1L6QqRIZVQXuTGlUiv0oBJAF0NNNd9BT7n1HkOheItSIMCu6+NPUU42h/DPMyAV/T2TOdy8pBFqPCm1YrIqEzuP6/YOxZTHWHJZZm1hmg1QzK7kNvTUlpRuX5gCWUFrvPmEDZj1IDVJSwLzFUaDGtqvVawWMDd6zz46J9xaZlS+tLrfPR3pOjWzQD1SUVkVDx90h/m/tLSmPEaXRBUAip0uiOydPxyMCRf6GKoKMlZyExkDD/nlaDZdRH2XXcV4NowlsMX3TCv616frN9FRVCX6t+pFH7/E0yPWeSGpC6adIubiBGnlAMIVhtNGWBwVK0vcO0NQvcdpjQmkKj44qzc+PMSAkbR1iYG9/QU4NPjroxbZqzPVYxu/0a4Atx/DuCLf6HrJxR7g64H6jE9/uB+9Kg2q5KcYvwDr3/n70pRur/Q4RPohRW6Z+uiAOIxIUN0zivBqZaeY1jWjQ5xGL2u1upK1kNpqAdoacKcrdPVux+o4kVWeGRBXylxG17X3oJp0it3fSiPKuhcTOSriqFSm81CHqHtmk4fYs48lMLTLz0LrMAYFLJ6aZmFHjCZxm7xXawA78ZaAF3/HFownlRkSN5SjCkWv3gJzx8HWL1CKWuvHNkAnEDvmZgIew0IygmysUnAnWuUa0V9ZzmrEDB84OLVRbRsXpS/AiMlDr2NBcpflaXjKVWwmNwvt/rJbxwAWVuY+sDRdYQhU6E7Tdu6QjcE5EmU+h7YVIClbdHd/6YBaG0NJJkVJ8tTjzANDaicT5Yv5W6tPHPCFWK6nuuKksdCtzYgyKxiL53p+1N1uHFDEXZtKUhintNuMNCvYKZzKSpJO7EgakL3Gx1gylpB2BkKyyvkGyFjWccqhnj4xsixi6MpAGAWANL70Ku2bC7C93dOQnMd052oqKpL1EXRYjXkCIAl6HZ3bCrC++/EsD9QOdkUKSDCwgisFyKSuBzrVZmp6Iz1zTFmAcDDhZIYKr58lYD7thZg6/o8tNZzTLOsau1TTZdpASgWTbE7/YjjRPc8jKnw4xjkRvVBX4lk+6CczEok51gWdkJQTJnLKj1A5/qVGwQ88t083L7Cg8WN9CKV3g/MHPfVdJkWgHw+P16toFAExeCOHh96H8vD679PhKsSvupnTTiACMGAioxR5gkVW2a9RCGy29BdQMLLYdZxUHGuCp8qrG9St61LzQBks1n6FG3a5Vbz3Dj672OP5CAzzuDt1+PgT6p6vqyWDyoAsNKdncuFVjywMoEslxHQhtsE7LzXgySlA832tSQ80oF0idwNXrp06Sqim+EzsCsp0ZTi8NQTk/DUvhwsXqU6P7lg4YeFD9XutJAhGxoNSiDC9UQDmFkNkctfnlr0oF5iz6MFWLvSr/oq7OsvbhzykAzpEvn1OLpPvre394l4PL4EUZzyYwTzm6PEMRbXdHlwxz0eNC1jWKNz+Y5fpkL0szqs+lo71bcARJYlUmRhW2s8oZQFdEt9X28Rnv7hJDQkua41yj/SsLf2SCQSFP+nnn322V+fPXvWi/yFyODg4CttbW3PZDKZmmsDD9vAPCbo0SyDoTSHsTGOnSGD+roAUqkA/viHFBx6NQbehOoNqJhy7MUUrTzleAcZf+f3PHj6ySx0tDDJ9lFGY2MjfeXym/b29n2zKoTOnTv3RnNz848wDJxa3hKTdeIul1VbyhWwpDFA9/atz1kAntk7ARs2JuDtPyXg/En16Qwdd0z7izNKNAJ0rw/gwd487LwnDy2p6MpT6KL1fdKh6pyrnVy1alXyxIkTbyIID9fqBTMNH02bRy+5kWFw6mwMTp9yYeCqIxc7k2jxJct8WNvjQc9qSnUIBrK940Qvccn6Y2NjhzZv3vzo+fPnc7MCgMbhw4fv37Vr10FEs87zvDkBQWggish+nhS1gELrBjEpDEtbVlOOn+bbBnolnu3r6+vds2fP+7P2APM3p0+f/tnatWtfmMCWLNLnMjXyhjCo2KtFsxzE/PX19XDmzJnnenp6XpwpW9b6qOSFCxdeWLFixU9yuRzMlSfM9SDLJ5NJSuEvdXV1PYeHcjNat9ZFIJRUf3//T7u7u59D96qfD2+Y7SDCa2hoINKb+Oqrr365bt26l/DwZC21Eo8QtpPr169/8eDBg4+PjIy8i2gHSI70LaH8GotY/lb8dwHzHHomPZvmgLVKQHN66623Hkflf1Wr8lE8oPKa5gMHDuzauHHjoziBezHuVqIVGnFSjGKw1hXZaFwhdBbxydL0mXwG9y+m0+mjJ0+efBOLNvqiNR1tUXz2/2PEXBfDVNm6d+/eZegdHS0tLW1YfTWgRRL0hSkKnyPl6T8F+IVCIU+NDVp7CMPx6v79+69gihsG9X4Voip/MwDMdI/5igVR47GFsTAWxsJYGLWM/wAUZOkdnTv2tgAAAABJRU5ErkJggg==' };
  function iconOf(k) { return icons[k] || MARKS[k]; }
  function App(k, c) {
    if (iconOf(k)) return '<img class="' + (c || 'size-5') + ' flex-none ' + (c === 'size-[34px]' ? 'rounded-[8px]' : 'rounded-[5px]') + '" src="' + iconOf(k) + '" alt="">';
    /* stand-ins for the design page; the app has the real icons. pi has no app, and OpenCode's app is optional: both draw
       their own published marks (pi.dev's logo, opencode.ai's), not ours. */
    var g = {
      claude: ['#D97757', '<g stroke="#fff" stroke-width="1.7" stroke-linecap="round"><path d="M12 5.5v13"/><path d="M5.5 12h13"/><path d="M7.4 7.4l9.2 9.2"/><path d="M16.6 7.4l-9.2 9.2"/></g>'],
      opencode: ['#131010', '<path d="M9 10.5h6v6H9z" fill="#5A5858"/><path fill-rule="evenodd" d="M18 19.5H6v-15h12zM15 7.5H9v9h6z" fill="#fff"/>'],
      pi: ['#18181B', '<g transform="translate(.07 .07) scale(.02982)"><path fill="#F09082" d="M165.29 165.29H517.36V400H400V282.65H165.29Z"/><path fill="#4D9ABF" d="M165.29 282.65H282.65V400H400V517.36H282.65V634.72H165.29Z"/><path fill="#F1BE58" d="M517.36 400H634.72V634.72H517.36Z"/></g>']
    }[k] || ['#52525B', ''];
    return '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="' + g[0] + '"/>' + g[1] + '</svg>';
  }
  /* A terminal session: the icon says where Pick up takes you, so it is the terminal's, with the agent (Claude, Codex,
     OpenCode, pi) as a small badge on its corner. A session in the Claude or Codex app keeps that app's icon. In herdr,
     the terminal is the one showing herdr. */
  var TERMS = { terminal: 'Terminal', iterm: 'iTerm2', ghostty: 'Ghostty', cmux: 'cmux', warp: 'Warp', kitty: 'kitty', wezterm: 'WezTerm', vscode: 'VS Code', cursor: 'Cursor', zed: 'Zed', conductor: 'Conductor' };
  function AppOf(p, c) {
    /* a session Conductor runs wears Conductor's icon the way a terminal session wears its terminal's; Reply still goes through the card (no `via`) */
    var host = p.via || p.opens;
    if (!host) return App(p.app, c);
    var small = c === 'size-3.5', tile = c === 'size-[34px]', b = small ? 'size-2 -bottom-[2px] -right-[3px]' : tile ? 'size-[17px] -bottom-[3px] -right-[4px]' : 'size-[11px] -bottom-[3px] -right-[3px]';
    var term = icons[host] ? '<img class="' + (c || 'size-5') + ' flex-none ' + (tile ? 'rounded-[8px]' : 'rounded-[5px]') + '" src="' + icons[host] + '" alt="">'
      : '<svg class="' + (c || 'size-5') + ' flex-none" viewBox="0 0 24 24" aria-hidden="true"><rect width="24" height="24" rx="6" fill="#27272A"/><path d="M7 8l4 4-4 4M12.5 16.5h5" stroke="#E4E4E7" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    return '<span class="relative flex flex-none" title="' + agentName(p.app) + ' in ' + (p.host === 'herdr' ? 'herdr, in ' : '') + esc(TERMS[host] || 'a terminal') + '">' + term +
      /* a real app icon has a clear margin around its rounded square (Apple's icon grid): in a badge it is scaled past it, so
         the ring sits on the icon's own edge instead of leaving a dark band between them */
      '<span class="absolute ' + b + ' flex overflow-hidden ' + (tile ? 'rounded-[5px] ring-2' : 'rounded-[3px] ring-[1.5px]') + ' ring-black">' + App(p.app, iconOf(p.app) ? 'size-full scale-[1.24]' : 'size-full') + '</span></span>';
  }
  /* where the main button takes you, by name: "Open Claude", "Open Ghostty" */
  function goLabel(p) { return 'Open ' + (p && (p.via || p.opens) ? TERMS[p.via || p.opens] || 'Terminal' : agentShort(p && (p.app || (p.status && p.status.app)))); }
  /* The arc turns inside its own drawing, around its own centre (12, 12). Turning the whole icon with CSS made it wobble
     wherever it sat on a fraction of a pixel (beside a project name of any width): it circled a centre a little off its own. */
  var STILL = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
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
  function Phrase(ph) { return (ph.spin ? Spinner('size-3', glow(COLORS.running)) : '') + '<span class="' + (ph.c ? '' : 'text-muted-foreground') + '"' + (ph.c ? ' style="color:' + ph.c + '"' : '') + '>' + esc(ph.t) + '</span>'; }
  var ENTER = svg('enter', 'size-2');
  /* a footer action: `act` is what it does, `key` its shortcut */
  function Act(v, label, key, act) { return Button(v, label, key ? Kbd(key, v === 'default') : '', (v === 'default' ? 'pr-0.5' : '') + '" data-act="' + act); }
  /* On a card you opened, Up and Down flip to the next session's card; it says so, since nothing else would tell you.
     The card Perch opened by itself offers Not now there instead (N snoozes either way). */
  function Flip() {
    if (snap && snap.proactive) return Act('ghost', 'Not now', 'N', 'snooze');
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
    '<div class="inner pt-8 pb-1.5">' +
      /* the chat's title is the heading, the whole line its own; its status, in words, ends the grey line under it */
      /* the app's icon at full size, like a notification, beside two lines: the title, the whole line its own, and in grey
         the project and what you were doing with the status at its right. Then, apart, what happened; then Next. Read top
         to bottom in a glance. */
      '<div class="rv mt-1.5 flex items-center gap-[11px] px-4" style="--i:1"><span class="o-app flex flex-none"></span><div class="flex min-w-0 flex-1 flex-col gap-px">' +
        '<span dir="auto" class="o-name min-w-0 truncate text-left text-sm font-semibold leading-[19px] tracking-[-0.02em]"></span>' +
        '<div class="flex min-w-0 items-baseline gap-2"><p dir="auto" class="o-sub min-w-0 flex-1 truncate text-left text-[13px] leading-[18px] text-muted-foreground"></p><span class="o-st ml-auto flex flex-none items-center gap-1.5 text-xs"></span></div></div></div>' +
      '<p dir="auto" class="o-h rv mt-2.5 px-4 text-[13px] leading-[18px]" style="--i:2"></p>' +
      '<p dir="auto" class="o-c rv mt-0.5 px-4 text-[13px] leading-[18px] text-muted-foreground line-clamp-2" style="--i:2"></p>' +
      '<div class="o-ask rv px-4" style="--i:3"></div>' +
      /* while you reply: what the agent actually said, in place of the summary, so you answer what you read */
      '<div class="o-said rv mt-2.5 px-4" style="--i:2"><div class="o-said-in max-h-[150px] overflow-y-auto rounded-lg bg-black/[0.18] px-3 py-1.5 text-[13px] leading-[19px] text-foreground/90"></div></div>' +
      '<p class="o-nx rv mt-2.5 flex items-baseline gap-2 px-4 text-[13px] leading-[18px]" style="--i:3"><span class="o-nl font-medium text-muted-foreground">Next</span><span class="o-orb -my-px hidden flex-none self-center"><svg></svg></span><span dir="auto" class="o-x min-w-0 flex-1 text-foreground line-clamp-2"></span></p>' +
      '<div class="rv relative mt-2 h-9 px-2.5" style="--i:4"><div class="f-main flex h-9 items-center gap-0.5">' + Button('ghost', 'All sessions', Kbd('\u2190'), 'x-list pl-1.5') + '<span class="flex-1"></span><span class="o-acts flex items-center gap-0.5"></span></div>' +
      '<div class="f-rep hidden h-9 items-center gap-1.5"><button aria-label="Close reply" title="Close (Esc)" class="x-rclose flex h-7 flex-none cursor-pointer items-center rounded-md px-0.5 opacity-75 transition-opacity hover:opacity-100">' + Kbd('esc') + '</button><input class="r-in h-7 min-w-0 flex-1 rounded-lg bg-white/[0.1] px-2.5 text-[13px] text-foreground caret-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none transition-[background-color,box-shadow] duration-200 placeholder:text-white/35 focus:bg-white/[0.13] focus:shadow-[inset_0_0_0_1px_rgba(255,255,255,0.2)]" placeholder="Reply to Claude\u2026" spellcheck="false" autocomplete="off" aria-label="Reply">' + Button('default', '<span class="x-send-l">Send</span>', Kbd(svg('enter', 'size-2'), 1), 'x-send h-7 rounded-lg pr-1') + '</div>' +
      '<div class="f-snz hidden h-9 items-center gap-1"><span class="pl-1.5 text-[13px] text-muted-foreground">Remind me in</span><span class="flex-1"></span>' + Button('ghost', '30 min', Kbd('1'), 'x-s1') + Button('ghost', '2 hours', Kbd('2'), 'x-s2') + Button('ghost', 'Tomorrow', Kbd('3'), 'x-s3') + '</div></div>' +
    '</div></div>' +
    /* Settings is Command+comma, here and on the card: in the list, letters type into the filter */
    '<div class="pane p-switch">' + '<button aria-label="Settings" title="Settings (\u2318,)" class="x-gear rv absolute right-[30px] top-[7px] z-10 flex h-[18px] cursor-pointer items-center gap-1 rounded-md pl-[3px] pr-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('gear', 'size-3') + Kbd('\u2318,') + '</button>' +
    '<button class="upd-chip rv absolute left-[44px] top-[7px] z-10 hidden h-[18px] cursor-pointer items-center gap-1 rounded-md px-1.5 text-[11px] font-medium transition-colors" style="--i:0"></button>' +
    '<button aria-label="Dismiss" title="Dismiss (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8">' +
      header('<div class="s-h truncate text-sm font-medium leading-4">Jump back in</div>', '<span class="s-n flex-none text-xs text-muted-foreground">Type to filter</span>') +
      '<div class="rv relative" style="--i:1"><div class="s-l max-h-[196px] overflow-y-auto px-1.5 pb-1"></div><div class="s-bar"><i></i></div></div>' +
      '<div class="rv s-ft flex h-8 items-center justify-center gap-3.5 text-xs text-muted-foreground" style="--i:3"><span class="flex items-baseline gap-1.5">' + Keys('\u2191', '\u2193') + 'Choose</span><button class="x-back flex cursor-pointer items-baseline gap-1.5 rounded-md px-1 text-muted-foreground transition-colors hover:text-foreground">' + Kbd('\u2192') + 'Details</button><span class="flex items-baseline gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Open</span><span class="flex items-baseline gap-1.5">' + Kbd('esc') + 'Close</span></div>' +
    '</div></div>' +
    '<div class="pane p-onb">' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-1.5"><div class="onb"></div></div></div>' +
    '<div class="pane p-set">' + '<span class="rv absolute left-11 top-[7px] z-10 flex h-[18px] items-center text-[13px] font-medium tracking-[-0.01em]" style="--i:0">Settings</span>' + '<span class="s-ver rv absolute right-[36px] top-[7px] z-10 flex h-[18px] items-center text-[11px] tabular-nums text-muted-foreground/60" style="--i:0"></span>' + '<button aria-label="Close" title="Close (Esc)" class="x-close rv absolute right-2.5 top-[7px] z-10 grid size-[18px] cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground" style="--i:0">' + svg('x', 'size-3') + '</button>' +
    '<div class="inner pt-8 pb-1.5"><div class="set"></div></div></div>' +
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
        return '<li class="flex gap-2"' + (it.lvl ? ' style="margin-left:' + it.lvl * 16 + 'px"' : '') + '><span class="flex-none text-muted-foreground' + (it.num ? ' min-w-[1.1em] text-right tabular-nums' : '') + '">' + it.mark + '</span><span dir="auto" class="min-w-0">' + it.text.split('\n').map(function (l) { return md(l); }).join('<br>') + '</span></li>';
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
    return '<div class="md-tbl -mx-3 my-1.5 px-1"><table><thead><tr>' + head.map(function (h, j) { return cell('th', h, j); }).join('') + '</tr></thead><tbody>' +
      body.map(function (r) { return '<tr>' + r.map(function (v, j) { return cell('td', v, j); }).join('') + '</tr>'; }).join('') + '</tbody></table></div>';
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
    else if (a === 'snooze') snoozeMenu(true);
    else if (a === 'allow' || a === 'deny') post({ type: 'answer', choice: a });
    else if (a === 'pick') askKey(String(+b.dataset.i + 1));
    else if (a === 'qback') askKey('back');
    else if (a === 'qnext') askKey('next');
    else if (a === 'flip') post({ type: 'flip' });
    else if (a === 'live') { liveNext = true; post({ type: 'settings' }); }   /* the reason line's Settings: opens it with Live status chosen */
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
  /* the notch's clip never scrolls, whatever asks it to (focus, scrollIntoView): its content only ever grows into place */
  if (window.webkit && window.webkit.messageHandlers) window.addEventListener('scroll', function () { if (window.scrollX || window.scrollY) window.scrollTo(0, 0); });
  n.querySelector('.clip').addEventListener('scroll', function (e) { if (e.target.scrollTop || e.target.scrollLeft) { e.target.scrollTop = 0; e.target.scrollLeft = 0; } });
  /* the session the open reply is for; what you type there is kept as its draft (Swift holds them, snap.drafts) */
  var replyFor = '';
  function replyMenu(open, quiet) {
    footer(open ? fRep : fMain);
    showSaid(open);
    var p = snap && snap.projects[snap.selected];
    /* the words you left in this session's reply are still there, the caret after them */
    if (open && p && p.id !== replyFor) { replyFor = p.id; rIn.value = (snap.drafts && snap.drafts[p.id]) || ''; }
    /* focus without scrolling: the card is still growing, and a scroll to the field would shove the whole notch up */
    if (open) setTimeout(function () { caretAt(rIn.value.length); }, 30); else { replyFor = ''; rIn.value = ''; rIn.blur(); }
    if (!quiet) post({ type: 'replyMenu', open: open });
  }
  rIn.addEventListener('input', function () { if (replyFor) post({ type: 'draft', id: replyFor, text: rIn.value }); });
  /* files dropped on the card or pasted from Finder: their paths go in where the caret is, opening the reply if need be */
  function addPaths(list) {
    if (lastSt !== 'open' || !list || !list.length) return;
    if (dropping) dropped();
    if (fRep.style.display !== 'flex') { if (!q('.o-acts [data-act=reply]')) return; replyMenu(true); }
    var v = rIn.value, a = document.activeElement === rIn ? rIn.selectionStart : v.length, b = document.activeElement === rIn ? rIn.selectionEnd : v.length;
    var t = list.join(' ');
    if (a > 0 && !/\s/.test(v.charAt(a - 1))) t = ' ' + t;
    if (b < v.length && !/\s/.test(v.charAt(b))) t += ' ';
    rIn.value = v.slice(0, a) + t + v.slice(b);
    rIn.dispatchEvent(new Event('input'));
    var e = a + t.length; setTimeout(function () { caretAt(e); }, 40);
  }
  /* Files dragged over the card (n of them; 0 when the drag goes away), the pointer at x, y in the page. The reply opens for them if
     it was closed, and closes again if they go elsewhere; its field lights up and says what a drop does, and more so with
     the file right on it; the character looks on wide-eyed, its eyes on the file as it moves. Dropped, it squints happily
     and hops. */
  var dropping = 0, dropOpened = false;
  function dragOver(n, x, y) {
    if (lastSt !== 'open') return;
    if (n && !dropping) {
      if (fRep.style.display !== 'flex') { if (!q('.o-acts [data-act=reply]')) return; replyMenu(true, true); dropOpened = true; }
      cr.dataset.m = 'alert'; lookAt(rIn, 60);
    }
    var was = dropping; dropping = n;
    var r = rIn.getBoundingClientRect();
    var on = !!n && x != null && x >= r.left - 8 && x <= r.right + 8 && y >= r.top - 8 && y <= r.bottom + 8;
    rIn.classList.toggle('drop', !!n); rIn.classList.toggle('on', on);
    rIn.placeholder = !n ? replyHint() : (on ? 'Release to add ' : 'Drop to add ') + (n > 1 ? 'their paths' : 'its path');
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
  function replyHint() { var p = snap && snap.projects[snap.selected]; return p ? 'Reply to ' + agentShort(p.app || p.status.app) + '\u2026' : ''; }
  /* focus the field with the caret at i, the words scrolled so it shows */
  function caretAt(i) {
    rIn.focus({ preventScroll: true }); rIn.setSelectionRange(i, i);
    if (i >= rIn.value.length) rIn.scrollLeft = rIn.scrollWidth;
  }
  /* replying: the card shows the agent's own last message instead of the summary, and grows or shrinks to fit */
  function showSaid(open) {
    var pane = q('.p-open'), p = snap && snap.projects[snap.selected], on = !!(open && p && p.said);
    if ((pane.dataset.rep === '1') === on) return;
    pane.dataset.rep = on ? '1' : '';
    /* a long one opens at its end, where the question usually is, with a soft edge saying there is more above */
    if (on) { var box = q('.o-said-in'); box.innerHTML = (p.asked ? '<div dir="auto" class="o-you">' + esc(p.asked) + '</div>' : '') + mdBlock(p.said); box.classList.toggle('ov', box.scrollHeight > box.clientHeight + 1); fitLastTable(box); box.scrollTop = box.scrollHeight; box.querySelectorAll('.md-tbl').forEach(tblEdge); }
    if (snap && lastSt === 'open') layout('open', snap);
    if (on && !(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches))
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
      if (f) w.dataset.f = f; else delete w.dataset.f;
    };
    set(); w.onscroll = set;
  }
  function sendReply() {
    var t = rIn.value.trim(); if (!t) return;
    var p = snap && snap.projects[snap.selected];
    /* a terminal session takes it right here: the card clears and the words go off into the notch */
    if (p && p.via && sendFly(t)) { post({ type: 'reply', text: t, close: SEND_CLOSE }); return; }
    /* without Accessibility Perch asks for it first; your words stay here and go out once it is on */
    if (snap.canSend === false && !(p && p.via)) { if (!snap.allowing) post({ type: 'reply', text: t }); rIn.focus({ preventScroll: true }); return; }
    replyMenu(false, true); post({ type: 'reply', text: t });
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
  function saidScroll(d) {
    var el = saidTarget(q('.o-said-in'), d);
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
    if (e.key === 'Enter') { e.preventDefault(); sendReply(); }
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
  scene.querySelectorAll('.x-close').forEach(function (b) { b.onclick = function () { post({ type: 'dismiss' }); }; });

  /* ---- render ---- */
  var last = { phase: null, token: null };
  var snap = null;

  /* Questions, one at a time: a number answers and moves on, Back returns, the last one sends them all together. */
  var asking = { key: '', step: 0, picks: [], p: null };
  function questionCard(p, a) {
    var key = p.id + '|' + a.subject + '|' + a.questions.length;
    if (asking.key !== key) asking = { key: key, step: 0, picks: a.questions.map(function () { return []; }), p: p };
    asking.p = p;
    var n = a.questions.length, qn = a.questions[asking.step], picks = asking.picks[asking.step];
    status(Phrase({ t: n > 1 ? 'Question ' + (asking.step + 1) + ' of ' + n : 'Asked you something', c: COLORS.attention }));
    var h = q('.o-h'); h.innerHTML = esc(qn.text) + (qn.multi ? ' <span class="text-muted-foreground">Choose any</span>' : ''); h.title = qn.text; h.classList.add('line-clamp-2');
    h.style.marginTop = '6px';   /* the tallest card there is: every point goes to the choices */
    var c = q('.o-c'); c.textContent = ''; c.style.display = 'none';
    q('.o-ask').innerHTML = '<div class="-mx-2 mt-1.5 flex flex-col">' + qn.options.map(function (o, i) {
      var on = picks.indexOf(o) >= 0, rec = /\s*\(recommended\)\s*$/i, label = o.replace(rec, ''), note = qn.notes[i] || '';
      return '<button data-act="pick" data-i="' + i + '" class="flex w-full cursor-pointer items-start gap-2.5 rounded-lg px-2 py-[3px] text-left transition-colors ' + (on ? 'bg-white/[0.1]' : 'hover:bg-white/[0.06]') + '">' +
        Kbd(String(i + 1)) + '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">' + esc(label) + (rec.test(o) ? '<span class="ml-1.5 text-xs text-muted-foreground">Recommended</span>' : '') + '</span>' +
        (note ? '<span class="block truncate text-[11.5px] leading-[14px] text-muted-foreground">' + esc(note) + '</span>' : '') + '</span>' +
        (qn.multi ? '<span class="flex-none self-center ' + (on ? 'text-[#8CCFA4]' : 'text-transparent') + '">' + svg('check', 'size-3') + '</span>' : '') + '</button>';
    }).join('') + '</div>';
    q('.o-nx').style.display = 'none';
    var last = asking.step === n - 1, ready = qn.multi && picks.length;
    q('.o-acts').innerHTML = (asking.step ? Act('ghost', 'Back', '\u2190', 'qback') : Flip()) +
      (ready ? Act('default', last ? 'Send' : 'Next', ENTER, 'qnext') : Act(asking.step ? 'ghost' : 'default', goLabel(p), ENTER, 'go'));
  }
  /* A question Perch cannot answer (no hooks, or read from the transcript): its first question and its choices, to read.
     Nothing on it is pressable: a message sent while a question is open dismisses it, so the only way on is the app itself. */
  function readQuestion(p, a) {
    var n = a.questions.length, qn = a.questions[0];
    status(Phrase({ t: n > 1 ? 'Question 1 of ' + n : 'Asked you something', c: COLORS.attention }));
    var h = q('.o-h'); h.innerHTML = esc(qn.text) + (qn.multi ? ' <span class="text-muted-foreground">Choose any</span>' : ''); h.title = qn.text; h.classList.add('line-clamp-2');
    h.style.marginTop = '6px';
    var c = q('.o-c'); c.textContent = ''; c.style.display = 'none';
    /* four choices with their notes and the reason would not fit the panel: past three, the labels alone */
    var terse = qn.options.length > 3;
    q('.o-ask').innerHTML = '<div class="-mx-2 mt-1.5 flex flex-col">' + qn.options.map(function (o, i) {
      var rec = /\s*\(recommended\)\s*$/i, label = o.replace(rec, ''), note = terse ? '' : qn.notes[i] || '';
      return '<div class="flex w-full items-start gap-2.5 px-2 py-[3px]"><span class="grid size-4 flex-none place-items-center"><span class="size-1.5 rounded-full bg-white/25"></span></span>' +
        '<span class="min-w-0 flex-1"><span class="block truncate text-[13px] leading-4">' + esc(label) + (rec.test(o) ? '<span class="ml-1.5 text-xs text-muted-foreground">Recommended</span>' : '') + '</span>' +
        (note ? '<span class="block truncate text-[11.5px] leading-[14px] text-muted-foreground">' + esc(note) + '</span>' : '') + '</span></div>';
    }).join('') + '</div>' + (a.why ? '<div class="mt-3 text-[11px] leading-[14px] text-muted-foreground/70">' + esc(a.why).replace('Settings', '<span data-act="live" role="link" class="cursor-pointer underline underline-offset-2 hover:text-foreground">Settings</span>') + '</div>' : '');
    q('.o-nx').style.display = 'none';
    q('.o-acts').innerHTML = Flip() + Act('default', goLabel(p), ENTER, 'go');
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

  /* The card's edge springs to a new height (input.css, .n), but the words inside reflow at once, so what sits below
     them would jump. Each block glides from where it was on the same spring instead; on another session's card the new
     words also settle in. */
  var cardId = null, iconKey = '';
  function settleCard(change, fresh) {
    var els = [].slice.call(q('.p-open').querySelectorAll('.rv')), was = els.map(function (el) { return el.offsetParent ? el.getBoundingClientRect().top : null; });
    var said = els.map(function (el) { return el.textContent; }), icon = q('.o-app'), iconWas = iconKey;
    change();
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    els.forEach(function (el, i) {
      if (!el.offsetParent) return;
      var dy = was[i] == null ? 0 : was[i] - el.getBoundingClientRect().top;
      if (Math.abs(dy) > .5) el.animate([{ transform: 'translateY(' + dy + 'px)' }, { transform: 'none' }], { duration: 600, delay: 50, easing: 'cubic-bezier(.3,1.5,.45,1)', fill: 'backwards' });
      /* only words that changed settle in; the buttons and the corner icons stay put */
      /* the app icon stays as it is when the next session is in the same app: only the words beside it settle in */
      var tgt = el.contains(icon) && iconKey === iconWas ? icon.nextElementSibling : el;
      if (fresh && !el.querySelector('.f-main') && el.textContent !== said[i]) tgt.animate([{ opacity: 0, filter: 'blur(2px)' }, { opacity: 1, filter: 'none' }], { duration: 280, delay: i * 30, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
    });
  }

  /* the card's status; drawn again only when it changes, so its spinner keeps turning */
  function status(html, title) {
    var st = q('.o-st'); if (st.dataset.h !== html) { st.innerHTML = html; st.dataset.h = html; } st.title = title || '';
  }
  function fill(p) {
    var a = p.ask, ph = phrase(p), h = q('.o-h'), c = q('.o-c'), box = q('.o-ask');
    /* drawn again only when it changes: a new image blinks while it decodes */
    var ik = p.app + '|' + (p.via || p.opens || '') + '|' + !!icons[p.via || p.opens || p.app];
    if (ik !== iconKey) { q('.o-app').innerHTML = AppOf(p, 'size-[34px]'); iconKey = ik; }
    /* a chat started without a project is named by its title alone */
    q('.o-name').textContent = p.topic || p.name; q('.o-name').title = p.topic || p.name;
    status(Phrase(ph), p.status.text);
    h.classList.remove('line-clamp-2'); h.title = ''; h.style.display = ''; h.style.marginTop = '';
    /* the grey line: the project, then (on a plain card) what you were doing */
    var sub = q('.o-sub'), proj = p.topic ? '<span class="text-foreground/70">' + esc(p.name) + '</span>' : '';
    sub.innerHTML = proj; sub.title = p.topic ? p.name : ''; sub.style.display = proj ? '' : 'none';
    if (a && a.kind === 'question' && a.answerable && a.questions && a.questions.length) { questionCard(p, a); return; }
    if (a && a.kind === 'question' && a.questions && a.questions.length && a.questions[0].options.length) { readQuestion(p, a); return; }
    if (a) {
      /* what the agent is asking, and the means to answer it right here */
      h.textContent = a.kind === 'question' ? a.subject : a.title;
      c.textContent = a.kind === 'plan' ? a.subject : '';
      box.innerHTML = a.kind === 'permission' && a.subject
        ? '<div dir="auto" class="mt-2 line-clamp-2 break-all rounded-md bg-white/[0.07] px-2.5 py-1.5 font-mono text-xs leading-[18px] text-foreground/90">' + esc(a.subject) + '</div>'
        : '';
    } else {
      /* "You were creating a database." becomes the grey line under the title, "Creating a database"; a headline that only
         repeats the title is left out. What happened is the body, in white, two lines at most. */
      var norm = function (t) { return String(t || '').replace(/[.\u2026\s]+$/, '').toLowerCase().slice(0, 60); };
      var was = String(p.headline || '').replace(/^\s*you were\s+/i, '').replace(/[.\s]+$/, '');
      var did = String(p.context || '').replace(/^\s*the assistant\s+/i, '');
      var said = !(p.topic && norm(p.headline) === norm(p.topic)) && was;
      if (said) { sub.innerHTML = proj + (proj ? ' \u00b7 ' : '') + esc(was.charAt(0).toUpperCase() + was.slice(1)); sub.title = (p.topic ? p.name + ': ' : '') + p.headline; sub.style.display = ''; }
      if (did) { h.innerHTML = md(did.charAt(0).toUpperCase() + did.slice(1)); h.classList.add('line-clamp-2'); }
      else h.innerHTML = said ? '' : md(p.headline);
      c.innerHTML = ''; box.innerHTML = '';
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
    q('.o-x').classList.toggle('truncate', !!now);   /* the step changes every few seconds: one line, never a jump in height */
    q('.o-x').classList.toggle('shimmer', !!now);    /* grey with a passing light: it is happening, not yours to do */
    q('.o-x').classList.toggle('line-clamp-2', !now);   /* the step is one line; the next step may take two */
    q('.o-x').innerHTML = md(nx) + (now ? '<span class="shine" aria-hidden="true">' + md(nx) + '</span>' : '');   /* the light's copy of the words, markup and all */
    q('.o-nx').style.display = nx ? '' : 'none';
    q('.o-acts').innerHTML = a && a.answerable && a.kind === 'permission' ? Act('ghost', 'Deny', 'D', 'deny') + Act('ghost', goLabel(p), ENTER, 'go') + Act('default', 'Allow', 'A', 'allow')
      : a ? Flip() + Act('default', goLabel(p), ENTER, 'go')
      : Act('ghost', 'Reply', 'R', 'reply') + Flip() + Act('default', goLabel(p), ENTER, 'go');
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
  function list(s) {
    var empty = !s.projects.length, typed = s.query || '', rows = s.shown || s.projects.map(function (p, k) { return k; });
    q('.s-ft').style.display = empty ? 'none' : '';
    /* what you typed replaces the title, with a caret; the right side counts what is left */
    q('.s-h').innerHTML = typed ? '<span dir="auto">' + esc(typed) + '</span><i class="s-caret"></i>' : 'Jump back in';
    var reading = switchFx === 'watch' && typed !== fxTyped && !!typed; fxTyped = typed;
    if (reading) { var caret = q('.s-h .s-caret'); if (caret) setTimeout(function () { lookAt(caret, 0); }, 0); }
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
          : '<span class="text-foreground">Nothing to pick up yet</span><span class="text-muted-foreground">Sessions from your agents in the last two weeks show up here.</span>') + '</div>';
      edges(); return;
    }
    /* Rows are drawn again only when they change, so a row that is reading itself out is not cut short. Swift sends them
       in order, by section (what needs you, today, earlier), and a small header starts each. A row leads with the
       session's title and how long ago; at the right, its mark (rowMark) and its project in grey. */
    var sec = '';
    var html = rows.map(function (k) {
      var p = s.projects[k], first = p.topic || p.name, second = p.topic ? p.name : '', name = sectionOf(p), head = '';
      if (name !== sec) { head = '<div class="s-sec' + (sec ? '' : ' first') + '">' + esc(name) + '</div>'; sec = name; }
      return head + '<div class="row flex h-9 cursor-pointer items-center gap-2 rounded-md px-1.5 text-sm transition-colors" data-i="' + k + '">' +
        AppOf(p) +
        /* title and project each truncate on their own, so a Hebrew title loses its end, not its start */
        '<span class="flex min-w-0 flex-1 items-center gap-2"><span dir="auto" class="mq nm min-w-0 truncate text-left font-medium"><span class="mq-in">' + esc(first) + '</span></span>' +
        '<span class="tm flex-none text-xs tabular-nums text-muted-foreground"></span></span>' +
        '<span class="flex min-w-0 max-w-[38%] flex-none items-center justify-end gap-2"><span class="rk grid size-4 flex-none place-items-center"></span>' +
        (second ? '<span dir="auto" class="mq tp min-w-0 truncate text-xs text-muted-foreground"><span class="mq-in">' + esc(second) + '</span></span>' : '') + '</span></div>';
    }).join('');
    if (html !== listSig) {
      listSig = html; hovered = null; lastSel = -1; marquee(null); sl.innerHTML = html; keyPtr = ptrAt.slice();   /* redrawn rows under a still pointer are not a choice */
      /* a row shows that session's card in the notch; Return (or the card's Open) opens it */
      sl.querySelectorAll('.row').forEach(function (r) {
        r.onclick = function () { post({ type: 'details', index: +r.dataset.i }); };
        r.ondblclick = function () { post({ type: 'choose', index: +r.dataset.i }); };
        r.onmouseenter = function () {
          hovered = r; marquee(r);
          var i = +r.dataset.i;
          if (!ptrMoved()) return;
          listKb = false; markList();
          if (i === (pend >= 0 ? pend : lastSel)) return;
          pend = ptrPick = i; clearTimeout(pendT); pendT = setTimeout(function () { pend = -1; }, 800);
          sl.querySelectorAll('.row').forEach(function (x) { x.classList.toggle('bg-accent', x === r); });
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
      if (tm.textContent !== t) tm.textContent = t;
      if (rk.dataset.m !== m) { rk.innerHTML = m; rk.dataset.m = m; }   /* not innerHTML: its copy never reads back the same, and a redrawn spinner restarts its turn */
    });
    /* the chosen row stays in view, clear of the edge fades, as the arrows move past the fifth */
    if (sel && cs !== ptrPick) {
      var top = sel.offsetParent === sl ? sel.offsetTop : sel.offsetTop - sl.offsetTop, pad = 20;
      if (top - pad < sl.scrollTop) sl.scrollTop = top - pad;
      else if (top + sel.offsetHeight > sl.scrollTop + sl.clientHeight - pad) sl.scrollTop = top + sel.offsetHeight - sl.clientHeight + pad;
    }
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
  function layout(st, s) {
    /* No hardware notch (an external display): nothing is drawn at rest. The live activity and the card grow from the top centre; the box keeps a size to grow from. */
    var scr = s.screen, virt = !scr.hasNotch, idleW = virt ? 148 : scr.notchW, idleH = virt ? Math.min(scr.notchH || 24, 28) : scr.notchH;
    var w = st === 'idle' ? idleW : CARD_W, h = idleH;
    if (st !== 'idle') { var pane = q('.p-' + st); h = pane.querySelector('.inner').offsetHeight; }
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
    cr.style.opacity = (st === 'idle' && !news && !hello) || choosing ? 0 : 1;
    cr.dataset.news = news ? '1' : '';
    /* its face says how things are: wide-eyed when something needs you, happy when something finished */
    var cp = st === 'open' || (st === 'switch' && switchFx === 'watch') ? s.projects[s.selected] : null;
    if (!celebrating && !hello && !dropping) cr.dataset.m = st === 'idle' ? (news ? 'alert' : 'sleep')
      : st === 'new' ? 'happy' : (cp && cp.status.kind === 'attention' ? 'alert' : (cp && cp.status.kind === 'done' && cp.fresh ? 'happy' : 'awake'));
    post({ type: 'size', width: w, height: h });
    /* Swift needs the shape to let clicks through to it, and the keys to listen for while it shows */
    var mode = st === 'idle' ? act.mode : '', keys = !mode || mode === 'sent' || (act.p && act.p.update) ? [] : mode === 'full' ? act.keys : act.keys.filter(function (k) { return k !== 'reply'; });   /* an update has buttons for the mouse only */
    var sig = [mode, w, h, act.p ? act.p.id : '', keys.join()].join('|');
    if (sig !== actSent.sig) { actSent = { sig: sig }; post({ type: 'activity', mode: mode, width: w, height: h, keys: keys }); }
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
  var MARK = {
    done: Ring('done'), ask: Ring('question'), run: Ring('permission'), plan: Ring('plan'), need: Ring('need')
  };
  function actKind(p) {
    if (p.update) return 'update';
    if (p.ask) return { permission: 'run', question: 'ask', plan: 'plan' }[p.ask.kind] || 'need';
    return p.status.kind === 'attention' ? 'need' : 'done';
  }
  function actKey(p) { return p.update ? 'update|' + p.update.version + '|' + p.update.phase + '|' + (p.update.nudge || 0) : p.id + '|' + actKind(p) + '|' + (p.ask ? p.ask.subject : p.status.text); }
  /* what you can do from here, as [action, label, key]; the first one is the main one */
  function actButtons(p, k) {
    var a = p.ask;
    if (k === 'done') return [['pick', goLabel(p), '\u21a9'], ['reply', 'Reply', 'R']];
    if (a && a.answerable && a.kind === 'permission') return [['allow', 'Allow', 'Y'], ['deny', 'Deny', 'N']];
    var qn = a && a.answerable && a.kind === 'question' && a.questions && a.questions.length === 1 && a.questions[0];
    if (qn && !qn.multi && qn.options.length <= 3) return qn.options.map(function (o, i) { return ['pick' + (i + 1), o.replace(/\s*\(recommended\)\s*$/i, ''), String(i + 1), /\(recommended\)\s*$/i.test(o)]; });
    if (a && a.answerable) return [['open', 'Answer', '\u21a9']];
    return [['pick', goLabel(p), '\u21a9']];
  }
  function actWords(p, k) {
    return k === 'done' ? 'Finished' : k === 'run' ? 'Needs your OK' : k === 'ask' ? 'Asked you' : k === 'plan' ? 'Has a plan' : phrase(p, true).t;
  }
  /* Hovering a choice says its title and note below everything else: only what is under the pointer, and nothing that
     is already there moves (the pointer would lose it). */
  function actExtra(p, k) {
    if (!actMore || act.mode !== 'full' || k !== 'ask') return '';
    var qs = p.ask && p.ask.questions && p.ask.questions[0]; if (!qs) return '';
    if (actMore.c != null) {
      var o = qs.options[actMore.c]; if (o == null) return '';
      return '<div class="act-ex"><b>' + esc(o.replace(/\s*\(recommended\)\s*$/i, '')) + (/\(recommended\)\s*$/i.test(o) ? '<i class="act-rec">Recommended</i>' : '') + '</b>' + esc((qs.notes && qs.notes[actMore.c]) || '') + '</div>';
    }
    return '';
  }
  function renderAct() {
    actEl.dataset.mode = act.mode;
    /* what was there stays while it fades; shown again, its names are measured again */
    if (!act.mode) { actGlideFor = ''; return; }
    if (act.mode === 'sent') { renderSent(act.p); actGlide(); return; }
    actEl.classList.remove('chose');
    var p = act.p, k = act.kind, a = p.ask, body = '', bodyCls = '';
    if (act.mode !== 'full' || k !== 'ask') actMore = null;
    if (k === 'update') { renderUpd(p.update); return; }
    if (k === 'run') body = '<span class="act-cmd">' + esc(a.subject || 'a command') + '</span>';
    else if (k === 'ask') { bodyCls = ' askq'; body = '<span dir="auto" class="act-q">' + esc((a.questions && a.questions[0] && a.questions[0].text) || a.subject || 'Asked you something') + '</span>'; }   /* a question is said in full: it wraps */
    else if (k === 'plan' && a.subject) body = '<span dir="auto" class="act-t">' + esc(a.subject) + '</span>';
    var bs = actButtons(p, k);
    act.keys = ['gone'].concat(bs.map(function (b) { return b[0]; }));
    /* the cross to put it away at the left; actions at the right, the main one at the edge. A question's choices keep
       their order, 1 to 3, and shrink to fit; the recommended one, if any, is the bright one. */
    var choices = /^pick\d$/.test(bs[0][0]), list = choices ? bs : bs.slice().reverse();
    /* choices share one Command+Option, said once, so each keeps room for its words */
    /* The short project sits beside the camera; the session's longer title has the row below, before the buttons. A small
       cross at the left of the row puts it away (Command+Option+. does too). A chat with no project is named by its title
       alone, on top. */
    var split = p.topic && p.name !== p.topic;
    var btns = '<button class="act-b act-x" data-a="gone" aria-label="Dismiss" title="Dismiss (\u2318\u2325.)">' + svg('x', 'size-3') + '</button>' +
      (choices ? '<span class="act-mod">' + CMDOPT + '</span>' : split ? '<span dir="auto" class="act-p"><span class="mq-in">' + esc(p.topic) + '</span></span>' : '<span class="act-gap"></span>') +
      list.map(function (b, i) {
        var main = choices ? !!b[3] : i === list.length - 1;
        /* a choice leads with its number, as on the card; an action ends with its keys */
        var label = '<span class="act-bl">' + esc(b[1]) + '</span>', key = '<kbd>' + (choices ? '' : b[0] === 'reply' ? '\u2318' : CMDOPT) + b[2] + '</kbd>';
        return '<button class="act-b' + (main ? ' go' : '') + (choices ? ' ch' : '') + '" data-a="' + b[0] + '" title="' + esc(b[1]) + '">' + (choices ? key + label : label + key) + '</button>';
      }).join('');
    var html = '<span class="act-l">' + AppOf(p, 'size-[15px]') + '<span dir="auto" class="act-n"><span class="mq-in">' + esc(split ? p.name : p.topic || p.name) + '</span></span></span>' +
      '<span class="act-r"><span class="act-s' + (k === 'done' ? ' ok' : '') + '">' + esc(actWords(p, k)) + '</span>' + MARK[k] + '</span>' + actExtra(p, k) +
      (body ? '<div class="act-body' + bodyCls + '">' + body + '</div>' : '') + '<div class="act-btns">' + btns + '</div>';
    /* drawn again only when it changes, so a name gliding along is not cut short by a refresh */
    if (actEl._h !== html) { actEl.innerHTML = html; actEl._h = html; }
    actEl._for = p.id;
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
    var html = '<span class="act-l">' + crHtml('', 15, shapeOf(charNow.shape), ph === 'restarting' ? 'sleep' : 'awake') + '<span class="act-n"><span class="mq-in">Perch ' + esc(u.version) + '</span></span></span>' +
      '<span class="act-r"><span class="act-s ' + (ph === 'updated' || ph === 'current' ? 'ok' : 'mu') + '">' + words + '</span>' + mark + '</span>' + body + (btns ? '<div class="act-btns">' + btns + '</div>' : '');
    var key = html.replace(/stroke-dashoffset="[^"]*"/, '');   /* the ring moves in place, so it eases instead of snapping */
    if (actEl._h !== key) { actEl.innerHTML = html; actEl._h = key; }
    var arc = actEl.querySelector('.upd-arc'); if (arc) arc.style.strokeDashoffset = String(UPD_C * (1 - (u.progress || 0)));
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
    if (act.mode === 'sent') return [Math.ceil(Math.min(460, Math.max(idleW + 2 * side, idleW + 150)) / 2) * 2, idleH];   /* one line: what it was about, and that it went */
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
    bb.style.bottom = ex ? 'auto' : ''; bb.style.top = ex ? (base - 35) + 'px' : '';
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
    error: ['<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>', '#F08A8A']
  };
  function nMark(k) {
    var m = NMARK[k];
    return '<svg class="size-4 flex-none" viewBox="0 0 24 24" fill="none" stroke="' + m[1] + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="' + glow(m[1]) + '" aria-hidden="true">' + m[0] + '</svg>';
  }
  function notifyKind(p) { var k = actKind(p); return actErr(p) ? 'error' : k === 'need' ? 'ask' : k; }   /* a guessed wait, with no request open, is a question */
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
    if (sentNext && Date.now() - sentNext.at < 3000) { var sn = sentNext; sentNext = null; actGone[actKey(sn.p)] = 1; sentBase = known; sentShow(sn.p, sn.words, true, true); return; }
    sentNext = null;
    if (actPressing) return;   /* the choice you pressed is lighting up: the row folds in a moment, nothing else moves it */
    /* Perch's own update: downloading or waiting to restart it is only wings (and gives way to a session that needs you); restarting
       and arriving say their piece in the row */
    var u = s.update, up = u && updP(u), ukey = up && actKey(up);
    /* the timer of the phase before (the offer folding away) must not fold this one */
    if (u && act.p && act.p.update && act.p.update.phase !== u.phase) clearTimeout(actTimer);
    if (up && !s.quiet && !actGone[ukey]) {
      var showing = act.mode === 'full' && act.p && act.p.update && act.p.update.phase === u.phase && (u.phase !== 'failed' || act.p.update.problem === u.problem);   /* a failure that says something else is a new one */
      /* downloading: only the character and the ring. Downloaded: nothing on the notch, it restarts at a quiet moment (the list and Settings have Restart). */
      if (u.phase === 'downloading' && !need.length) { setAct('wings', up, true); return; }
      if (u.phase === 'restarting' || u.phase === 'checking') { clearTimeout(actTimer); setAct('full', up, true); return; }
      if (u.phase === 'available') { setAct('full', up, true); if (!showing && !up.update.notesOpen) actLater(9000); return; }
      /* a small row that says it and goes: updated, up to date, could not check */
      if (u.phase === 'updated' || u.phase === 'current' || u.phase === 'failed') { setAct('full', up, true); if (!showing) actLater(u.phase === 'failed' ? (u.problem ? 9000 : 4500) : 3500); return; }
    }
    if (act.p && act.p.update && !(up && !s.quiet && !actGone[ukey] && u.phase !== 'ready')) { setAct('', null, true); }
    var arrived = known && heard.filter(function (p) { return known.need.indexOf(actKey(p)) < 0; })[0];
    var landed = known && done.filter(function (p) { return known.done.indexOf(p.id) < 0; })[0];
    /* it is saying an answer went: it says it to the end; what arrives meanwhile is said after it (sentDone) */
    if (act.mode === 'sent') return;
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
    if (act.p && (actErr(act.p) || act.p.update)) actGone[actKey(act.p)] = 1;   /* said once */
    var n2 = waiting(snap); setAct(n2.length ? 'wings' : '', n2[0]); }
  function actDo(a) {
    var p = act.p; if (!p || !act.mode || act.keys.indexOf(a) < 0) return;
    if (a === 'gone') {
      if (p.update) { updNotes = false; post({ type: 'update', action: 'later' }); }
      actGone[actKey(p)] = 1; clearTimeout(actTimer);
      if (act.kind === 'done') post({ type: 'activitySeen', id: p.id });
      actSettle(); return;
    }
    if (a === 'notes') { updNotes = !updNotes; clearTimeout(actTimer); if (snap && snap.update) setAct('full', updP(snap.update)); return; }
    if (a === 'reveal' || a === 'retry') { post({ type: 'update', action: a === 'reveal' ? 'reveal' : 'check' }); actGone[actKey(p)] = 1; clearTimeout(actTimer); setAct('', null); return; }
    if (a === 'install') { updNotes = false; post({ type: 'update', action: 'install' }); actGone[actKey(p)] = 1; clearTimeout(actTimer); setAct('', null); return; }
    var m = null;
    if (a === 'allow' || a === 'deny') m = { type: 'activityAnswer', id: p.id, choice: a };
    else if (/^pick\d$/.test(a)) { var qn = p.ask.questions[0], ans = {}; ans[qn.text] = qn.options[+a.slice(4) - 1]; m = { type: 'activityAnswer', id: p.id, answers: ans }; }
    else post({ type: a === 'pick' ? 'activityPick' : 'activityOpen', id: p.id, reply: a === 'reply' });
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
  /* Swift: that answer reached nothing (the request was settled or let go a moment before). The line says so, however far it got. */
  var sentLate = {};
  function notSent(id) {
    sentLate[id] = Date.now();
    if (act.mode === 'sent' && act.p && act.p.id === id && sent && sent.ok) sentShow(act.p, '', false);
  }
  function sentShow(p, words, ok, quiet) {
    if (ok !== false && Date.now() - (sentLate[p.id] || 0) < 3000) ok = false;
    if (ok === false) words = 'Didn\u2019t send';
    /* each answer is a line of its own (`n`), even for the same session with the same words; it folds out of the row only
       when that row is what shows now (`fold`), otherwise (a card closing, a row already put away) it is drawn afresh */
    sent = { words: words, ok: ok !== false, n: ++sentN, fold: (act.mode === 'full' || act.mode === 'sent') && !!act.p && act.p.id === p.id };
    clearTimeout(actTimer); clearTimeout(sentT);
    setAct('sent', p, quiet);
    sentT = setTimeout(sentDone, sent.ok ? SENT_MS : 4500);
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
    var right = '<span dir="auto" class="act-s' + (sent.ok ? ' said' : '') + '">' + esc(sent.words) + '</span>' + (sent.ok ? SentMark() : Ring('need'));
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
    if (!sent.ok) { mark.animate([{ opacity: 0, transform: 'scale(.4)' }, { opacity: 1, transform: 'scale(1.18)', offset: .6 }, { opacity: 1, transform: 'none' }], { duration: 420, delay: 200 + lag, easing: 'cubic-bezier(.3,1.4,.5,1)', fill: 'backwards' }); return; }
    mark.animate([{ opacity: 0, transform: 'translate(-7px, 7px) scale(.75)' }, { opacity: 1, transform: 'translate(1px, -1px)', offset: .7 }, { opacity: 1, transform: 'none' }], { duration: 480, delay: 200 + lag, easing: 'cubic-bezier(.2,.8,.3,1)', fill: 'backwards' });
  }
  actEl.addEventListener('click', function (e) {
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
  /* resting the pointer on it holds it open; leaving gives it a moment more */
  actEl.addEventListener('mouseenter', function () { if (act.mode === 'full') { actHeld = true; clearTimeout(actTimer); } });
  actEl.addEventListener('mouseleave', function () { if (actHeld) { actHeld = false; actLater(2500); } actMoreSet(null); });
  /* the pointer's moves reach here from WebKit, or from the page's own replay of them */
  actEl.addEventListener('mousemove', function (e) {
    if (act.mode !== 'full' || act.kind !== 'ask' || !e.target.closest) return;
    var qs = act.p.ask && act.p.ask.questions && act.p.ask.questions[0], ch = e.target.closest('.act-b.ch');
    if (ch && qs) {
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
    return ph === 'available' ? v + ' is available' : ph === 'ready' ? v + ' is ready' : ph === 'failed' ? '<span style="color:' + COLORS.attention + '">' + esc(u.short || (u.during === 'update' ? 'couldn\u2019t update' : 'couldn\u2019t check')) + '</span>' : ph ? '' : 'checked daily';
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
  var verSig = '';
  /* What is new, after an update. The card says it once: Perch and its version, the headline, then the few lines behind it (six show,
     the rest scroll). It opens by itself, so it takes no keys; Got it goes on to the list. */
  var wnSig = '';
  function whatsNew(w) {
    if (!w) return;
    var sig = JSON.stringify(w); if (sig === wnSig) return; wnSig = sig;
    var bl = w.bullets || [], rows = bl.filter(function (b) { return b !== w.headline; });
    var list = rows.length ? '<div class="wn-l o-said-in rv mx-4 mt-1.5 max-h-[150px] overflow-y-auto rounded-lg bg-black/[0.18] px-3 py-1.5" style="--i:2">' + rows.map(function (b) {
      return '<div dir="auto" class="flex items-start gap-2 py-[3px] text-[12.5px] leading-[18px] text-foreground/80"><i class="mt-[8px] size-[3px] flex-none rounded-full bg-zinc-500"></i><span class="min-w-0">' + esc(b) + '</span></div>';
    }).join('') + '</div>' : '';
    q('.wn').innerHTML =
      header('<div class="truncate text-sm font-medium leading-4">What\u2019s new in Perch</div>', '<span class="flex-none text-xs tabular-nums text-muted-foreground">' + esc(w.version) + '</span>') +
      '<div dir="auto" class="rv px-4 pb-0.5 pt-1 text-[13.5px] font-medium leading-[19px] tracking-[-0.01em]" style="--i:1">' + esc(w.headline || 'Perch ' + w.version) + '</div>' + list +
      '<div class="rv flex h-9 items-center justify-end px-2.5 pt-1" style="--i:3">' + Button('default', 'Got it', Kbd(CMDOPT + svg('enter', 'size-2'), 1), 'wn-ok h-7 rounded-lg pl-3 pr-1.5') + '</div>';
    var box = q('.wn-l'); if (box) box.classList.toggle('ov', box.scrollHeight > box.clientHeight + 1);   /* a list that scrolls fades at its edges, as the expanded reply does */
    q('.wn-ok').onclick = function () { post({ type: 'whatsnew', action: 'done' }); };
  }
  function apply(s) {
    /* Settings says which build this is, small, beside its close; a test build says so under the notch instead. A downloaded update waits beside it until Perch is quiet: Restart does it now. */
    /* Settings says which build this is, small, beside its close (the hardware notch hides anything nearer the middle) */
    var head = s.testBuild ? '' : (s.version || '');
    if (head !== verSig) { verSig = head; q('.s-ver').textContent = head; }
    if (actDemoOn && !s.demo) { actDemoLast = s; return; }
    snap = s;
    if (s.icons) icons = s.icons;
    var st = { idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', onboarding: 'onb', settings: 'set', whatsnew: 'new' }[s.phase];
    updChip(s, st);
    var p = s.projects[s.selected];
    if (st !== 'open') { snoozeMenu(false, true); replyMenu(false, true); }
    /* a reply belongs to its session: if the card moved to another one under it, the reply closes (its words stay a draft) */
    else if (replyFor && p && p.id !== replyFor) replyMenu(false);
    if (st !== 'open' && dropping) { dropping = 0; dropOpened = false; rIn.classList.remove('drop', 'on'); }
    if (p && !dropping) rIn.placeholder = replyHint();
    if (Date.now() - pickedAt > 1000) applyCharacter(s.character);
    if (st === 'onb') onb(s.onboarding); else { onbStep = -1; onbSig = ''; }
    if (st === 'new') whatsNew(s.whatsNew); else wnSig = '';
    if (st === 'set') {
      settingsApply(s.settings);
      if (liveNext) { liveNext = false; setFocus = 3; setKb = true; paintFocus(); setTimeout(flashLive, 300); }
    } else { setSig = ''; setFocus = 0; setKb = true; setHot = -1; appsAt = 0; appsOpen = false; showOpen = false; }
    var flipped = st === 'open' && lastSt === 'open' && p && cardId && p.id !== cardId;
    if (p) { if (st === 'open' && lastSt === 'open') settleCard(function () { fill(p); }, p.id !== cardId); else fill(p); }
    if (st !== 'open') orbFor('');
    if (flipped) setTimeout(function () { switched(p); }, 0);   /* after layout sets its face */
    cardId = st === 'open' && p ? p.id : null;
    moments(s, st);
    activity(s, st);
    testTag(s);
    if (st === 'switch') list(s); else { marquee(null); lastSel = -1; }
    /* Without Accessibility Perch cannot type for you: Send asks for it, then sends once it is on.
       A terminal session takes a reply without Accessibility: Perch types it into its tab. */
    var canSend = s.canSend !== false || !!(p && p.via);
    q('.x-send-l').textContent = canSend ? 'Send' : s.allowing ? 'Waiting for access' : 'Allow and send';
    /* while it waits there is nothing to press: no Return on it, and it steps back */
    q('.x-send kbd').style.display = !canSend && s.allowing ? 'none' : '';
    q('.x-send').style.opacity = !canSend && s.allowing ? '.6' : '';
    q('.x-send').title = canSend ? '' : s.allowing ? 'Turn Perch on in System Settings, Accessibility. Your reply goes out as soon as it is on.'
      : 'Perch needs Accessibility to send for you. Allow it once and this reply goes out.';
    /* green only while a finished session is news, blue while it works; one you have already seen glows in the character's colour */
    var glow = { attention: ['233,168,119', '244,210,180'], done: ['140,207,164', '196,234,210'], running: ['141,200,232', '198,228,246'] };
    var gk = st === 'open' && p && glow[p.status.kind] && !(p.status.kind === 'done' && p.fresh === false) ? glow[p.status.kind] : null, g = gk || ['245,184,59', '255,222,140'];
    n.style.setProperty('--glow', g[0]); n.style.setProperty('--glow-hi', g[1]);
    n.dataset.g = gk ? 'status' : 'char';
    n.dataset.run = st === 'open' && p && p.status.kind === 'running' ? '1' : '';   /* working: the light breathes (input.css) */
    var allDone = st === 'onb' && s.onboarding && s.onboarding.step === s.onboarding.total - 1;
    n.style.setProperty('--gcol', allDone ? COLORS.done : (st === 'onb' && introGlow) || charNow.color);
    var was = lastSt;
    if (st === 'idle' && was !== 'idle') hand(false);
    lastSt = st;
    if (st === 'switch' && was !== 'switch') { listKb = true; keyPtr = ptrAt.slice(); markList(); }   /* opened (by the hotkey too): the first row is lit, and a pointer resting over a row of it has not chosen that row */
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
  document.addEventListener('mousemove', function (e) { if (e.isTrusted) { ptrAt = [e.clientX, e.clientY]; sweep(e.clientX, e.clientY); if (lastSt === 'switch') markList(); realMoveAt = Date.now(); if (hvEls.length) hoverAt(-1, -1); } }, true);
  function hoverAt(x, y) {
    var el = x < 0 ? null : document.elementFromPoint(x, y), chain = [];
    for (var c = el; c && c !== document.documentElement; c = c.parentElement) chain.push(c);
    hvEls.forEach(function (c) { if (chain.indexOf(c) < 0) { c.classList.remove('hv'); c.dispatchEvent(new MouseEvent('mouseleave')); } });
    chain.slice().reverse().forEach(function (c) { if (hvEls.indexOf(c) < 0) { c.classList.add('hv'); c.dispatchEvent(new MouseEvent('mouseenter')); } });
    hvEls = chain;
    if (el) el.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: x, clientY: y }));
    hand(!!el && getComputedStyle(el).cursor === 'pointer');
  }
  /* WebKit shows the hand only on a card with the keyboard; on one without, Swift shows it when the page says */
  var handOn = false;
  function hand(on) { if (on !== handOn) { handOn = on; post({ type: 'hand', on: on }); } }
  function cursor(x, y) {
    ptrAt = [x, y]; sweep(x, y); if (lastSt === 'switch') markList();
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
      return otitle(o, 'Open Perch with', 'Press the shortcut you want. Esc goes back.') +
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
  var onbStep = -1, onbSig = '', onbLast = null;
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
    return '<div class="o-foot mt-3 flex h-9 items-center gap-1 px-2.5">' + (back ? Button('ghost', 'Back', Kbd('\u2190'), 'o-back') : (left || '')) + '<span class="flex-1"></span>' + (mid || '') +
      Button('default', label, Kbd(svg('enter', 'size-2'), 1), 'o-primary pr-0.5" data-a="' + action) + '</div>';
  }
  /* a tile's second line on the apps step: one quiet word while the first scan runs, then what it found */
  function srcLine(o, x) { return o.scanning ? 'Scanning\u2026' : x.count ? x.names.slice(0, 2).join(', ') + (x.count > 2 ? ', +' + (x.count - 2) : '') : 'Nothing found yet'; }
  function liveNote(on) { return on ? 'Codex may ask you once to trust the new hook.' : 'Adds a small hook to each agent. You can remove it in Settings.'; }
  /* off: Turn on, or Skip; on: Next */
  function liveFoot(on) { return ofootIn(true, on ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), on ? 'Next' : 'Turn on', on ? 'next' : 'hooks'); }
  function tick(done) { return done ? Ring('done') : '<span class="size-4 flex-none rounded-full border border-muted-foreground/40"></span>'; }
  function orow(icon, label, right) { return '<div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]">' + icon + '<span class="flex-1">' + label + '</span><span class="text-muted-foreground">' + right + '</span></div>'; }
  function ohint(left, text) { return '<div class="flex items-baseline gap-3"><span class="flex w-[4.5rem] flex-none">' + left + '</span><span class="text-muted-foreground">' + text + '</span></div>'; }
  function onbDo(a) {
    if (a === 'finish') helloNext = true;
    if (a === 'hooks') post({ type: 'hooks', on: true }); else post({ type: 'onb', action: a });
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
        oi(4, g ? '' : '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">Switch Perch on in System Settings. Switched it on but nothing changes? <button class="o-restart cursor-pointer underline underline-offset-2 hover:text-foreground">Restart Perch</button></p>') +
        ofoot(5, true, g ? '' : Button('ghost', 'Skip', Kbd('S'), 'o-skip'), g ? 'Next' : 'Open System Settings', g ? 'next' : 'accessibility');
    } else if (st === 3) {
      h = shortcutStep(o);
    } else if (st === 4) {
      var rows = o.sources.map(function (x) {
        var sw = '<button role="switch" aria-checked="' + x.enabled + '" aria-label="Include ' + x.name + '" data-id="' + x.id + '" class="o-sw sw"><i></i></button>';
        return '<div class="o-tile flex h-11 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3" data-id="' + x.id + '"><span class="o-ic flex-none ' + (x.enabled ? '' : 'opacity-50') + '">' + App(x.id, 'size-5') + '</span><span class="min-w-0 flex-1"><span class="block truncate text-[13px] font-medium leading-4">' + x.name + '</span><span class="o-line block truncate text-xs leading-4 text-muted-foreground' + (o.scanning ? ' opacity-60' : '') + '">' + esc(srcLine(o, x)) + '</span></span>' + sw + '</div>';
      }).join('');
      h = otitle(o, 'Choose your apps', 'Perch only reads the ones you switch on. You can change this later from the menu bar.') +
        /* more than two agents sit two to a row, so the card keeps its height */
        oi(3, '<div class="mt-3 ' + (o.sources.length > 2 ? 'grid grid-cols-2' : 'flex flex-col') + ' gap-1.5 px-4">' + rows + '</div>') +
        oi(4, '<p class="mt-2 px-4 text-xs leading-4 text-muted-foreground">macOS may ask to let Perch see a project folder. Choose Allow.</p>') +
        ofoot(5, true, '', 'Next', 'next');
    } else if (st === 5) {
      var live = o.live === 'on';
      h = otitle(o, 'Know the moment they need you', 'Your agents tell Perch when they finish or need your OK, and you can answer from the notch.') +
        oi(3, '<div class="mt-3 px-4"><div class="flex h-10 items-center gap-2.5 rounded-lg bg-white/[0.06] px-3 text-[13px]"><span class="flex-1">Live status</span>' +
          '<button role="switch" aria-checked="' + live + '" aria-label="Live status" class="o-live sw"><i></i></button></div></div>') +
        oi(4, '<p class="o-note mt-2 px-4 text-xs leading-4 text-muted-foreground">' + liveNote(live) + '</p>') +
        oi(5, liveFoot(live));
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
    box.querySelectorAll('.o-sw').forEach(function (b) { b.onclick = function () { var on = b.getAttribute('aria-checked') !== 'true'; setSw(b, on); b.closest('.o-tile').querySelector('.o-ic').classList.toggle('opacity-50', !on); post({ type: 'source', id: b.dataset.id, enabled: on }); }; });
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
    var sig = [o.step, o.only, o.step === 2 || o.step === 3 ? o.accessibility : '', o.step === 3 ? JSON.stringify(o.shortcut) : '', o.step === 4 ? o.sources.map(function (x) { return x.id; }).join(',') : ''].join('|');
    if (sig === onbSig) {
      var was = onbLast; onbLast = o;
      if (o.step === 4) onbSources(o);
      if (o.step === 5 && (!was || was.live !== o.live)) onbLive(o);
      return;
    }
    /* the introduction uses none of this data: a scan finishing must not cut it short */
    if (o.step === 0 && onbStep === 0 && onbSig && o.only === (onbLast && onbLast.only)) { onbSig = sig; onbLast = o; return; }
    var animate = o.step !== onbStep; if (animate) scWasTried = ''; onbStep = o.step; onbSig = sig; onbRender(o, animate);
    if (animate && o.step === o.total - 1) setTimeout(celebrate, 60);
  }
  /* the apps step, in place: a switch slides, a tile's line fades to what the scan found */
  function onbSources(o) {
    q('.onb').querySelectorAll('.o-tile').forEach(function (t) {
      var x = o.sources.filter(function (y) { return y.id === t.dataset.id; })[0], b = t.querySelector('.o-sw'), sub = t.querySelector('.o-line'), line;
      if (!x) return;
      if (b.getAttribute('aria-checked') !== String(x.enabled)) { setSw(b, x.enabled); t.querySelector('.o-ic').classList.toggle('opacity-50', !x.enabled); }
      line = srcLine(o, x);
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

  /* ---- settings, inside the notch ---- */
  var setLast = null, setSig = '';
  /* a switch changes in place so it slides; redrawing it would just snap to the new state */
  function setSw(b, on) {
    b.setAttribute('aria-checked', String(on));   /* .sw in input.css draws it from this */
  }
  function swHtml(on, key, label) {
    return '<button role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-k="' + key + '" class="s-sw sw"><i></i></button>';
  }
  function srow(left, right) { return '<div class="s-row mx-2 flex h-[30px] items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors">' + left + '<span class="flex-none">' + right + '</span></div>'; }
  /* each setting leads with its mark in a small quiet tile, so the rows tell apart at a glance */
  function stile(ic) { return ic ? '<span class="grid size-[18px] flex-none place-items-center rounded-[5px] bg-white/[0.08] text-muted-foreground" aria-hidden="true">' + svg(ic, 'size-[11px]') + '</span>' : ''; }
  function slabel(t, sub, ic) {
    var txt = t + (sub ? ' <span class="text-muted-foreground">' + sub + '</span>' : '');
    return ic ? '<span class="flex min-w-0 flex-1 items-center gap-2">' + stile(ic) + '<span class="min-w-0 truncate">' + txt + '</span></span>' : '<span class="min-w-0 flex-1 truncate">' + txt + '</span>';
  }
  var scSetSaved = '';
  var axAsked = false;   /* Allow was clicked: if it is still not working, the switch in System Settings is stale */
  function settingsRender(o) {
    setLast = o;
    var sh = shapeOf(charNow.shape), colorName = ''; PALETTE.forEach(function (c) { if (c[1] === charNow.color) colorName = c[0].toLowerCase(); });
    /* a small segmented choice: each button says which setting it is (data-key) and its value (data-m) */
    var segOf = function (key, vals, name) {
      return '<span class="flex rounded-md bg-white/[0.07] p-0.5">' + vals.map(function (m) {
        return '<button class="s-seg h-5 cursor-pointer rounded px-2 text-xs transition-colors ' + (o[key] === m ? 'bg-white/[0.16] text-foreground' : 'text-muted-foreground hover:text-foreground') + '" data-key="' + key + '" data-m="' + m + '">' + name(m) + '</button>';
      }).join('') + '</span>';
    };
    var awaySeg = segOf('idleMinutes', [10, 20, 60], function (m) { return m === 60 ? '1 hour' : m + ' min'; });
    var questSeg = segOf('questionSeconds', [30, 60, 300], function (m) { return m === 300 ? '5 min' : m === 60 ? '1 min' : m + ' s'; });
    var sc = scOf(o.shortcut),
      /* when it does not work the keys turn orange and the tooltip says why; the Accessibility row below carries the fix. The recorder page says it in words. */
      scRow = srow('<span class="flex min-w-0 flex-1 items-center gap-2">' + stile('keyboard') + '<span class="truncate">Open Perch</span><button class="s-sc -my-0.5 cursor-pointer rounded-md px-0.5 py-0.5 transition hover:bg-white/10 active:scale-95" aria-label="Change the shortcut" title="' + (sc.works ? 'Change' : sc.why) + '">' + scKeysHtml(sc, sc.works ? '' : COLORS.attention) + '</button></span>', '<span class="s-gr flex items-center gap-1">' + Button('ghost', 'Change', '', 's-sc') + (sc.custom ? Button('ghost', 'Reset', '', 's-scr') : '') + '</span>');
    var rows = [
      scRow,
      srow(slabel('Character', sh[1] + ', ' + colorName, 'cat'), Button('ghost', 'Change', '', 's-change s-gr')).replace('<div class="', '<div class="s-char '),
      srow(slabel('Apps', '', 'grid'), appsHtml(o)).replace('<div class="', '<div class="s-appsrow relative '),
      /* which moments the notch announces (the list and the cards say all of them) */
      srow(slabel('Notify me about', '', 'bell'), notifyHtml()).replace('<div class="', '<div class="s-notrow relative '),
      srow(slabel('Live status', '', 'pulse'), swHtml(o.live === 'on', 'live', 'Live status')),
      /* the minutes are how long you are away, not a reminder after an agent replies: the line under it says what follows */
      srow(slabel('Welcome back after', '', 'timer'), awaySeg),
      /* a question nobody answers leaves the notch after this long (it stays in the list) */
      srow(slabel('Questions stay in the notch for', '', 'hourglass'), questSeg),
      /* where the shortcut opens Perch and where it shows up by itself; hovering a screen's top still opens it on that screen */
      srow(slabel('Show Perch on', '', 'monitor'), showHtml(o)).replace('<div class="', '<div class="s-showrow relative '),
    ].concat([
      /* nothing to do when it is allowed, so the row only shows while it is not */
      o.accessibility ? '' : srow(slabel('Reply and shortcuts', o.accessibility ? 'allowed' : (axAsked ? 'turn Perch on there' : 'needs access'), 'access'), o.accessibility ? '' : Button('ghost', axAsked ? 'Open' : 'Allow', '', 's-ax s-gr" title="Opens Accessibility in System Settings with a fresh switch for this build of Perch. Turn it on there.')),
      srow(slabel('Open at login', '', 'login'), swHtml(o.login, 'login', 'Open at login'))
    ]).concat(snap && snap.canUpdate ? [
      /* a build that can update says where it stands; a local test build has no updater and no row */
      srow(slabel('Updates', '<span class="s-updsub">' + updSub(snap) + '</span>', 'refresh'), '<span class="s-updslot flex h-6 items-center gap-1.5">' + updSlot(snap) + '</span>')
    ] : []).filter(Boolean);
    /* the same room between the settings whatever rows show; the panel is tall enough for all eleven (408 pt) */
    rows = rows.join('');
    var box = q('.set');
    box.innerHTML = '<div>' + rows + '</div>' +
      /* the keys, like the list's: every setting can be changed without the mouse */
      '<div class="mt-1 flex h-9 items-center gap-1 px-2.5"><span class="flex items-center gap-3.5 pl-1.5 text-xs text-muted-foreground"><span class="flex items-baseline gap-1.5">' + Keys('\u2191', '\u2193') + 'Choose</span><span class="flex items-baseline gap-1.5">' + Kbd(svg('enter', 'size-2')) + 'Change</span></span>' +
      '<span class="flex-1"></span>' + Button('ghost', 'Quit Perch', '', 's-quit') + Button('default', o.back ? 'Back' : 'Done', Kbd('esc', 1), 's-done') + '</div>';
    box.querySelectorAll('.s-row').forEach(function (r, i) { r.addEventListener('mouseenter', function () { if (ptrMoved()) { setFocus = i; setHot = i; setKb = false; paintFocus(); } }); r.addEventListener('mouseleave', function () { if (setHot === i) { setHot = -1; paintFocus(); } }); });
    paintFocus();
    box.querySelectorAll('.s-sw').forEach(function (b) { b.onclick = function () {
      var on = b.getAttribute('aria-checked') !== 'true';
      setSw(b, on);   /* slide now; the app confirms (or puts it back) a moment later */
      if (b.dataset.k === 'login') post({ type: 'setting', key: b.dataset.k, value: on });
      else if (b.dataset.k === 'live') post({ type: 'hooks', on: on });
    }; });
    bindApps(box); bindNotify(box); bindShow(box); bindUpdSlot(box, snap);
    var sb0 = box.querySelector('.s-show'); if (sb0) { sb0._k = showKey(o); showClamp(sb0.querySelector('.s-showmenu')); }
    /* a shortcut you just recorded: its keys spring once, so it never lands without a word */
    var chip = box.querySelector('button.s-sc');
    if (chip && sc.saved && !sc.recording && scSetSaved !== sc.keys.join('')) { if (chip.animate && !STILL) chip.animate([{ transform: 'scale(.9)' }, { transform: 'scale(1.14)', offset: .5 }, { transform: 'scale(1)' }], { duration: 480, easing: 'cubic-bezier(.3,1.4,.5,1)' }); }
    scSetSaved = sc.saved ? sc.keys.join('') : '';
    var row = box.querySelector('.s-char');
    if (row) { row.onmouseenter = function () { if (cr.dataset.m === 'awake') { cr.dataset.m = 'happy'; look(-1.2, 1.6); } }; row.onmouseleave = function () { if (cr.dataset.m === 'happy') cr.dataset.m = 'awake'; }; }
    box.querySelectorAll('.s-seg').forEach(function (b) { b.onclick = function () { post({ type: 'setting', key: b.dataset.key, value: +b.dataset.m }); }; });
    var on = function (sel, fn) { box.querySelectorAll(sel).forEach(function (b) { b.onclick = fn; }); };
    on('.s-sc', function () { post({ type: 'onbOpen', step: 3, only: true }); });
    on('.s-scr', function () { post({ type: 'shortcut', action: 'reset' }); });
    on('.s-change', function () { post({ type: 'onbOpen', step: 1, only: true }); });
    on('.s-ax', function () { axAsked = true; post({ type: 'onb', action: 'accessibility' }); });
    on('.s-quit', function () { post({ type: 'quit' }); });
    /* Esc and this button go back to the card or list Settings came from, or close it when it came from elsewhere */
    on('.s-done', function () { post({ type: setLast && setLast.back ? 'back' : 'dismiss' }); });
  }
  /* Apps: the icons of the agents Perch reads and a chevron; it opens a menu with a check for each */
  var appsOpen = false;
  function appsHtml(o) {
    var on = o.sources.filter(function (x) { return x.enabled; });
    var faces = on.length ? '<span class="flex gap-[3px]">' + on.map(function (x) { return App(x.id, 'size-4'); }).join('') + '</span>'
      : '<span class="text-xs text-muted-foreground">None</span>';
    var items = o.sources.map(function (x, i) {
      return '<button role="menuitemcheckbox" aria-checked="' + x.enabled + '" data-k="' + x.id + '" data-i="' + i + '" class="s-app flex h-7 w-full cursor-pointer items-center gap-2 rounded-md px-2 text-left text-[13px] ' + (x.enabled ? 'text-foreground' : 'text-muted-foreground') + '">' +
        '<span class="flex-none ' + (x.enabled ? '' : 'opacity-50') + '">' + App(x.id, 'size-4') + '</span><span class="flex-1 truncate">' + x.name + '</span>' +
        (x.count ? '<span class="text-xs text-muted-foreground">' + x.count + '</span>' : '') +
        '<span class="flex size-3.5 flex-none items-center">' + (x.enabled ? svg('check', 'size-3.5') : '') + '</span></button>';
    }).join('');
    return '<span class="s-apps"><button aria-haspopup="menu" aria-expanded="' + appsOpen + '" aria-label="Apps Perch reads" class="s-apptrig inline-flex h-6 cursor-pointer items-center gap-1.5 rounded-md pl-1.5 pr-1 transition-colors hover:bg-white/[0.08]' + (appsOpen ? ' bg-white/[0.08]' : '') + '">' + faces + svg('chev', 'size-3 text-muted-foreground') + '</button>' +
      '<span role="menu" class="s-appmenu absolute right-2 top-[calc(100%+2px)] z-20 w-[196px] flex-col gap-px rounded-lg bg-[#1c1c1f] p-1 shadow-[0_12px_32px_rgba(0,0,0,0.55)] ring-1 ring-white/[0.08] ' + (appsOpen ? 'flex' : 'hidden') + '">' + items + '</span></span>';
  }
  function bindApps(box) {
    var trig = box.querySelector('.s-apptrig');
    if (trig) trig.onclick = function (e) { e.stopPropagation(); appsMenu(!appsOpen); };
    box.querySelectorAll('.s-app').forEach(function (b) {
      b.onclick = function (e) { e.stopPropagation(); post({ type: 'source', id: b.dataset.k, enabled: b.getAttribute('aria-checked') !== 'true' }); };
      b.onmouseenter = function () { if (ptrMoved()) { appsAt = +b.dataset.i; paintFocus(); } };
    });
  }
  /* opens or closes the menu in place; a click anywhere else on the card closes it */
  function appsMenu(open) {
    if (open && notOpen) notifyMenu(false);
    if (open && showOpen) showMenu(false);
    appsOpen = open; if (open) appsAt = 0;
    var box = q('.set'), m = box && box.querySelector('.s-appmenu'), t = box && box.querySelector('.s-apptrig');
    if (!m) return;
    m.classList.toggle('hidden', !open); m.classList.toggle('flex', open);
    t.setAttribute('aria-expanded', String(open)); t.classList.toggle('bg-white/[0.08]', open);
    paintFocus();
  }
  document.addEventListener('click', function (e) { if (appsOpen && !e.target.closest('.s-apps')) appsMenu(false); if (notOpen && !e.target.closest('.s-notify')) notifyMenu(false); if (showOpen && !e.target.closest('.s-show')) showMenu(false); });
  /* Notify me about: the marks of the moments the notch announces and a chevron; it opens a menu with a check for each, as Apps does */
  var notOpen = false, notAt = 0;
  function notifyOn(k) { return ((snap && snap.notifyOff) || []).indexOf(k) < 0; }
  function notifyHtml() {
    var on = NOTIFY.filter(function (x) { return notifyOn(x[0]); });
    var faces = on.length ? '<span class="flex gap-[3px]">' + on.map(function (x) { return nMark(x[0]); }).join('') + '</span>' : '<span class="text-xs text-muted-foreground">Nothing</span>';
    var items = NOTIFY.map(function (x, i) {
      var y = notifyOn(x[0]);
      return '<button role="menuitemcheckbox" aria-checked="' + y + '" data-k="' + x[0] + '" data-i="' + i + '" class="s-nitem flex h-7 w-full cursor-pointer items-center gap-2 rounded-md px-2 text-left text-[13px] ' + (y ? 'text-foreground' : 'text-muted-foreground') + '">' +
        '<span class="flex-none ' + (y ? '' : 'opacity-50') + '">' + nMark(x[0]) + '</span><span class="flex-1 truncate">' + x[1] + '</span>' +
        '<span class="flex size-3.5 flex-none items-center">' + (y ? svg('check', 'size-3.5') : '') + '</span></button>';
    }).join('');
    return '<span class="s-notify"><button aria-haspopup="menu" aria-expanded="' + notOpen + '" aria-label="What the notch tells you about" class="s-notrig inline-flex h-6 cursor-pointer items-center gap-1.5 rounded-md pl-1.5 pr-1 transition-colors hover:bg-white/[0.08]' + (notOpen ? ' bg-white/[0.08]' : '') + '">' + faces + svg('chev', 'size-3 text-muted-foreground') + '</button>' +
      '<span role="menu" class="s-notmenu absolute right-2 top-[calc(100%+2px)] z-20 w-[216px] flex-col gap-px rounded-lg bg-[#1c1c1f] p-1 shadow-[0_12px_32px_rgba(0,0,0,0.55)] ring-1 ring-white/[0.08] ' + (notOpen ? 'flex' : 'hidden') + '">' + items + '</span></span>';
  }
  function bindNotify(box) {
    var trig = box.querySelector('.s-notrig');
    if (trig) trig.onclick = function (e) { e.stopPropagation(); notifyMenu(!notOpen); };
    box.querySelectorAll('.s-nitem').forEach(function (b) {
      b.onclick = function (e) { e.stopPropagation(); post({ type: 'notify', kind: b.dataset.k, enabled: b.getAttribute('aria-checked') !== 'true' }); };
      b.onmouseenter = function () { if (ptrMoved()) { notAt = +b.dataset.i; paintFocus(); } };
    });
  }
  function notifyMenu(open) {
    if (open && appsOpen) appsMenu(false);
    if (open && showOpen) showMenu(false);
    notOpen = open; if (open) notAt = 0;
    var box = q('.set'), m = box && box.querySelector('.s-notmenu'), t = box && box.querySelector('.s-notrig');
    if (!m) return;
    m.classList.toggle('hidden', !open); m.classList.toggle('flex', open);
    t.setAttribute('aria-expanded', String(open)); t.classList.toggle('bg-white/[0.08]', open);
    paintFocus();
  }
  /* Show Perch on: the screen it opens on now and a chevron; the menu has one check, the two ways of following you first,
     then each display by name. It opens upward: the row sits low on the card. A display you chose that is not connected
     stays listed, so the choice is still there to see; until it is back Perch follows the mouse. While a display without a
     notch is connected, the menu ends with Hover opens on external displays: a display without a notch shows nothing at
     rest, and this lets its top edge open Perch (the shortcut always does). It switches in place and the menu stays open. */
  var showOpen = false, showAt = 0;
  var DEV_DISPLAYS = [{ id: '1', name: 'Built-in Retina Display', connected: true }, { id: '2', name: 'LG UltraFine', connected: true }];
  var SHOW_WAYS = [['mouse', 'Screen with mouse'], ['window', 'Screen with active window']];
  function showChoices(o) {
    return SHOW_WAYS.map(function (w) { return { id: w[0], name: w[1], on: true }; })
      .concat((o.displays || []).map(function (x) { return { id: x.id, name: x.name, on: x.connected !== false, display: true }; }));
  }
  function showHtml(o) {
    var all = showChoices(o), cur = o.showOn || 'mouse', now = all.filter(function (x) { return x.id === cur; })[0] || all[0];
    var items = all.map(function (x, i) {
      var y = x.id === now.id;
      return (x.display && !all[i - 1].display ? '<span class="mx-2 my-1 block h-px"></span>' : '') +
        '<button role="menuitemradio" aria-checked="' + y + '" data-k="' + x.id + '" data-i="' + i + '" class="s-sitem flex h-7 w-full cursor-pointer items-center gap-2 rounded-md px-2 text-left text-[13px] ' + (x.on ? 'text-foreground' : 'text-muted-foreground') + '">' +
        '<span class="flex-1 truncate">' + x.name + '</span>' + (x.on ? '' : '<span class="text-xs text-muted-foreground">Not connected</span>') +
        '<span class="flex size-3.5 flex-none items-center">' + (y ? svg('check', 'size-3.5') : '') + '</span></button>';
    }).join('') + (o.hasExternal ? '<span class="mx-2 my-1 block h-px"></span>' +
      '<button role="menuitemcheckbox" aria-checked="' + !!o.hoverExternal + '" data-k="hover" data-i="' + all.length + '" class="s-sitem flex h-7 w-full cursor-pointer items-center gap-2 rounded-md px-2 text-left text-[13px] text-foreground">' +
      '<span class="flex-1 truncate">Hover opens on external displays</span><span class="s-hovsw sw" aria-checked="' + !!o.hoverExternal + '"><i></i></span></button>' : '');
    return '<span class="s-show"><button aria-haspopup="menu" aria-expanded="' + showOpen + '" aria-label="Which screen Perch shows on" class="s-showtrig inline-flex h-6 max-w-[190px] cursor-pointer items-center gap-1.5 rounded-md pl-2 pr-1 text-xs text-muted-foreground transition-colors hover:bg-white/[0.08] hover:text-foreground' + (showOpen ? ' bg-white/[0.08]' : '') + '"><span class="truncate">' + now.name + '</span>' + svg('chev', 'size-3 flex-none') + '</button>' +
      '<span role="menu" class="s-showmenu absolute bottom-[calc(100%+2px)] right-2 z-20 w-[268px] flex-col gap-px rounded-lg bg-[#1c1c1f] p-1 shadow-[0_12px_32px_rgba(0,0,0,0.55)] ring-1 ring-white/[0.08] ' + (showOpen ? 'flex' : 'hidden') + '">' + items + '</span></span>';
  }
  /* what the menu shows, so it is drawn again only when that changes: not for opening or closing it (Swift sends
     Settings every half second while sessions are written, and a redraw would drop it back under the notch) and not
     for the hover switch, which slides in place */
  function showKey(o) { return JSON.stringify([o.showOn || 'mouse', o.displays || [], !!o.hasExternal]); }
  /* it opens upward but never under the notch: when it would, it slides down over its own row */
  function showClamp(m) {
    m.style.transform = '';
    var pane = showOpen && m.closest('.pane');
    if (pane) { var over = pane.getBoundingClientRect().top + 38 - m.getBoundingClientRect().top; if (over > 0) m.style.transform = 'translateY(' + Math.ceil(over) + 'px)'; }
  }
  function bindShow(box) {
    var trig = box.querySelector('.s-showtrig');
    if (trig) trig.onclick = function (e) { e.stopPropagation(); showMenu(!showOpen); };
    box.querySelectorAll('.s-sitem').forEach(function (b) {
      b.onclick = function (e) {
        e.stopPropagation();
        if (b.dataset.k === 'hover') {
          var on = b.getAttribute('aria-checked') !== 'true';
          b.setAttribute('aria-checked', String(on)); setSw(b.querySelector('.s-hovsw'), on);   /* slide now; the app confirms a moment later */
          post({ type: 'setting', key: 'hoverExternal', value: on }); return;
        }
        showMenu(false); post({ type: 'setting', key: 'showOn', value: b.dataset.k });
      };
      b.onmouseenter = function () { if (ptrMoved()) { showAt = +b.dataset.i; paintFocus(); } };
    });
  }
  function showMenu(open) {
    if (open && appsOpen) appsMenu(false);
    if (open && notOpen) notifyMenu(false);
    showOpen = open;
    var box = q('.set'), m = box && box.querySelector('.s-showmenu'), t = box && box.querySelector('.s-showtrig');
    if (open && box) { var its = [].slice.call(box.querySelectorAll('.s-sitem[role=menuitemradio]')); showAt = Math.max(0, its.findIndex(function (b) { return b.getAttribute('aria-checked') === 'true'; })); }
    if (!m) return;
    m.classList.toggle('hidden', !open); m.classList.toggle('flex', open);
    t.setAttribute('aria-expanded', String(open)); t.classList.toggle('bg-white/[0.08]', open);
    showClamp(m);
    paintFocus();
  }
  /* the highlighted row, moved with the arrow keys or the pointer; with the Apps menu open, the app in it */
  var setFocus = 0, appsAt = 0, liveNext = false, setHot = -1, setKb = true;   /* a row is lit while the pointer is on it or the keys chose it */
  /* opened from a question's "Settings": Live status is the row chosen, and it lights up once so the eye lands on it */
  function flashLive() {
    var r = q('.set').querySelectorAll('.s-row')[3];
    if (r && r.animate && !STILL) r.animate([{ backgroundColor: 'rgba(255,255,255,.2)' }, { backgroundColor: 'rgba(255,255,255,0)' }], { duration: 1800, easing: 'ease-out' });
  }
  function paintFocus() {
    var box = q('.set'), rows = box.querySelectorAll('.s-row');
    setFocus = Math.max(0, Math.min(setFocus, rows.length - 1));
    rows.forEach(function (r, i) { r.classList.toggle('bg-accent', i === setFocus && (setKb || i === setHot) && !appsOpen && !notOpen && !showOpen); });
    var sitems = box.querySelectorAll('.s-sitem');
    showAt = Math.max(0, Math.min(showAt, sitems.length - 1));
    sitems.forEach(function (b, i) { b.classList.toggle('bg-white/[0.08]', showOpen && i === showAt); });
    var items = box.querySelectorAll('.s-app');
    appsAt = Math.max(0, Math.min(appsAt, items.length - 1));
    items.forEach(function (b, i) { b.classList.toggle('bg-white/[0.08]', appsOpen && i === appsAt); });
    var nitems = box.querySelectorAll('.s-nitem');
    notAt = Math.max(0, Math.min(notAt, nitems.length - 1));
    nitems.forEach(function (b, i) { b.classList.toggle('bg-white/[0.08]', notOpen && i === notAt); });
  }
  /* arrows, Return and Space, forwarded from the app while Settings has the keyboard */
  function settingsKey(k) {
    keyPtr = ptrAt.slice(); setKb = true;
    var box = q('.set'), rows = box.querySelectorAll('.s-row'), row = rows[setFocus];
    /* with the Apps menu open, the keys are the menu's: arrows move, Return or Space switches, Esc or Left closes */
    if (appsOpen) {
      var items = box.querySelectorAll('.s-app');
      if (k === 'down' || k === 'up') { appsAt = (appsAt + (k === 'down' ? 1 : -1) + items.length) % items.length; paintFocus(); }
      else if (k === 'enter' && items[appsAt]) items[appsAt].click();
      else if (k === 'esc' || k === 'left') appsMenu(false);
      return;
    }
    if (notOpen) {
      var ni = box.querySelectorAll('.s-nitem');
      if (k === 'down' || k === 'up') { notAt = (notAt + (k === 'down' ? 1 : -1) + ni.length) % ni.length; paintFocus(); }
      else if (k === 'enter' && ni[notAt]) ni[notAt].click();
      else if (k === 'esc' || k === 'left') notifyMenu(false);
      return;
    }
    if (showOpen) {
      var si = box.querySelectorAll('.s-sitem');
      if (k === 'down' || k === 'up') { showAt = (showAt + (k === 'down' ? 1 : -1) + si.length) % si.length; paintFocus(); }
      else if (k === 'enter' && si[showAt]) si[showAt].click();
      else if (k === 'esc' || k === 'left') showMenu(false);
      return;
    }
    if (k === 'esc') { post({ type: 'back' }); return; }
    if (k === 'down' || k === 'up') { setFocus = (setFocus + (k === 'down' ? 1 : -1) + rows.length) % rows.length; paintFocus(); return; }
    if (!row) return;
    var seg = row.querySelectorAll('.s-seg'), apps = row.querySelector('.s-apptrig');
    if (apps && (k === 'right' || k === 'enter')) { appsMenu(true); return; }
    var nt = row.querySelector('.s-notrig');
    if (nt && (k === 'right' || k === 'enter')) { notifyMenu(true); return; }
    if (row.querySelector('.s-showtrig') && (k === 'right' || k === 'enter')) { showMenu(true); return; }
    if (k === 'left' || k === 'right') {
      var d = k === 'right' ? 1 : -1;
      /* on a row that has no sideways choice, Left goes back to where Settings came from */
      if (!(seg.length && setLast)) { if (k === 'left') post({ type: 'back' }); return; }
      if (seg.length && setLast) {
        var vals = [].map.call(seg, function (b) { return +b.dataset.m; }), i = Math.max(0, vals.indexOf(setLast[seg[0].dataset.key]));
        post({ type: 'setting', key: seg[0].dataset.key, value: vals[Math.max(0, Math.min(vals.length - 1, i + d))] });
      }
      return;
    }
    /* Return or Space: flip the switch, step the segment, or press the row's button */
    if (seg.length && setLast) { var v = [].map.call(seg, function (b) { return +b.dataset.m; }), sk = seg[0].dataset.key; post({ type: 'setting', key: sk, value: v[(v.indexOf(setLast[sk]) + 1) % v.length] }); return; }
    var c = row.querySelector('.s-sw, button'); if (c) c.click();
  }
  function settingsApply(o) {
    if (!o) return;
    var upd = snap ? [snap.update, !!snap.canUpdate] : 0, sig = JSON.stringify([o, charNow, upd, snap && snap.notifyOff]); if (sig === setSig) return;
    /* the same rows with new values: change them in place, so switches and the segment animate */
    var shape = JSON.stringify([o.shortcut, o.accessibility, !!o.hasExternal, o.sources.map(function (x) { return x.id; }), charNow, snap && snap.canUpdate]), box = q('.set');
    if (setSig && box.dataset.shape === shape) {
      setSig = sig; setLast = o;
      box.querySelectorAll('.s-sw').forEach(function (b) { setSw(b, b.dataset.k === 'login' ? !!o.login : o.live === 'on'); });
      var ap = box.querySelector('.s-apps'); if (ap) { ap.outerHTML = appsHtml(o); bindApps(box); paintFocus(); }
      var nf = box.querySelector('.s-notify'); if (nf) { nf.outerHTML = notifyHtml(); bindNotify(box); paintFocus(); }
      var sw2 = box.querySelector('.s-show'), skey = showKey(o);
      if (sw2 && sw2._k !== skey) { sw2.outerHTML = showHtml(o); sw2 = box.querySelector('.s-show'); sw2._k = skey; bindShow(box); showClamp(sw2.querySelector('.s-showmenu')); paintFocus(); }
      else if (sw2) {
        /* the same menu: only the hover switch may have moved, and it slides */
        var hv = sw2.querySelector('.s-sitem[data-k=hover]');
        if (hv && hv.getAttribute('aria-checked') !== String(!!o.hoverExternal)) { hv.setAttribute('aria-checked', String(!!o.hoverExternal)); setSw(hv.querySelector('.s-hovsw'), !!o.hoverExternal); }
      }
      var us = box.querySelector('.s-updslot');
      if (us && snap) {
        var html = updSlot(snap), key = html.replace(/stroke-dashoffset="[^"]*"/, '');
        if (us._k !== key) { us.innerHTML = html; us._k = key; bindUpdSlot(us, snap); }
        var sb = box.querySelector('.s-updsub'); if (sb) sb.textContent = ''; if (sb) sb.innerHTML = updSub(snap);
        var arc = us.querySelector('.upd-arc'); if (arc) arc.style.strokeDashoffset = String(UPD_C * (1 - (snap.update.progress || 0)));
      }
      box.querySelectorAll('.s-seg').forEach(function (b) {
        var on = +b.dataset.m === o[b.dataset.key];
        ['bg-white/[0.16]', 'text-foreground'].forEach(function (c) { b.classList.toggle(c, on); });
        ['text-muted-foreground', 'hover:text-foreground'].forEach(function (c) { b.classList.toggle(c, !on); });
      });
      return;
    }
    setSig = sig; settingsRender(o); box.dataset.shape = shape;
  }

  window.perch = { held: function (list) { scHeldNow = list || []; scHeldApply(); }, hi: function () { if (lastSt === 'idle' && !hello && !celebrating) sayHello(); }, _icons: function (o) { icons = o; }, actKey: actDo, actDemo: actDemo, hot: function (on) { n.dataset.hot = on ? '1' : ''; }, onbKey: onbKey, setKey: settingsKey, askKey: askKey, answering: function (choice) { noteAnswer({ type: 'answer', choice: choice }); }, notSent: notSent, still: function () { still = true; cr.classList.remove('blink'); }, apply: apply, listKey: function () { listKb = true; markList(); }, cursor: cursor, snoozeMenu: function (o) { snoozeMenu(o); }, replyMenu: function (o) { if (o && !q('.o-acts [data-act=reply]')) return; replyMenu(o); }, paths: addPaths, dragOver: dragOver, say: function (t) { pop('awake', 2600, t); },
    /* Swift hid the panel to move it to another display: it shows it again once what goes there is on screen */
    painted: function (token) { requestAnimationFrame(function () { requestAnimationFrame(function () { post({ type: 'painted', token: token }); }); }); } };
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (snap) layout({ idle: 'idle', open: 'open', switcher: 'switch', restoring: 'idle', onboarding: 'onb', settings: 'set' }[snap.phase], snap); });

  /* ---- bridge ---- */
  function post(m) {
    if (m.type === 'answer') noteAnswer(m);
    if (NATIVE) window.webkit.messageHandlers.perch.postMessage(m); else dev(m);
  }
  window.addEventListener('error', function (e) { if (NATIVE) window.webkit.messageHandlers.perch.postMessage({ type: 'log', text: String(e.message) + ' @' + e.lineno }); });

  /* ---- browser-only dev harness (never runs inside the app) ---- */
  var devFrom = '', devSc = Object.assign({}, SC0);
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
      else if (m.action === 'reset') devScSync(Object.assign({}, SC0, { saved: true }));
      else if (m.action === 'try' && !devSc.recording) devScSync({ tried: true, saved: false });
      return;
    }
    /* the drafts Swift keeps, kept here instead */
    if (m.type === 'draft') { base.drafts = base.drafts || {}; if (m.text) base.drafts[m.id] = m.text; else delete base.drafts[m.id]; if (snap) snap.drafts = base.drafts; return; }
    if (m.type === 'reply' && snap && snap.projects[snap.selected] && base.drafts) delete base.drafts[snap.projects[snap.selected].id];
    /* Esc while it waits for Accessibility: back to the card, and the wait is off */
    if (m.type === 'replyMenu' && !m.open && snap && snap.allowing) { var s0 = JSON.parse(JSON.stringify(snap)); s0.allowing = false; base.allowing = false; apply(s0); return; }
    if (m.type === 'whatsnew') { window.perchDev.show('switcher', false, false); return; }   /* Got it: on to the list */
    if (!snap || m.type === 'size' || m.type === 'log' || m.type === 'hand' || m.type === 'snoozeMenu' || m.type === 'replyMenu') return;
    var s = JSON.parse(JSON.stringify(snap));
    if (m.type === 'flip') { s.selected = (s.selected + (m.dir || 1) + s.projects.length) % s.projects.length; s.timerToken++; apply(s); return; }
    /* a reply to a terminal session flies off first, then the card closes */
    if (m.type === 'reply' && snap.projects[snap.selected] && snap.projects[snap.selected].via) { setTimeout(function () { var s2 = JSON.parse(JSON.stringify(snap)); s2.phase = 'idle'; s2.timerToken++; apply(s2); }, (m.close || .76) * 1000); return; }
    /* without Accessibility the card stays, waiting for it; the words stay in the field */
    if (m.type === 'reply' && snap.canSend === false) { s.allowing = true; s.timerToken++; apply(s); return; }
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
    if (m.type === 'settings') { devFrom = snap.phase === 'open' || snap.phase === 'switcher' ? snap.phase : ''; s.phase = 'settings'; s.settings = s.settings || { sources: [], accessibility: true, idleMinutes: 20, questionSeconds: 60, login: false, live: 'on', hasExternal: !s.screen.hasNotch, hoverExternal: false, showOn: 'mouse', displays: DEV_DISPLAYS, shortcut: devScOut(true) }; if (!s.settings.sources.length) s.settings.sources = [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }]; }
    if (m.type === 'setting' && s.settings) { s.settings[m.key] = m.value; if (m.key === 'questionSeconds') s.questionSeconds = m.value; }
    if (m.type === 'notify') { var off = (s.notifyOff || []).filter(function (k) { return k !== m.kind; }); if (!m.enabled) off.push(m.kind); s.notifyOff = off; }
    if (m.type === 'source' && s.settings) { s.settings.sources.forEach(function (x) { if (x.id === m.id) x.enabled = m.enabled; }); }
    if (m.type === 'onbOpen') { window.perchDev.onboarding(m.step || 0, true, m.only); return; }
    if (m.type === 'onb' && m.action === 'next' && s.onboarding && s.onboarding.only) { window.perchDev.settings(null, true); return; }
    if (m.type === 'onb' && !s.onboarding) { if (m.action === 'accessibility' && s.settings) { s.settings.accessibility = true; } else return; }
    if (m.type === 'quit') { s.phase = 'idle'; }
    if (m.type === 'switcher') s.phase = 'switcher';
    /* answered from the notch: that session goes on, working again */
    if (m.type === 'activityAnswer') { s.projects = s.projects.map(function (x) { return x.id === m.id ? Object.assign({}, x, { ask: null, attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: x.app === 'codex' ? 'Codex is working' : 'Claude Code is working', app: x.app } }) : x; }); var nw = document.getElementById('now'); if (nw) nw.textContent = 'Sent from the notch: ' + (m.choice || Object.keys(m.answers).map(function (k) { return m.answers[k]; }).join(' / ')); }
    if (m.type === 'pick') { s.selected = m.index; if (typeof base !== 'undefined') base.selected = m.index; }
    if (m.type === 'details') { s.selected = m.index; s.phase = 'open'; s.autoCollapse = false; }
    if (m.type === 'back') s.phase = snap.phase === 'settings' && devFrom ? devFrom : 'open';
    if (s.phase === 'settings' && s.settings) s.settings.back = !!devFrom;
    s.timerToken++; s.autoCollapse = s.phase === 'open'; apply(s);
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
      { id: 'api', name: 'api-server', branch: 'main', away: '1m', at: '12:01 PM', asked: 'Add a rate limiter to the public API, per key, with a burst allowance. Keep it simple, a token bucket is fine, and make sure the 429 tells clients when to retry.', said: 'The limiter is in: a token bucket per API key, 60 requests a minute with a burst of 20. Over the limit, the API answers `429` with a `Retry-After` header.\n\n```ts\napp.use(rateLimit({ perKey: 60, burst: 20 }))\n```\n\nI am running the test suite now.', headline: 'Rate limiter for the public API.', context: 'You asked: \u201cadd a rate limiter to the public API, per key, with a burst allowance\u201d', now: 'Run the test suite', next: '', topic: 'Rate limiter for the public API', app: 'claude', via: 'ghostty', attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'Claude Code is working', app: 'claude' } },
      { id: 'fluid', name: 'FluidAgent', via: 'terminal', branch: 'main', away: '23h', at: 'Yesterday', headline: 'You were stopping a runaway tool loop.', context: 'The agent now stops after three identical calls.', next: '', topic: 'Stop it when the tool loop runs away', app: 'codex', attention: false, fresh: false, line: '23h ago', status: { kind: 'idle', text: 'Codex finished', app: 'codex' } },
      { id: 'gaps', name: 'spec-gap-finder', branch: 'main', away: '2d', at: 'Wed', headline: 'You were setting up the PDF gap finder.', context: 'It reads a spec and a supplier answer and lists what is missing.', next: '', topic: 'PDF gap analysis app and the supplier questionnaire', app: 'claude', attention: false, fresh: false, line: '2d ago', status: { kind: 'idle', text: 'Claude finished', app: 'claude' } },
      /* the other agents: OpenCode at work in Ghostty, and pi in a herdr pane (herdr shown in Ghostty) */
      { id: 'tui', name: 'tui-kit', via: 'ghostty', branch: 'main', away: '2m', at: '12:03 PM', headline: 'Keyboard focus for the table.', context: 'Moving focus with the arrow keys, then making Tab leave the table.', now: 'Running `bun test`', next: '', topic: 'Keyboard focus for the table component', app: 'opencode', attention: false, fresh: false, line: 'Working now', status: { kind: 'running', text: 'OpenCode is working', app: 'opencode' },
        said: 'Arrow keys now move focus between cells, and Home and End jump to the ends of a row. I am running the tests before I touch Tab.' },
      { id: 'scraper', name: 'price-scraper', via: 'ghostty', host: 'herdr', branch: 'main', away: '12m', at: '11:52 AM', headline: 'You were retrying failed pages.', context: 'Failed pages now retry three times with backoff, and the run log lists the ones that never loaded.', next: 'Run it against the full catalogue', topic: 'Retry failed pages with backoff', app: 'pi', attention: false, fresh: true, line: 'Finished 12m ago', status: { kind: 'done', text: 'pi finished', app: 'pi' },
        said: 'Failed pages now retry three times, waiting 1, 4 and 16 seconds. Pages that still fail go to `failed.txt` with their status code.\n\nNext: run it against the full catalogue.' },
      /* a workspace in Conductor: Conductor's icon with the agent on its corner, and Open Conductor on the button */
      { id: 'phoenix', name: 'conductor-test', opens: 'conductor', branch: 'asafofer/ls-files', away: '6m', at: '1:30 PM', headline: 'Ls files.', context: 'The only tracked file in the workspace is `README.md`, which is 7 bytes.', next: '', topic: 'Ls files', app: 'claude', attention: false, fresh: true, line: 'Finished 6m ago', status: { kind: 'done', text: 'Claude Code replied', app: 'claude' },
        asked: 'Run `ls` with bash and tell me what files are here.', said: 'The only tracked file in the workspace is `README.md`, which is 7 bytes.' }
    ];
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
    var autoTimer, devQuery = '';
    function devShown() {
      var words = devQuery.toLowerCase().split(/\s+/).filter(Boolean);
      var mins = function (p) { var m = /^(\d+)([mhd])/.exec(p.away || ''); return m ? +m[1] * { m: 1, h: 60, d: 1440 }[m[2]] : 1e9; };
      var rank = function (p) { return { 'Needs you': 0, Today: 1 }[sectionOf(p)] === undefined ? 2 : { 'Needs you': 0, Today: 1 }[sectionOf(p)]; };
      return P.map(function (p, k) { return k; }).filter(function (k) { var hay = (P[k].name + ' ' + P[k].topic).toLowerCase(); return words.every(function (w) { return hay.indexOf(w) >= 0; }); })
        .sort(function (a, b) { return rank(P[a]) - rank(P[b]) || mins(P[a]) - mins(P[b]) || a - b; });
    }
    window.perchDev = {
      /* a character as markup, for pages that draw it outside the notch (ui/install/background.html, the disk image's picture) */
      character: function (shape, size, mood) { return crHtml('', size, shapeOf(shape), mood); },
      show: function (ph, quiet, mine) { clearTimeout(autoTimer); devQuery = ''; if (base.once) base.once = false; else { base.canSend = true; base.allowing = false; } snoozeMenu(false, true); replyMenu(false, true); if (ph === 'switcher') { var top = devShown()[0]; if (top !== undefined) base.selected = top; } var s = Object.assign({}, base, { character: charNow, projects: quiet ? P.map(function (x) { return Object.assign({}, x, { attention: false }); }) : P, phase: ph, autoCollapse: ph === 'open', proactive: ph === 'open' && !mine, shown: ph === 'switcher' ? devShown() : null, timerToken: Math.random() }); apply(s); },
      setNotch: function (has) {
        base.screen = has ? { hasNotch: true, notchW: 185, notchH: 32 } : { hasNotch: false, notchW: 0, notchH: 24 };
        if (snap) apply(Object.assign({}, snap, { screen: base.screen, timerToken: Math.random() }));
      },
      shortcut: function (patch) { devScSync(patch); },
      settings: function (o, keep) {
        if (!keep) devSc = Object.assign({}, SC0, o && o.shortcut || {});
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        apply(Object.assign({}, base, { phase: 'settings', character: charNow, autoCollapse: false, timerToken: Math.random(), update: o && o.update ? o.update : null, notifyOff: o && o.notifyOff || [],
          settings: Object.assign({ sources: [{ id: 'claude', name: 'Claude Code', enabled: true }, { id: 'codex', name: 'Codex', enabled: true }], accessibility: true, idleMinutes: 20, questionSeconds: 60, login: false, live: 'on', hasExternal: !base.screen.hasNotch, hoverExternal: false, showOn: 'mouse', displays: DEV_DISPLAYS, shortcut: devScOut(!o || o.accessibility !== false) }, o || {}) }));
      },
      /* `scan`: the first scan is still running when the step opens; it comes in, then the app keeps sending the same
         snapshot every half second, as it does while sessions are written */
      onboarding: function (step, accessibility, only, live, all, scan) {
        devSc = only && step === 3 ? Object.assign({}, devSc, { recording: true, error: '', saved: false, tried: false }) : Object.assign({}, SC0);
        clearTimeout(autoTimer); snoozeMenu(false, true); replyMenu(false, true);
        var sources = [{ id: 'claude', name: 'Claude Code', count: 3, names: ['Website', 'Docs', 'Finance'], enabled: true }, { id: 'codex', name: 'Codex', count: 1, names: ['Onboarding flow'], enabled: true }];
        if (all) sources = sources.concat([{ id: 'opencode', name: 'OpenCode', count: 1, names: ['tui-kit'], enabled: true }, { id: 'pi', name: 'pi', count: 1, names: ['price-scraper'], enabled: true }]);
        var s0 = Object.assign({}, base, { phase: 'onboarding', character: charNow, autoCollapse: false, timerToken: Math.random(),
          onboarding: { step: step, total: 7, shortcut: devScOut(!!accessibility), accessibility: !!accessibility, scanning: !!scan, sources: sources, only: !!only, live: live || 'off' } });
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
        if (o.fresh !== false && (o.fresh || !snap || !snap.update || snap.update.phase !== phase)) { actGone = {}; if (o.fresh) updNotes = false; }
        var calm = P.map(function (x) { return Object.assign({}, x, { attention: false, ask: null, fresh: false, status: x.status.kind === 'attention' || x.status.kind === 'done' ? { kind: 'idle', text: 'Finished', app: x.app } : x.status }); });
        base.update = phase ? { version: phase === 'checking' ? '0.3.0' : '0.3.1', phase: phase, progress: o.progress || 0, notes: 'Record your own shortcut to open Perch', problem: o.problem || '', fix: o.fix || '', during: o.during || '', short: o.short || '',
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
          whatsNew: { version: '0.3.10', headline: 'Lists and code read better in a reply', bullets: bullets } }));
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
      updStop: function () { updTok++; document.getElementById('scene').style.opacity = '1'; },
      /* how an answer from the notch says it went: 'answer' (one line, your answer and a check) or 'check' (the wings, the app and a check) */
      /* an answer that came too late (answered in the app already, or Perch had let the question go): the line says it did not send */
      sentFail: function (a) {
        var p = act.p, b = actEl.querySelector('.act-btns [data-a="' + a + '"]'); if (!p) return;
        clearTimeout(actTimer); act.keys = []; actPressing = true; sentBase = actKnown; if (b) { actEl.classList.add('chose'); b.classList.add('on'); }
        notSent(p.id);   /* as Swift says it: a moment after the press, before the row has folded */
        setTimeout(function () { actPressing = false; sentShow(p, 'Sent'); }, 170);
      },
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
      clearDrafts: function () { base.drafts = {}; if (snap) snap.drafts = base.drafts; },
      step: function (d) {
        var shown = devShown(), at = shown.indexOf(base.selected);
        if (!shown.length) return;
        base.selected = at < 0 ? shown[0] : shown[(at + d + shown.length) % shown.length];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, shown: shown, timerToken: Math.random() }));
      },
      /* the same narrowing as ListFilter in Swift: every word must appear in the name or the title */
      type: function (t) {
        devQuery = t; var shown = devShown(); if (shown.length) base.selected = shown[0];
        apply(Object.assign({}, base, { phase: 'switcher', autoCollapse: false, query: devQuery, shown: shown, timerToken: Math.random() }));
      }
    };
    /* recording and trying the shortcut with the browser's own keys (capture phase, before anything else sees them) */
    var scMods = [], scKey = false, SC_GLYPH = [['ctrlKey', '\u2303'], ['altKey', '\u2325'], ['shiftKey', '\u21E7'], ['metaKey', '\u2318']];
    var scHeld = function (e) { return SC_GLYPH.filter(function (g) { return e[g[0]]; }).map(function (g) { return g[1]; }); };
    var scTaken = { '\u2303\u2325P': 'the welcome card', '\u2303\u2325L': 'the project list', '\u2303\u2325Q': 'Quit Perch', '\u2318Q': 'Quit in every app', '\u2318W': 'Close in every app', '\u2318C': 'Copy', '\u2318V': 'Paste', '\u2318Space': 'Spotlight' };
    /* what you press is only a choice; Return alone saves it, another try replaces it */
    var scDone = function (keys, kind) { devScSync({ pending: keys, pendKind: kind, error: '', attempt: [], picks: (devSc.picks || 0) + 1 }); };
    var scSave = function () {
      var keys = devSc.pending, kind = devSc.pendKind, same = keys.join('') === SC0.keys.join('') && kind === 'tap';
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
        if (mods.length < 2) { devScSync({ error: 'A tap needs two or more modifier keys', attempt: mods, refusals: (devSc.refusals || 0) + 1 }); return; }
        var tap = mods.join('');
        if (scTaken[tap]) { devScSync({ error: tap + ' is ' + scTaken[tap], attempt: mods, refusals: (devSc.refusals || 0) + 1 }); return; }
        scDone(mods.slice().sort(function (a, b) { return '\u2303\u2325\u21E7\u2318'.indexOf(a) - '\u2303\u2325\u21E7\u2318'.indexOf(b); }), 'tap');
      } else if (snap.phase === 'onboarding' && snap.onboarding.step === 3 && devSc.kind === 'tap' && mods.slice().sort().join('') === devSc.keys.slice().sort().join('')) devScSync({ tried: true });
    }, true);
    document.addEventListener('keydown', function (e) {
      var ph = snap && snap.phase; if (!ph || ph === 'idle') return;
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
        if (ask.kind === 'question') { var m2 = { Enter: 'enter', Backspace: 'back', ArrowLeft: 'back', ArrowRight: 'next' }[e.key] || (/^[1-9]$/.test(k) ? k : null); if (m2) { e.preventDefault(); askKey(m2); return; } }
      }
      if (e.key === 'Escape' && ph === 'switcher' && devQuery) { window.perchDev.type(''); return; }
      if (e.key === 'Escape' && ph === 'settings') { settingsKey('esc'); return; }
      if (e.key === 'Escape') { if (fSnz.style.display === 'flex') snoozeMenu(false, true); else if (fRep.style.display === 'flex') replyMenu(false); else window.perchDev.show('idle'); }
      else if (e.key === 'Enter' && (ph === 'open' || ph === 'switcher')) window.perchDev.show('idle');
      else if (e.key === 'Tab' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.key === 'Tab' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open'); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'switcher') { e.preventDefault(); window.perchDev.step(e.key === 'ArrowDown' ? 1 : -1); }
      else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && ph === 'open') { e.preventDefault(); dev({ type: 'flip', dir: e.key === 'ArrowDown' ? 1 : -1 }); }
      else if (e.key === 'ArrowRight' && ph === 'switcher') { e.preventDefault(); window.perchDev.show('open', false, true); }
      else if (e.key === 'ArrowLeft' && ph === 'open') { e.preventDefault(); window.perchDev.show('switcher'); }
      else if (e.metaKey && e.key === ',') { e.preventDefault(); window.perchDev.settings(); }
      else if (ph === 'switcher' && (e.key === 'Backspace' || (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !(e.key === ' ' && !devQuery)))) { e.preventDefault(); window.perchDev.type(e.key === 'Backspace' ? devQuery.slice(0, -1) : devQuery + e.key); }
      else if ((e.key === 'n' || e.key === 'N') && ph === 'open') snoozeMenu(fSnz.style.display !== 'flex', true);
      else if (fSnz.style.display === 'flex' && /^[123]$/.test(e.key)) { snoozeMenu(false, true); window.perchDev.show('idle'); }

    });
  }
})();

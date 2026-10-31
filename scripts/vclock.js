/* A virtual clock for filming the design page frame by frame (scripts/film-design.swift; first written for the trailer):
   timers, frames, Date and every CSS/Web animation run on time the filmer sets (window.__vt.to(ms)), never on the wall clock. */
(function () {
  var vt = 0, seq = 0, timers = [], rafs = [], anims = new Map();
  var RealDate = Date, t0 = RealDate.now(), p0 = performance.now();
  window.setTimeout = function (f, ms) { var a = [].slice.call(arguments, 2), id = ++seq; timers.push({ id: id, at: vt + Math.max(0, +ms || 0), f: f, a: a }); return id; };
  window.setInterval = function (f, ms) { var a = [].slice.call(arguments, 2), id = ++seq, every = Math.max(1, +ms || 1); timers.push({ id: id, at: vt + every, f: f, a: a, every: every }); return id; };
  window.clearTimeout = window.clearInterval = function (id) { timers = timers.filter(function (t) { return t.id !== id; }); };
  window.requestAnimationFrame = function (f) { var id = ++seq; rafs.push({ id: id, f: f }); return id; };
  window.cancelAnimationFrame = function (id) { rafs = rafs.filter(function (r) { return r.id !== id; }); };
  function VDate() { var a = [].slice.call(arguments); return a.length ? new (Function.prototype.bind.apply(RealDate, [null].concat(a)))() : new RealDate(t0 + vt); }
  VDate.prototype = RealDate.prototype; VDate.now = function () { return t0 + vt; }; VDate.UTC = RealDate.UTC; VDate.parse = RealDate.parse;
  window.Date = VDate;
  performance.now = function () { return p0 + vt; };
  function seek() {
    /* SVG's own animations (the spinners' animateTransform) run on each svg's clock: hold them on ours */
    document.querySelectorAll('animateTransform, animate').forEach(function (el) {
      var svg = el.ownerSVGElement; while (svg && svg.ownerSVGElement) svg = svg.ownerSVGElement;
      if (svg && svg.__vt !== vt) { svg.__vt = vt; svg.pauseAnimations(); svg.setCurrentTime(vt / 1000); }
    });
    document.getAnimations().forEach(function (a) {
      if (!anims.has(a)) anims.set(a, vt);
      if (a.playState !== 'paused') a.pause();
      a.currentTime = Math.max(0, vt - anims.get(a));
    });
  }
  function due(to) {
    for (;;) {
      var next = null;
      timers.forEach(function (t) { if (t.at <= to && (!next || t.at < next.at || (t.at === next.at && t.id < next.id))) next = t; });
      if (!next) return;
      vt = Math.max(vt, next.at);
      if (next.every) next.at += next.every; else timers = timers.filter(function (t) { return t !== next; });
      try { typeof next.f === 'function' ? next.f.apply(window, next.a) : (0, eval)(next.f); } catch (e) { console.error(e); }
      seek();
    }
  }
  /* the film always has full motion, whatever the filming browser's Reduce motion says */
  var mm = window.matchMedia.bind(window);
  window.matchMedia = function (q) { return /prefers-reduced-motion/.test(q) && /reduce/.test(q) ? mm('not all') : mm(q); };
  window.__noReducedMotion = function () {
    [].forEach.call(document.styleSheets, function (sh) {
      var rules; try { rules = sh.cssRules; } catch (e) { return; }
      for (var i = rules.length - 1; i >= 0; i--) if (rules[i].media && /prefers-reduced-motion/.test(rules[i].media.mediaText)) sh.deleteRule(i);
    });
  };
  window.__vt = {
    now: function () { return vt; },
    /* moves time forward to `ms`, a frame (1/60 s) at a time: due timers in order, then frame callbacks, then animations */
    to: function (ms) {
      while (vt < ms) {
        var step = Math.min(ms, vt + 1000 / 60);
        due(step); vt = step;
        var fr = rafs; rafs = [];
        fr.forEach(function (r) { try { r.f(p0 + vt); } catch (e) { console.error(e); } });
        seek();
      }
      seek();
    }
  };
})();

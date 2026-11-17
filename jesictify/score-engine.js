/* Jesictify · 점수 엔진 (v1.0)
 * 숫자를 만드는 유일한 경로입니다. 화면·리포트의 모든 숫자는 이 파일의 함수에서만 나옵니다.
 * - computeScores : 한터 차트 이력 -> 축별 점수 (결정적 계산, 검색 데이터는 읽지 않음)
 * - deriveSignal  : 리스크 근거(findings) -> 신호등 (규칙으로 계산, 사람이 직접 지정하지 않음)
 * - traceNumbers  : 근거 문장 속 숫자가 원문 인용문에 있는지 검사
 * - buildLedger   : 모든 숫자를 id 와 산식, 입력과 함께 장부로 출력
 * 브라우저(window.EumwonScore)와 Node 양쪽에서 동일하게 동작합니다.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.EumwonScore = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var CFG = { minDays: 3, portfolioCap: 4 };
  var AXES = [
    { id: 'hot',       no: '①', name: '현재 화제성',        weight: 25 },
    { id: 'persist',   no: '②', name: '지속력',             weight: 20 },
    { id: 'expand',    no: '③', name: '대중 확장성',        weight: 15 },
    { id: 'portfolio', no: '④', name: 'IP 포트폴리오',      weight: 15 },
    { id: 'fandom',    no: '⑤', name: '팬덤 구매력',        weight: 25 },
    { id: 'risk',      no: '⑥', name: '사업 리스크·접근성', weight: 0 }
  ];
  var SEVERITIES = ['ok', 'info', 'caution', 'critical'];
  var VERIFIED_LEVELS = ['raw', 'extract', 'none'];

  function fmt(n, d) {
    d = d || 0;
    return Number(n).toLocaleString('ko-KR', { minimumFractionDigits: d, maximumFractionDigits: d });
  }
  function clamp(v) { return Math.max(0, Math.min(100, v)); }

  /* ---------- 점수 ---------- */
  function computeScores(D) {
    var latest = (D.latest_chart && D.latest_chart.entries) || [];
    var hist = D.chart_history || [];
    var times = [], days = [];
    hist.forEach(function (r) {
      if (times.indexOf(r.chart_time) < 0) times.push(r.chart_time);
      var d = r.chart_time.slice(0, 10);
      if (days.indexOf(d) < 0) days.push(d);
    });
    times.sort();
    var nSnap = times.length, nDays = days.length;
    var persistOn = nDays >= CFG.minDays;

    var names = [];
    latest.concat(hist).forEach(function (r) { if (names.indexOf(r.artist) < 0) names.push(r.artist); });

    var rows = names.map(function (a) {
      var now = latest.filter(function (e) { return e.artist === a; });
      var best = now.reduce(function (m, e) { return e.score > m.score ? e : m; }, { score: 0 });
      var o = { artist: a, songs: now.slice().sort(function (x, y) { return x.rank - y.rank; }), best: best.score ? best : null, axes: {} };

      /* ① 현재 화제성: 현재 TOP20 최고곡의 한터 음원 지수 (1위=10,000 -> 100점) */
      if (o.best) {
        o.axes.hot = { v: clamp(o.best.score / 100), why: "현재 최고곡 '" + o.best.title + "' " + o.best.rank + '위 · 지수 ' + fmt(o.best.score, 2) + ' ÷ 100' };
      } else {
        o.axes.hot = { v: 0, why: '현재 TOP 20 밖 (0점 처리)' };
      }

      /* ② 지속력: 관측 기간 중 TOP20 체류율 60% + 최고점 대비 현재 지수 40% */
      var present = 0, peak = 0;
      times.forEach(function (t) {
        var rs = hist.filter(function (r) { return r.chart_time === t && r.artist === a; });
        if (rs.length) { present++; peak = Math.max(peak, Math.max.apply(null, rs.map(function (r) { return r.score; }))); }
      });
      var presence = nSnap ? present / nSnap : 0;
      var retention = peak > 0 ? Math.min(1, (o.best ? o.best.score : 0) / peak) : 0;
      o.presence = presence; o.present = present;
      if (persistOn) {
        o.axes.persist = { v: clamp(100 * (0.6 * presence + 0.4 * retention)), why: '체류율 ' + fmt(presence * 100, 0) + '% (' + present + '/' + nSnap + '회) · 최고점 대비 ' + fmt(retention * 100, 0) + '%' };
      } else {
        o.axes.persist = { v: null, why: '관측 ' + nDays + '일치 (최소 ' + CFG.minDays + '일 필요). 참고: 오늘 체류 ' + present + '/' + nSnap + '회' };
      }

      /* ③ 대중 확장성: 실제 Google Trends 연결 전에는 계산하지 않음 (D.search_trends 는 읽지 않는다) */
      o.axes.expand = { v: null, why: '실검색 데이터 필요 (현재 샘플 데이터만 존재)' };

      /* ④ IP 포트폴리오: 동시 진입곡 수 50% + 곡 간 지수 분산도 50% */
      var n = now.length;
      if (n) {
        var sum = now.reduce(function (s, e) { return s + e.score; }, 0);
        var share = best.score / sum;
        var cnt = Math.min(n, CFG.portfolioCap) / CFG.portfolioCap * 100;
        var div = n > 1 ? (1 - share) / (1 - 1 / n) * 100 : 0;
        o.axes.portfolio = { v: clamp(0.5 * cnt + 0.5 * div), why: '진입곡 ' + n + '곡 · 최고곡 지수 비중 ' + fmt(share * 100, 0) + '%' };
      } else {
        o.axes.portfolio = { v: 0, why: '현재 진입곡 없음' };
      }

      /* ⑤ 팬덤 구매력 / ⑥ 리스크: 점수 없음 */
      o.axes.fandom = { v: null, why: '음반·굿즈·콘서트 데이터 필요' };
      o.axes.risk = { v: null, why: '' };

      /* 종합(잠정): 값이 있는 축만 가중치 재정규화 */
      var wsum = 0, acc = 0;
      AXES.forEach(function (ax) {
        var v = o.axes[ax.id].v;
        if (ax.weight && v != null) { wsum += ax.weight; acc += ax.weight * v; }
      });
      o.composite = wsum ? acc / wsum : null;
      return o;
    });

    var totalW = AXES.reduce(function (s, a) { return s + a.weight; }, 0);
    var liveW = AXES.reduce(function (s, a) {
      var on = a.id === 'hot' || a.id === 'portfolio' || (a.id === 'persist' && persistOn);
      return s + (on ? a.weight : 0);
    }, 0);
    rows.sort(function (x, y) { return (y.composite || 0) - (x.composite || 0) || y.axes.hot.v - x.axes.hot.v; });
    return { rows: rows, nSnap: nSnap, nDays: nDays, persistOn: persistOn, coverage: liveW / totalW, liveW: liveW, totalW: totalW,
             chartTime: D.latest_chart ? D.latest_chart.chart_time : null };
  }

  /* ---------- 리스크: 근거 -> 신호등 ---------- */
  var WORD_NUM = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
                   first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6, seventh: 7, eighth: 8, ninth: 9 };
  /* 한국어 고유어 숫자와 상대 연도 표현: 환산 규칙을 코드에 명시해 둔다 */
  var KO_NUM = { '하루': 1, '이틀': 2, '사흘': 3, '나흘': 4, '닷새': 5 };
  var REL_YEAR = { '재작년': -2, '지난해': -1, '작년': -1, '올해': 0, '내년': 1 };
  var MONTH_NUM = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };

  function digitRuns(s) {
    var m = String(s || '').match(/\d+/g) || [];
    return m.map(function (x) { return String(parseInt(x, 10)); });
  }
  function contextNumbers(f) {
    var out = [], p = String(f.published || '');
    var parts = p.match(/\d+/g) || [];
    parts.forEach(function (x) { out.push(String(parseInt(x, 10))); });
    var low = String(f.quote || '').toLowerCase();
    Object.keys(WORD_NUM).forEach(function (w) { if (new RegExp('\\b' + w + '\\b').test(low)) out.push(String(WORD_NUM[w])); });
    Object.keys(MONTH_NUM).forEach(function (m) { if (new RegExp('\\b' + m + '[a-z]*\\.?\\s', 'i').test(f.quote || '')) out.push(String(MONTH_NUM[m])); });
    Object.keys(KO_NUM).forEach(function (w) { if ((f.quote || '').indexOf(w) >= 0) out.push(String(KO_NUM[w])); });
    var py = parseInt(p.slice(0, 4), 10);
    if (py) Object.keys(REL_YEAR).forEach(function (w) { if ((f.quote || '').indexOf(w) >= 0) out.push(String(py + REL_YEAR[w])); });
    (f.numbers_ok || []).forEach(function (x) { out.push(String(parseInt(x, 10))); });
    return out;
  }
  /* 근거 문장(text, short)의 숫자는 모두 원문 인용문(quote), 기사 발행일, 영문 숫자 표기, 또는 명시 허용(numbers_ok) 안에 있어야 한다 */
  function traceNumbers(f) {
    var allowed = digitRuns(f.quote).concat(contextNumbers(f));
    var bad = [];
    digitRuns((f.text || '') + ' ' + (f.short || '')).forEach(function (n) { if (allowed.indexOf(n) < 0 && bad.indexOf(n) < 0) bad.push(n); });
    return bad;
  }

  function isUsable(f) {
    return f.type !== 'absence' && f.verified && f.verified !== 'none' && !!f.quote;
  }
  /* 신호등 규칙: 검증된 critical -> 경고, 검증된 caution -> 주의, 검증된 ok -> 양호, 그 외 -> 확인 필요 */
  function deriveSignal(findings) {
    var c = { critical: 0, caution: 0, ok: 0, info: 0, ignored: 0 };
    (findings || []).forEach(function (f) {
      if (!isUsable(f)) { c.ignored++; return; }
      if (c[f.severity] != null) c[f.severity]++;
    });
    var signal = c.critical ? 'red' : c.caution ? 'yellow' : c.ok ? 'green' : 'gray';
    return { signal: signal, counts: c };
  }
  var SEV_RANK = { critical: 3, caution: 2, ok: 1, info: 0 };
  function headline(findings) {
    var u = (findings || []).filter(isUsable).sort(function (a, b) { return SEV_RANK[b.severity] - SEV_RANK[a.severity]; });
    var top = u.filter(function (f) { return f.severity === 'critical' || f.severity === 'caution'; });
    var pick = (top.length ? top : u).slice(0, 2).map(function (f) { return f.short; });
    return pick.length ? pick.join(' · ') : '근거로 쓸 수 있는 검증된 기사를 찾지 못했습니다';
  }
  function evaluateRisk(RISK) {
    var out = {};
    if (!RISK || !RISK.artists) return out;
    Object.keys(RISK.artists).forEach(function (name) {
      var a = RISK.artists[name];
      var d = deriveSignal(a.findings);
      out[name] = { signal: d.signal, counts: d.counts, declared: a.declared_signal, mismatch: a.declared_signal !== d.signal, summary: headline(a.findings) };
    });
    return out;
  }

  /* ---------- 장부: 모든 숫자의 출처 ---------- */
  function round1(v) { return v == null ? null : Math.round(v * 10) / 10; }
  function buildLedger(R, riskEval) {
    var facts = [];
    function add(id, value, formula, inputs) { facts.push({ id: id, value: value, formula: formula, inputs: inputs || null }); }
    add('meta.chart_time', R.chartTime, '한터 실시간 음원차트 집계 기준 시각');
    add('meta.snapshots', R.nSnap, '스냅샷 수');
    add('meta.days', R.nDays, '관측 일수');
    add('meta.coverage_pct', round1(R.coverage * 100), '반영된 축 가중치 ÷ 전체 가중치 × 100', { liveW: R.liveW, totalW: R.totalW });
    R.rows.forEach(function (o) {
      add('score.' + o.artist + '.composite', round1(o.composite), '반영 가능한 축의 가중평균', null);
      AXES.forEach(function (ax) {
        if (ax.id === 'risk' || ax.id === 'expand' || ax.id === 'fandom') return;
        add('score.' + o.artist + '.' + ax.id, round1(o.axes[ax.id].v), o.axes[ax.id].why, null);
      });
      add('score.' + o.artist + '.songs', o.songs.length, '현재 TOP 20 진입곡 수');
      if (riskEval[o.artist]) add('risk.' + o.artist + '.signal', riskEval[o.artist].signal, '검증된 근거의 최고 심각도');
    });
    return facts;
  }

  return { CFG: CFG, AXES: AXES, SEVERITIES: SEVERITIES, VERIFIED_LEVELS: VERIFIED_LEVELS, fmt: fmt,
           computeScores: computeScores, deriveSignal: deriveSignal, headline: headline, evaluateRisk: evaluateRisk,
           traceNumbers: traceNumbers, isUsable: isUsable, buildLedger: buildLedger, digitRuns: digitRuns };
});

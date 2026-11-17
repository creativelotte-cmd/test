/* Jesictify · 화면 내 자동 검증 (엔진과 별도로 다시 구현한 독립 계산)
 * 페이지를 열 때마다: 점수 재계산 · 범위 · 검색 데이터 격리 · 신호등 규칙 · 근거 숫자 추적을 확인합니다.
 * 실패하면 점수(numBad) 또는 해당 팀 신호등(riskBad)을 화면에서 끕니다. */
(function () {
  'use strict';
  var TOL = 0.05;
  function derive(fs) {
    var c = 0, y = 0, g = 0;
    (fs || []).forEach(function (f) {
      if (f.type === 'absence' || !f.verified || f.verified === 'none' || !f.quote) return;
      if (f.severity === 'critical') c++; else if (f.severity === 'caution') y++; else if (f.severity === 'ok') g++;
    });
    return c ? 'red' : y ? 'yellow' : g ? 'green' : 'gray';
  }
  function run(D, R, RISK, RISKEVAL) {
    var E = window.EumwonScore, fails = [], total = 0, riskBad = {}, numBad = false;
    function chk(ok, msg, isNum) { total++; if (!ok) { fails.push(msg); if (isNum) numBad = true; } }
    var latest = (D.latest_chart && D.latest_chart.entries) || [];
    /* 1) 화제성/포트폴리오/종합 독립 재계산 */
    R.rows.forEach(function (o) {
      var now = latest.filter(function (e) { return e.artist === o.artist; });
      var best = now.reduce(function (m, e) { return Math.max(m, e.score); }, 0);
      var hot = best ? best / 100 : 0;
      chk(Math.abs(hot - o.axes.hot.v) <= TOL, o.artist + ' 화제성 불일치', true);
      var n = now.length, sum = now.reduce(function (s, e) { return s + e.score; }, 0), top = best;
      var even = n > 1 ? (1 - top / sum) / (1 - 1 / n) * 100 : 0;
      var pf = 0.5 * (Math.min(n, 4) / 4 * 100) + 0.5 * even;
      chk(n === 0 || Math.abs(pf - o.axes.portfolio.v) <= TOL, o.artist + ' 포트폴리오 불일치', true);
      ['hot', 'persist', 'portfolio'].forEach(function (k) { var v = o.axes[k].v; chk(v == null || (v >= 0 && v <= 100), o.artist + ' ' + k + ' 범위 이탈', true); });
      var w = { hot: 25, persist: 20, portfolio: 15 }, a = 0, s2 = 0;
      Object.keys(w).forEach(function (k) { var v = o.axes[k].v; if (v != null) { a += w[k] * v; s2 += w[k]; } });
      chk(o.composite == null || (s2 && Math.abs(a / s2 - o.composite) <= TOL), o.artist + ' 종합 불일치', true);
      chk(o.axes.expand.v == null && o.axes.fandom.v == null, o.artist + ' 데이터 없는 축에 값이 있음', true);
    });
    /* 2) 검색 데이터 격리: 값을 바꿔도 점수가 같아야 함 */
    var D2 = JSON.parse(JSON.stringify(D));
    if (D2.search_trends) D2.search_trends.forEach(function (r) { r.interest = 9999; });
    var R2 = E.computeScores(D2);
    chk(JSON.stringify(R2.rows.map(function (o) { return [o.artist, o.composite]; })) === JSON.stringify(R.rows.map(function (o) { return [o.artist, o.composite]; })), '검색 데이터가 점수에 영향을 줌', true);
    /* 3) 리스크: 신호 규칙 + 숫자 추적 */
    if (RISK && RISK.artists) Object.keys(RISK.artists).forEach(function (name) {
      var a = RISK.artists[name], bad = [];
      var d = derive(a.findings);
      if (d !== a.declared_signal) bad.push('선언 ' + a.declared_signal + ' ≠ 규칙 ' + d);
      if (RISKEVAL[name] && RISKEVAL[name].signal !== d) bad.push('엔진 ≠ 독립 규칙');
      (a.findings || []).forEach(function (f) {
        if (f.type === 'absence') return;
        if (!f.quote) bad.push(f.id + ' 인용문 없음');
        else if (E.traceNumbers) { var t = E.traceNumbers(f); if (t && t.length) bad.push(f.id + ' 추적 불가 숫자 ' + t.join(',')); }
        if (!/^https:\/\//.test(f.url || '')) bad.push(f.id + ' 출처 URL');
      });
      chk(!bad.length, name + ': ' + bad.join('; '), false);
      if (bad.length) riskBad[name] = bad.join('; ');
    });
    return { ok: !fails.length, total: total, passed: total - fails.length, fails: fails, numBad: numBad, riskBad: riskBad };
  }
  window.EumwonVerify = { run: run };
})();

/* Jesictify · IP 사업화 분석 (v0.1)
 * 목적: K-POP IP로 상품/유통을 출시하려는 기업의 의사결정 보조.
 * 원칙: (1) 실데이터가 있는 축만 점수에 반영 (2) source=sample 데이터는 사용하지 않음
 *       (3) 데이터가 없는 축은 추정하지 않고 '대기/확인 필요'로 표시
 * 입력: window.EUMWON_DATA (web/data.js, scripts/build-data.ps1이 매시간 갱신)
 */
(function () {
  'use strict';

  var E = window.EumwonScore;   /* 숫자를 만드는 유일한 경로: score-engine.js */
  if (!E) { document.getElementById('ipBody').innerHTML = '<tr><td colspan="8" class="empty">score-engine.js 를 불러오지 못해 분석을 중단했습니다 (숫자는 엔진에서만 생성됩니다).</td></tr>'; return; }
  var CFG = E.CFG, AXES = E.AXES;

  /* ⑥ 사업 리스크: data/risk.json → web/risk-data.js (웹 조사 결과, 점수에는 포함하지 않음) */
  var RISK = window.IP_RISK || null;
  var RISKEVAL = E.evaluateRisk(RISK);   /* 신호등은 근거에서 규칙으로 계산 (선언값 무시) */
  var VERDICT = { ok: true, fails: [] };  /* verify-live.js 가 채움 */
  var SIG = {
    green:  { label: '양호',      cls: 'g' },
    yellow: { label: '주의',      cls: 'y' },
    red:    { label: '경고',      cls: 'r' },
    gray:   { label: '확인 필요', cls: 'n' }
  };
  function riskOf(name) { return RISK && RISK.artists && RISK.artists[name] ? RISK.artists[name] : null; }
  function sigHtml(name) {
    var r = riskOf(name);
    if (!r) return '<span class="sig n"><i></i>미조사</span>';
    var ev = RISKEVAL[name]; var sg = ev ? ev.signal : 'gray';
    if (VERDICT.riskBad && VERDICT.riskBad[name]) return '<span class="sig n" title="검증 실패: ' + esc(VERDICT.riskBad[name]) + '"><i></i>검증 실패</span>';
    var s = SIG[sg] || SIG.gray;
    return '<span class="sig ' + s.cls + '" title="' + esc(ev ? ev.summary : '') + '"><i></i>' + s.label + '</span>';
  }
  function safeUrl(u) { return /^https:\/\//.test(u) ? u : '#'; }

  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  var fmt = E.fmt;
  var clamp = function (v) { return Math.max(0, Math.min(100, v)); };
  var fmtTime = function (iso) { return iso ? iso.slice(0, 16).replace('T', ' ') : '-'; };

  var compute = E.computeScores;

  /* ---------- 화면 ---------- */
  function renderBadge() {
    var el = $('ipVerify'); if (!el) return;
    var v = VERDICT;
    el.className = 'ip-verify ' + (v.ok ? 'ok' : 'bad');
    el.innerHTML = v.ok
      ? '<b>✓ 자동 검증 통과</b> · ' + v.passed + '/' + v.total + '건 (점수 재계산 · 신호등 규칙 · 숫자 추적). 근거는 <b>추출 확인</b> 단계이며 원문 대조는 별도 도구에서 합니다.'
      : '<b>⚠ 검증 실패 ' + v.fails.length + '건</b> · ' + v.fails.slice(0, 3).map(esc).join(' / ') + (v.numBad ? ' · 점수 표시를 중단했습니다' : ' · 해당 팀 신호등을 비활성화했습니다');
  }

  function axisStatus(ax, R) {
    if (ax.id === 'hot' || ax.id === 'portfolio') return ['live', '반영 중'];
    if (ax.id === 'persist') return R.persistOn ? ['live', '반영 중'] : ['wait', '대기 ' + R.nDays + '/' + CFG.minDays + '일'];
    if (ax.id === 'risk') {
      if (!RISK) return ['manual', '수동 조사'];
      var done = R.rows.filter(function (r) { var k = riskOf(r.artist); return k && RISKEVAL[r.artist] && RISKEVAL[r.artist].signal !== 'gray'; }).length;
      return [done === R.rows.length ? 'live' : 'wait', '조사 ' + done + '/' + R.rows.length + '팀'];
    }
    return ['wait', '데이터 대기'];
  }
  var AX_NEED = {
    hot: '한터 음원 지수 (확보됨)',
    persist: '일간 스냅샷 ' + CFG.minDays + '일 이상 누적',
    expand: '실제 Google Trends 연결',
    portfolio: '한터 음원 지수 (확보됨)',
    fandom: '음반 차트·굿즈·콘서트 데이터',
    risk: RISK ? '웹 조사 ' + esc(RISK.meta.checked_at) + ' 기준 · 신호등 + 원문 링크' : '웹 조사 후 신호등 + 원문 링크'
  };

  function coverHtml(e, cls) {
    var ch = esc((e.artist || '?').trim().charAt(0));
    var h = 0; String(e.artist).split('').forEach(function (c) { h = (h * 31 + c.charCodeAt(0)) % 360; });
    var ph = 'background:linear-gradient(135deg,hsl(' + h + ' 45% 38%),hsl(' + ((h + 40) % 360) + ' 45% 22%))';
    if (e.album_id && window.__coverFail) {
      return '<img class="' + cls + '" src="https://resource.hanteochart.io/album/' + encodeURIComponent(e.album_id) + '_s150.jpg" alt="" loading="lazy" referrerpolicy="no-referrer" data-ph="' + ph + '" data-ch="' + ch + '" onerror="__coverFail(this)">';
    }
    return '<div class="' + cls + ' ph" style="' + ph + '">' + ch + '</div>';
  }
  var cell = function (ax) { return ax.v == null ? '<span class="num" title="' + esc(ax.why) + '">–</span>' : '<span class="num" title="' + esc(ax.why) + '">' + fmt(ax.v, 0) + '</span>'; };

  function render(D) {
    var R = compute(D);
    if (window.EumwonVerify) { VERDICT = window.EumwonVerify.run(D, R, RISK, RISKEVAL); RISKEVAL = E.evaluateRisk(RISK); }
    if (VERDICT.numBad) R.rows.forEach(function (o) { o.composite = null; });
    renderBadge();
    var covPct = fmt(R.coverage * 100, 0);

    $('ipMeta').innerHTML = '<b>Jesictify</b> · 집계 기준 <b>' + esc(fmtTime(D.latest_chart.chart_time)) + '</b> (KST) · 스냅샷 <b>' + R.nSnap + '</b>회 (' + R.nDays + '일치) · 대상 <b>' + R.rows.length + '</b>팀';
    $('ipNotice').innerHTML = '<b>잠정 점수</b> · 현재 실데이터가 있는 축만 반영합니다 (가중치 기준 <b>' + covPct + '%</b> 충족). ' +
      '데이터가 없는 축은 추정하지 않고 비워 두며, 검색 관심도는 샘플 데이터라 사용하지 않습니다.';

    $('ipAxes').innerHTML = AXES.map(function (ax) {
      var st = axisStatus(ax, R);
      return '<div class="card"><div class="k">' + ax.no + ' ' + esc(ax.name) + (ax.weight ? ' · 가중치 ' + ax.weight + '%' : ' · 점수 제외') + '</div>' +
        '<div class="v"><span class="chip ' + st[0] + '">' + esc(st[1]) + '</span></div>' +
        '<div class="s" title="' + esc(AX_NEED[ax.id]) + '">' + esc(AX_NEED[ax.id]) + '</div></div>';
    }).join('');

    $('ipBody').innerHTML = R.rows.map(function (o, i) {
      var cov = o.best || { artist: o.artist, album_id: '' };
      return '<tr data-i="' + i + '" tabindex="0">' +
        '<td class="c-rank">' + (i + 1) + '</td>' +
        '<td><div class="track">' + coverHtml(cov, 'cover') + '<div class="t-text"><div class="t-title" title="' + esc(o.artist) + '">' + esc(o.artist) + '</div>' +
        '<div class="t-artist">' + (o.best ? esc(o.best.title) : 'TOP 20 밖') + '</div></div></div></td>' +
        '<td class="c-score"><span class="num"><b style="color:var(--ink-1)">' + (o.composite == null ? '–' : fmt(o.composite, 1)) + '</b></span><div class="bar"><i style="width:' + (o.composite || 0).toFixed(1) + '%"></i></div></td>' +
        '<td class="c-ax">' + cell(o.axes.hot) + '</td>' +
        '<td class="c-ax">' + cell(o.axes.persist) + '</td>' +
        '<td class="c-ax">' + cell(o.axes.portfolio) + '</td>' +
        '<td class="c-ax"><span class="num">' + o.songs.length + '</span></td>' +
        '<td class="c-sig">' + sigHtml(o.artist) + '</td></tr>';
    }).join('');

    var rows = Array.prototype.slice.call(document.querySelectorAll('#ipBody tr'));
    function pick(i) {
      rows.forEach(function (r) { r.classList.toggle('on', +r.dataset.i === i); });
      detail(R, R.rows[i], i);
    }
    rows.forEach(function (tr) {
      tr.addEventListener('click', function () { pick(+tr.dataset.i); });
      tr.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); pick(+tr.dataset.i); } });
    });
    if (R.rows.length) pick(0);

    $('ipFoot').innerHTML =
      '<b>산식</b> (모든 값 0~100)<br>' +
      '① 화제성 = 현재 TOP 20 최고곡의 한터 음원 지수 ÷ 100 · 한터 지수는 1위가 항상 10,000인 <b>1위 대비 상대값</b>이므로 절대 청취량이 아닙니다<br>' +
      '② 지속력 = 체류율 60% + 최고점 대비 현재 지수 40% · 관측 ' + CFG.minDays + '일 이상일 때만 산출<br>' +
      '④ 포트폴리오 = 동시 진입곡 수(' + CFG.portfolioCap + '곡 만점) 50% + 곡 간 지수 분산도 50%<br>' +
      '종합(잠정) = 값이 있는 축의 가중평균 (가중치 ①25 ②20 ③15 ④15 ⑤25 중 반영 가능한 축만 재정규화)<br>' +
      (RISK
        ? '⑥ 리스크는 점수에 넣지 않고 웹 조사 결과를 신호등으로 따로 표시합니다 (' + esc(RISK.meta.checked_at) + ' 기준). ' +
          '양호: ' + esc(RISK.meta.rubric.green) + ' · 주의: ' + esc(RISK.meta.rubric.yellow) + ' · 경고: ' + esc(RISK.meta.rubric.red) + ' · 확인 필요: ' + esc(RISK.meta.rubric.gray) + '<br>' + esc(RISK.meta.disclaimer)
        : '⑥ 리스크는 점수에 넣지 않고 별도 조사 결과(신호등 + 원문 링크)로 표시할 예정입니다.') +
      '<br>이 화면은 투자·제휴 판단의 참고 자료이며 결론을 대신하지 않습니다.';
  }

  function detail(R, o, i) {
    var rows = AXES.map(function (ax) {
      var a = o.axes[ax.id];
      var st = axisStatus(ax, R);
      var val = ax.id === 'risk' ? sigHtml(o.artist) : a.v == null ? '<span class="chip ' + st[0] + '">' + esc(st[1]) + '</span>' : '<b class="num" style="color:var(--ink-1)">' + fmt(a.v, 1) + '</b>';
      var bar = a.v == null ? '' : '<div class="bar"><i style="width:' + a.v.toFixed(1) + '%"></i></div>';
      return '<div class="ax-row"><div class="ax-h"><span>' + ax.no + ' ' + esc(ax.name) + '</span>' + val + '</div>' + bar + '<div class="ax-why">' + esc(a.why) + '</div></div>';
    }).join('');
    $('ipDetail').innerHTML =
      '<div class="now-in"><div class="now-h">IP 상세<span>잠정 · 충족도 ' + fmt(R.coverage * 100, 0) + '%</span></div>' +
      coverHtml(o.best || { artist: o.artist }, 'now-art').replace('loading="lazy" ', '') +
      '<div class="now-title">' + esc(o.artist) + '</div>' +
      '<span class="now-rank">종합(잠정) ' + (o.composite == null ? '-' : fmt(o.composite, 1)) + ' · ' + (i + 1) + '위 / ' + R.rows.length + '팀</span>' +
      '<div class="box"><div class="box-t">축별 점수와 근거</div><div class="box-s">모든 수치는 한터차트 실시간 음원차트 기준</div>' + rows + '</div>' +
      riskBox(o.artist) +
      '<div class="box"><div class="box-t">현재 TOP 20 진입곡 · ' + o.songs.length + '곡</div><ul class="songs">' +
      (o.songs.length ? o.songs.map(function (s) { return '<li><span>' + s.rank + '위 · ' + esc(s.title) + '</span><span class="num">' + fmt(s.score, 2) + '</span></li>'; }).join('') : '<li><span>진입곡 없음</span></li>') +
      '</ul></div></div>';
  }

  function riskBox(name) {
    var r = riskOf(name);
    if (!r) return '<div class="box"><div class="box-t">⑥ 사업 리스크</div><div class="box-s">아직 조사하지 않았습니다</div></div>';
    var LV = { raw: '원문 대조', extract: '추출 확인', none: '미검증' };
    var fl = (r.findings || []).map(function (x) {
      var use = E.isUsable(x);
      var tag = x.type === 'absence' ? '못 찾음 (근거 아님)' : (LV[x.verified] || '미검증');
      return '<li class="rk' + (use ? '' : ' rk-off') + '"><div class="rk-k">' + esc(x.kind) + ' · <span title="신호등 계산에 ' + (use ? '반영' : '제외') + '">' + esc(tag) + '</span></div><div>' + esc(x.text) + '</div>' +
        (x.quote ? '<div class="rk-q">“' + esc(x.quote) + '”</div>' : '') +
        (x.url ? '<a class="rk-src" href="' + esc(safeUrl(x.url)) + '" target="_blank" rel="noopener noreferrer">' + esc(x.source) + (x.published ? ' · ' + esc(x.published) : '') + '</a>' : '') + '</li>';
    }).join('');
    var tv = (r.to_verify || []).map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('');
    return '<div class="box"><div class="box-t">⑥ 사업 리스크 ' + sigHtml(name) + '</div>' +
      '<div class="box-s">웹 조사 ' + esc(RISK.meta.checked_at) + ' 기준 · 소속사: ' + esc(r.agency) + '</div>' +
      '<div class="rk-sum">' + esc(RISKEVAL[name] ? RISKEVAL[name].summary : '') + '</div>' +
      (fl ? '<ul class="rk-list">' + fl + '</ul>' : '<div class="box-s">근거로 쓸 만한 기사를 찾지 못했습니다</div>') +
      (tv ? '<div class="rk-vt"><b>계약 전 확인할 것</b><ul>' + tv + '</ul></div>' : '') + '</div>';
  }

  /* ---------- 화면 전환 (#ip ↔ 기존 홈) ---------- */
  function route() {
    var ip = location.hash === '#ip';
    $('viewHome').hidden = ip; $('viewIp').hidden = !ip;
    $('detail').hidden = ip; $('ipDetail').hidden = !ip;
    Array.prototype.forEach.call(document.querySelectorAll('.nav a'), function (a) { a.classList.remove('on'); });
    var on = document.querySelector(ip ? '.nav a[href="#ip"]' : '.nav a[href="#top"]');
    if (on) on.classList.add('on');
    if (ip) window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);

  var D = window.EUMWON_DATA;
  if (D && D.latest_chart && D.latest_chart.entries && D.latest_chart.entries.length) {
    render(D);
  } else {
    $('ipBody').innerHTML = '<tr><td colspan="8" class="empty">아직 수집된 데이터가 없습니다. scripts/run-all.ps1 을 실행하세요.</td></tr>';
  }
  route();
})();

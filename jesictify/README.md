# 음원 데일리

한터차트 실시간 음원차트 TOP 20과 가수·곡별 구글 검색 관심도를 함께 보는 페이지입니다.
추가 설치 없이 Windows 기본 PowerShell 5.1만으로 동작합니다.

## 구성

| 경로 | 역할 |
|---|---|
| `scripts/collect-chart.ps1` | 한터 실시간 차트 1~20위 수집 → `data/chart_snapshots.csv` 누적, 새 가수는 `data/artists.csv`에 등록 |
| `scripts/collect-google.ps1` | Google Trends API 수집기. **승인 대기 중**이라 지금은 건너뜀 (`config/google.json`의 `approved`) |
| `scripts/sample-trends.ps1` | **임시** 샘플 검색 관심도(가수+곡). 실제 구글 데이터가 생기면 자동으로 멈춤 |
| `scripts/build-data.ps1` | CSV를 합쳐 `data/eumwon-daily.json`(분석용)과 `web/data.js`(화면용) 생성 |
| `scripts/run-all.ps1` | 위 단계를 한 번에 실행 (매시간 실행 대상) |
| `scripts/register-task.ps1` | Windows 작업 스케줄러에 매시간 실행 작업 등록 |
| `scripts/serve.ps1` | 미리보기용 로컬 서버 (http://localhost:8765) |
| `web/index.html` | 음원 데일리 화면 (파일을 직접 열어도 동작) |
| `archive/naver/` | 보관용: 네이버 데이터랩 수집기 (개발자센터 신규 등록 중단으로 미사용) |
| `archive/youtube/` | 보관용: 유튜브 조회수 수집기 (API 키 문제로 미사용) |
| `archive/social/` | 보관용: 한터 주간 소셜차트 수집기와 8주치 데이터 (음원 TOP 20 가수와 겹치는 경우가 적어 미사용) |

## 데이터 (클로드/분석툴 연결용)

- `data/chart_snapshots.csv`: chart_time, collected_at, rank, title, artist, score(음원 지수), rank_move, album_id, source
- `data/artists.csv`: artist, search_keyword(검색어, 직접 수정 가능), first_seen, active(Y/N)
- `data/search_trends.csv`: date, target_type(artist/song), artist, title, keyword, geo, interest, source, fetched_at
  - source가 `sample`이면 샘플, `google_trends`이면 실제 데이터
  - 곡 검색어 = "가수 곡명"
- `data/eumwon-daily.json`: 위 데이터를 합친 최신 데이터셋 (최근 7일 차트 이력 포함)

## 실행

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\register-task.ps1
```

작업 삭제: `Unregister-ScheduledTask -TaskName EumwonDaily-Collect -Confirm:$false`

## 참고

- 한터차트 robots.txt는 `/api/`를 막고 있어 공개 HTML 페이지만 읽습니다.
- 구글 검색 관심도는 절대 검색 횟수가 아닌 상대 지수이며, 최신값은 약 2일 늦게 반영됩니다.

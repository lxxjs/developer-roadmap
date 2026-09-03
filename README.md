# WalkArrow

걸을 때 가야 하는 방향만 애플워치에 화살표로 보여주는 도보 내비게이션.

목적지를 정하면 아이폰이 도보 경로를 계산해 워치로 보내고, 워치는 GPS와 나침반으로
**지금 어느 쪽으로 걸어야 하는지**를 화살표 하나와 남은 거리로 표시한다. 지도를 띄우지
않는 것이 요점이다 — 걸으면서 손목에서 읽어야 하는 정보는 방향과 거리뿐이다.

## 왜 네이버지도 플러그인이 아닌가

네이버지도는 서드파티 플러그인이나 확장 API를 제공하지 않는다. 네이버 클라우드
플랫폼의 Directions API도 자동차 경로만 다루고 공개된 도보 경로 엔드포인트가 없다.
그래서 두 가지로 나눴다.

- **목적지 전달**: iOS 공유 시트. 네이버지도에서 장소 → 공유 → WalkArrow.
  네이버가 지원하는 유일한 하드오프 지점이다.
- **경로 계산**: MapKit 도보 경로(`MKDirections`, `transportType = .walking`).
  실제 보행자 경로를 돌려주는, 사용 가능한 선택지다.

공유 링크 포맷은 **비공식**이다. 네이버는 공유 URL 구조를 여러 번 바꿨기 때문에
파서는 아무것도 신뢰하지 않는다: 후보 좌표는 모두 범위 검사를 거치고, 위치가 애매한
파라미터는 한반도 범위 안일 때만 채택하며, 파싱이 실패하면 장소명을 지오코딩하고,
그것도 실패하면 직접 입력으로 떨어진다. 공유 확장은 저장 전에 항상 파싱 결과를
사용자에게 보여준다.

## 구조

```
Sources/Shared/     iOS·워치·확장이 모두 함께 컴파일하는 코드
  Models/           GeoPoint, Destination, WalkRoute
  Geo/              GeoMath, Polyline, RouteTracker   ← 핵심 로직
  Store/            App Group 기반 목적지 저장소
  Sync/             WatchConnectivity 페이로드
  Parsing/          네이버 공유 URL 파서 + 단축링크 해석
Sources/iOS/        아이폰 앱: 경로 계산, 워치 응답, 목적지 관리
Sources/Watch/      워치 앱: 나침반 화면, 위치·헤딩, 햅틱
Sources/Share/      공유 확장
Tests/SharedTests/  Shared 레이어 유닛 테스트
```

### 데이터 흐름

```
네이버지도 ──공유시트──▶ 공유 확장 ──App Group──▶ 목적지 저장소
                                                      │
워치에서 목적지 선택 ──WCSession──▶ 아이폰 앱(백그라운드 웨이크)
                                        │
                                   MKDirections 도보 경로
                                        │
                    ◀──applicationContext── 단순화된 폴리라인
                                        │
                              RouteTracker(워치) ──▶ 화살표 방위각
```

**워치가 요청 주체**라는 점이 중요하다. 워치의 `WCSession` 메시지는 아이폰 앱을
백그라운드에서 깨우기 때문에, 네이버지도에서 장소를 공유한 뒤 아이폰 앱을 한 번도
열지 않고 손목에서 바로 안내를 시작할 수 있다.

### 화살표를 어떻게 정하는가

`RouteTracker`가 GPS 픽스마다 하는 일:

1. 현재 위치를 경로 폴리라인에 투영해 진행 거리를 구한다.
2. 진행 지점에서 **30m 앞**을 조준점으로 잡는다. 회전 지점이 그 안에 들어오면
   회전 지점을 조준한다 — 회전 너머를 조준하면 화살표가 코너 안쪽 건물을 가리킨다.
3. 조준점까지의 방위각에서 나침반 헤딩을 빼서 화살표 회전각을 낸다.

## 알고리즘 설계 근거

세 가지 결정은 구현 전에 수치 실험으로 검증했고, 각각 대응하는 테스트가 있다.

| 결정 | 근거 |
|---|---|
| **전방 탐색 윈도우** (`forwardSearchWindow: 40`) | 3m 간격으로 되돌아오는 U자 경로에 ±5m GPS 노이즈를 넣으면, 경로 전체에서 최근접점을 찾는 방식은 100회 중 42회 진행도를 반대쪽 다리로 오인한다. 전방 윈도우는 0회. → `testProgressDoesNotJumpBackOnADoublingRoute` |
| **조준점 최소 거리** (`minimumAimDistance: 3`) | 도착 지점에서는 조준점과 현재 위치가 같아지고 `atan2(0,0) == 0`이라, 화살표가 도착 직전 정북으로 튄다. 조준점이 3m 안이면 이전 방위각을 유지한다. → `testBearingHoldsSteadyOnArrival` |
| **폴리라인 단순화** (`tolerance: 2m`) | 5m 간격 601점(3km) 경로가 10점 안팎으로 줄고 전체 길이 오차는 수 m 이내. `updateApplicationContext`의 약 262KB 한계에 한참 못 미친다. → `testSimplificationKeepsShapeAndRespectsCap` |
| **단순화 캡은 데시메이션으로 처리** (`tolerance * 4` 상한) | 점 수 캡을 맞추려 tolerance를 무제한 올리면 실제 코너가 지워진다. 정점이 직선에서 20m 벗어난 4km 지그재그는 tolerance 20m를 넘는 순간 **직선 2점으로 붕괴**해서, 화살표가 경로가 아니라 목적지를 가리키게 된다. 상한을 넘으면 균등 데시메이션으로 넘긴다 — 해상도는 낮아지지만 남는 점은 모두 원본 경로 위의 실제 정점이다. → `testSimplificationUnderCapKeepsShapeRatherThanFlattening` |

접평면(local tangent plane) 근사는 세그먼트 단위 계산에만 쓴다. 왕복 오차는 1.8km에서
5cm로, 보행 GPS 노이즈보다 훨씬 작다. → `testLocalOffsetRoundTrips`

그 외 실사용 대응:

- **경로 이탈은 연속 3회 확인 후에만** 인정한다(`offRouteConfirmations: 3`). 한 번의
  튄 픽스로 재탐색을 걸지 않는다. 복귀 판정에는 히스테리시스를 둔다(40m 이탈 / 20m 복귀).
- **GPS 정확도가 나쁘면 이탈 임계값을 넓힌다.** 도심 협곡에서 정확도 60m인 픽스가
  55m 벗어난 것은 노이즈이지 이탈이 아니다.
- **재탐색 쿨다운** 워치 20초 / 아이폰 5초. `MKDirections`는 요청을 스로틀한다.
- **헤딩은 단위벡터 EMA로 평활화**한다. 각도를 직접 평균하면 359°와 1°가 180°로
  평균되어 북쪽을 지날 때마다 화살표가 뒤집힌다.
- **화살표 회전각은 누적한다**(`RotationAccumulator`). SwiftUI `rotationEffect`는 주는
  숫자 사이를 보간하므로, 179° 다음에 -179°를 주면 2°가 아니라 한 바퀴를 돈다.
- **나침반이 없는 기종**(Series 4)에서는 GPS course로 대체한다. 걷는 중에만 의미가
  있어서 UI가 "걸으면 방향이 잡혀요"라고 알린다.

## 빌드

빌드에는 **macOS + Xcode 15 이상**이 필요하다. 프로젝트 파일은 [XcodeGen]으로 생성한다.

```bash
brew install xcodegen
xcodegen generate
open WalkArrow.xcodeproj
```

Xcode에서 한 번만 설정할 것:

1. **서명** — 세 타겟(`WalkArrow`, `WalkArrowShare`, `WalkArrowWatch`) 모두에
   본인 Apple Developer 팀을 지정한다. `project.yml`의 `DEVELOPMENT_TEAM`에 넣어두면
   재생성해도 유지된다.
2. **App Group** — 세 타겟에 `group.com.lxxjs.walkarrow`가 붙어 있는지 확인한다.
   entitlements 파일에는 이미 선언되어 있지만, 개발자 계정에서 그룹을 실제로
   프로비저닝해야 한다. 이게 안 되면 공유 확장이 저장한 목적지가 앱에 보이지 않는다.
3. **번들 ID** — `com.lxxjs.*`를 본인 것으로 바꾸려면 `project.yml`과 세 개의
   `Info.plist`/entitlements에서 함께 바꿔야 한다(워치의 `WKCompanionAppBundleIdentifier`
   는 아이폰 앱 번들 ID와 정확히 일치해야 한다).

테스트는 Xcode 없이도 돌 수 있다:

```bash
swift test          # Shared 레이어만 (macOS)
```

Xcode에서는 `WalkArrow` 스킴의 `WalkArrowTests`로 같은 테스트가 돈다.

## 실기기에서 확인할 것

시뮬레이터로는 이 앱의 핵심을 검증할 수 없다. 자성 헤딩이 없고 GPS course도 나오지
않기 때문에 화살표가 `isArrowResolved == false` 상태에 머문다. 실제 확인 항목:

- [ ] 워치에서 목적지 선택 → 아이폰 앱을 열지 않은 상태에서 경로가 도착하는지
- [ ] 제자리에서 몸을 돌렸을 때 화살표가 즉시 따라오는지(헤딩 갱신 경로)
- [ ] 코너 20~30m 전에 화살표가 회전 지점을 조준하는지
- [ ] 의도적으로 40m 이상 벗어났을 때 주황색 이탈 표시 + 재탐색이 도는지
- [ ] 손목을 내렸다 올렸을 때(Always On) 화면이 읽히는지
- [ ] 도착 반경 20m 안에서 "도착" + 성공 햅틱

## 현재 한계

- **포그라운드 전용.** 워치 앱이 화면에 있을 때만 위치를 갱신한다. Always On
  디스플레이는 지원하지만, 손목을 내린 채로 백그라운드 안내가 계속되지는 않는다.
  watchOS에서 지속적 백그라운드 위치를 얻는 정식 경로는 `HKWorkoutSession`이고,
  이는 HealthKit 권한과 "운동 기록이 남는다"는 부작용을 동반해서 이번에는 넣지 않았다.
- **네이버 공유 포맷 의존.** 위에 쓴 대로 방어적으로 만들었지만 네이버가 포맷을 바꾸면
  좌표 추출이 깨질 수 있다. 그때도 장소명 지오코딩과 직접 입력 경로는 살아 있다.
- **경로 계산은 MapKit.** 한국 도보 경로 품질은 네이버지도만 못하다. 골목이나 실내
  통로에서 차이가 난다.
- **아이폰이 필요하다.** 워치 단독으로는 경로를 계산하지 못한다.

## 라이선스

MIT. `license` 파일 참조.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen

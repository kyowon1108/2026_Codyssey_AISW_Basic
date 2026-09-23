# B1-1 디자인 기준

## 0. Research Log

- 방향: 사용자가 요청한 토스의 파랑을 포인트 색으로 삼고, 흰 바탕과 넓은 여백으로 간결하게 구성한다. 토스 디자인 시스템의 `blue500`은 `#3182f6`이다. 출처: https://tossmini-docs.toss.im/tds-mobile/foundation/colors/
- 참고: frontend 참고 자료의 `minimalist-skill.md`에서 좁은 본문 폭, 여백, 절제된 장식을 적용했다. `revolut.md`에서는 금융 제품 특유의 명확한 정보 위계와 큰 클릭 영역만 참고했다. 두 브랜드의 로고·문구·레이아웃은 복제하지 않는다.
- 사용자가 제공한 사진이 시각적 중심이므로 별도 생성 이미지는 사용하지 않는다. 학습 과제의 순수 HTML/CSS/JS 제약과 단순한 화면 요청에 맞춘다.

## 1. Atmosphere

담백하고 신뢰감 있는 개인 포트폴리오. 기억에 남는 장면은 푸른 강조 제목 옆에 있는 실제 프로필 사진이다. 방문자는 첫 화면에서 이름과 관심사를 확인하고, 아래에서 경험과 GitHub 프로젝트를 살핀다.

## 2. Color tokens

| 역할 | Light | Dark |
| --- | --- | --- |
| `--color-bg` | `#ffffff` | `#101820` |
| `--color-surface` | `#f9fafb` | `#18232e` |
| `--color-text` | `#191f28` | `#f2f4f6` |
| `--color-muted` | `#4e5968` | `#b0b8c1` |
| `--color-border` | `#e5e8eb` | `#333d4b` |
| `--color-blue` | `#3182f6` | `#64a8ff` |
| `--color-blue-strong` | `#1b64da` | `#90c2ff` |
| `--color-blue-soft` | `#e8f3ff` | `#19304a` |
| `--color-error` | `#d22030` | `#ff8b95` |
| `--color-button` | `#1b64da` | `#1b64da` |
| `--color-button-hover` | `#1957c2` | `#1957c2` |

Blue 500과 neutral 계열은 토스 디자인 시스템을 참고한다. 파랑은 링크·버튼·강조 문구에 집중한다.
작은 버튼 글자의 대비를 위해 버튼 배경에는 더 진한 blue700을 사용한다.

## 3. Typography

- 시스템 한글 산세리프를 사용한다: `-apple-system`, `BlinkMacSystemFont`, `Apple SD Gothic Neo`, `Malgun Gothic`, `sans-serif`.
- Hero: `clamp(2.5rem, 7vw, 5rem)`, 700, line-height 1.18.
- Section heading: `clamp(1.75rem, 4vw, 2.5rem)`, 700.
- Body: 1rem~1.125rem, line-height 1.7. 보조 정보는 0.875rem 이하로 내리지 않는다.

## 4. Spacing and layout

- 기본 간격: 4, 8, 12, 16, 24, 32, 48, 64, 96px.
- 본문 최대 폭: 1120px. 모바일 좌우 여백: 20px.
- 모바일 우선. 768px에서 2열 배치, 1024px에서 여백과 글자 크기를 넓힌다.
- 프로젝트 카드: `repeat(auto-fit, minmax(min(100%, 280px), 1fr))`.

## 5. Primitives and states

| 요소 | 기본 | 상호작용·상태 | 접근성 |
| --- | --- | --- | --- |
| 버튼/링크 | 파란 주 버튼, 테두리 보조 버튼 | hover 밝기, active 이동, focus 윤곽 | 44px 이상 높이 |
| 네비게이션 | 데스크톱 가로, 모바일 접힘 | 메뉴 열림/닫힘, 스크롤 배경 | `aria-expanded`, 키보드 닫기 |
| 프로젝트 카드 | 제목·설명·언어·별 수 | hover 얕은 그림자 | 실제 저장소 링크 |
| 상태 패널 | 프로젝트 로딩/빈/오류 | 오류일 때 재시도 | `aria-live` |
| 폼 필드 | 레이블·입력·에러 문구 | 입력 중 검증, 제출 결과 | `for`/`id`, `aria-invalid` |

## 6. Motion

- 버튼과 카드: 180ms. 메뉴: 220ms. 섹션 등장: 500ms.
- 전환은 `opacity`, `transform`을 중심으로 한다.
- IntersectionObserver 임계값: 0.2. `prefers-reduced-motion`이면 등장 효과와 부드러운 스크롤을 해제한다.

## 7. Depth

- 표면은 흰색/밝은 회색의 단계와 1px 경계로 구분한다.
- 카드에만 매우 얕은 그림자를 둔다. 프로필 사진은 원본의 1672×941 비율과 전체 화면을 유지하며 크롭하거나 모서리를 자르지 않는다.

## 8. Accessibility and accepted debt

- WCAG AA 수준의 대비, 키보드 초점 표시, 의미 있는 이미지 대체 텍스트, 폼 오류 연결을 지향한다.
- 현재 허용된 디자인 부채는 없다.

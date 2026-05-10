---
name: research-report
description: 웹 검색을 통해 정보를 수집하고, 체계적인 리서치 보고서를 작성합니다. 사용자가 특정 주제에 대한 조사, 리서치, 보고서 작성을 요청할 때 사용합니다.
allowed-tools: search_web write_file
metadata:
  display-name: Research Report Generator
  status: active
---

# Skill: Research Report Generator

## Purpose

사용자가 특정 주제에 대한 조사를 요청할 때, 웹 검색을 통해 다양한 소스에서 정보를 수집하고, 이를 체계적으로 정리한 리서치 보고서를 작성합니다.

## Workflow

### Step 1: 주제 분석 및 검색 계획 수립

사용자의 요청을 분석하여 조사해야 할 핵심 질문들을 도출합니다:

- 주제의 핵심 개념은 무엇인가?
- 어떤 측면들을 조사해야 하는가?
- 어떤 검색 키워드가 효과적일까?

### Step 2: 정보 수집 (search_web 활용)

다양한 관점에서 정보를 수집합니다:

1. 기본 개념/정의 검색
2. 최신 트렌드/뉴스 검색
3. 전문가 의견/연구 자료 검색
4. 비교 분석/대안 검색 (필요시)

**중요**: 각 검색 결과의 출처를 기록해두세요.

### Step 3: 정보 분석 및 구조화

수집한 정보를 다음 기준으로 분석합니다:

- 신뢰성: 출처의 권위와 정확성
- 관련성: 요청된 주제와의 연관성
- 최신성: 정보의 시점
- 다양성: 여러 관점 포함 여부

### Step 4: 보고서 작성

다음 구조로 보고서를 작성합니다:

```markdown
# [주제] 리서치 보고서

## 개요
[주제에 대한 간략한 소개 및 조사 범위]

## 핵심 발견사항
### 1. [첫 번째 핵심 발견]
[상세 설명]

### 2. [두 번째 핵심 발견]
[상세 설명]

## 분석
[발견사항들에 대한 종합적 분석]

## 결론 및 제언
[핵심 요약 및 추천 사항]

## 참고 자료
- [출처 1]
- [출처 2]
```

### Step 5: 파일 저장 (선택적)

사용자가 파일 저장을 요청한 경우:

- write_file 도구를 사용하여 보고서를 마크다운 파일로 저장
- 파일명 형식: `research_[주제]_[날짜].md`

## Input Schema

이 스킬은 다음과 같은 형태의 입력을 기대합니다:

```json
{
  "topic": "조사할 주제 (필수)",
  "depth": "basic | detailed | comprehensive (선택, 기본값: detailed)",
  "aspects": ["특정 측면들"] (선택),
  "save_to_file": true | false (선택, 기본값: false)
}
```

## Output Format

최종 출력은 다음을 포함해야 합니다:

- 마크다운 형식의 구조화된 보고서
- 최소 3개 이상의 신뢰할 수 있는 출처
- 명확한 결론 및 요약

## Examples

### Example 1: 기술 트렌드 조사

**사용자 요청**: "2024년 AI 에이전트 트렌드에 대해 조사해줘"

**실행 흐름**:

1. search_web("2024 AI agent trends")
2. search_web("autonomous AI agents applications")
3. search_web("AI agent frameworks comparison 2024")
4. 정보 종합 및 보고서 작성

**예상 출력**:

```markdown
# 2024년 AI 에이전트 트렌드 리서치 보고서

## 개요
AI 에이전트는 자율적으로 작업을 수행할 수 있는 지능형 시스템으로...

## 핵심 발견사항
### 1. 멀티 에이전트 시스템의 부상
여러 에이전트가 협력하여 복잡한 작업을 수행하는 패러다임이...

### 2. Tool Use의 표준화
OpenAI Function Calling, Claude Tool Use 등...

## 참고 자료
- [출처 URL 1]
- [출처 URL 2]
```

### Example 2: 비교 분석 조사

**사용자 요청**: "Elixir와 Go의 동시성 모델을 비교 분석해줘"

**실행 흐름**:

1. search_web("Elixir concurrency model BEAM")
2. search_web("Go goroutines concurrency")
3. search_web("Elixir vs Go concurrency comparison")
4. 비교 분석 테이블 포함 보고서 작성

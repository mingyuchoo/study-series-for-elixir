---
name: firecrawl
description: Firecrawl MCP 도구를 사용하여 웹 페이지를 스크래핑, 크롤링, 검색합니다. 사용자가 웹 콘텐츠 수집, 사이트 크롤링, 웹 검색, 구조화된 데이터 추출을 요청할 때 사용합니다.
allowed-tools: mcp__firecrawl__scrape mcp__firecrawl__crawl mcp__firecrawl__map mcp__firecrawl__search mcp__firecrawl__extract
metadata:
  display-name: Firecrawl Web Scraper
  status: active
  mcp-server: firecrawl
---

# Skill: Firecrawl Web Scraper

## Purpose

Firecrawl MCP 서버를 통해 웹 페이지 스크래핑, 사이트 크롤링, 웹 검색, 구조화된 데이터 추출 기능을 제공합니다.

## Prerequisites

이 스킬을 사용하려면 다음이 필요합니다:

1. **Firecrawl API 키**: [https://firecrawl.dev/app/api-keys](https://firecrawl.dev/app/api-keys)에서 발급
2. **환경 변수 설정**: `FIRECRAWL_API_KEY` 환경 변수 설정

## Available Tools

### 1. scrape - 단일 페이지 스크래핑

URL에서 콘텐츠를 추출하여 마크다운으로 변환합니다.

**사용 예시**:

- 뉴스 기사 내용 추출
- 문서 페이지 수집
- 블로그 포스트 읽기

### 2. crawl - 사이트 크롤링

웹사이트 전체 또는 특정 경로를 크롤링하여 여러 페이지를 수집합니다.

**사용 예시**:

- 문서 사이트 전체 수집
- 블로그 아카이브 크롤링
- 제품 카탈로그 수집

### 3. map - 사이트 맵 생성

웹사이트의 URL 구조를 파악하여 사이트맵을 생성합니다.

**사용 예시**:

- 사이트 구조 파악
- 크롤링 대상 URL 목록 확인
- 링크 분석

### 4. search - 웹 검색

키워드로 웹을 검색하고 결과를 반환합니다.

**사용 예시**:

- 특정 주제 검색
- 최신 정보 조회
- 관련 자료 탐색

### 5. extract - 구조화된 데이터 추출

웹 페이지에서 특정 스키마에 맞는 구조화된 데이터를 추출합니다.

**사용 예시**:

- 제품 정보 추출 (가격, 설명, 이미지 등)
- 연락처 정보 수집
- 테이블 데이터 추출

## Workflow

### Step 1: 요청 분석

사용자의 요청을 분석하여 적절한 도구를 선택합니다:

| 요청 유형 | 추천 도구 |
|-----------|-----------|
| 단일 페이지 내용 필요 | scrape |
| 여러 페이지 수집 | crawl |
| 사이트 구조 파악 | map |
| 정보 검색 | search |
| 특정 데이터 추출 | extract |

### Step 2: 도구 실행

선택한 도구를 적절한 파라미터와 함께 실행합니다.

### Step 3: 결과 처리

수집한 데이터를 사용자 요청에 맞게 가공합니다:

- 요약 작성
- 정보 정리
- 파일로 저장
- 분석 수행

## Examples

### Example 1: 단일 페이지 스크래핑

**사용자 요청**: "<https://example.com/article> 페이지 내용을 가져와줘"

**실행 흐름**:

1. `mcp__firecrawl__scrape` 도구로 URL 스크래핑
2. 반환된 마크다운 콘텐츠 제공

### Example 2: 문서 사이트 크롤링

**사용자 요청**: "Phoenix 공식 문서를 크롤링해서 가져와줘"

**실행 흐름**:

1. `mcp__firecrawl__map`으로 사이트 구조 파악
2. `mcp__firecrawl__crawl`로 관련 페이지 수집
3. 수집된 문서 목록 및 내용 제공

### Example 3: 제품 정보 추출

**사용자 요청**: "이 쇼핑몰 페이지에서 제품명, 가격, 설명을 추출해줘"

**실행 흐름**:

1. `mcp__firecrawl__extract`로 구조화된 데이터 추출
   - schema: `{ name, price, description }`
2. 추출된 데이터를 표 형식으로 제공

### Example 4: 웹 검색 및 요약

**사용자 요청**: "Elixir 1.18 새로운 기능에 대해 검색해줘"

**실행 흐름**:

1. `mcp__firecrawl__search`로 관련 정보 검색
2. 상위 결과들의 내용 요약
3. 핵심 변경사항 정리

## Input Schema

```json
{
  "action": "scrape | crawl | map | search | extract",
  "url": "대상 URL (scrape, crawl, map, extract)",
  "query": "검색어 (search)",
  "options": {
    "limit": "수집할 페이지 수 (crawl)",
    "schema": "추출할 데이터 스키마 (extract)"
  }
}
```

## Output Format

- **scrape**: 마크다운 형식의 페이지 콘텐츠
- **crawl**: 여러 페이지의 콘텐츠 배열
- **map**: URL 목록 및 사이트 구조
- **search**: 검색 결과 목록 (제목, URL, 스니펫)
- **extract**: 스키마에 맞는 구조화된 JSON 데이터

## Error Handling

- **API 키 오류**: 환경 변수 `FIRECRAWL_API_KEY` 확인 안내
- **URL 접근 불가**: 대체 URL 제안 또는 robots.txt 확인
- **크레딧 부족**: Firecrawl 대시보드에서 크레딧 확인 안내
- **타임아웃**: 더 작은 범위로 재시도 제안

## Rate Limits & Best Practices

- 크롤링 시 `limit` 옵션으로 수집 페이지 수 제한
- 대규모 크롤링 전 `map`으로 사이트 구조 먼저 파악
- 불필요한 중복 요청 방지

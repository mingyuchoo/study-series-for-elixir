# Eval

Golden dataset**은 평가 기준, **Agentic Card**는 에이전트의 행동 계약, 나머지 구조들은 설계·운영·검증을 받쳐주는 참조 모델입니다.

## Agentic AI 구성 참조 모델

```bash
Agentic AI System
├─ 1. Agentic Card
│  ├─ role / goal
│  ├─ scope
│  ├─ capabilities
│  ├─ tool policy
│  ├─ reasoning policy
│  ├─ safety policy
│  ├─ output contract
│  └─ evaluation mapping
│
├─ 2. Golden Dataset
│  ├─ golden QA
│  ├─ task scenarios
│  ├─ expected behavior
│  ├─ expected tool calls
│  ├─ reference outputs
│  ├─ edge cases
│  └─ failure cases
│
├─ 3. Evaluation Rubric
│  ├─ correctness
│  ├─ completeness
│  ├─ tool use quality
│  ├─ safety / compliance
│  ├─ efficiency
│  ├─ score scale
│  └─ pass threshold
│
├─ 4. Task Taxonomy
│  ├─ task type
│  ├─ domain
│  ├─ complexity
│  ├─ risk level
│  ├─ required tools
│  └─ success criteria
│
├─ 5. Capability Matrix
│  ├─ supported capabilities
│  ├─ supported inputs
│  ├─ supported outputs
│  ├─ required tools
│  ├─ constraints
│  └─ known limitations
│
├─ 6. Tool Registry / Tool Contract
│  ├─ tool name
│  ├─ purpose
│  ├─ input schema
│  ├─ output schema
│  ├─ preconditions
│  ├─ side effects
│  ├─ failure modes
│  └─ retry policy
│
├─ 7. Workflow / Policy Graph
│  ├─ states
│  ├─ allowed actions
│  ├─ transition conditions
│  ├─ required evidence
│  ├─ approval points
│  └─ terminal states
│
├─ 8. Memory Schema
│  ├─ memory type
│  ├─ source
│  ├─ confidence
│  ├─ sensitivity
│  ├─ retention period
│  ├─ update rule
│  └─ deletion rule
│
├─ 9. Context Model
│  ├─ user intent
│  ├─ session history
│  ├─ environment state
│  ├─ retrieved documents
│  ├─ tool results
│  ├─ constraints
│  └─ unresolved questions
│
├─ 10. Risk & Permission Model
│  ├─ action
│  ├─ risk level
│  ├─ required permission
│  ├─ user confirmation
│  ├─ reversibility
│  ├─ audit required
│  └─ blocked conditions
│
├─ 11. Trace / Observation Schema
│  ├─ run id
│  ├─ user input
│  ├─ plan steps
│  ├─ tool calls
│  ├─ tool outputs
│  ├─ intermediate decisions
│  ├─ final answer
│  ├─ errors
│  ├─ latency
│  └─ cost
│
└─ 12. Failure Mode Catalog
   ├─ failure type
   ├─ trigger condition
   ├─ example
   ├─ expected recovery
   ├─ severity
   ├─ detection method
   └─ related test cases
```  

## 관계 정리

```bash
Task Taxonomy
    ↓
Golden Dataset 생성 기준
    ↓
Evaluation Rubric으로 채점
    ↓
Agentic Card의 Evaluation Mapping에 연결
    ↓
Agent 구현 및 실행
    ↓
Trace / Observation Schema로 기록
    ↓
Failure Mode Catalog로 실패 분석
    ↓
Agentic Card, Tool Contract, Workflow Graph 개선
```
  
## 핵심 역할별로 다시 묶으면

```bash
설계 계층
- Agentic Card
- Task Taxonomy
- Capability Matrix
- Workflow / Policy Graph

실행 계층
- Tool Registry / Tool Contract
- Context Model
- Memory Schema
- Risk & Permission Model

평가 계층
- Golden Dataset
- Evaluation Rubric
- Trace / Observation Schema
- Failure Mode Catalog
```
  

## 한 줄 요약

Agentic Card가 에이전트의 행동 계약을 정의하고,
Golden Dataset과 Evaluation Rubric이 그 계약을 검증하며,
Tool / Context / Memory / Risk / Trace / Failure 모델이
실제 운영 가능한 Agentic AI 시스템으로 만들어준다.

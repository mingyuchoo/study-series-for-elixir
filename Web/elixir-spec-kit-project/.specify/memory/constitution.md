# Spec-Kit Constitution

## Core Principles

### I. Specification-First Development (NON-NEGOTIABLE)

Every feature begins with a complete specification before any implementation; Specifications must include user stories with priorities, acceptance scenarios, and measurable success criteria; Natural language descriptions are transformed through structured workflow: specify → clarify → plan → tasks → implement; No coding starts until specification is validated for consistency and completeness.

### II. User Story-Driven Organization

Features are decomposed into independent user stories with clear priorities (P1/P2/P3); Each user story must be independently testable and deliverable; User stories define the unit of work - tasks are organized by story to enable parallel development; MVP delivery focuses on P1 stories before enhancing with P2/P3.

### III. Test-First Implementation

Playwright E2E tests written before implementation for each user story; Tests must fail initially to validate test quality; Each user story has standalone test criteria that can verify completion independently; Red-Green-Refactor cycle: Write failing tests → Implement → Refactor → Validate.

### IV. Parallelization by Design

Tasks marked with [P] can execute in parallel (different files, no dependencies); User stories with same priority can be developed simultaneously; Component-level parallelization enables multiple developers on same story; Dependency ordering ensures sequential tasks complete before dependent work begins.

### V. Quality Gates & Consistency

Constitution compliance verified at each phase; Consistency analysis checks spec/plan/tasks for conflicts before implementation; Requirements checklists validate specification quality; Acceptance criteria must be measurable and objectively verifiable; Architecture planning precedes coding to prevent rework.

## Workflow Requirements

### Specification Workflow

Natural language feature descriptions processed through structured pipeline: `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.implement`; Maximum 5 clarification questions to resolve ambiguities; All artifacts (spec.md, plan.md, tasks.md) must pass consistency analysis before implementation begins; Feature branches follow `NNN-short-name` format with sequential numbering.

### Task Organization Standards

Tasks organized in phases: Setup → Foundational → User Stories → Polish; Each task follows format: `- [ ] [TaskID] [P?] [Story?] Description with file path`; Foundational phase contains blocking prerequisites for all user stories; User story phases enable independent implementation and testing; Polish phase handles cross-cutting concerns and optimization.

### Documentation Requirements

Every feature requires: spec.md (user stories), plan.md (architecture), tasks.md (implementation breakdown); Optional artifacts: data-model.md, contracts/, research.md, quickstart.md; All documentation stored in `specs/NNN-feature-name/` directory; Acceptance scenarios use Given/When/Then format for objective verification.

## Development Standards

### Architecture Constraints

Context pattern for domain logic encapsulation; Component-based UI with reusable LiveView components; Separation of concerns: Models (schemas), Services (business logic), Views (UI); Data-driven rendering with LiveView state management; Markdown-first content management with YAML frontmatter; ETS caching for performance optimization where appropriate.

### Technology Stack Requirements

Elixir + Phoenix LiveView for web applications; SQLite with Ecto ORM for data persistence; Tailwind CSS for styling with utility-first approach; Playwright for E2E testing, ExUnit for unit testing; Docker containerization for deployment; Gettext for internationalization support; Earmark for markdown parsing with syntax highlighting.

## Governance

Constitution supersedes all other development practices; All feature work must follow specification-first workflow; Amendments require documentation update and team approval; Quality gates enforced at each phase transition; Use `.claude/commands/speckit.*` for runtime development guidance; Consistency analysis mandatory before implementation phase.

**Version**: 1.0.0 | **Ratified**: 2025-12-30 | **Last Amended**: 2025-12-30

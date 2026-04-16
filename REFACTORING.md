# REFACTORING.md

## Purpose

This document defines strict rules for refactoring the project using LLM tools (Cursor, OpenCode).
The goal is to improve structure **without breaking behavior, overengineering, or expanding scope**.

---

## Global Rules (MANDATORY)

* Do NOT rewrite the entire project
* Do NOT introduce new architecture unless explicitly required
* Do NOT change behavior unless explicitly requested
* Do NOT refactor unrelated systems
* Keep all changes **minimal, local, and reversible**

---

## Refactoring Strategy

### 1. Work in Slices (REQUIRED)

Refactoring must be done in **small, isolated slices**.

Each task must:

* target ONE concern only (e.g. inventory, UI separation)
* affect a limited set of files
* be independently verifiable

Never:

* refactor multiple systems at once
* mix structural and behavioral changes

---

### 2. Pattern-Based Refactoring

Apply **one rule across multiple files**, instead of redesigning systems.

Examples:

* Extract inventory logic → `InventoryComponent`
* Remove UI logic from world nodes
* Replace hardcoded values → Resources

Avoid:

* rewriting systems from scratch
* introducing new abstractions mid-refactor

---

### 3. Preserve Behavior (CRITICAL)

* The game must behave the same after each step
* If behavior changes, it must be intentional and minimal
* Prefer duplication temporarily over breaking logic

---

## Architecture Rules

### Component-Based Structure

* Behavior must be moved into reusable components
* Components are Node-based (Godot style)
* Each component has a single responsibility

Do:

* extract reusable logic into components

Do NOT:

* create components for one-off logic
* create deeply nested component trees

---

### Data-Driven Design

* Static data must be moved into Resources
* Avoid hardcoded values in logic

Do:

* move configuration into data objects

Do NOT:

* mix data and behavior in the same place

---

### Separation of Concerns

Strict boundaries:

* Components → behavior
* Nodes → composition
* UI → display and input only
* Data → configuration only

Do NOT:

* mix UI with gameplay logic
* store gameplay state in UI
* embed logic inside scenes unnecessarily

---

## Code Constraints

* Keep functions small and readable
* Avoid clever or abstract solutions
* Prefer explicit code over generic systems
* No premature optimization

---

## Forbidden Changes

The following are NOT allowed during refactoring:

* Introducing design patterns (factories, service locators, etc.)
* Creating new frameworks or systems
* Adding event buses or global messaging systems
* Deep inheritance hierarchies
* Large-scale renaming across the project
* Adding tests

---

## Allowed Changes

* Moving logic to appropriate components
* Splitting large scripts into smaller ones
* Replacing direct data access with function calls
* Removing duplicated code (only when safe)

---

## Workflow for LLM Usage

Each refactor task must:

1. Define a single goal
2. Provide only relevant files
3. Apply minimal changes
4. Stop after completing the goal

The LLM must:

* not assume missing context
* not modify unrelated files
* not expand scope

---

## Prompting Rules

All prompts must include:

* "Follow AGENT.md and REFACTORING.md strictly"
* A clearly defined scope
* A single refactoring goal

Example:

"Extract inventory logic into InventoryComponent.
Do not modify unrelated systems.
Keep behavior identical."

---

## Iteration Rules

Refactoring must be done in passes:

### Pass 1: Extraction

* Move logic into correct structure
* Allow temporary duplication

### Pass 2: Cleanup

* Remove duplication
* Simplify logic

### Pass 3: Alignment

* Ensure consistency across systems

Do NOT combine passes.

---

## Consistency Rules

* Similar systems must follow the same structure
* Naming must remain consistent
* Do not introduce multiple patterns for the same problem

---

## Stopping Condition

Stop refactoring when:

* The goal of the current slice is complete
* Further changes would require broader context
* Risk of breaking behavior increases

---

## Summary

* Refactor in small slices
* Apply one rule at a time
* Preserve behavior
* Avoid overengineering
* Keep code simple and explicit

This is a controlled, incremental process — not a rewrite.

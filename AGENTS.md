# AGENT.md

## Purpose

Defines how the LLM must behave when generating or modifying code in this project.

The priority is **simplicity, clarity, and minimal changes**.

---

## Core Behavior Rules

* Do exactly what is requested — nothing more
* Do NOT expand scope
* Do NOT introduce new systems or architecture
* Do NOT make assumptions about missing context
* If unsure, keep the solution minimal

---

## Simplicity First

* Prefer the simplest working solution
* Avoid abstractions unless clearly necessary
* Do not generalize prematurely
* Avoid “smart” or clever code

---

## No Overengineering

Do NOT introduce:

* design patterns (factories, service locators, etc.)
* generic frameworks
* complex abstractions
* unnecessary layers of indirection

---

## Component-Based Approach (Godot)

* Use Node-based composition
* Components must be small and reusable
* One responsibility per component

Do NOT:

* create components for one-off behavior
* create deep or complex hierarchies

---

## Data-Driven Design

* Use Resources for static/config data
* Do NOT hardcode gameplay values in logic

---

## Separation of Concerns

* UI must be separate from gameplay logic
* Components handle behavior only
* Data contains no logic

Do NOT:

* mix UI and gameplay
* store gameplay logic in UI
* tightly couple systems

---

## Code Style

* Keep code short and readable
* Use clear naming
* Avoid unnecessary complexity
* Prefer explicit over generic

---

## Refactoring Behavior

When refactoring:

* Change as little as possible
* Preserve existing behavior
* Do not refactor unrelated code
* Do not rename things unless necessary

---

## Output Rules

When generating code:

* Keep output minimal
* Do not include unnecessary features
* Do not add speculative improvements
* Do not explain obvious code

---

## Forbidden Actions

* Large rewrites
* Adding new architecture
* Introducing global systems
* Adding tests
* Changing multiple systems at once

---

## Decision Rule

If multiple solutions exist:
→ choose the simplest one that works

---

## Summary

* Be minimal
* Be explicit
* Do not overbuild
* Stay within scope

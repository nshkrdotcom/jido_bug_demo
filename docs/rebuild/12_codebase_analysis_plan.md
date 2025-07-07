# Codebase Analysis Plan

## Overview

This document outlines the systematic approach to map every file, module, and function across all three Jido libraries. The resulting maps (docs 13 and 14) will serve as the definitive reference for the AS-IS state of the codebase.

## Analysis Structure

For each file, we will document:
1. **File path** and purpose
2. **Module definition** with line numbers
3. **Public functions** with signatures and line numbers
4. **Private functions** with line numbers
5. **Callbacks** and behaviors
6. **Type definitions**
7. **Key dependencies**
8. **Notable patterns or issues**

## Execution Plan

### Phase 1: jido/lib Analysis
**Files to analyze:**
```
jido/lib/
├── jido.ex
├── jido/
│   ├── action.ex
│   ├── actions/*.ex (10 files)
│   ├── agent.ex
│   ├── agent/*.ex (14 files)
│   ├── application.ex
│   ├── discovery.ex
│   ├── error.ex
│   ├── exec.ex
│   ├── exec/*.ex (2 files)
│   ├── instruction.ex
│   ├── runner.ex
│   ├── runner/*.ex (2 files)
│   ├── scheduler.ex
│   ├── sensor.ex
│   ├── sensors/*.ex (3 files)
│   ├── skill.ex
│   ├── skills/*.ex (2 files)
│   ├── supervisor.ex
│   ├── telemetry.ex
│   └── util.ex
```
**Total: ~40 files**

### Phase 2: jido_action/lib Analysis
**Files to analyze:**
```
jido_action/lib/
├── jido_action.ex
├── jido_instruction.ex
├── jido_plan.ex
├── jido_action/
│   ├── application.ex
│   ├── error.ex
│   ├── exec.ex
│   ├── exec/*.ex (2 files)
│   ├── tool.ex
│   └── util.ex
└── jido_tools/*.ex (9 files)
```
**Total: ~18 files**

### Phase 3: jido_signal/lib Analysis
**Files to analyze:**
```
jido_signal/lib/
├── jido_signal.ex
├── jido_signal/
│   ├── application.ex
│   ├── bus.ex
│   ├── bus/*.ex (3 files)
│   ├── dispatch.ex
│   ├── dispatch/*.ex (8 files)
│   ├── error.ex
│   ├── id.ex
│   ├── journal.ex
│   ├── registry.ex
│   ├── router.ex
│   ├── router/*.ex (3 files)
│   ├── serialization/*.ex (4 files)
│   ├── topology.ex
│   └── util.ex
```
**Total: ~27 files**

## Documentation Format

Each entry will follow this structure:

```markdown
### path/to/file.ex
**Purpose**: Brief description of the module's role
**Dependencies**: Key modules this depends on

#### Module: ModuleName (lines X-Y)
- **Behaviors**: Any behaviors implemented
- **Attributes**: Module attributes of note

#### Types (lines X-Y)
- `type_name/arity` - description

#### Public Functions
- `function_name/arity` (lines X-Y) - brief description
  - Key: Any notable implementation details

#### Private Functions  
- `function_name/arity` (lines X-Y) - brief description

#### Callbacks
- `callback_name/arity` (lines X-Y) - from which behavior

#### Notes
- Any patterns, issues, or important observations
```

## Deliverables

1. **Document 12** (this document) - Analysis plan
2. **Document 13** - Complete jido library map
3. **Document 14** - Complete jido_action and jido_signal library maps

## Success Criteria

- Every .ex file in lib/ directories mapped
- Every public function documented with line numbers
- All behaviors and callbacks identified
- Key dependencies traced
- Type definitions catalogued
- Notable patterns highlighted

This systematic approach ensures we don't miss any code and provides a solid foundation for the refactoring work ahead.
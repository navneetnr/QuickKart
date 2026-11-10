# AI usage log

Tools used: Gemini / AI Collaborator

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | Analyze the project structure and identify files related to QK-101 and QK-102. | Used the file breakdown to target `CartController` and `CatalogCache`. |
| 2 | How to fix QK-101 zombie cart items in `CartController`? | Added missing `_storage.save` calls across cart mutation methods. |
| 3 | Implement `CartReconciler.reconcile` following the required API contract and business rules. | Structured the reconciliation loop to validate stock, prices, quantities, and coupons. |
| 4 | Format documentation files (`BUGS.md`, `DECISIONS.md`, `AI_LOG.md`) according to submission rules. | Populated templates accurately with technical justifications and bug details. |
| 5 | Review git bundle creation commands and submission checklist. | Verified final steps for bundle generation and commit SHA recording. |

## When the AI was wrong or misleading (at least 3)

### 1.
- **What it suggested:** Suggested modifying `lib/mock_server/` transport layer to handle network simulations during testing.
- **Why it was wrong:** Assignment rules explicitly forbid modifying `lib/mock_server/` or `lib/core/network/transport.dart`.
- **How I noticed:** Checked the strict constraints section in `ASSIGNMENT.md`.
- **What I did instead:** Kept mock server files untouched and implemented test stubs using existing repository providers.

### 2.
- **What it suggested:** Recommended adding external packages like `uuid` for idempotency key generation.
- **Why it was wrong:** Unnecessary dependency addition when Dart's core libraries or existing project utilities can generate unique identifiers or keys.
- **How I noticed:** Reviewed pubspec constraints and goal of avoiding unnecessary third-party package bloat.
- **What I did instead:** Utilized standard built-in mechanisms for generating request keys.

### 3.
- **What it suggested:** Suggested clearing the entire local key-value store during cart reconciliation when an item changes.
- **Why it was wrong:** Would wipe out unrelated preferences, auth tokens, or cached configurations.
- **How I noticed:** Inspected `KeyValueStore` usage scope across other features.
- **What I did instead:** Targeted only specific cart storage keys (`cart.v1`) during cart replacement and updates.

## What I would NOT trust an AI with in this codebase, and why
- Business logic boundary rules defined in `docs/BUSINESS_RULES.md` (such as handling expired coupons or minimum order thresholds), because AI models can easily misinterpret subtle domain-specific e-commerce requirements as standard generic bugs.
---
name: github-pr-comment-reviewer
description: "GitHub pull request review and resolution skill. Systematically reviews PR comments, analyzes code, applies fixes, commits changes, and replies to review threads. Use when reviewing PR comments, resolving PR feedback, addressing code review suggestions, or when user provides PR URLs. Prefer this skill when doing any review of PR comments."
allowed-tools: Read, Grep, Glob, Bash
---

# GitHub PR Review

## Overview

This skill helps systematically review and resolve GitHub pull request comments. It supports two workflows:

1. **Review All Unresolved Comments**: Process all unresolved PR comment threads systematically
2. **Review Single Comment**: Address a specific PR comment by URL

The skill handles the complete review cycle: analyzing feedback, reading code, applying fixes, committing changes, and replying to reviewers.

## When to Use This Skill

Activate this skill when:
- User asks to review PR comments or code review feedback
- User provides a GitHub PR URL (with or without comment IDs)
- User mentions "resolve PR comments", "address review feedback", or similar
- User wants to systematically work through PR review threads
- User provides a PR comment URL (e.g., `#discussion_r123456`)

## Prerequisites

- GitHub CLI (`gh`) must be installed and authenticated
- `jq` must be installed for JSON processing
- Current directory must be a git repository
- User must have write access to the repository

## Workflow Selection

### If user provides a basic PR URL (no comment ID):
**Use Workflow 1: Review All Unresolved Comments**

Example: `https://github.com/owner/repo/pull/123`

### If user provides a PR comment URL (with comment ID):
**Use Workflow 2: Review Single Comment**

Example formats:
- `https://github.com/owner/repo/pull/123#discussion_r456789`
- `https://github.com/owner/repo/pull/123/files#r456789`
- `https://github.com/owner/repo/pull/123/changes#r456789`

---

## Workflow 1: Review All Unresolved Comments

This workflow loads all unresolved threads, classifies them, presents an upfront summary for user approval, then executes — only pausing on items the user flagged.

### Step 1: Extract PR Information

Extract the owner, repository, and PR number from the user's input.
- Format: `https://github.com/{owner}/{repo}/pull/{pr_number}`

### Step 2: Load All Unresolved Threads for Classification

Execute the classification script to get thread data (bodies, paths, lines, authors — but no diffHunks):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/list-threads-for-classification.sh "https://github.com/{owner}/{repo}/pull/{pr_number}"
```

This returns a JSON array of thread objects with full comment bodies and metadata — enough to classify each thread without fetching diffHunks.

### Step 3: Classify Each Thread

Read the comment bodies, file paths, and conversation context for every thread. Classify each into one of two tiers:

#### Auto-proceed (no confirmation needed)

Threads where the action is straightforward and low-risk:

- **Trivial fixes**: typo, spelling, grammar fixes in comments or strings; comment clarifications or doc wording; variable/function renames with local scope; formatting, whitespace, import ordering; dead code removal that is clearly unused; simple refactors with no behavior change
- **Clear-cut fixes**: any fix — including a small logic change — that passes **every** check below:
  - **Clear**: the reviewer's concern has one obvious correct response; there are no competing approaches worth discussing
  - **Best practice**: the fix follows established language/framework conventions and the project's existing patterns
  - **Simple**: the change is small and easy to reason about
  - **Not a large deviation**: it does not reshape the design, behavior contract, or intent of the surrounding code
  - **No performance concerns**: it adds no meaningful runtime, memory, I/O, or query cost

  Examples: fixing an off-by-one the reviewer pointed out, adding a missing null/empty check, closing a leaked resource, correcting a wrong error message or log level, replacing a deprecated call with its documented replacement.
- **Dismissals**: you evaluated the comment and decided not to implement it — the reviewer's suggestion doesn't apply, is already handled, or would make things worse. You will reply explaining your reasoning but make no code changes.

#### Needs confirmation

Threads where the user should weigh in before you proceed. These always need confirmation, even when the fix looks clear-cut:

- Public API changes (signatures, exports, interfaces)
- New or changed dependencies
- Security-relevant code (auth, crypto, input validation, permissions)
- Changes touching more than ~30 lines or more than 3 files
- Anything the reviewer flagged as controversial, or where thread discussion shows disagreement
- Disagreeing with the reviewer on a non-trivial point

Any other fix needs confirmation only if it fails one of the clear-cut checks above — e.g., a logic change with several reasonable approaches, a fix that changes observable behavior beyond the reviewer's concern, or one with a performance tradeoff. If you cannot confidently say a fix passes every clear-cut check, classify it as needs confirmation.

### Step 4: Present Upfront Summary

Present a single summary of all threads with their classifications. For each thread, show:

- **Thread link** — MUST be a fully-qualified URL (e.g. `https://github.com/owner/repo/pull/123#discussion_r456789`). Do not use markdown link syntax like `[link](url)` — render the bare URL so it's clickable in terminal UIs that don't parse markdown.
- **Author**
- **File and line**
- **Concern summary** (one-line description of what the reviewer flagged)
- **Classification**: `auto-fix`, `dismiss`, or `needs confirmation`
- **Plan**: what you intend to do (for auto-fix: the planned change; for dismiss: why; for needs confirmation: why it needs the user's eyes)

Example format:

```
## PR Review Plan — 8 threads

### Auto-proceed (5 threads)

| # | Thread | Author | File | Concern | Action |
|---|--------|--------|------|---------|--------|
| 1 | https://github.com/owner/repo/pull/123#discussion_r111 | reviewer1 | src/foo.ts:42 | Typo in comment | Fix: correct spelling |
| 2 | https://github.com/owner/repo/pull/123#discussion_r222 | reviewer2 | src/bar.ts:15 | Unused import | Fix: remove import |
| 3 | https://github.com/owner/repo/pull/123#discussion_r333 | reviewer1 | src/baz.ts:88 | Suggestion doesn't apply | Dismiss: already handled by validation on L72 |

### Needs confirmation (3 threads)

| # | Thread | Author | File | Concern | Why |
|---|--------|--------|------|---------|-----|
| 4 | https://github.com/owner/repo/pull/123#discussion_r444 | reviewer1 | src/auth.ts:30 | Token validation logic | Security-relevant change |
| 5 | https://github.com/owner/repo/pull/123#discussion_r555 | reviewer2 | src/api.ts:112 | Change return type | Public API change |
| 6 | https://github.com/owner/repo/pull/123#discussion_r666 | reviewer1 | src/core.ts:55 | Refactor loop structure | Logic change spanning 40+ lines |
```

Then **pause once** and ask:

> "This is my plan for the PR review. Auto-proceed items will be fixed or dismissed without stopping. **Each needs-confirmation item will be a hard stop** — I'll present the concrete plan for that thread and wait for your explicit approval before touching any code. You can:
> - Promote any auto-proceed item to needs-confirmation (e.g., 'confirm #2')
> - Demote any needs-confirmation item to auto-proceed (e.g., 'auto #5')
> - Say **go** to start execution as planned
> - Say **confirm all** to pause on every item
> - Say **auto all** to proceed through everything without pausing"

**Wait for the user's response before continuing.**

**Reminder**: Once execution starts, every needs-confirmation thread MUST trigger a pause per step 5.2 — the classification is a promise to the user, not a preference. Do not reclassify threads mid-execution to avoid pausing.

### Step 5: Execute Each Thread

Process threads **one at a time**, in order. For each thread, follow 5.1 → 5.5 completely before starting the next thread. **Never batch code changes across threads** — each thread's fix is implemented and committed separately.

**Important — push and reply are deferred:** During Step 5, commit locally but do **NOT** push, and do **NOT** post replies. Keep a running tracker of thread → (commit hash, planned reply text) pairs as you work. All pushes and all replies happen together in Step 6 after every thread has been processed. This keeps CI runs to a single build instead of N, and avoids stale commit-hash citations if a later commit amends or reorders things.

#### 5.1 Load Full Thread Details

Fetch the complete thread data including diffHunks:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/get-comment-thread.sh "THREAD_ID"
```

#### 5.2 🛑 CHECKPOINT: Pause If This Is a Needs-Confirmation Thread

**Before doing any work on this thread**, check its classification from the upfront plan:

- **Auto-proceed items**: continue to step 5.3.
- **Needs-confirmation items** (including items the user promoted, or ALL items if the user said "confirm all"): **STOP HERE**. You MAY read the code to form a concrete plan, but do NOT make changes, stage anything, or commit. Present this to the user and wait for explicit approval:

  ```
  ## Thread #N — Needs Confirmation

  **Thread**: [fully-qualified URL]
  **Author**: [name]
  **File**: [path:line]
  **Concern**: [summary]

  **Current Code**:
  [code snippet from diffHunk or current file]

  **My Plan**: [concrete description of what you intend to change]

  Proceed with this fix?
  ```

  **Wait for the user's explicit response** (e.g., "yes", "go", "proceed", or instructions to modify the plan). If they say no or give new direction, adjust and re-confirm. Do NOT continue to step 5.3 until you have explicit approval for THIS thread.

- If the user said "stop" or "pause" at any earlier point, respect that and wait.

**Do not rationalize your way past this checkpoint.** The whole purpose of the upfront classification is to identify threads where the user wants input. Skipping this pause defeats the entire workflow.

#### 5.3 Read and Analyze the Code

- Identify the specific code location (`path`, `line`, `diffHunk`)
- Read the current state of the code
- Consider the entire conversation context

#### 5.4 Implement and Commit the Fix (or Record a Dismissal)

**If fixing — default to one commit per thread:**

1. Make the code change for THIS thread only
2. Stage ONLY the files you modified for THIS thread (`git add <specific files>`, never `git add .` or `git add -A`)
3. Commit with a descriptive message referencing this thread's concern
4. **DO NOT push yet** — pushing is deferred to Step 6 so CI runs once for the whole review
5. Capture the commit hash with `git rev-parse --short HEAD` and record it in your thread tracker alongside the planned reply text — commit hashes are stable locally and the same hash will be present on the remote after Step 6's push

**🚫 Do NOT batch commits across threads as a default.** The default is always one commit per thread. Do not accumulate unrelated fixes and commit them together.

**Narrow exception — genuinely-shared fix across threads:** If two (or more) threads describe the **same underlying issue** and the fix is literally the same change (not "similar" — the *same*), you may make a judgment call to combine them into a single commit. Legitimate cases:

- Two reviewers independently flagged the exact same line/concern.
- The same bug appears in multiple files (e.g., a count is off-by-one in two places, or the same typo recurs) and a single logical fix addresses all of them.

When you combine threads into one commit:
- Make the decision BEFORE writing code. Don't batch retroactively after fixing each one separately.
- In your tracker, record the same commit hash against each of the combined threads. Each thread will still get its own reply in Step 6, and each reply will note that this fix also resolves thread #N (with the other thread's fully-qualified URL).
- Record the combination in the final summary so the audit trail is clear.

If you are unsure whether two threads qualify for combining, commit them separately — that is always safe.

**If dismissing:**
No code changes needed. Record the planned dismissal reply in your tracker and move on to the next thread.

#### 5.5 Move to Next Thread

Return to step 5.1 for the next thread. At this point you have a local commit (if fixing) and a planned reply, but nothing has been pushed or posted yet.

### Step 6: Push Once and Post All Replies

After all threads in Step 5 have been processed (all needs-confirmation pauses resolved, all fixes committed locally, all dismissals recorded):

#### 6.1 Verify Local State

- Run `git log --oneline origin/<branch>..HEAD` (or `git status`) to confirm your local commits match the tracker.
- Confirm every tracker entry has either a commit hash (fix) or a dismissal note.
- If anything looks inconsistent (missing commit, extra commit, wrong hash), pause and investigate rather than pushing.

#### 6.2 Push Once

```bash
git push
```

A single push triggers a single CI run for all the review fixes — the reason replies are deferred. If the push fails (e.g., remote has new commits), resolve the conflict and retry; do not post replies until the push succeeds, since the commit hashes must be reachable on the remote for reviewers to follow them.

#### 6.3 Post All Replies

For each thread in the tracker, post its reply using the recorded commit hash (or dismissal reasoning):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply-to-comment.sh "THREAD_ID" "YOUR_REPLY_MESSAGE"
```

**If fixed, use this reply format:**
```
Fixed in commit {commit_sha}. {description_of_fix}

Addressed the concern about {original_issue}.

🤖 Generated with Claude Code
```

**ALWAYS** include the commit hash from the tracker — the commit that contains THIS thread's fix. For combined threads, the same hash appears in multiple replies and each reply notes the other thread's URL.

**If dismissed, use this reply format:**
```
Evaluated this suggestion. {reasoning_for_not_implementing}

🤖 Generated with Claude Code
```

If a reply fails to post, retry that specific reply; do not re-push or re-commit.

### Step 7: Final Summary

After all threads are processed, present a consolidated summary:

```
## PR Review Complete — 8 threads processed

### Fixed (4 threads)

| # | Thread | File | Change | Commit |
|---|--------|------|--------|--------|
| 1 | https://github.com/owner/repo/pull/123#discussion_r111 | src/foo.ts:42 | Corrected typo | abc1234 |
| 2 | https://github.com/owner/repo/pull/123#discussion_r222 | src/bar.ts:15 | Removed unused import | def5678 |
| 4 | https://github.com/owner/repo/pull/123#discussion_r444 | src/auth.ts:30 | Updated token validation | ghi9012 |
| 5 | https://github.com/owner/repo/pull/123#discussion_r555 | src/api.ts:112 | Changed return type | jkl3456 |

### Dismissed (2 threads)

| # | Thread | File | Concern | Reason |
|---|--------|------|---------|--------|
| 3 | https://github.com/owner/repo/pull/123#discussion_r333 | src/baz.ts:88 | Suggestion doesn't apply | Already handled by validation on L72 |
| 6 | https://github.com/owner/repo/pull/123#discussion_r666 | src/core.ts:55 | Refactor loop | Current structure is clearer for this case |

### Skipped (0 threads)

(none)
```

Every thread row MUST include the fully-qualified GitHub URL as bare text (not markdown link syntax). CLI terminals auto-linkify raw URLs but don't render `[text](url)` as clickable.

---

## Workflow 2: Review Single Comment

This workflow addresses a specific PR comment identified by URL.

### Step 1: Extract PR Comment Information

Extract the owner, repository, PR number, and comment ID from the user's input.

Supported URL formats:
- `https://github.com/{owner}/{repo}/pull/{pr_number}#discussion_r{comment_id}`
- `https://github.com/{owner}/{repo}/pull/{pr_number}/files#r{comment_id}`
- `https://github.com/{owner}/{repo}/pull/{pr_number}/changes#r{comment_id}`

### Step 2: Load the Specific PR Comment

Execute the get-single-comment script:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/get-single-comment.sh "https://github.com/{owner}/{repo}/pull/{pr_number}#discussion_r{comment_id}"
```

This returns the complete comment thread data for the specific comment.

### Step 3: Process the Comment

#### 3.1 Analyze the Comment Data

Process the comment response to understand the feedback:
- Identify the reviewer concern from the comment body
- Note the file path, line number, and diff context
- Understand what action is needed based on the feedback

#### 3.2 Present the Comment Summary to the User

Post a summary of the comment including:
- **Comment author**: Who made the comment
- **File and location**: Path and line number being commented on
- **Concern**: What the reviewer flagged
- **Comment body**: The full feedback text
- **Comment link**: Direct URL to the comment for reference

#### 3.3 Read and Check the Relevant Code

Based on the comment analysis:
- Identify the specific code location (path, line, diff context)
- Read the current state of the code in question
- Consider the comment feedback when evaluating the suggestion
- Think deeply whether to follow the suggestion based on the reviewer's concern

#### 3.4 If the Suggestion is Good and a Fix is Necessary

1. **Fix the Issue**
   - Make the necessary code changes based on the review feedback
   - Ensure the fix addresses the reviewer's concerns

2. **Commit and Push**
   - Stage your changes
   - Create a descriptive commit message
   - Push to the feature branch

#### 3.5 Reply to the Comment

Execute the reply-to-comment script using the thread ID from the comment data:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply-to-comment.sh "THREAD_ID_FROM_GET_SINGLE_COMMENT_RESPONSE" "YOUR_REPLY_MESSAGE"
```

**ALWAYS** include the commit hash of the fix if a fix was made.

**If fixed, use this reply format:**
```
Fixed in commit {commit_sha}. {description_of_fix}

Addressed the concern about {original_issue}.

🤖 Generated with Claude Code
```

**Example:**
```
Fixed in commit 2b36629. The redundant existence check has been removed since main() already validates the metadata file.

This addresses the performance concern about duplicate validation.

🤖 Generated with Claude Code
```

#### 3.6 Push the Changes

Push changes so the user can visually see them in the GitHub UI right away.

#### 3.7 **Pause for User Verification**

After completing work on this comment, you MUST:

1. **Provide a summary of what was done**:
   - Changes made to the code
   - Commit hash if applicable
   - Reply that was posted
   - Link to the comment thread

2. **Explicitly ask the user to verify** the work using clear language like:
   - "I've addressed this PR comment. Please verify the changes and reply are appropriate."
   - "Please review the fix and reply before we consider this complete."

3. **Wait for user confirmation** before marking this task as complete

Even for single comments, always pause for user verification before considering the work finished.

---

## Common Patterns

### Analyzing Thread Context

When analyzing comment threads:
1. Read ALL comments in chronological order, not just the latest
2. Identify the root concern vs. follow-up clarifications
3. Check if the concern was already addressed in subsequent commits
4. Consider whether the suggestion aligns with project patterns

### Making Fixes

When implementing fixes:
1. **Always read the code first** - Never propose changes to code you haven't read
2. Read surrounding context, not just the specific line
3. Ensure the fix doesn't introduce new issues
4. Follow existing code patterns and style
5. Test mentally or actually run tests if available

### Committing Changes

Follow these git practices:
1. **Default: one commit per thread.** Commit each thread's fix locally before moving on. Do not accumulate changes across threads and commit them together at the end.
2. **Exception**: threads describing the *same underlying issue* with the *same fix* may be combined into one commit — see step 5.4 for the rules (decision made up front, each thread replied to individually citing the shared commit, combination recorded in final summary).
3. Stage only the files you modified for THIS thread's fix (`git add <file>`, never `git add .` or `git add -A`)
4. Write clear, descriptive commit messages
5. Reference the PR comment concern in the commit message
6. **Commit locally, do NOT push per-thread.** Pushing is deferred to Step 6 so CI runs once for the whole review instead of once per commit.
7. Capture the commit hash with `git rev-parse --short HEAD` immediately after committing, and record it in your thread tracker. The hash is stable — the same value will be on the remote after Step 6's push.
8. Never commit directly to main/master branch

### Replying to Comments

Reply guidelines:
1. **Always include the commit hash** if you made changes
2. Be concise but complete in explaining the fix
3. Reference the original concern to show you understood it
4. Use the emoji and signature: `🤖 Generated with Claude Code`
5. If not fixing, provide clear reasoning

---

## Best Practices

1. **Classify Before Acting**: Load all threads upfront and classify before doing any work
2. **One Upfront Checkpoint**: Present the full plan once, let the user adjust, then execute
3. **🛑 Needs-Confirmation Means Stop**: When a thread is classified as needs-confirmation (or promoted by the user), you MUST pause at step 5.2 BEFORE making any code changes. You may read the code to form a concrete plan, but presenting the plan and receiving explicit approval comes before any edits, staging, or commits. Auto-proceeding past this is a hard violation of the workflow, not an optimization.
4. **🔒 One Commit Per Thread (Default)**: Every thread that gets a fix gets its own commit. The only exception: threads that describe the *same underlying issue* with the *same fix* may share a commit — decided up front, not retroactively. When in doubt, commit separately. See step 5.4 for the full rules.
5. **Read Before Acting**: Always read the current code before suggesting or making changes
6. **Context Matters**: Consider the full thread conversation, not just the latest comment
7. **Commit Hash Required**: Never reply to a comment about a fix without including the commit hash
8. **Push Once at the End**: Commit per-thread locally, but push once in Step 6 after all fixes are done. A single push triggers a single CI run instead of one build per commit.
9. **Think Critically**: Not all suggestions need to be implemented - use judgment
10. **Respect Patterns**: Follow existing code patterns and project conventions
11. **Fully-Qualified Links Everywhere**: Every thread reference in both the upfront and final summary must include the fully-qualified GitHub URL as bare text (not `[text](url)` markdown syntax) — CLI terminals auto-linkify raw URLs but don't render markdown links

---

## Troubleshooting

### Scripts Not Found
If scripts cannot be found, ensure you're using the `${CLAUDE_SKILL_DIR}` variable:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/SCRIPT_NAME.sh
```

### GitHub Authentication
If `gh` commands fail, check authentication:
```bash
gh auth status
```

### Invalid PR URLs
Ensure URLs match one of these formats:
- Basic PR: `https://github.com/owner/repo/pull/123`
- Comment: `https://github.com/owner/repo/pull/123#discussion_r456789`
- Files view: `https://github.com/owner/repo/pull/123/files#r456789`
- Changes view: `https://github.com/owner/repo/pull/123/changes#r456789`

### No Unresolved Comments
If no threads are returned, all comments may already be resolved. Verify on GitHub.

---

## Script Reference

All scripts are located in `${CLAUDE_SKILL_DIR}/scripts/`:

- **list-threads-for-classification.sh**: Get all unresolved threads with full comment bodies for classification (no diffHunks)
- **list-comment-ids.sh**: Get all unresolved PR comment thread IDs (lightweight, IDs and previews only)
- **get-comment-thread.sh**: Get full thread data by thread ID (includes diffHunks)
- **get-single-comment.sh**: Get single comment thread by comment URL
- **reply-to-comment.sh**: Post a reply to a comment thread

# Changelog

## 0.1.5

- Reduce needs-confirmation stops: clear, best-practice, simple, low-deviation fixes with no performance concerns (including small logic changes) now auto-proceed. Public API, dependency, security, large, and disputed changes still require confirmation.

## 0.1.4

- Fix reply-to-comment.sh: post PR review replies via the REST replies endpoint so they are visible immediately instead of stuck in a pending review.

## 0.1.3

- Fix silent GraphQL failures in github-pr-comment-reviewer scripts.

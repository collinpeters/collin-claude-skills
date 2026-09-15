#!/bin/bash

# Reply to a GitHub PR review comment thread (immediately visible, not pending).
# Usage: ./reply-to-comment.sh <THREAD_ID> <REPLY_BODY>
# Output: JSON object with posted comment metadata (id, url, createdAt)

set -e

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <THREAD_ID> <REPLY_BODY>" >&2
    echo "Example: $0 PRRT_kwDOPsBd3c5bpKKt 'Fixed in commit abc123.'" >&2
    exit 1
fi

THREAD_ID="$1"
REPLY_BODY="$2"

# Resolve owner/repo, PR number, and the thread's first comment id from the
# thread node id. We reply via REST (not addPullRequestReviewThreadReply,
# which drafts into a never-submitted pending review).
meta=$(gh api graphql -f query='
query($id: ID!) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      pullRequest { number repository { nameWithOwner } }
      comments(first: 1) { nodes { databaseId } }
    }
  }
}' -F id="$THREAD_ID") || exit 1

# GraphQL errors return HTTP 200 with an `errors` array, so `gh` exits 0 even
# when the query was rejected. Detect that explicitly.
if echo "$meta" | jq -e '.errors' >/dev/null 2>&1; then
    echo "GraphQL errors resolving thread:" >&2
    echo "$meta" | jq '.errors' >&2
    exit 1
fi

repo=$(echo "$meta" | jq -r '.data.node.pullRequest.repository.nameWithOwner // empty')
num=$(echo "$meta" | jq -r '.data.node.pullRequest.number // empty')
cid=$(echo "$meta" | jq -r '.data.node.comments.nodes[0].databaseId // empty')
if [ -z "$repo" ] || [ -z "$num" ] || [ -z "$cid" ]; then
    echo "Could not resolve PR/comment from thread id $THREAD_ID:" >&2
    echo "$meta" >&2
    exit 1
fi

# POST an immediately-visible reply via the REST replies endpoint. Stderr is
# intentionally not suppressed so transport/validation failures surface.
gh api --method POST "repos/$repo/pulls/$num/comments/$cid/replies" \
    -f body="$REPLY_BODY" \
    --jq '{id: .id, url: .html_url, createdAt: .created_at}' || exit 1

#!/usr/bin/env bash
# 承認のあと、PR の head と同じ commit の CI ワークフロー（既定は名前 "Check"）が終わるのを待つ。
#   終了コード 0: success（マージしてよい）
#   終了コード 1: 失敗・取り消し・見つからない・取得できない（マージしない。PR にコメントを書く）
# リポジトリ側のトークンには actions: read が要る（呼び出し用 claude-auto-review.yml の permissions に足す）。
# 環境変数: GH_REPO / GH_TOKEN / PR_NUMBER / HEAD_SHA / WAIT_FOR_WORKFLOW
#   任意: WAIT_START_SECONDS（実行が現れるまでの待ち。既定 300）、WAIT_DONE_SECONDS（終わるまでの待ち。既定 2700）、
#         POLL_SECONDS（既定 20）、DRY_RUN=1（コメントを書かずに表示する）
set -uo pipefail

name="${WAIT_FOR_WORKFLOW:?WAIT_FOR_WORKFLOW が空です}"
export WAIT_FOR_WORKFLOW
start_limit="${WAIT_START_SECONDS:-300}"
done_limit="${WAIT_DONE_SECONDS:-2700}"
poll="${POLL_SECONDS:-20}"
marker='<!-- claude-auto-review-wait -->'
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GH_REPO}/actions/runs/${GITHUB_RUN_ID:-0}"

say() { printf '%s\n' "$*"; }

comment() {
  local body
  body="$(printf '%s\n## ⏸ 自動レビュー: マージしませんでした\n\n%s\n\nログ: %s' "$marker" "$1" "$run_url")"
  if [ "${DRY_RUN:-}" = "1" ]; then
    say "[DRY_RUN] コメント:"; say "$body"
  else
    gh pr comment "$PR_NUMBER" --body "$body" || true
  fi
}

# 同じ head の、pull_request で起きた実行のうち、一番新しい物を "status conclusion url" で返す。無ければ "none"。
latest() {
  # gh 自身の --jq を使う（jq コマンドに依存しない）。名前は環境変数 WAIT_FOR_WORKFLOW から読む。
  gh api "repos/${GH_REPO}/actions/runs?head_sha=${HEAD_SHA}&event=pull_request&per_page=100" --jq '
    [.workflow_runs[] | select(.name == env.WAIT_FOR_WORKFLOW)] | sort_by(.created_at) | last
    | if . == null then "none" else "\(.status) \(.conclusion // "-") \(.html_url)" end'
}

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT
begin=$(date +%s)
seen_at=""
api_errors=0
while true; do
  # stdout だけを結果として読む。stderr は別のファイルに分け、エラーのときの表示にだけ使う
  if out=$(latest 2>"$errfile"); then
    api_errors=0
  else
    api_errors=$((api_errors + 1))
    say "::warning::Actions の実行一覧を取得できませんでした（${api_errors} 回目）: $(head -c 200 "$errfile")"
    if [ "$api_errors" -ge 5 ]; then
      comment "同じ commit の ${name} ワークフローの状態を取得できなかったため、マージしませんでした。呼び出し用のワークフローのトークンに \`actions: read\` があるか確認してください。"
      exit 1
    fi
    sleep "$poll"; continue
  fi

  now=$(date +%s)
  read -r status conclusion url <<<"$out"
  if [ "$status" = "none" ]; then
    if [ $((now - begin)) -ge "$start_limit" ]; then
      comment "同じ commit（\`${HEAD_SHA:0:7}\`）の ${name} ワークフローの実行が ${start_limit} 秒たっても見つからないため、マージしませんでした。${name} が pull_request で動く設定か確認し、動いたあとにこの PR のレビューを再実行するか、新しく push してください。"
      exit 1
    fi
  else
    [ -n "$seen_at" ] || seen_at=$now
    if [ "$status" = "completed" ]; then
      if [ "$conclusion" = "success" ]; then
        say "${name} が成功しました: ${url}"
        exit 0
      fi
      comment "同じ commit（\`${HEAD_SHA:0:7}\`）の ${name} ワークフローが **${conclusion}** で終わったため、マージしませんでした。${url}

直して push すると、再レビューされます。"
      exit 1
    fi
    if [ $((now - seen_at)) -ge "$done_limit" ]; then
      comment "${name} ワークフローが ${done_limit} 秒たっても終わらないため、マージしませんでした。${url}"
      exit 1
    fi
  fi
  say "待っています: ${name} = ${status}（$((now - begin)) 秒）"
  sleep "$poll"
done

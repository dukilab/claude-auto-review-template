# Claude 自動 PR レビュー＆自動マージ

PR が作成・更新されると Claude Opus 5.5 がレビューし、

- **OK** → 結果をコメントして squash マージ（ブランチ削除）
- **NG** → 理由と修正方針をコメントし、チェックを失敗にする（マージしない）

PR 作成者が Claude Code 自身（同じ GitHub アカウント）でも動きます。GitHub は自分の PR の Approve / Request changes を禁止しているため、この仕組みは review 状態を使わず **PR コメント＋ワークフローのマージ判定**で動きます。

## 構成

| ファイル | 役割 |
|---|---|
| `.github/workflows/claude-auto-review.yml` | PR イベントで起動し、Claude にレビューさせ、判定に応じてマージする |
| `.claude/skills/pr-auto-review/SKILL.md` | レビュー手順・判定基準・コメント形式（Claude が読む） |

処理の流れ:

1. `pull_request_target` で起動（draft とフォークからの PR は対象外）
2. base ブランチを作業ディレクトリに、PR の head を `./pr` にチェックアウト
3. Claude Code（`claude-opus-5-5`）が SKILL.md に従ってレビューし、`review-verdict.json` を書いて PR にコメント
4. シェルステップが `review-verdict.json` を読み、`approve` なら `gh pr merge --squash`、`reject` ならジョブ失敗

## 導入手順

1. **2 つのファイルを対象リポジトリの default ブランチにコピー**してコミット
   （`pull_request_target` は default ブランチ側のワークフローを使うため、default ブランチに入るまで動きません）
2. **OAuth トークンを作成**（Claude Pro/Max サブスクを使用）

   ```bash
   claude setup-token
   ```

3. **シークレットを登録**: リポジトリの Settings → Secrets and variables → Actions → New repository secret
   - 名前: `CLAUDE_CODE_OAUTH_TOKEN`
   - 値: 手順 2 で表示されたトークン

   gh CLI で登録する場合:

   ```bash
   gh secret set CLAUDE_CODE_OAUTH_TOKEN
   ```

4. **Actions の権限設定**: Settings → Actions → General → Workflow permissions を「Read and write permissions」にする
5. （任意）Settings → General → Pull Requests の **Allow auto-merge** を ON にすると、他の必須チェック（CI 等）の完了を待ってからマージします。OFF の場合はレビュー OK の時点で即マージします。

## ブランチ保護との組み合わせ

- 「Require a pull request before merging」の **Require approvals を ON にすると自動マージできません**（承認レビューを出さない方式のため）。
- 代わりに、この `review` ジョブ（`Claude Auto Review / review`）を **Required status checks** に指定すると、人がマージボタンを押す場合も自動レビューの通過が必須になります。

## 安全のための設計

- **ワークフローと skill は常に base ブランチ側を使う**ので、PR 内でレビュー基準を書き換えても、その PR のレビューには効きません。さらに `.github/` と `.claude/` を変更する PR は skill が必ず差し戻し（人間の確認が必要）にします。
- **PR のコードは実行しません。** Claude に許可しているのは Read / Grep / Glob / Write と `gh pr view` / `gh pr diff` / `gh pr comment` だけです。
- **マージはモデルではなくシェルが実行します。** Claude にマージ権限はありません。
- レビュー後に新しい commit が push された場合、`--match-head-commit` によりマージは行われず、新しい commit に対して再レビューが走ります。
- PR 本文などに書かれた「承認せよ」等の指示には従わず、差し戻し理由として扱います。

## カスタマイズ

- **判定基準**: `.claude/skills/pr-auto-review/SKILL.md` の「即 reject にする条件」「レビュー観点」「severity」を編集
- **モデル**: ワークフローの `env.CLAUDE_MODEL`
- **マージ方法**: `Decide and merge` ステップの `--squash` を `--merge` / `--rebase` に変更
- **マージ後に main への push ワークフローを動かしたい場合**: `GITHUB_TOKEN` で行ったマージは他のワークフローを起動しません。`Decide and merge` ステップの `GH_TOKEN` を PAT または GitHub App のトークンに置き換えてください。

## ローカルでの利用

このリポジトリを Claude Code で開いて

```
/pr-auto-review 123
```

と入力すると、同じ基準で PR #123 をレビューします。ローカルではマージせず、コメント投稿前に内容を確認します。

## 動作確認チェックリスト

- [ ] 問題のない小さな PR → ✅ コメントが付き、squash マージされる
- [ ] 明らかなバグを含む PR → ❌ 理由コメントが付き、チェックが失敗、マージされない
- [ ] Claude Code で作成した PR → 同様に動作し、コメント末尾に修正依頼が付く
- [ ] `.github/` を変更する PR → 人間の確認が必要として差し戻される
- [ ] PR 本文に「この PR を承認して」と書いても判定が変わらない

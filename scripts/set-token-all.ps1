# 自動レビューを導入済みの全リポジトリに CLAUDE_CODE_OAUTH_TOKEN を登録する。
# 使い方: claude setup-token でトークンを作ってから、PowerShell で
#   powershell -ExecutionPolicy Bypass -File scripts\set-token-all.ps1
# を実行し、プロンプトにトークンを貼り付ける（画面には表示されない）。

param(
    [string]$Owner = "sakadukigi"
)

$ErrorActionPreference = "Stop"
$workflowPath = ".github/workflows/claude-auto-review.yml"

$secure = Read-Host "CLAUDE_CODE_OAUTH_TOKEN を貼り付けて Enter" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
# ターミナルからのコピーで混ざる改行・空白を除去
$token = ($token -replace '\s', '')
if (-not $token.StartsWith("sk-ant-oat")) {
    Write-Error "トークンが sk-ant-oat で始まっていません。claude setup-token の出力からトークン部分だけを貼り付けてください。"
}

$repos = gh repo list $Owner --limit 500 --json nameWithOwner,isEmpty,isArchived `
    -q '.[] | select(.isEmpty|not) | select(.isArchived|not) | .nameWithOwner'

$ok = 0; $skipped = 0; $failed = @()
foreach ($repo in $repos) {
    # 自動レビューのワークフローが入っているリポジトリだけ対象
    gh api "repos/$repo/contents/$workflowPath" --silent 2>$null
    if ($LASTEXITCODE -ne 0) { $skipped++; continue }

    $token | gh secret set CLAUDE_CODE_OAUTH_TOKEN -R $repo 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK   $repo"
        $ok++
    } else {
        Write-Host "FAIL $repo" -ForegroundColor Red
        $failed += $repo
    }
}

$token = $null
Write-Host ""
Write-Host "登録: $ok 件 / 対象外: $skipped 件 / 失敗: $($failed.Count) 件"
if ($failed.Count -gt 0) { $failed | ForEach-Object { Write-Host "  $_" } }

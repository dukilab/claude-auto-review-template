# 自動レビューを導入済みの全リポジトリに CLAUDE_CODE_OAUTH_TOKEN を登録する。
# 使い方: claude setup-token でトークンを作ってから、PowerShell で
#   powershell -ExecutionPolicy Bypass -File scripts\set-token-all.ps1
# を実行し、プロンプトにトークンを貼り付ける（画面には表示されない）。

param(
    [string]$Owner = "sakadukigi"
)

# Windows PowerShell 5.1 では native コマンドの stderr が ErrorRecord になり、
# Stop だとそこで止まってしまうため Continue にして $LASTEXITCODE で判定する。
$ErrorActionPreference = "Continue"
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
    Write-Host "トークンが sk-ant-oat で始まっていません。claude setup-token の出力からトークン部分だけを貼り付けてください。" -ForegroundColor Red
    exit 1
}

$repos = gh repo list $Owner --limit 500 --json nameWithOwner,isEmpty,isArchived `
    -q '.[] | select(.isEmpty|not) | select(.isArchived|not) | .nameWithOwner'
if ($LASTEXITCODE -ne 0) {
    Write-Host "リポジトリ一覧を取得できませんでした。gh auth status を確認してください。" -ForegroundColor Red
    exit 1
}

$ok = 0; $skipped = 0; $failed = @()
foreach ($repo in $repos) {
    # 自動レビューのワークフローが入っているリポジトリだけ対象（404 は対象外、それ以外の失敗は FAIL）
    $res = (gh api "repos/$repo/contents/$workflowPath" --silent 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        if ($res -match "HTTP 404") { $skipped++ }
        else {
            Write-Host "FAIL $repo : $($res.Trim())" -ForegroundColor Red
            $failed += $repo
        }
        continue
    }

    $res = ($token | gh secret set CLAUDE_CODE_OAUTH_TOKEN -R $repo 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK   $repo"
        $ok++
    } else {
        Write-Host "FAIL $repo : $($res.Trim())" -ForegroundColor Red
        $failed += $repo
    }
}

$token = $null
Write-Host ""
Write-Host "登録: $ok 件 / 対象外: $skipped 件 / 失敗: $($failed.Count) 件"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

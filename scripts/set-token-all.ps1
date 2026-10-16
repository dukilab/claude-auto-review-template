# 自動レビューを導入済みのリポジトリに CLAUDE_CODE_OAUTH_TOKEN を登録する。
#
# 使い方（Windows PowerShell）:
#   powershell -ExecutionPolicy Bypass -File scripts\set-token-all.ps1                     # 導入済みの全リポジトリ
#   powershell -ExecutionPolicy Bypass -File scripts\set-token-all.ps1 -Repo owner/name    # 指定したリポジトリだけ
#   powershell -ExecutionPolicy Bypass -File scripts\set-token-all.ps1 -ResetToken         # 保存済みトークンを入れ直す
#
# トークンは初回だけ入力を求め、Windows のユーザー専用暗号化（DPAPI）で
# %APPDATA%\claude-auto-review\oauth-token.xml に保存する。以降は入力なしで登録できる。
# このファイルは同じ Windows ユーザーでしか復号できない。値は画面に表示しない。

param(
    [string]$Owner = "",
    [string[]]$Repo = @(),
    [switch]$ResetToken
)

# Windows PowerShell 5.1 では native コマンドの stderr が ErrorRecord になり、
# Stop だとそこで止まってしまうため Continue にして $LASTEXITCODE で判定する。
$ErrorActionPreference = "Continue"
$workflowPath = ".github/workflows/claude-auto-review.yml"
$storeDir = Join-Path $env:APPDATA "claude-auto-review"
$storeFile = Join-Path $storeDir "oauth-token.xml"

function ConvertTo-PlainText([Security.SecureString]$secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# --- トークンの取得（保存済みがあればそれを使う） ---
$token = $null
if ((Test-Path $storeFile) -and -not $ResetToken) {
    try {
        $token = ConvertTo-PlainText (Import-Clixml $storeFile)
        Write-Host "保存済みのトークンを使います。"
    } catch {
        Write-Host "保存済みトークンを読み込めませんでした。入力し直してください。" -ForegroundColor Yellow
        $token = $null
    }
}
if (-not $token) {
    $secure = Read-Host "CLAUDE_CODE_OAUTH_TOKEN を貼り付けて Enter" -AsSecureString
    # ターミナルからのコピーで混ざる改行・空白を除去
    $token = ((ConvertTo-PlainText $secure) -replace '\s', '')
    if (-not $token.StartsWith("sk-ant-oat")) {
        Write-Host "トークンが sk-ant-oat で始まっていません。claude setup-token の出力からトークン部分だけを貼り付けてください。" -ForegroundColor Red
        exit 1
    }
    New-Item -ItemType Directory -Force $storeDir | Out-Null
    ConvertTo-SecureString $token -AsPlainText -Force | Export-Clixml $storeFile
    Write-Host "トークンを暗号化して保存しました。"
}
$token = ($token -replace '\s', '')
if (-not $token.StartsWith("sk-ant-oat")) {
    Write-Host "保存済みトークンの形式が不正です。-ResetToken を付けて実行し、入力し直してください。" -ForegroundColor Red
    exit 1
}

# --- 対象リポジトリ ---
# powershell -File 経由だと "a/b,c/d" が 1 つの文字列で渡るので分割する
$Repo = @($Repo | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Repo.Count -gt 0) {
    $repos = $Repo
} else {
    if (-not $Owner) {
        $Owner = (gh api user -q .login 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $Owner) {
            Write-Host "GitHub のユーザー名を取得できませんでした。gh auth status を確認してください。" -ForegroundColor Red
            exit 1
        }
    }
    $repos = gh repo list $Owner --limit 1000 --json nameWithOwner,isEmpty,isArchived `
        -q '.[] | select(.isEmpty|not) | select(.isArchived|not) | .nameWithOwner'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "リポジトリ一覧を取得できませんでした。gh auth status を確認してください。" -ForegroundColor Red
        exit 1
    }
}

$ok = 0; $skipped = 0; $failed = @()
foreach ($r in $repos) {
    # 自動レビューのワークフローが入っているリポジトリだけ対象（404 は対象外、それ以外の失敗は FAIL）
    $res = (gh api "repos/$r/contents/$workflowPath" --silent 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        if ($res -match "HTTP 404") {
            if ($Repo.Count -gt 0) { Write-Host "SKIP $r : ワークフローが入っていません" -ForegroundColor Yellow }
            $skipped++
        } else {
            Write-Host "FAIL $r : $($res.Trim())" -ForegroundColor Red
            $failed += $r
        }
        continue
    }

    $res = ($token | gh secret set CLAUDE_CODE_OAUTH_TOKEN -R $r 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK   $r"
        $ok++
    } else {
        Write-Host "FAIL $r : $($res.Trim())" -ForegroundColor Red
        $failed += $r
    }
}

$token = $null
Write-Host ""
Write-Host "登録: $ok 件 / 対象外: $skipped 件 / 失敗: $($failed.Count) 件"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

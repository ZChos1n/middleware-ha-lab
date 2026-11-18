@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Push middleware-ha-lab to GitHub
echo ============================================================
echo.
echo  TWO THINGS TO PREPARE FIRST:
echo.
echo  1) Create an EMPTY public repo on GitHub:
echo     https://github.com/new
echo     - Repository name: middleware-ha-lab
echo     - Public, and DO NOT check "Add a README file"
echo.
echo  2) Generate a token (old ones may be revoked):
echo     https://github.com/settings/tokens/new
echo     - Expiration: 90 days
echo     - Scopes: check BOTH "repo" and "workflow"
echo.
set /p GH_TOKEN="  Paste your ghp_ token here: "

if "%GH_TOKEN%"=="" (
  echo  ERROR: token is empty. Run again.
  pause
  exit /b 1
)

REM --- Use current proxy if present; otherwise direct ---
if defined HTTPS_PROXY (
  echo  Using proxy: %HTTPS_PROXY%
  set HTTP_PROXY=%HTTPS_PROXY%
  set http_proxy=%HTTPS_PROXY%
  set https_proxy=%HTTPS_PROXY%
)

echo.
echo  Configuring remote...
git remote remove origin 2>nul
git remote add origin "https://%GH_TOKEN%@github.com/ZChos1n/middleware-ha-lab.git"

echo  Pushing (branch main)...
git branch -M main
git push -u origin main
set RESULT=%ERRORLEVEL%

echo  Cleaning token from git config...
git remote set-url origin "https://github.com/ZChos1n/middleware-ha-lab.git"

echo.
if "%RESULT%"=="0" (
  echo  SUCCESS: https://github.com/ZChos1n/middleware-ha-lab
) else (
  echo  FAILED - see error above. Common causes:
  echo   - repo not created / wrong name
  echo   - token missing repo or workflow scope
  echo   - proxy issue: set HTTPS_PROXY to your local proxy address
)
echo.
pause

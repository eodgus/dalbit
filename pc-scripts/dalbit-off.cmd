@echo off
rem Double-click: end the running Sunshine session so the second monitor goes away.
rem Sunshine runs the app's undo commands when the session is quit, which removes the virtual display.
rem An optional dalbit-off.local.cmd next to this file runs afterwards for PC-specific cleanup.
chcp 65001 >nul
setlocal
set PKG=io.github.eodgus.dalbit
set SUNSHINE_STATE=%ProgramFiles%\Sunshine\config\sunshine_state.json

for /f "usebackq delims=" %%u in (`powershell -NoProfile -Command "(Get-Content -Raw '%SUNSHINE_STATE%' | ConvertFrom-Json).root.uniqueid"`) do set HOST_UUID=%%u
if not defined HOST_UUID (echo Sunshine 호스트 ID를 읽지 못했습니다: %SUNSHINE_STATE% & pause & exit /b 1)

adb get-state >nul 2>&1 || goto :local
echo 확장모드를 종료하는 중...
adb shell input keyevent KEYCODE_WAKEUP
adb shell am force-stop %PKG%
adb shell am start -n %PKG%/com.limelight.ShortcutTrampoline --es UUID %HOST_UUID% --ez Quit true >nul

:local
if exist "%~dp0dalbit-off.local.cmd" call "%~dp0dalbit-off.local.cmd"
echo 확장모드를 종료했습니다.
echo 잠시 후 창이 닫힙니다.
timeout /t 3

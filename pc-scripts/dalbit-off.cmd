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

rem Same device choice as dalbit-on.cmd: USB first, then a wireless debugging device.
set ADB=adb -d
%ADB% get-state >nul 2>&1 && goto :found
for /l %%i in (1,1,5) do (
  for /f "tokens=1,2" %%s in ('adb devices') do if "%%t"=="device" (
    echo %%s| findstr /c:":" /c:"_adb-tls" >nul && (set "ADB=adb -s %%s" & goto :found)
  )
  for /f "tokens=3" %%a in ('adb mdns services 2^>nul ^| findstr /c:"_adb-tls-connect._tcp"') do adb connect %%a >nul
  timeout /t 1 /nobreak >nul
)
echo 기기를 찾지 못했습니다. USB 케이블로 연결하거나, 기기의 개발자 옵션에서 무선 디버깅을 켜 주세요.
goto :local

:found
echo 확장모드를 종료하는 중...
%ADB% shell input keyevent KEYCODE_WAKEUP
%ADB% shell am force-stop %PKG%
rem Dalbit only takes Quit through QuitTrampoline, which only adb can start.
%ADB% shell am start -n %PKG%/com.limelight.QuitTrampoline --es UUID %HOST_UUID% --ez Quit true >nul

:local
if exist "%~dp0dalbit-off.local.cmd" call "%~dp0dalbit-off.local.cmd"
echo 확장모드를 종료했습니다.
echo 잠시 후 창이 닫힙니다.
timeout /t 3

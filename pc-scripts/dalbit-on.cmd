@echo off
rem Double-click: turn the Android device into a second monitor.
rem Wakes the device, turns on USB tethering, waits for the PC side of the link,
rem then starts the Sunshine app named below in Dalbit (Dalbit prefers the USB link).
rem Without a USB adb device it uses a paired wireless debugging device and only starts Dalbit.
rem Needs adb (Android platform-tools) on PATH and USB or wireless debugging on the device.
chcp 65001 >nul
setlocal
rem Name of the Sunshine app that extends the desktop onto the virtual display.
set APP=Extend Mode
set PKG=io.github.eodgus.dalbit
set SUNSHINE_STATE=%ProgramFiles%\Sunshine\config\sunshine_state.json

for /f "usebackq delims=" %%u in (`powershell -NoProfile -Command "(Get-Content -Raw '%SUNSHINE_STATE%' | ConvertFrom-Json).root.uniqueid"`) do set HOST_UUID=%%u
if not defined HOST_UUID (echo Sunshine 호스트 ID를 읽지 못했습니다: %SUNSHINE_STATE% & pause & exit /b 1)

rem Prefer USB, even when the device is also connected over Wi-Fi.
set ADB=adb -d
%ADB% get-state >nul 2>&1 && goto :found
rem Otherwise use a paired device with wireless debugging on. adb connects to it by itself once mDNS finds it,
rem which can take a moment after the adb server starts, so also connect to the address mDNS advertises.
rem -e fails when more than one TCP device or emulator is connected; use -s <serial> if that happens.
set ADB=adb -e
for /l %%i in (1,1,5) do (
  %ADB% get-state >nul 2>&1 && goto :found
  for /f "tokens=3" %%a in ('adb mdns services 2^>nul ^| findstr /c:"_adb-tls-connect._tcp"') do adb connect %%a >nul
  timeout /t 1 /nobreak >nul
)
echo 기기를 찾지 못했습니다. USB 케이블로 연결하거나, 기기의 개발자 옵션에서 무선 디버깅을 켜 주세요.
pause & exit /b 1

:found
%ADB% shell input keyevent KEYCODE_WAKEUP
rem Only skips a swipe lock screen; a PIN/pattern still has to be entered on the device.
%ADB% shell wm dismiss-keyguard
rem Over Wi-Fi there is no tethering to set up; Dalbit connects over Wi-Fi by itself.
if "%ADB%"=="adb -e" goto :launch

%ADB% shell ip -4 addr show rndis0 2>nul | findstr /c:"inet " >nul && goto :tethered
echo PC 쪽 USB 연결을 기다리는 중...
echo USB 테더링 켜는 중...
rem USB re-enumerates here, so adb drops for a moment.
%ADB% shell svc usb setFunctions rndis
%ADB% wait-for-device
for /l %%i in (1,1,20) do (
  %ADB% shell ip -4 addr show rndis0 2>nul | findstr /c:"inet " >nul && goto :tethered
echo PC 쪽 USB 연결을 기다리는 중...
  timeout /t 1 /nobreak >nul
)
echo USB 테더링을 켜지 못했습니다. 기기의 테더링 설정 화면을 엽니다.
%ADB% shell am start -a android.settings.TETHER_SETTINGS >nul
pause & exit /b 1

:tethered
echo PC 쪽 USB 연결을 기다리는 중...
rem Wait for Windows to get an address on the tethering adapter, or Dalbit falls back to Wi-Fi.
powershell -NoProfile -Command "$t=0; while ($t -lt 20 -and -not (Get-NetAdapter -InterfaceDescription '*Remote NDIS*' -ErrorAction SilentlyContinue | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ? IPAddress -notlike '169.254*')) { sleep 1; $t++ }"

:launch
%ADB% shell am start -n %PKG%/com.limelight.ShortcutTrampoline --es UUID %HOST_UUID% --es AppName "'%APP%'" >nul
echo 확장모드 연결을 시작했습니다.
echo 잠시 후 창이 닫힙니다.
timeout /t 3

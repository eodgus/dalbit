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
rem Otherwise use a device on Wi-Fi: a paired one with wireless debugging on, or one already connected with
rem adb connect. adb connects to a paired device by itself once mDNS finds it, which can take a moment after the
rem adb server starts, so also connect to the address mDNS advertises. The serial is picked explicitly because
rem adb -e fails when the same device shows up both ways.
for /l %%i in (1,1,5) do (
  for /f "tokens=1,2" %%s in ('adb devices') do if "%%t"=="device" (
    echo %%s| findstr /c:":" /c:"_adb-tls" >nul && (set "ADB=adb -s %%s" & goto :found)
  )
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
if not "%ADB%"=="adb -d" goto :launch

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
rem Keeps the mouse cursor on the main monitor when the tablet is touched; dalbit-off.cmd stops it.
start "" powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0dalbit-cursor.ps1"
%ADB% shell am start -n %PKG%/com.limelight.ShortcutTrampoline --es UUID %HOST_UUID% --es AppName "'%APP%'" >nul
echo 확장모드 연결을 시작했습니다.
echo 잠시 후 창이 닫힙니다.
timeout /t 3

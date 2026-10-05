@echo off
rem Double-click: turn the USB-connected Android device into a second monitor.
rem Wakes the device, turns on USB tethering, waits for the PC side of the link,
rem then starts the Sunshine app named below in Dalbit (Dalbit prefers the USB link).
rem Needs adb (Android platform-tools) on PATH and USB debugging on the device.
chcp 65001 >nul
setlocal
rem Name of the Sunshine app that extends the desktop onto the virtual display.
set APP=Extend Mode
set PKG=io.github.eodgus.dalbit
set SUNSHINE_STATE=%ProgramFiles%\Sunshine\config\sunshine_state.json

for /f "usebackq delims=" %%u in (`powershell -NoProfile -Command "(Get-Content -Raw '%SUNSHINE_STATE%' | ConvertFrom-Json).root.uniqueid"`) do set HOST_UUID=%%u
if not defined HOST_UUID (echo Sunshine 호스트 ID를 읽지 못했습니다: %SUNSHINE_STATE% & pause & exit /b 1)

adb get-state >nul 2>&1 || (echo 기기가 USB/ADB로 연결돼 있지 않습니다. & pause & exit /b 1)

adb shell input keyevent KEYCODE_WAKEUP
rem Only skips a swipe lock screen; a PIN/pattern still has to be entered on the device.
adb shell wm dismiss-keyguard

adb shell ip -4 addr show rndis0 2>nul | find "inet " >nul && goto :tethered
echo PC 쪽 USB 연결을 기다리는 중...
echo USB 테더링 켜는 중...
rem USB re-enumerates here, so adb drops for a moment.
adb shell svc usb setFunctions rndis
adb wait-for-device
for /l %%i in (1,1,20) do (
  adb shell ip -4 addr show rndis0 2>nul | find "inet " >nul && goto :tethered
echo PC 쪽 USB 연결을 기다리는 중...
  timeout /t 1 /nobreak >nul
)
echo USB 테더링을 켜지 못했습니다. 기기의 테더링 설정 화면을 엽니다.
adb shell am start -a android.settings.TETHER_SETTINGS >nul
pause & exit /b 1

:tethered
echo PC 쪽 USB 연결을 기다리는 중...
rem Wait for Windows to get an address on the tethering adapter, or Dalbit falls back to Wi-Fi.
powershell -NoProfile -Command "$t=0; while ($t -lt 20 -and -not (Get-NetAdapter -InterfaceDescription '*Remote NDIS*' -ErrorAction SilentlyContinue | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ? IPAddress -notlike '169.254*')) { sleep 1; $t++ }"

adb shell am start -n %PKG%/com.limelight.ShortcutTrampoline --es UUID %HOST_UUID% --es AppName "'%APP%'" >nul
echo 확장모드 연결을 시작했습니다.
echo 잠시 후 창이 닫힙니다.
timeout /t 3

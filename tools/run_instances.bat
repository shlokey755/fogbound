@echo off
REM Opens several Fogbound windows on ONE Windows computer so you can test the
REM hosted (hotspot) game without a second device. Window 1 hosts, the rest join.
REM
REM Usage:  set GODOT=C:\path\to\Godot_v4.3-stable_win64.exe
REM         tools\run_instances.bat [WINDOWS]       (2 to 4, default 2)
REM
REM Click inside a window to give it the keyboard, then use WASD / arrows.

setlocal
if "%GODOT%"=="" set GODOT=godot
set COUNT=%1
if "%COUNT%"=="" set COUNT=2
cd /d "%~dp0.."

"%GODOT%" --headless --path . --import >nul 2>&1

start "Fogbound host" "%GODOT%" --path . --resolution 640x360 --position 0,0 -- --auto-host --name=Host
timeout /t 2 /nobreak >nul
start "Fogbound Ann" "%GODOT%" --path . --resolution 640x360 --position 660,0 -- --auto-join --name=Ann
if %COUNT% GEQ 3 start "Fogbound Ben" "%GODOT%" --path . --resolution 640x360 --position 0,420 -- --auto-join --name=Ben
if %COUNT% GEQ 4 start "Fogbound Cy" "%GODOT%" --path . --resolution 640x360 --position 660,420 -- --auto-join --name=Cy

echo Started %COUNT% windows. In the host window pick a level and press START
echo (joiners press Ready first).
endlocal

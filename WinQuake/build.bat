@echo off
echo ========================================
echo OpenWatcom Build Script for Quake DOS
echo ========================================
echo.

REM Set OpenWatcom environment variables
set WATCOM=C:\WATCOM
set PATH=%WATCOM%\BINNT;%WATCOM%\BINW;%PATH%

REM Verify tools are available
echo Checking OpenWatcom installation...
where wcc386 >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: wcc386 not found!
    echo Please ensure OpenWatcom is installed in C:\WATCOM
    pause
    exit /b 1
)

where wasm >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: wasm not found!
    echo Please ensure OpenWatcom is installed in C:\WATCOM
    pause
    exit /b 1
)

where wlink >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: wlink not found!
    echo Please ensure OpenWatcom is installed in C:\WATCOM
    pause
    exit /b 1
)

echo.
echo OpenWatcom tools found successfully!
echo.
echo Starting build...
echo.

REM Run the build
wmake -f Makefile all

echo.
echo Build complete!
echo.
if exist quake486.exe (
    echo ========================================
    echo SUCCESS! quake486.exe created!
    echo ========================================
    echo.
    dir quake486.exe
) else (
    echo ========================================
    Build failed. Please review errors above.
    echo ========================================
)

pause

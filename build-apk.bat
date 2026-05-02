@echo off
setlocal
chcp 65001 >nul 2>&1

echo ==============================
echo   Music Player APK Builder
echo ==============================
echo.

echo [1/4] Stopping Gradle daemon...
call android\gradlew.bat --stop
if %errorlevel% neq 0 goto failed

echo.
echo [2/4] Cleaning release build cache...
if exist "build\app\intermediates\flutter\release" rmdir /s /q "build\app\intermediates\flutter\release"
if exist "build\app\outputs\apk\release" rmdir /s /q "build\app\outputs\apk\release"
if exist "build\app\outputs\flutter-apk\app-release.apk" del /f /q "build\app\outputs\flutter-apk\app-release.apk"
if exist "build\app\outputs\flutter-apk\app-release.apk.sha1" del /f /q "build\app\outputs\flutter-apk\app-release.apk.sha1"

echo.
echo [3/4] Fetching dependencies...
call flutter pub get
if %errorlevel% neq 0 goto failed

echo.
echo [4/4] Building release APK...
call flutter build apk --release
if %errorlevel% neq 0 goto failed

echo.
echo ==============================
echo   Build SUCCESS!
echo   APK: build\app\outputs\flutter-apk\app-release.apk
echo ==============================
goto done

:failed
echo.
echo ==============================
echo   Build FAILED!
echo ==============================

:done
pause

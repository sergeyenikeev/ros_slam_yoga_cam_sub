@echo off
setlocal
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PACKAGE_ROOT=%%~fI"
for %%I in ("%PACKAGE_ROOT%\..\..") do set "WORKSPACE_ROOT=%%~fI"

if not defined ROS2_UNDERLAY set "ROS2_UNDERLAY=C:\pixi_ws\ros2-windows"
if not defined PIXI_PROJECT_ROOT set "PIXI_PROJECT_ROOT=C:\pixi_ws"
if not defined PIXI_ENV_ROOT set "PIXI_ENV_ROOT=%PIXI_PROJECT_ROOT%\.pixi\envs\default"
if not defined PIXI_EXE set "PIXI_EXE=C:\Users\senik\.pixi\bin\pixi.exe"
if not defined RMW_IMPLEMENTATION set "RMW_IMPLEMENTATION=rmw_fastrtps_cpp"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VCVARS64="
if exist "%VSWHERE%" (
  for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find VC\Auxiliary\Build\vcvars64.bat`) do set "VCVARS64=%%~fI"
)
if not defined VCVARS64 set "VCVARS64=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS64%" exit /b 1

set "NINJA_EXE=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
if not exist "%NINJA_EXE%" exit /b 1
for %%I in ("%NINJA_EXE%") do set "NINJA_DIR=%%~dpI"

if not exist "%ROS2_UNDERLAY%\local_setup.bat" exit /b 1
if not exist "%PIXI_ENV_ROOT%\Scripts\colcon.exe" exit /b 1

call "%VCVARS64%"
if errorlevel 1 exit /b %errorlevel%

set "VisualStudioVersion=17.0"
set "CMAKE_GENERATOR=Ninja"
set "CMAKE_MAKE_PROGRAM=%NINJA_EXE%"
set "CMAKE_C_COMPILER=cl.exe"
set "CMAKE_CXX_COMPILER=cl.exe"
set "OpenCV_DIR=%PIXI_ENV_ROOT%\Library\cmake"
if exist "%OpenCV_DIR%\x64\vc17\lib\OpenCVConfig.cmake" set "OpenCV_DIR=%OpenCV_DIR%\x64\vc17\lib"
if exist "%OpenCV_DIR%\x64\vc16\lib\OpenCVConfig.cmake" set "OpenCV_DIR=%OpenCV_DIR%\x64\vc16\lib"

set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "PATH=%NINJA_DIR%;%PIXI_ENV_ROOT%;%PIXI_ENV_ROOT%\Library\mingw-w64\bin;%PIXI_ENV_ROOT%\Library\usr\bin;%PIXI_ENV_ROOT%\Library\bin;%PIXI_ENV_ROOT%\Scripts;%PIXI_ENV_ROOT%\bin;%PATH%"
set "CONDA_PREFIX=%PIXI_ENV_ROOT%"
set "PIXI_IN_SHELL=1"
set "PIXI_ENVIRONMENT_NAME=default"
set "PIXI_PROJECT_MANIFEST=%PIXI_PROJECT_ROOT%\pixi.toml"
set "PIXI_PROJECT_ROOT=%PIXI_PROJECT_ROOT%"
set "PIXI_EXE=%PIXI_EXE%"

call "%ROS2_UNDERLAY%\local_setup.bat"
if errorlevel 1 exit /b %errorlevel%

if exist "%WORKSPACE_ROOT%\install\local_setup.bat" (
  call "%WORKSPACE_ROOT%\install\local_setup.bat"
  if errorlevel 1 exit /b %errorlevel%
)

if "%~1"=="" (
  cd /d "%WORKSPACE_ROOT%"
  cmd /k
  exit /b 0
)

cd /d "%WORKSPACE_ROOT%"
call %*
exit /b %errorlevel%

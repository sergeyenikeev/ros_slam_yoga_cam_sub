@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%run_in_ros_env.cmd" colcon build --merge-install --packages-select yoga_cam_sub --cmake-clean-cache --cmake-force-configure --event-handlers console_cohesion+ --cmake-args -GNinja -DCMAKE_BUILD_TYPE=Release
exit /b %errorlevel%

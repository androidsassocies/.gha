@echo off
pushd "%~dp0"

RunUAT.bat BuildPlugin -plugin="PATH\TO\PLUGIN\MyPlugin.uplugin" -package="MY\NEW\PATH" -TargetPlatforms=Win64

popd

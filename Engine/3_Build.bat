set "PATH=c:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\Tools\;c:\Windows\System32"
call vsvars32.bat
devenv Build/INSTALL.vcxproj /build Release
pause

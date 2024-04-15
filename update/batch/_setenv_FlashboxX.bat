rem FlashboxX Settings
set FBX_IP=192.168.8.10
set FBX_LOGIN=pi
set FBX_PASSWORD=FlashboxX

rem tools
set PUTTYEXE=".\putty\putty.exe"
set PLINKEXE=".\putty\plink.exe"
set PSCPEXE=".\putty\pscp.exe"

rem If there is a config inside the userprofile use it
if exist "%USERPROFILE%\_setenv_FlashboxX.bat" (
    call "%USERPROFILE%\_setenv_FlashboxX.bat"
)

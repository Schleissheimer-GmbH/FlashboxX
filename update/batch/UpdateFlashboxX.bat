@echo off
call ".\_setenv_FlashboxX.bat"

echo : Copy files to FlashboxX %FBX_IP%
%PSCPEXE% -r -scp -batch -pw %FBX_PASSWORD% -P 22 "update" %FBX_LOGIN%@%FBX_IP%:/tmp

echo : Run update script on FlashboxX
%PLINKEXE% -ssh -P 22 -t -batch -pw %FBX_PASSWORD% %FBX_LOGIN%@%FBX_IP% "sudo chmod +x /tmp/update/UpdateFlashboxX.sh; sudo /tmp/update/UpdateFlashboxX.sh"

echo.
pause

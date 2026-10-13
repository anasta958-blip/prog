Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "WordFunc.nsh"

!define UninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\SkladKomforta"
Name "Склад Комфорта"
OutFile "${ReleaseDir}\SkladKomforta-${FileVersion}-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\SkladKomforta"
RequestExecutionLevel user
ManifestSupportedOS all
SetCompressor /SOLID zlib
VIProductVersion "${FileVersion}"
VIAddVersionKey /LANG=1049 "ProductName" "Склад Комфорта"
VIAddVersionKey /LANG=1049 "FileDescription" "Установка Склад Комфорта"
VIAddVersionKey /LANG=1049 "FileVersion" "${FileVersion}"
VIAddVersionKey /LANG=1049 "LegalCopyright" "Склад Комфорта"
ShowInstDetails show
ShowUninstDetails show
AllowSkipFiles off

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "Клиент будет установлен только для текущего пользователя, без прав администратора.$\r$\n$\r$\nПеред установкой или обновлением закройте приложение «Склад Комфорта».$\r$\n$\r$\nДля работы требуется подключение к интернету."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
InstallDir "$LOCALAPPDATA\Programs\SkladKomforta"
InstallDirRegKey HKCU "${UninstallKey}" "InstallLocation"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Function .onInit
  SetShellVarContext current
  SetRegView 64
  ${IfNot} ${IsNativeAMD64}
    MessageBox MB_ICONSTOP "Требуется Windows 10/11 x64."
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "Требуется Windows 10 или новее."
    Abort
  ${EndIf}
  ReadRegStr $0 HKCU "${UninstallKey}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} $0 "${FileVersion}" $1
    ${If} $1 == 1
      MessageBox MB_ICONSTOP "Уже установлена более новая версия приложения."
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

Section "Приложение (обязательно)" Main
  SectionIn RO
  !include "${ReleaseDir}\install-files.nsh"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateShortcut "$SMPROGRAMS\Склад Комфорта.lnk" "$INSTDIR\sklad_komforta_app.exe"
  WriteRegStr HKCU "${UninstallKey}" "DisplayName" "Склад Комфорта"
  WriteRegStr HKCU "${UninstallKey}" "DisplayVersion" "${FileVersion}"
  WriteRegStr HKCU "${UninstallKey}" "Publisher" "Склад Комфорта"
  WriteRegStr HKCU "${UninstallKey}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UninstallKey}" "DisplayIcon" "$INSTDIR\sklad_komforta_app.exe"
  WriteRegStr HKCU "${UninstallKey}" "UninstallString" '$\"$INSTDIR\uninstall.exe$\"'
  WriteRegDWORD HKCU "${UninstallKey}" "NoModify" 1
  WriteRegDWORD HKCU "${UninstallKey}" "NoRepair" 1
SectionEnd

Section /o "Ярлык на рабочем столе" Desktop
  CreateShortcut "$DESKTOP\Склад Комфорта.lnk" "$INSTDIR\sklad_komforta_app.exe"
SectionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 64
FunctionEnd

Section "Uninstall"
  ClearErrors
  Delete "$INSTDIR\sklad_komforta_app.exe"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "Закройте приложение «Склад Комфорта» и повторите удаление."
    Abort
  ${EndIf}
  !include "${ReleaseDir}\uninstall-files.nsh"
  Delete "$INSTDIR\uninstall.exe"
  Delete "$SMPROGRAMS\Склад Комфорта.lnk"
  Delete "$DESKTOP\Склад Комфорта.lnk"
  DeleteRegKey HKCU "${UninstallKey}"
  RMDir "$INSTDIR"
SectionEnd

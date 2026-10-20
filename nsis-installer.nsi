!include "MUI2.nsh"
; The name of the installer
Name "NLC Toolkit"

; The file to write
OutFile "nlc-toolkit-setup-win.exe"

; Request application privileges for Windows Vista and higher
RequestExecutionLevel admin

; Build Unicode installer
Unicode True

; The default installation directory
InstallDir "$PROGRAMFILES\NLC Toolkit"

; Registry key to check for directory (so if you install again, it will 
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\NLCToolkit" "Install_Dir"
!define MUI_ICON "chameleonultragui\windows\runner\resources\app_icon.ico"

;--------------------------------

; Pages
!insertmacro MUI_PAGE_LICENSE "LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
  
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------

!insertmacro MUI_LANGUAGE "English"


; The stuff to install
Section "NLC Toolkit (required)"

  SectionIn RO
  
  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  
  ; Put file there
  File /r "chameleonultragui\build\windows\x64\runner\Release\*.*"
  File "LICENSE"
  
  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\NLCToolkit "Install_Dir" "$INSTDIR"
  
  ; Write the uninstall keys for Windows
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NLCToolkit" "DisplayName" "NLC Toolkit"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NLCToolkit" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NLCToolkit" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NLCToolkit" "NoRepair" 1
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
SectionEnd

; Optional section (can be disabled by the user)
Section "Start Menu Shortcuts"
  CreateShortcut "$SMPROGRAMS\NLC Toolkit.lnk" "$INSTDIR\nlc_toolkit.exe"
SectionEnd

; Optional section (can be disabled by the user)
Section "Desktop Shortcut"
  CreateShortcut "$DESKTOP\NLC Toolkit.lnk" "$INSTDIR\nlc_toolkit.exe"
SectionEnd

;--------------------------------

; Uninstaller

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NLCToolkit"
  DeleteRegKey HKLM SOFTWARE\NLCToolkit

  ; Remove shortcuts, if any
  Delete "$SMPROGRAMS\NLC Toolkit.lnk"
  Delete "$DESKTOP\NLC Toolkit.lnk"

  ; Remove installation directory and all contents
  RMDir /r "$INSTDIR"

SectionEnd

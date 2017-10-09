﻿#######################################################################################
# WinForm with a SplitContainer to host 2 Windows File Explorers
# System.Windows.Forms.SplitContainer is a simple dual panel controller with a draggable splitter in the middle - how convenient!

#########################################################################################################################
#########################################################################################################################
#
# Latest source here: https://beejpowershell.codeplex.com/SourceControl/latest#PoshDualExplorers/PoshDualExplorers.ps1
#
#########################################################################################################################
#########################################################################################################################

# helpful posts
# http://www.codeproject.com/Articles/101367/Code-to-Host-a-Third-Party-Application-in-our-Proc
# http://www.codedisqus.com/CNVqVXqgUV/how-to-find-a-desktop-window-by-window-name-in-windows-81-update-2-os-using-the-win32-api-findwindow-in-powershell-environment.html
# http://www.catch22.net/software/winspy-17
# http://social.technet.microsoft.com/wiki/contents/articles/26207.how-to-add-a-powershell-gui-event-handler-with-parameters-part-2.aspx
# http://poshcode.org/4206
# https://gallery.technet.microsoft.com/scriptcenter/dd9d04c2-592b-4eb5-bb09-cd5725d35e68
# http://stackoverflow.com/questions/2518257/get-the-selected-file-in-an-explorer-window
# http://stackoverflow.com/questions/14193388/how-to-get-windows-explorers-selected-files-from-within-c
# http://windowsitpro.com/scripting/understanding-vbscript-shell-object-model-s-folder-and-folderitem-objects

# these two posts in particular showed me the approach that worked out for the file copy piece
#   http://blog.backslasher.net/copying-files-in-powershell-using-windows-explorer-ui.html
#   http://stackoverflow.com/questions/8292953/get-current-selection-in-windowsexplorer-from-a-c-sharp-application

$Error.Clear()

#load up all our .Net helper assemblies...
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
#Add-Type -Path $PSScriptRoot\Interop.SHDocVw.dll #generated by temporarily creating a Visual Studio project, then referencing C:\windows\system32\shdocvmw.dll and looking in the bin folder for this interop DLL
& $PSScriptRoot\Win32.ps1 #bunch of win32 api exports
& $PSScriptRoot\FontAwesome.ps1 # handy wrapper for FontAwesome as a .Net class, from here: https://github.com/microvb/FontAwesome-For-WinForms-CSharp

#save MainWindowHandle so we can hide explicitly here and keep available for showing at end for troubleshooting, IIF PowerShell errors were emitted 
#nugget: don't use -WindowStyle Hidden on the ps1 shortcut, it prevents retrieval of main MainWindowHandle here...
$process = Get-Process -Id $pid
$poShConsoleHwnd = $process.MainWindowHandle
if ($process.ProcessName -eq "powershell_ise") { $poShConsoleHwnd=0 }
function showPoShConsole {
  param([bool]$show = $true)
  
  if ($show -and [Win32]::IsWindowVisible($poShConsoleHwnd)) { $show=$false }

  [Win32]::ShowWindowAsync($poShConsoleHwnd, @([Win32]::SW_HIDE, [Win32]::SW_SHOWNORMAL)[$show]) | Out-Null
  [Win32]::SetForegroundWindow($poShConsoleHwnd) | Out-Null
}

showPoShConsole $false

# http://www.codeproject.com/Articles/101367/Code-to-Host-a-Third-Party-Application-in-our-Proc
#make sure any win32 messages like this aren't called till after wndproc message pump starts (i.e. [System.Windows.Forms.Application]::Run($frmMain))
$splitContainer_Resize =
{
  if (!$splitContainer.Panel1.Tag.Hwnd) { return }
  [Win32]::SetWindowPos(
      $splitContainer.Panel1.Tag.Hwnd,
      [Win32]::HWND_TOP,
      $splitContainer.Panel1.ClientRectangle.Left,
      $splitContainer.Panel1.ClientRectangle.Top-31, #these extra pixels hide the deadzone at top of file explorer window, maybe reserved for quick access toolbar
      $splitContainer.Panel1.ClientRectangle.Width,
      $splitContainer.Panel1.ClientRectangle.Height+31,
      [Win32]::NOACTIVATE -bor [Win32]::SHOWWINDOW
  ) | Out-Null

  if (!$splitContainer.Panel2.Tag.Hwnd) { return }
  [Win32]::SetWindowPos(
      $splitContainer.Panel2.Tag.Hwnd,
      [Win32]::HWND_TOP,
      $splitContainer.Panel2.ClientRectangle.Left,
      $splitContainer.Panel2.ClientRectangle.Top-31, #these extra pixels hide the deadzone at top of file explorer window, maybe reserved for quick access toolbar
      $splitContainer.Panel2.ClientRectangle.Width,
      $splitContainer.Panel2.ClientRectangle.Height+31,
      [Win32]::NOACTIVATE -bor [Win32]::SHOWWINDOW
  ) | Out-Null

}

$settingsPath = "$env:LocalAppData\PoShDualExplorers"

if ((Test-Path "$settingsPath\settings.xml")) {
  # from: https://practical365.com/exchange-server/using-xml-settings-file-powershell-scripts/
  $settings = Import-Clixml "$settingsPath\settings.xml"
}
else {
  $settings = @{}
  $settings.LeftFolders  = @("$env:USERPROFILE\Downloads")
  $settings.RightFolders = @("$env:USERPROFILE\Downloads")
}

function newFileEx {
  param([bool]$leftSide)

  # there's a few obnoxious bummers in play with regards to reliably launching an explorer window...
  # the Win32 FindWindow API used to retrieve the new explorer window handle (a linchpin in this overall approach) only locates by window title, so we need a reliable way to set that title...
  # using anything that flows through the explorer shell path "association" logic (e.g. Shell.Application.Explore(), start, item-invoke, etc) will, for example, mangle "c:\users\beej\downloads" to just "downloads" in the window title
  # further, start & invoke-item wind up creating a new quizo tab on the most recently created explorer window which actually screws up getting separate windows for left and right side panels...
  # launching explorer.exe "path" directly does conveniently yield a deterministic title like c:\users\beej\downloads 
  # BUT for some reason the Quizo Tabs didn't survive after the Win32 SetParent call versus the other launch approaches (fascinating)
  # fortunately, Shell.Application.Explore() actually does yield new windows yet still yields working Quizo tabs... it's the only thing i've found that threads the needle of constraints

  # so, use a known path we can lock onto...
  $objShell.Explore("$env:USERPROFILE\Downloads")
  do { $hwnd = [Win32]::FindWindow("CabinetWClass", "Downloads") } while ( $hwnd -eq 0 )
  # if these windows class lookups change in a future version of Windows, WinSpy tool is our friend: http://www.catch22.net/software/winspy-17
  

  #snag and save the individual "Window" interface (SHDocVw.InternetExplorer) for each of our File Explorers - to be used later for pulling the currently selected items in the CopyFile code
  #this stopped working out of the blue with an exception "0x80010100 (RPC_E_SYS_CALL_FAILED)" on certain shellwindow items: { $shDocVw = $shellWindows | ?{$_.HWND -eq $hwnd} } while ( !$shDocVw ) #my quick testing showed this would cycle 8 to 12 times before quiescing to a value
  $tries = 0
  do {
    $tries++
    for($idx=0; $idx -lt $shellwindows.Count; $idx++) {
      try {
       if ($shellwindows.Item($idx).HWND -eq $hwnd) { $shDocVw = $shellwindows.Item($idx); break }  #$shellwindows.Item($idx) could throw exception
      }
      catch {}
    }
  }
  while (!$shDocVw -and $tries -lt 20)
  if (!$shDocVw) {[System.Windows.Forms.MessageBox]::Show("couldn't obtain Explorer hWnd! aborting."); exit}

  $container = @($splitContainer.Panel2, $splitContainer.Panel1)[$leftSide]

  [Win32]::HideTitleBar($hwnd)

  $container.Tag = New-Object –TypeName PSObject -Property @{ ShDocVw=$shDocVw; Hwnd=$hwnd }

  # set the first tab to the first saved folder
  @((rightShell), (leftShell))[$leftSide].Navigate( (@($settings.RightFolders, $settings.LeftFolders)[$leftSide])[0] )

  # if Quizo Tabs are installed, launch folders from last saved session, which will pop in as tabs
  try {
    $qs = New-Object -ComObject "QTTabBarLib.Scripting"
    @($settings.RightFolders, $settings.LeftFolders)[$leftSide] | select -skip 1 | % { ii $_ }
    sleep -m 500
  } catch {}

  # i know it's silly but actually getting around to try this SetParent hack for creating dual explorers has been nagging me for years
  # had to move SetParent till after all initial launches to allow each one to "catch" it's restored last session tabs
  [Win32]::SetParent( $hwnd, @($splitContainer.Panel2.Handle, $splitContainer.Panel1.Handle)[$leftSide] ) | Out-Null
}


function uriToWindowsPath {
  param([string]$uri)

  #interesting, local drive letter paths get extra "file:///" prefix but UNC paths just get extra "file:"
  return [uri]::UnEscapeDataString($uri).Replace("file:///", "").Replace("file:", "").Replace("/", [char]92) #char92 just hides slash character from blog > google prettyprint munging
}

#IWebBrowser2 documentation gives several handy methods implemented on our ShDocVw object => https://msdn.microsoft.com/en-us/library/aa752127(v=vs.85).aspx
function leftShell { return $splitContainer.Panel1.Tag.ShDocVw }
function rightShell { return $splitContainer.Panel2.Tag.ShDocVw }
function leftPath { return uriToWindowsPath (leftShell).LocationUrl }
function rightPath { return uriToWindowsPath (rightShell).LocationUrl }
function leftSelectedItems { (leftShell).Document.SelectedItems() }
function rightSelectedItems { (rightShell).Document.SelectedItems() }
function leftFirstSelectedPath { $items = leftSelectedItems; if ($items -isnot [system.array]) { $items.Path } else { if ($items.Count -gt 0) { $items.Item(0).Path } } }
function rightFirstSelectedPath { $items = rightSelectedItems; if ($items -isnot [system.array]) { $items.Path } else { if ($items.Count -gt 0) { $items.Item(0).Path } } }

function copyLeftToRight {
  param([bool]$move)

  #debug: [System.Windows.Forms.MessageBox]::Show($explorerLeft_SHDocVw.Document.FocusedItem.Path)
  #debug: [System.Windows.Forms.MessageBox]::Show($explorerRight_SHDocVw.LocationUrl)
  
  # these two posts are what showed me the approach that worked here          
  #   http://blog.backslasher.net/copying-files-in-powershell-using-windows-explorer-ui.html
  #   http://stackoverflow.com/questions/8292953/get-current-selection-in-windowsexplorer-from-a-c-sharp-application

  $rightFolder = $objShell.NameSpace((rightPath))
  #when SHDocVw.InternetExplorer is hosting a File Explorer vs IE, it's .Document property then implements the Shell32.IShellFolderViewDual interface (among others, but this is the one we care about here)
  # => https://msdn.microsoft.com/en-us/library/windows/desktop/dd894076(v=vs.85).aspx

  #so then Shell32.IShellFolderViewDual.SelectedItems gives us a FolderItems collection => https://msdn.microsoft.com/en-us/library/windows/desktop/bb787800(v=vs.85).aspx
  # which naturally contains a list of FolderItem => https://msdn.microsoft.com/en-us/library/windows/desktop/bb787810(v=vs.85).aspx
  # but we're actually on interested in the collection itself in this case
  # and it's interesting that the Shell.Application.CopyHere method is compatible with the objects obtained from SHDocVw...
  # i.e. one starts to see that as obtuse as all these interfaces seem at first, they do actually hang together

  # Folder.CopyHere - https://msdn.microsoft.com/en-us/library/windows/desktop/bb787866%28v=vs.85%29.aspx
  @($rightFolder.CopyHere, $rightFolder.MoveHere)[$move].Invoke((leftShell).Document.SelectedItems()) #interesting, couldn't pass FolderItems collection as function result, would always only do first item
}

# https://msdn.microsoft.com/en-us/library/windows/desktop/bb787866%28v=vs.85%29.aspx
$objShell = New-Object -ComObject "Shell.Application"

#Shell.Application::Windows() gives us a collection of "SHDocVw.InternetExplorer" objects: https://msdn.microsoft.com/en-us/library/aa752084(v=vs.85).aspx
#which is goofy naming since this has nothing to do with IE but that's obviously just the way MS baked the shared UI components together
$shellWindows = $objShell.Windows()

$splitContainer = new-object System.Windows.Forms.SplitContainer
$splitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitContainer.SplitterWidth = 20

$frmMain = New-Object System.Windows.Forms.Form
$frmMain.Text = "DuEx"
$frmMain.Icon = New-Object system.drawing.icon ("$PSScriptRoot\PoShDualExplorers.ico")
$frmMain.WindowState = "Maximized";
$frmMain.Controls.Add($splitContainer)
$frmMain.Add_Resize($splitContainer_Resize)
$splitContainer.SplitterDistance = $frmMain.ClientRectangle.Width / 2;

#button toolbar
#https://adminscache.wordpress.com/2014/08/03/powershell-winforms-menu/
$buttonPanel = new-object System.Windows.Forms.Panel
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$frmMain.Controls.Add($splitContainer) | Out-Null
$frmMain.Controls.Add($buttonPanel) | Out-Null

function createButton {
    param([string]$toolTip, [string]$caption, [string]$faType, [System.Windows.Forms.Control]$parent, [scriptblock]$action)
    $faBtn = New-Object FaButton(55, 31, $toolTip, $caption, 32, $faType, $buttonPanel);
    #nugget: GetNewClosure() *copies* current scope value into the future scope, it can't be changed in that future calling scope and come back like a true closure, but we don't need it to in this case
    $faBtn.ThisButton.Add_Click({ $action.Invoke($faBtn) }.GetNewClosure() ) #nugget: pass pointer to wrappered button back into the action script to be able to change the icon upon state toggle
}

function hiddenState { (get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowSuperHidden).ShowSuperHidden }
function faHiddenState { @([Fa]::ToggleOff, [Fa]::ToggleOn)[(hiddenState)] }

createButton -toolTip "Diff" -caption "Diff" -faType ([Fa]::Code) -action { 
  $winmergepath = "C:\Program Files (x86)\WinMerge\WinMergeU.exe"

  if (-not (Test-Path $winmergepath)) {
    $response = [System.Windows.Forms.MessageBox]::Show("'$winmergepath' not installed", "Install WinMerge?", "YesNo")
    if ($response -eq "Yes") { start "http://winmerge.org/downloads/" } 
    return
  }

  if (leftFirstSelectedPath) {
    & $winmergepath /s /u "$(leftFirstSelectedPath)" "$(rightFirstSelectedPath)"
  }
  else {
    & $winmergepath /s /u "$(leftPath)" "$(rightPath)"
  }
}

createButton -toolTip "Show Operating System Files" -caption "Show Hidden" -faType (faHiddenState) -returnButton $true -action {
  param([FaButton]$thisButton)

  #flip the current value - we get a [bool] with the ! operator so that needs to be cast back to an [int]
  $newState = [int]!(hiddenState)

  #update the registry... keep both hiddens in sync for simplicity
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowSuperHidden $newState
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Hidden @(2,1)[$newState] #hidden property needs 2 & 1 for Hide/Show vs 0 & 1 with ShowSuperHidden

  #refresh both explorers to show/hide files accordingly
  (leftShell).Refresh()
  (rightShell).Refresh()

  #update the toggle button state
  $thisButton.FaType = (faHiddenState)
}

createButton -toolTip "Show PowerShell Console" -caption "Show CLI" -faType ([Fa]::Terminal) -action { showPoShConsole }
createButton -toolTip "Set Left path equal to Right" -caption "Path Left" -faType ([Fa]::LongArrowLeft) -action { (leftShell).Navigate((rightPath)) }
createButton -toolTip "Set Right path equal to Left" -caption "Path Right" -faType ([Fa]::LongArrowRight) -action { (rightShell).Navigate((leftPath)) }
createButton -toolTip "Swap Left and Right paths" -caption "Swap" -faType ([Fa]::Exchange) -action { $left = leftPath; (leftShell).Navigate((rightPath)); (rightShell).Navigate($left) }
createButton -toolTip "Copy Left side selected file/folder to Right" -caption "Copy" -faType ([Fa]::Copy) -action { copyLeftToRight $false }
createButton -toolTip "Move Left side selected file/folder to Right" -caption "Move" -faType ([Fa]::AngleDoubleRight) -action { copyLeftToRight $true }

$frmMain.add_Load({
  $splitContainer.Add_SplitterMoving($splitContainer_Resize)
  $splitContainer.Add_SplitterMoved($splitContainer_Resize)

  <#
  $qs = New-Object -ComObject "QTTabBarLib.Scripting"

  if (!$configFile.Settings.LeftPanel.Folder) { $f = $configFile.CreateElement("Folder"); $f.InnerText = "$env:USERPROFILE\Downloads"; $configFile.Settings.LeftPanel.AppendChild($f) }
  $leftFirst = ($configFile.Settings.LeftPanel.Folder | select -first 1)
  newFileEx $true "$leftFirst"
  $configFile.Settings.LeftPanel.Folder | select -skip 1 | % { ($qs.Windows | ? {$_.Path -eq "$leftFirst"} | select -First 1).Add($_) }

  if (!$configFile.Settings.RightPanel.Folder) { $f = $configFile.CreateElement("Folder"); $f.InnerText = "$env:USERPROFILE\Downloads"; $configFile.Settings.RightPanel.AppendChild($f) }
  $rightFirst = ($configFile.Settings.RightPanel.Folder | select -first 1)
  newFileEx $false "$rightFirst"
  $configFile.Settings.RightPanel.Folder | select -skip 1 | % { ($qs.Windows | ? {$_.Path -eq "$rightFirst"} | select -First 1).Add($_) }
  #>

  newFileEx $true
  newFileEx $false

  $splitContainer_Resize.Invoke()

  #register global hot keys 
  #$frmMain.RegisterHotKey(1, [HotKeyForm+KeyModifier]::None, [System.Windows.Forms.Keys]::F5, { [System.Windows.Forms.MessageBox]::Show("F5 global hot key was pressed!") })
  #"F5" { copyLeftToRight $true }
  #"F6" { copyLeftToRight $false }
})


$frmMain.add_FormClosing({
  [Win32]::SetParent($splitContainer.Panel1.Tag.Hwnd, 0) | Out-Null
  [Win32]::SetParent($splitContainer.Panel2.Tag.Hwnd, 0) | Out-Null

  #save Quizo Tabs if it's installed
  try {
    $qs = New-Object -ComObject "QTTabBarLib.Scripting" 
    $settings.LeftFolders  = [System.Array](($qs.Windows | ? { $_.Path -eq (leftPath)  } | select -first 1).Tabs | select-object -ExpandProperty Path)
    $settings.RightFolders = [System.Array](($qs.Windows | ? { $_.Path -eq (rightPath) } | select -first 1).Tabs | select-object -ExpandProperty Path)
    md -force $settingsPath > $null
    $settings | Export-Clixml "$settingsPath\settings.xml"
  } catch {}
 
  [Win32]::SendMessage($splitContainer.Panel1.Tag.Hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
  [Win32]::SendMessage($splitContainer.Panel2.Tag.Hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
})


[System.Windows.Forms.Application]::Run($frmMain)

if ($Error -and $poShConsoleHwnd -ne 0) { showPoShConsole; pause }
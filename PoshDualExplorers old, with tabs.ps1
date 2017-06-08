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
#Add-Type -Path $PSScriptRoot\Interop.SHDocVw.dll #generated byt doing a Visual Studio reference to C:\windows\system32\shdocvmw.dll
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

<#
function closeTab {
  param([System.Windows.Forms.TabPage]$tabPage)

  [Win32]::SendMessage($tabPage.Tag.Hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
  $tabPage.Tag.TabControl.TabPages.Remove($tabPage)
}
#>

#a stream of bummers drove a little extra code complexity here...
#$objShell.Explore($env:USERPROFILE) yields a window title with the user's "display" name vs their USERPROFILE/"account" name but we have to locate the window handle by title...hmmm
#Start-Process makes a easy to find title but all forms i tried were creating new explorer.exe processes which seemed like overkill...
#  e.g. Start-Process -FilePath "explorer.exe" -ArgumentList "$env:USERPROFILE"
#System.DirectoryServices.AccountManagement.UserPrincipal.Current.DisplayName would allow us to find window, but .Current was taking 5 seconds?!? presumably to timeout on finding a DC (on a non domain PC? braindead MS??)...
#so found the GetUserNameEx Win32API approach
$userDisplayName = New-Object System.Text.StringBuilder -ArgumentList 1024
[Win32]::GetUserNameEx([int][Win32+EXTENDED_NAME_FORMAT]::NameDisplay, $userDisplayName, [ref] $userDisplayName.Capacity) | Out-Null #nugget: embedded C# enum syntax

# http://www.codeproject.com/Articles/101367/Code-to-Host-a-Third-Party-Application-in-our-Proc
#ran into setwindowpos hang before wndproc message pump starts... 
$splitContainer_Resize =
{
  #if (!$containerLeft -or !$containerLeft.SelectedTab -or !$containerLeft.SelectedTab.Tag.Hwnd) { return }
  if (!$containerLeft -or !$containerLeft.Tag.Hwnd) { return }
  #$tab = $containerLeft.SelectedTab
  [Win32]::SetWindowPos(
      #$tab.Tag.Hwnd,
      $containerLeft.Tag.Hwnd,
      [Win32]::HWND_TOP,
      <#
      $tab.ClientRectangle.Left,
      $tab.ClientRectangle.Top-31, #these extra pixels hide the deadzone at top of file explorer window, maybe reserved for quick access toolbar
      $tab.ClientRectangle.Width,
      $tab.ClientRectangle.Height+31,
      #>
      $containerLeft.ClientRectangle.Left,
      $containerLeft.ClientRectangle.Top-31, #these extra pixels hide the deadzone at top of file explorer window, maybe reserved for quick access toolbar
      $containerLeft.ClientRectangle.Width,
      $containerLeft.ClientRectangle.Height+31,
      [Win32]::NOACTIVATE -bor [Win32]::SHOWWINDOW
  ) | Out-Null

  #if (!$containerRight -or !$containerRight.SelectedTab -or !$containerRight.SelectedTab.Tag.Hwnd) { return }
  if (!$containerRight -or !$containerRight.Tag.Hwnd) { return }
  #$tab = $containerRight.SelectedTab
  [Win32]::SetWindowPos(
      #$tab.Tag.Hwnd,
      $containerRight.Tag.Hwnd,
      [Win32]::HWND_TOP,
      <#
      $tab.ClientRectangle.Left,
      $tab.ClientRectangle.Top-31,
      $tab.ClientRectangle.Width,
      $tab.ClientRectangle.Height+31,
      #>
      $containerRight.ClientRectangle.Left,
      $containerRight.ClientRectangle.Top-31,
      $containerRight.ClientRectangle.Width,
      $containerRight.ClientRectangle.Height+31,
      [Win32]::NOACTIVATE -bor [Win32]::SHOWWINDOW
  ) | Out-Null
}

function newFileExTab {
  param([bool]$leftSide, [string]$folderPath)

  #$tabPage = New-Object System.Windows.Forms.TabPage
  $tabContainer = @($containerRight, $containerLeft)[$leftSide]
  #$tabPage.Text = "Tab" + ($tabContainer.TabCount + 1)

  #$tabContainer.TabPages.Add($tabPage)
  #$tabContainer.SelectedIndex = $tabContainer.TabCount-1

  #launch a new file explorer with a known path, which drives a known window title we can lock in on and manipulate further
  $objShell.Explore($env:USERPROFILE)

  # if these windows class lookups change over Win.next, WinSpy tool is our friend:
  # http://www.catch22.net/software/winspy-17
  do { $hwnd = [Win32]::FindWindow("CabinetWClass", [string]$userDisplayName) } while ( $hwnd -eq 0 )
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
  
  # good 'ol Win32 SetParent()
  # i know it's silly but actually trying this right here with our old friend explorer.exe has been haunting me literally for years
  #[Win32]::SetParent($hwnd, $tabPage.Handle) | Out-Null
  #[Win32]::SetParent($hwnd, $tabContainer.Handle) | Out-Null
  [Win32]::HideTitleBar($hwnd)

  #$tabPage.Tag = New-Object –TypeName PSObject -Property @{ ShDocVw=$shDocVw; Hwnd=$hwnd; TabControl=$tabContainer }
  $tabContainer.Tag = New-Object –TypeName PSObject -Property @{ ShDocVw=$shDocVw; Hwnd=$hwnd <#; TabControl=$tabContainer#> }
  #$tabPage.Text = "Hwnd: $hwnd"

  $splitContainer_Resize.Invoke()

  if ($folderPath) { @((rightShell), (leftShell))[$leftSide].Navigate($folderPath) }
}


function uriToWindowsPath {
  param([string]$uri)

  #interesting, local drive letter paths get extra "file:///" prefix but UNC paths just get extra "file:"
  return [uri]::UnEscapeDataString($uri).Replace("file:///", "").Replace("file:", "").Replace("/", [char]92) #char92 just hides slash character from blog > google prettyprint munging
}

#IWebBrowser2 documentation gives several handy methods implemented on our ShDocVw object => https://msdn.microsoft.com/en-us/library/aa752127(v=vs.85).aspx
function leftShell { return $containerLeft<#.SelectedTab#>.Tag.ShDocVw }
function rightShell { return $containerRight<#.SelectedTab#>.Tag.ShDocVw }
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

#$containerLeft = new-object System.Windows.Forms.TabControl
$containerLeft = new-object System.Windows.Forms.Panel
$containerLeft.Dock = "fill"
#$containerLeft.Add_DoubleClick({ closeTab $containerLeft.SelectedTab }) #nugget: doubleClick on the TabPage header actually registers on the TabControl vs the TabPage
$splitContainer.Panel1.Controls.Add($containerLeft)

#$containerRight = new-object System.Windows.Forms.TabControl
$containerRight = new-object System.Windows.Forms.Panel
$containerRight.Dock = "fill"
#$containerRight.Add_DoubleClick({ closeTab $containerRight.SelectedTab })
$splitContainer.Panel2.Controls.Add($containerRight)

$frmMain = New-Object System.Windows.Forms.Form
$frmMain.Text = "DuEx"
$frmMain.Icon = New-Object system.drawing.icon ("$PSScriptRoot\DualFileExplorers.ico")
$frmMain.WindowState = "Maximized";
$frmMain.Controls.Add($splitContainer)
$frmMain.Add_Resize($splitContainer_Resize)
$splitContainer.SplitterDistance = $frmMain.ClientRectangle.Width / 2;

#button toolbar
#https://adminscache.wordpress.com/2014/08/03/powershell-winforms-menu/
$buttonPanel = new-object System.Windows.Forms.Panel
$buttonPanel.Height = 90
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$frmMain.Controls.Add($splitContainer) | Out-Null
$frmMain.Controls.Add($buttonPanel) | Out-Null

function createButton {
    param([string]$toolTip, [string]$caption, [string]$faType, [System.Windows.Forms.Control]$parent, [scriptblock]$action)
    $faBtn = New-Object FaButton(65, 80, 25, $toolTip, $caption, 32, $faType, $buttonPanel);
    #nugget: GetNewClosure() *copies* current scope value into the future scope, it can't be changed in that future calling scope and come back like a true closure, but we don't need it to in this case
    $faBtn.Button.Add_Click({ $action.Invoke($faBtn.Button) }.GetNewClosure() ) #nugget: pass pointer to wrappered button back into the action script to be able to change the icon upon state toggle
}

function hiddenState { (get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowSuperHidden).ShowSuperHidden }
function faHiddenState { @([Fa]::ToggleOff, [Fa]::ToggleOn)[(hiddenState)] }

createButton -toolTip "Diff" -caption "Folder/File Diff" -faType ([Fa]::Code) -action { 
  if (leftFirstSelectedPath) {
    &"C:\Program Files (x86)\WinMerge\WinMergeU.exe" /s /u "$(leftFirstSelectedPath)" "$(rightFirstSelectedPath)"
  }
  else {
    &"C:\Program Files (x86)\WinMerge\WinMergeU.exe" /s /u "$(leftPath)" "$(rightPath)"
  }
}

createButton -toolTip "Show Operating System Files" -caption "Show Hidden" -faType (faHiddenState) -returnButton $true -action {
  param([System.Windows.Forms.Button]$thisButton)

  #flip the current value - we get a [bool] with the ! operator so that needs to be cast back to an [int]
  $newState = [int]!(hiddenState)

  #update the registry... keep both hiddens in sync for simplicity
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowSuperHidden $newState
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Hidden @(2,1)[$newState] #hidden property needs 2 & 1 for Hide/Show vs 0 & 1 with ShowSuperHidden

  #refresh both explorers to show/hide files accordingly
  (leftShell).Refresh()
  (rightShell).Refresh()

  #update the toggle button state
  $thisButton.Text = (faHiddenState)
}

#createButton -toolTip "Open Selected Folder New Tab RIGHT" -caption "Open Right" -faType ([Fa]::FolderO) -action { newFileExTab $false (rightFirstSelectedPath) }
#createButton -toolTip "Open Selected Folder New Tab LEFT" -caption "Open Left" -faType ([Fa]::FolderO) -action { newFileExTab $true (leftFirstSelectedPath) }
createButton -toolTip "Show PowerShell Console" -caption "Show CLI" -faType ([Fa]::Terminal) -action { showPoShConsole }
createButton -toolTip "Jam Right path to Left" -caption "Jam Left" -faType ([Fa]::LongArrowLeft) -action { (leftShell).Navigate((rightPath)) }
createButton -toolTip "Jam Left path to Right" -caption "Jam Right" -faType ([Fa]::LongArrowRight) -action { (rightShell).Navigate((leftPath)) }
createButton -toolTip "Swap Left and Right" -caption "Swap" -faType ([Fa]::Exchange) -action { $left = leftPath; (leftShell).Navigate((rightPath)); (rightShell).Navigate($left) }
createButton -toolTip "Copy Left to Right" -caption "Copy" -faType ([Fa]::Copy) -action { copyLeftToRight $false }
createButton -toolTip "Move Left to Right" -caption "Move" -faType ([Fa]::AngleDoubleRight) -action { copyLeftToRight $true }

$frmMain.add_Load({
  $splitContainer.Add_SplitterMoving($splitContainer_Resize)
  $splitContainer.Add_SplitterMoved($splitContainer_Resize)

  newFileExTab $true $env:USERPROFILE\Downloads
  newFileExTab $false $env:USERPROFILE\Downloads

  #register global hot keys 
  #$frmMain.RegisterHotKey(1, [HotKeyForm+KeyModifier]::None, [System.Windows.Forms.Keys]::F5, { [System.Windows.Forms.MessageBox]::Show("F5 global hot key was pressed!") })
  #"F5" { copyLeftToRight $true }
  #"F6" { copyLeftToRight $false }
})

#nugget: doubleClick in the blank area next to tab headers actually registers on the underlying control vs the TabControl
<#
$splitContainer.Panel1.Add_DoubleClick({ newFileExTab $true })
$splitContainer.Panel2.Add_DoubleClick({ newFileExTab $false })

$frmMain.add_FormClosing({
  $containerLeft.TabPages | %{ closeTab $_ }
})
#>

[System.Windows.Forms.Application]::Run($frmMain)

if ($Error -and $poShConsoleHwnd -ne 0) { showPoShConsole; pause }
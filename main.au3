#NoTrayIcon
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <Misc.au3>
#include <WinAPI.au3>
#include <StaticConstants.au3>
#include <Math.au3>
#include <WinAPISys.au3>

Opt("GUICloseOnEsc", 0)

; Trackbar message constants
Global Const $TBM_SETRANGEMIN = 0x00B1
Global Const $TBM_SETRANGEMAX = 0x00B2

; ==== GLOBALS ====
Global $hStageGUI
Global $lblTime
Global $hCtrlGUI
Global $btnStart
Global $btnStop
Global $radModeMin
Global $radModeTime
Global $inpMin
Global $inpSec
Global $spinHour
Global $spinMin
Global $chkReverse
Global $chkTop
Global $sldTrans
Global $iMode = 0         ; 0 = Minutes, 1 = Specific Time
Global $iReverse = 1
Global $iRunning = False
Global $iPaused = False
Global $iOrigSec = 0
Global $iElapsedOffset = 0
Global $hTimerStart = 0
Global $tgtSec = 0
Global $lastTime = ""

; ==== STAGE WINDOW ====
Local $iScreenW = @DesktopWidth
Local $iScreenH = @DesktopHeight
Local $iStageW = Int($iScreenW * 0.3)
Local $iStageH = Int($iScreenH / 8)

$hStageGUI = GUICreate("Timer", $iStageW, $iStageH, Default, Default, _
    BitOR($WS_CAPTION, $WS_THICKFRAME), _
    $WS_EX_TOOLWINDOW)
GUISetBkColor(0x000000, $hStageGUI)

$lblTime = GUICtrlCreateLabel("00:00", 0, 0, $iStageW, $iStageH, _
    BitOR($SS_CENTER, $SS_CENTERIMAGE) _
)
GUICtrlSetFont($lblTime, Int($iStageH * 0.6), 400, 0, "Arial")
GUICtrlSetColor($lblTime, 0xFFFFFF)

; Enable resize callback
GUISetOnEvent($GUI_EVENT_PRIMARYUP, "OnResizeStage")
GUISetState(@SW_SHOW, $hStageGUI)

; ===== CONTROLLER WINDOW =====
$hCtrlGUI = GUICreate("Timer", 300, 260)

; Mode selection
$radModeMin  = GUICtrlCreateRadio("Minutes/Sec", 10, 10, 100, 20)
$radModeTime = GUICtrlCreateRadio("Until Time",   120, 10, 100, 20)
GUICtrlSetState($radModeMin, $GUI_CHECKED)

; Minutes/Sec inputs
GUICtrlCreateLabel("Min:", 10, 40)
$inpMin = GUICtrlCreateInput("15", 50, 40, 40, 20)
GUICtrlCreateLabel("Sec:", 100, 40)
$inpSec = GUICtrlCreateInput("00", 140, 40, 40, 20)

; Specific time inputs
GUICtrlCreateLabel("Hour:", 10, 70)
$spinHour = GUICtrlCreateInput("9", 50, 70, 40, 20)
GUICtrlCreateLabel("Min:", 100, 70)
$spinMin  = GUICtrlCreateInput("15", 140, 70, 40, 20)
GUICtrlSetState($spinHour, $GUI_DISABLE)
GUICtrlSetState($spinMin,  $GUI_DISABLE)

; Options: Reverse, Topmost
$chkReverse = GUICtrlCreateCheckbox("Reverse", 10, 100)
GUICtrlSetState($chkReverse, $GUI_CHECKED)

$chkTop = GUICtrlCreateCheckbox("Top", 120, 100)
GUICtrlSetState($chkTop, $GUI_CHECKED)

; Transparency slider
GUICtrlCreateLabel("Transparency", 10, 130)
$sldTrans = GUICtrlCreateSlider(10, 150, 200, 20)
GUICtrlSetData($sldTrans, 100)

; Control buttons
$btnStart = GUICtrlCreateButton(">", 10, 190, 50, 30)
$btnStop  = GUICtrlCreateButton("[]", 70, 190, 50, 30)

GUISetState(@SW_SHOW, $hCtrlGUI)

RemoveWindowCloseButton($hStageGUI)
WinSetOnTop($hStageGUI, "", 1)

; ==== MAIN LOOP ====
While True
    Local $msg = GUIGetMsg()
    Switch $msg
        Case $GUI_EVENT_CLOSE
            Exit
        Case $radModeMin
			ToggleMode(0)
		Case $radModeTime
			ToggleMode(1)
        Case $chkReverse
            $iReverse = (GUICtrlRead($chkReverse) = $GUI_CHECKED)
        Case $chkTop
            WinSetOnTop($hStageGUI, "", GUICtrlRead($chkTop))
        Case $btnStart
            _StartPause()
        Case $btnStop
            _Stop()
    EndSwitch

    ; Transparency update
    WinSetTrans($hStageGUI, "", Int(GUICtrlRead($sldTrans) * 2.55))

    ; Timer update
    If $iRunning And Not $iPaused Then
        _UpdateTimer()
    EndIf

    Sleep(10)
WEnd

; ==== FUNCTIONS ====
Func ToggleMode($mode)
    If $mode = 0 Then
        ; Minutes/Sec mode
        GUICtrlSetState($radModeMin,  $GUI_CHECKED)
        GUICtrlSetState($radModeTime, $GUI_UNCHECKED)
        GUICtrlSetState($inpMin,      $GUI_ENABLE)
        GUICtrlSetState($inpSec,      $GUI_ENABLE)
        GUICtrlSetState($spinHour,    $GUI_DISABLE)
        GUICtrlSetState($spinMin,     $GUI_DISABLE)
    Else
        ; Until Time mode
        GUICtrlSetState($radModeTime, $GUI_CHECKED)
        GUICtrlSetState($radModeMin,  $GUI_UNCHECKED)
        GUICtrlSetState($inpMin,      $GUI_DISABLE)
        GUICtrlSetState($inpSec,      $GUI_DISABLE)
        GUICtrlSetState($spinHour,    $GUI_ENABLE)
        GUICtrlSetState($spinMin,     $GUI_ENABLE)
    EndIf
    $iMode = $mode
EndFunc

Func _StartPause()
    If Not $iRunning Then
        ; Initialize new timer
        $iReverse = (GUICtrlRead($chkReverse) = $GUI_CHECKED)
        If $iMode = 0 Then
            Local $m = Int(GUICtrlRead($inpMin))
            Local $s = Int(GUICtrlRead($inpSec))
            $iOrigSec = $m * 60 + $s
        Else
            Local $h  = Int(GUICtrlRead($spinHour))
            Local $mn = Int(GUICtrlRead($spinMin))
            Local $now = @HOUR * 3600 + @MIN * 60 + @SEC
            Local $tgt = $h * 3600 + $mn * 60
            If $tgt <= $now Then $tgt += 86400
            $tgtSec   = $tgt
            $iOrigSec = $tgt - $now
        EndIf

        $iElapsedOffset = 0
        $hTimerStart    = TimerInit()

        ; Gray out inputs
        GUISetState($GUI_DISABLE, $radModeMin)
        GUISetState($GUI_DISABLE, $radModeTime)
        GUISetState($GUI_DISABLE, $inpMin)
        GUISetState($GUI_DISABLE, $inpSec)
        GUISetState($GUI_DISABLE, $spinHour)
        GUISetState($GUI_DISABLE, $spinMin)
        GUISetState($GUI_DISABLE, $chkReverse)

        $iRunning = True
        $iPaused  = False
        GUICtrlSetData($btnStart, "||")
    ElseIf Not $iPaused Then
        ; Pause
        $iPaused = True
        If $iMode = 0 Then $iElapsedOffset += Int(TimerDiff($hTimerStart) / 1000)
        GUICtrlSetData($btnStart, ">")
    Else
        ; Resume
        $iPaused    = False
        $hTimerStart = TimerInit()
        GUICtrlSetData($btnStart, "||")
    EndIf
EndFunc

Func _Stop()
    $iRunning = False
    $iPaused  = False
    GUICtrlSetData($lblTime, "00:00")

    ; Re-enable inputs
    GUISetState($GUI_ENABLE, $radModeMin)
    GUISetState($GUI_ENABLE, $radModeTime)
    GUISetState($GUI_ENABLE, $inpMin)
    GUISetState($GUI_ENABLE, $inpSec)
    GUISetState($GUI_ENABLE, $spinHour)
    GUISetState($GUI_ENABLE, $spinMin)
    GUISetState($GUI_ENABLE, $chkReverse)

    GUICtrlSetData($btnStart, ">")
EndFunc

Func _UpdateTimer()
    Local $dispSec = 0
    If $iMode = 0 Then
        $dispSec = $iReverse ? _
            $iOrigSec - (Int(TimerDiff($hTimerStart) / 1000) + $iElapsedOffset) : _
            Int(TimerDiff($hTimerStart) / 1000) + $iElapsedOffset
    Else
        Local $now = @HOUR * 3600 + @MIN * 60 + @SEC
        Local $rem = $tgtSec - $now
        $dispSec = $iReverse ? $rem : $iOrigSec - $rem
    EndIf
    If $dispSec < 0 Then $dispSec = 0

    Local $mi = Int($dispSec / 60)
    Local $se = Mod($dispSec, 60)

	Local $sNewTime = StringFormat("%02d:%02d", $mi, $se)

	If $sNewTime <> $lastTime Then
		GUICtrlSetData($lblTime, $sNewTime)
		$lastTime = $sNewTime
	EndIf
EndFunc

Func OnResizeStage()
    Local $a = WinGetPos($hStageGUI)
    Local $w = $a[2]
    Local $h = $a[3]
    Local $fs = _Max(Int($h * 0.6), 10)
    GUICtrlSetFont($lblTime, $fs, 400, 0, "Arial")
	GUICtrlSetColor($lblTime, 0xFFFFFF)
    Local $pos = ControlGetPos($hStageGUI, "", $lblTime)
    GUICtrlSetPos($lblTime, _
        Int(($w - $pos[2]) / 2), _
        Int(($h - $pos[3]) / 2) _
    )
EndFunc

Func RemoveWindowCloseButton($hWin)
	Local $dwStyle = _WinAPI_GetWindowLong($hWin, $GWL_STYLE)
	; clear the WS_SYSMENU bit (that adds the X)
	$dwStyle = BitAND($dwStyle, BitNOT($WS_SYSMENU))
	_WinAPI_SetWindowLong($hWin, $GWL_STYLE, $dwStyle)
	; refresh the non‑client frame
	_WinAPI_SetWindowPos($hWin, 0, 0, 0, 0, 0, _
		BitOR($SWP_NOMOVE, $SWP_NOSIZE, $SWP_FRAMECHANGED))
EndFunc
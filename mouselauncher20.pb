; **************************************************************************
; * MouseLauncher 2026
; * Copyright (C) 2026 Mave-rick84
; * ; * This program is free software: you can redistribute it and/or modify
; * it under the terms of the GNU General Public License as published by
; * the Free Software Foundation, either version 3 of the License, or
; * (at your option) any later version.
; * ; * This program is distributed in the hope that it will be useful,
; * but WITHOUT ANY WARRANTY; without even the implied warranty of
; * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; * GNU General Public License for more details.
; * ; * You should have received a copy of the GNU General Public License
; * along with this program. If not, see <https://www.gnu.org/licenses/>.
; **************************************************************************
EnableExplicit
; --- CONTROLLO ISTANZA UNICA ---
#AppMutexName = "MouseLauncher_2026" 
Define hMutex = CreateMutex_(0, 0, #AppMutexName)
If hMutex <> 0 And GetLastError_() = 183 ; #ERROR_ALREADY_EXISTS
  ReleaseMutex_(hMutex)
  CloseHandle_(hMutex)
  End 
EndIf

CompilerIf Not Defined(POINT, #PB_Structure)
  Structure POINT
    x.l
    y.l
  EndStructure
CompilerEndIf
; --- FIX COSTANTI API ---
CompilerIf Not Defined(SWP_NOMOVE, #PB_Constant)
  #SWP_NOMOVE = $2
CompilerEndIf
CompilerIf Not Defined(SWP_NOZORDER, #PB_Constant)
  #SWP_NOZORDER = $4
CompilerEndIf
CompilerIf Not Defined(SW_SHOWNORMAL, #PB_Constant)
  #SW_SHOWNORMAL = 1
CompilerEndIf
; --- PARAMETRI DI SISTEMA & FILE ---
Global WinSize.i      = 270
Global RaggioBuco.i   = 15
Global PosizioneApp.f = 0.68
Global EffettoLoFi.f  = 0.4         
Global Trasparenza.i  = 230 ; 255 = Opaco, 0 = Invisibile
Global LastHoveredSlice.i = -1
Global StartupAuto.b = 0
Global AppPath.s = GetPathPart(ProgramFilename())
Global ConfigPath.s = AppPath + "mouselauncher.ini"
#GCLP_HCURSOR = -12
#EM_SETLIMITTEXT = $C5
; --- COSTANTI API WINDOWS PER REGISTRO (Win7)
#HKEY_CURRENT_USER = $80000001
#ERROR_SUCCESS      = 0
#KEY_WRITE          = $20006
#KEY_READ           = $20019
#REG_SZ             = 1
Enumeration
  #WinMenu
  #WinSettings
  #WinHelp
  #ListApps
  #BtnAdd
  #BtnDel
  #BtnSave
  #TxtLabel
  #TxtCmd
  #BtnColor
  #ColorPreview
  #BtnBrowseFile = 100 
  #BtnBrowsePath
  #BtnUpdate
  #BtnUP
  #BtnDOWN
  #BtnTest
  #BtnDuplicate
  #GWL_EXSTYLE = -20
  #WS_EX_LAYERED = $80000
  #LWA_ALPHA = $2
EndEnumeration
#IDC_ARROW = 32512
#IDC_HAND  = 32649
#VK_MBUTTON = $04 : #VK_LBUTTON = $01 : #VK_ESCAPE = $1B : #VK_S = $53 : #VK_CONTROL = $11 : #VK_MENU = $12
#VK_XBUTTON1 = $05
#VK_XBUTTON2 = $06
Global TriggerKey.i = #VK_MBUTTON ; Default
Structure Slice
  label.s
  color.i
  cmd.s
  targetX.f
  targetY.f
  startAngle.f
  endAngle.f
EndStructure
Global FontNome.s = "Segoe UI"
Global FontTaglia.i = 10
Global FontID.i 
Global FontBold.b = 1 
Global FontColore.i = $FFFFFF ; Bianco di default
Global NewList Slices.Slice()
Global MenuVisibile.b = #False, HelpAperto.b = #False, mPos.POINT, MenuImage.i, CurrentColor.i = $FF0000

; AGGIORNA ANTEPRIMA COLORE
; Disegna il quadratino di colore nel canvas dei settings
Procedure UpdateColorPreview()
  If IsGadget(#ColorPreview)
    Protected output = CanvasOutput(#ColorPreview)
    If output And StartDrawing(output)
      Box(0, 0, OutputWidth(), OutputHeight(), CurrentColor)
      DrawingMode(#PB_2DDrawing_Outlined)
      Box(0, 0, OutputWidth(), OutputHeight(), $888888)
      StopDrawing()
    EndIf
  EndIf
EndProcedure

; Gestione help centrale con spiegazione comandi
Procedure ToggleSmartHelp(x, y)
  If HelpAperto
    If IsWindow(#WinHelp) : CloseWindow(#WinHelp) : EndIf
    HelpAperto = #False
  Else
    If OpenWindow(#WinHelp, x + 15, y + 15, 200, 50, "", #PB_Window_BorderLess | #PB_Window_Invisible)
      StickyWindow(#WinHelp, #True)
      SetWindowColor(#WinHelp, $222222) 
      Protected t1 = TextGadget(#PB_Any, 5, 8, 190, 18, "ESC: Chiudi Menu", #PB_Text_Center)
      Protected t2 = TextGadget(#PB_Any, 5, 26, 190, 18, "CTRL+ALT+S: Settings", #PB_Text_Center)
      SetGadgetColor(t1, #PB_Gadget_FrontColor, $FFFFFF) : SetGadgetColor(t1, #PB_Gadget_BackColor, $222222)
      SetGadgetColor(t2, #PB_Gadget_FrontColor, $FFFFFF) : SetGadgetColor(t2, #PB_Gadget_BackColor, $222222)
      HideWindow(#WinHelp, #False)
      HelpAperto = #True
    EndIf
  EndIf
EndProcedure
; SCRITTURA REGISTRO AUTO-AVVIO
; Aggiunge o rimuove il programma dalla chiave 'Run' di Windows
Procedure SetStartup(State.b)
  Protected Key.s = "Software\Microsoft\Windows\CurrentVersion\Run"
  Protected AppPath.s = Chr(34) + ProgramFilename() + Chr(34)
  Protected AppName.s = "MouseLauncher"
  Protected hKey.i

  If State
    ; Crea o aggiorna la chiave nel registro per l'utente corrente
    If RegCreateKeyEx_(#HKEY_CURRENT_USER, Key, 0, 0, 0, #KEY_WRITE, 0, @hKey, 0) = #ERROR_SUCCESS
      RegSetValueEx_(hKey, AppName, 0, #REG_SZ, @AppPath, Len(AppPath)*SizeOf(Character))
      RegCloseKey_(hKey)
    EndIf
  Else
    ; Rimuove la chiave
    If RegOpenKeyEx_(#HKEY_CURRENT_USER, Key, 0, #KEY_WRITE, @hKey) = #ERROR_SUCCESS
      RegDeleteValue_(hKey, AppName)
      RegCloseKey_(hKey)
    EndIf
  EndIf
EndProcedure
; Verifica se la chiave di registro esiste già
Procedure.b GetStartupState()
  Protected Key.s = "Software\Microsoft\Windows\CurrentVersion\Run"
  Protected hKey.i, Type.i, Size.i = 1024
  Protected Buffer.s = Space(1024)
  Protected Result.b = #False
  
  If RegOpenKeyEx_(#HKEY_CURRENT_USER, Key, 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    If RegQueryValueEx_(hKey, "MouseLauncher", 0, @Type, @Buffer, @Size) = #ERROR_SUCCESS
      Result = #True
    EndIf
    RegCloseKey_(hKey)
  EndIf
  ProcedureReturn Result
EndProcedure

; Salvataggio parametri INI
Procedure SaveSettings()
  If CreatePreferences(ConfigPath)
    PreferenceComment(" MouseLauncher Configuration")
    PreferenceComment(" WinSize: Diametro della finestra (es. 200-500)")
    PreferenceComment(" RaggioBuco: Dimensione area centrale '?' (es. 10-30)")
    PreferenceComment(" PosizioneApp: Distanza testi dal centro (0.1 - 0.9)")
    PreferenceComment(" EffettoLoFi: Qualita riempimento (0.1=Pieno, 1.0=Rigato)")
    PreferenceComment(" FontNome: Nome del font (es. Arial, Segoe UI, Verdana)")
    PreferenceComment(" FontTaglia: Dimensione del testo (es. 9-14)")
    PreferenceComment(" FontBold: Grassetto (1 = SI, 0 = NO)")
    PreferenceComment(" FontColore: Colore del testo in HEX (es. $FFFFFF)")
    PreferenceComment(" Trasparenza: Opacita del menu (0-255, es. 200)")
    PreferenceComment(" StartupAuto: Avvio con windows (1 = Si, 0 = No)")
    PreferenceComment(" TriggerKey: Pulsante di attivazione 4 = Middle click(wheel), 5=Back, 6=Forward")
    
    PreferenceGroup("General")
    WritePreferenceInteger("WinSize", WinSize)
    WritePreferenceInteger("RaggioBuco", RaggioBuco)
    WritePreferenceFloat("PosizioneApp", PosizioneApp)
    WritePreferenceFloat("EffettoLoFi", EffettoLoFi)
    WritePreferenceString("FontNome", FontNome)
    WritePreferenceInteger("FontTaglia", FontTaglia)
    WritePreferenceInteger("FontBold", FontBold)
    WritePreferenceString("FontColore", "$" + Hex(FontColore, #PB_Long))
    WritePreferenceInteger("Trasparenza", Trasparenza)
    WritePreferenceInteger("StartupAuto", StartupAuto)
    WritePreferenceInteger("TriggerKey", TriggerKey) 
    PreferenceComment("")
    PreferenceComment(" Elenco Applicazioni")
    WritePreferenceInteger("Count", ListSize(Slices()))
    
    Protected i = 0
    ForEach Slices()
      PreferenceGroup("App_" + Str(i))
      WritePreferenceString("Label", Slices()\label)
      WritePreferenceString("Cmd", Slices()\cmd)
      WritePreferenceString("Color", "$" + Hex(Slices()\color, #PB_Long))
      i + 1
    Next
    ClosePreferences()
  EndIf
EndProcedure
; Legge i parametri o lo crea se il file manca
Procedure LoadSettings()
  ClearList(Slices())
  
  ; 1. Tentativo di apertura del file configurazione
  If OpenPreferences(ConfigPath)
    PreferenceGroup("General")
    
    ; Leggo i valori. Se una chiave manca usa il valore attuale della variabile Global
    WinSize      = ReadPreferenceInteger("WinSize", WinSize)
    RaggioBuco   = ReadPreferenceInteger("RaggioBuco", RaggioBuco)
    PosizioneApp = ReadPreferenceFloat("PosizioneApp", PosizioneApp)
    EffettoLoFi  = ReadPreferenceFloat("EffettoLoFi", EffettoLoFi)
    FontNome     = ReadPreferenceString("FontNome", FontNome)
    FontTaglia   = ReadPreferenceInteger("FontTaglia", FontTaglia)
    FontBold     = ReadPreferenceInteger("FontBold", FontBold)
    FontColore   = Val(ReadPreferenceString("FontColore", "$" + Hex(FontColore, #PB_Long)))
    Trasparenza  = ReadPreferenceInteger("Trasparenza", Trasparenza)
    StartupAuto = ReadPreferenceInteger("StartupAuto", 0)
    TriggerKey = ReadPreferenceInteger("TriggerKey", #VK_MBUTTON)
    If TriggerKey < #VK_MBUTTON Or TriggerKey > #VK_XBUTTON2
      TriggerKey = #VK_MBUTTON
    EndIf
    
    Protected stile = #PB_Font_HighQuality
    If FontBold : stile | #PB_Font_Bold : EndIf
    If FontID : FreeFont(FontID) : EndIf
    FontID = LoadFont(#PB_Any, FontNome, FontTaglia, stile)
    
    ; Caricamento delle fette dal file
    Protected count = ReadPreferenceInteger("Count", 0)
    Protected i
    For i = 0 To count - 1
      PreferenceGroup("App_" + Str(i))
      AddElement(Slices())
      Slices()\label = ReadPreferenceString("Label", "New")
      Slices()\cmd   = ReadPreferenceString("Cmd", "calc.exe")
      Slices()\color = Val(ReadPreferenceString("Color", "$808080"))
    Next
    
    ClosePreferences()
  Else
    ; Se il file non esiste, carica comunque il font con i valori globali iniziali
    Protected stileD = #PB_Font_HighQuality
    If FontBold : stileD | #PB_Font_Bold : EndIf
    If FontID : FreeFont(FontID) : EndIf
    FontID = LoadFont(#PB_Any, FontNome, FontTaglia, stileD)
  EndIf
  
  ; --- DEFAULT DI PRIMO AVVIO (Se la lista è vuota perché il file non esiste) ---
  If ListSize(Slices()) = 0
    AddElement(Slices()) : Slices()\label="DOCS"       : Slices()\cmd="shell:Personal"       : Slices()\color=$0000CC
    AddElement(Slices()) : Slices()\label="BROWSER"    : Slices()\cmd="https://www.google.com" : Slices()\color=$0059B3
    AddElement(Slices()) : Slices()\label="CMD"        : Slices()\cmd="cmd.exe"              : Slices()\color=$00A3C2
    AddElement(Slices()) : Slices()\label="TASK MGR"   : Slices()\cmd="taskmgr.exe"          : Slices()\color=$00B386
    AddElement(Slices()) : Slices()\label="NOTE"    : Slices()\cmd="notepad.exe"          : Slices()\color=$00CC00
    AddElement(Slices()) : Slices()\label="CPANEL"     : Slices()\cmd="control"              : Slices()\color=$66CC00
    AddElement(Slices()) : Slices()\label="DEVICE"     : Slices()\cmd="devmgmt.msc"          : Slices()\color=$CCCC00
    AddElement(Slices()) : Slices()\label="SCREENSHOT" : Slices()\cmd="snippingtool.exe"     : Slices()\color=$FF8000
    AddElement(Slices()) : Slices()\label="IPCONFIG"   : Slices()\cmd="cmd /k ipconfig /all" : Slices()\color=$CC0000
    AddElement(Slices()) : Slices()\label="MSCFG"      : Slices()\cmd="msconfig"             : Slices()\color=$990066
    ; Creo file INI
    SaveSettings() 
  EndIf
EndProcedure
; GENERAZIONE GRAFICA MENU
; Disegna disco, spicchi e testi. HoverIdx gestisce l'animazione
Procedure CreateMenuImage(HoverIdx.i = -1)
  If IsImage(MenuImage) : FreeImage(MenuImage) : EndIf
  Protected i.i = 0, count = ListSize(Slices()), rad.f
  If count = 0 : count = 1 : EndIf  
  Protected angleStep.f = 360 / count
  Protected centro = WinSize / 2
  MenuImage = CreateImage(#PB_Any, WinSize, WinSize)
  
  If StartDrawing(ImageOutput(MenuImage))
    If IsFont(FontID) : DrawingFont(FontID(FontID)) : EndIf   
    ; Sfondo e calcolo angoli
    Box(0, 0, WinSize, WinSize, RGB(35, 35, 45))
    
    ForEach Slices()
      Protected drawColor = Slices()\color
      Protected textOffset.f = 0 
      
      Slices()\startAngle = i * angleStep
      Slices()\endAngle = (i + 1) * angleStep
      Protected medial.f = Radian(Slices()\startAngle + angleStep/2 - 90)     
      
      Slices()\targetX = centro + (centro * PosizioneApp) * Cos(medial)
      Slices()\targetY = centro + (centro * PosizioneApp) * Sin(medial)
      
      If i = HoverIdx
        ; Schiarimento
        Protected r = Red(drawColor) + 50 : If r > 255 : r = 255 : EndIf
        Protected g = Green(drawColor) + 50 : If g > 255 : g = 255 : EndIf
        Protected b = Blue(drawColor) + 50 : If b > 255 : b = 255 : EndIf
        drawColor = RGB(r, g, b)
        
        textOffset = 5.0 ; <--- Il testo si sposta di tot px verso l'esterno
      EndIf

      ; 1. DISEGNO FETTA (Sempre fissa al centro)
      rad = Slices()\startAngle
      While rad <= Slices()\endAngle
        Define cR.f = Cos(Radian(rad-90))
        Define sR.f = Sin(Radian(rad-90))
        LineXY(centro, centro, centro + (centro * cR), centro + (centro * sR), drawColor)
        rad + EffettoLoFi
      Wend
      
      ; 2. DISEGNO TESTO (Dinamico)
      ; Uso PosizioneApp + l'offset per spingere la scritta verso il bordo
      Protected drawTxtX = centro + ((centro * PosizioneApp) + textOffset) * Cos(medial)
      Protected drawTxtY = centro + ((centro * PosizioneApp) + textOffset) * Sin(medial)
      
      DrawingMode(#PB_2DDrawing_Transparent)
      DrawText(drawTxtX - (TextWidth(Slices()\label)/2), drawTxtY - (TextHeight(Slices()\label)/2), Slices()\label, FontColore)
      
      ; Linea di separazione tra le fette
      LineXY(centro, centro, centro + centro * Cos(Radian(Slices()\startAngle-90)), centro + centro * Sin(Radian(Slices()\startAngle-90)), 0)
      i + 1
    Next
    
    ; Buco centrale fisso
    Circle(centro, centro, RaggioBuco, 0) 
    DrawText(centro - (TextWidth("?")/2), centro - (TextHeight("?")/2), "?", FontColore)
    StopDrawing()
  EndIf
EndProcedure
; FINESTRA DELLE IMPOSTAZIONI
Procedure OpenSettingsWin()
  Protected i.i, y.i = 40
  Protected G_WinSize, G_Raggio, G_PosApp, G_LoFi, G_FontN, G_FontT, G_FontC, G_Trasp, G_Bold, G_Trigger
  
  #TxtAttivazione = 500 
  #ComboTrigger   = 501
  
  
  If IsWindow(#WinMenu) : HideWindow(#WinMenu, #True) : EndIf
  While WindowEvent() : Wend ; Svuota la coda degli eventi
  Delay(20) 

  If OpenWindow(#WinSettings, 0, 0, 620, 595, "MouseLauncher - Settings", #PB_Window_SystemMenu | #PB_Window_ScreenCentered)
    StickyWindow(#WinSettings, #True)   
    SetWindowColor(#WinSettings, #PB_Default) 

    FrameGadget(#PB_Any, 10, 5, 600, 242, " Impostazioni Generali ")
    
    TextGadget(#TxtAttivazione, 375, y+3, 85, 20, "Attivazione:")
    ComboBoxGadget(#ComboTrigger, 440, y, 150, 22)
    
    AddGadgetItem(#ComboTrigger, 0, "Middle Button")
    AddGadgetItem(#ComboTrigger, 1, "X-Button 1 (Back)")
    AddGadgetItem(#ComboTrigger, 2, "X-Button 2 (Forward)")
    
    Select TriggerKey
      Case #VK_XBUTTON1 : SetGadgetState(#ComboTrigger, 1)
      Case #VK_XBUTTON2 : SetGadgetState(#ComboTrigger, 2)
      Default           : SetGadgetState(#ComboTrigger, 0)
    EndSelect

    UpdateWindow_(WindowID(#WinSettings))
    InvalidateRect_(GadgetID(#TxtAttivazione), 0, #True)
    InvalidateRect_(GadgetID(#ComboTrigger), 0, #True)
      
    TextGadget(#PB_Any, 25, y+3, 80, 20, "Dim. Cerchio:")
    G_WinSize = StringGadget(#PB_Any, 110, y, 50, 22, Str(WinSize), #PB_String_Numeric)
    TextGadget(#PB_Any, 170, y+3, 400, 20, "Diametro totale del menu (pixel)")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "Dim. Centro:")
    G_Raggio = StringGadget(#PB_Any, 110, y, 50, 22, Str(RaggioBuco), #PB_String_Numeric)
    TextGadget(#PB_Any, 170, y+3, 400, 20, "Dimensione zona centrale vuota (pixel)")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "PosizioneApp:")
    G_PosApp = StringGadget(#PB_Any, 110, y, 50, 22, StrF(PosizioneApp, 2))
    TextGadget(#PB_Any, 170, y+3, 400, 20, "Distanza testi dal centro (0.1 a 0.9)")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "Effetto LoFi:")
    G_LoFi = StringGadget(#PB_Any, 110, y, 50, 22, StrF(EffettoLoFi, 2))
    TextGadget(#PB_Any, 170, y+3, 400, 20, "Dettaglio cerchio (0.1 pieno, 1.0 rigato)")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "FontNome:")
    G_FontN = StringGadget(#PB_Any, 110, y, 120, 22, FontNome)
    TextGadget(#PB_Any, 240, y+3, 350, 20, "Esempio: Segoe UI, Arial, Verdana")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "FontSize/Col:")
    G_FontT = StringGadget(#PB_Any, 110, y, 40, 22, Str(FontTaglia), #PB_String_Numeric)
    G_FontC = StringGadget(#PB_Any, 155, y, 75, 22, "$" + Hex(FontColore, #PB_Long))
    G_Bold  = CheckBoxGadget(#PB_Any, 240, y, 120, 22, "Testo Grassetto")
    SetGadgetState(G_Bold, FontBold)
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "Trasparenza:")
    G_Trasp = StringGadget(#PB_Any, 110, y, 50, 22, Str(Trasparenza), #PB_String_Numeric)
    TextGadget(#PB_Any, 170, y+3, 300, 20, "Opacità menu (0=Invisibile, 255=Pieno)")
    
    y + 26 : TextGadget(#PB_Any, 25, y+3, 80, 20, "Sistema:")
    Protected G_Startup = CheckBoxGadget(#PB_Any, 110, y, 150, 22, "Avvia con Windows")
    SetGadgetState(G_Startup, GetStartupState()) ; Controlla direttamente il registro
    ; --- Elenco ---
    y = 255
    FrameGadget(#PB_Any, 10, y, 600, 285, " Elenco Applicazioni ")
    ListIconGadget(#ListApps, 20, y+25, 515, 180, "Etichetta", 120, #PB_ListIcon_GridLines | #PB_ListIcon_FullRowSelect | #PB_ListIcon_AlwaysShowSelection)
    AddGadgetColumn(#ListApps, 1, "Comando / Percorso", 320)
    AddGadgetColumn(#ListApps, 2, "Colore", 70)      
    ButtonGadget(#BtnUP, 570, y+25, 30, 75, "▲")
    ButtonGadget(#BtnDOWN, 570, y+110, 30, 75, "▼")
    
    y + 215
    
    ButtonGadget(#BtnAdd, 20, y, 120, 25, "AGGIUNGI RIGA")
    ButtonGadget(#BtnDuplicate, 150, y, 120, 25, "DUPLICA RIGA")
    ButtonGadget(#BtnDel, 280, y, 120, 25, "ELIMINA RIGA")
    
    y + 35
    TextGadget(#PB_Any, 25, y+5, 50, 20, "Testo:")
    StringGadget(#TxtLabel, 60, y, 100, 25, "")
    ;SendMessage_(GadgetID(#TxtLabel), #EM_SETLIMITTEXT, 10, 0)
    TextGadget(#PB_Any, 165, y+5, 60, 20, "Comando:")
    StringGadget(#TxtCmd, 222, y, 220, 25, "")
    ButtonGadget(#BtnBrowseFile, 450, y, 40, 25, "File")
    SetClassLongPtr_(GadgetID(#BtnBrowseFile), #GCLP_HCURSOR, LoadCursor_(0, #IDC_HAND))
    GadgetToolTip(#BtnBrowseFile, "Lancia File")
    ButtonGadget(#BtnBrowsePath, 500, y, 40, 25, "Folder")
    GadgetToolTip(#BtnBrowsePath, "Apri Cartella")
    CanvasGadget(#ColorPreview, 550, y, 25, 25)
    SetGadgetAttribute(#ColorPreview, #PB_Canvas_Cursor, #PB_Cursor_Hand)
    GadgetToolTip(#ColorPreview, "Clicca qui per cambiare colore")
    ;ButtonGadget(#BtnColor, 120, y+30, 110, 30, "Colore")   
    
    ButtonGadget(#BtnSave, 15, 545, 590, 40, "SALVA E CHIUDI", #PB_Button_Default)
    
    ForEach Slices() 
  ; quadratino colorato 16x16
  Protected img = CreateImage(#PB_Any, 16, 16)
  If StartDrawing(ImageOutput(img))
    Box(0, 0, 16, 16, Slices()\color)
    DrawingMode(#PB_2DDrawing_Outlined)
    Box(0, 0, 16, 16, $444444) ; Bordino grigio scuro
    StopDrawing()
  EndIf
  
  ; aggiunge la riga: l'ImageID(img) mette il colore nella prima colonna
  AddGadgetItem(#ListApps, -1, Slices()\label + Chr(10) + Slices()\cmd + Chr(10) + "$" + Hex(Slices()\color, #PB_Long), ImageID(img))
  Next
  UpdateColorPreview()
    
    Repeat
      Protected ev = WaitWindowEvent()     
      Select ev
        Case #PB_Event_Gadget
          Protected gd = EventGadget()
          If (gd = #TxtLabel Or gd = #TxtCmd) And EventType() = #PB_EventType_Change
            Protected s = GetGadgetState(#ListApps)
            If s > -1
              SetGadgetItemText(#ListApps, s, GetGadgetText(#TxtLabel), 0)
              SetGadgetItemText(#ListApps, s, GetGadgetText(#TxtCmd), 1)
            EndIf
          EndIf

          Select gd
            Case #ListApps
              Protected sel = GetGadgetState(#ListApps)
              If sel > -1
                SetGadgetText(#TxtLabel, GetGadgetItemText(#ListApps, sel, 0))
                SetGadgetText(#TxtCmd, GetGadgetItemText(#ListApps, sel, 1))
                CurrentColor = Val(GetGadgetItemText(#ListApps, sel, 2)) : UpdateColorPreview()
              EndIf
            
            Case #BtnUP
              Protected upIdx = GetGadgetState(#ListApps)
              If upIdx > 0
                Protected ut0.s = GetGadgetItemText(#ListApps, upIdx, 0) : Protected ut1.s = GetGadgetItemText(#ListApps, upIdx, 1) : Protected ut2.s = GetGadgetItemText(#ListApps, upIdx, 2)
                Protected uColSp = Val(ut2) : Protected uImgSp = CreateImage(#PB_Any, 16, 16)
                If StartDrawing(ImageOutput(uImgSp)) : Box(0, 0, 16, 16, uColSp) : DrawingMode(#PB_2DDrawing_Outlined) : Box(0, 0, 16, 16, $444444) : StopDrawing() : EndIf
                RemoveGadgetItem(#ListApps, upIdx) : AddGadgetItem(#ListApps, upIdx - 1, ut0 + Chr(10) + ut1 + Chr(10) + ut2, ImageID(uImgSp)) : SetGadgetState(#ListApps, upIdx - 1)
              EndIf

            Case #BtnDOWN
              Protected dnIdx = GetGadgetState(#ListApps)
              If dnIdx > -1 And dnIdx < CountGadgetItems(#ListApps) - 1
                Protected dt0.s = GetGadgetItemText(#ListApps, dnIdx, 0) : Protected dt1.s = GetGadgetItemText(#ListApps, dnIdx, 1) : Protected dt2.s = GetGadgetItemText(#ListApps, dnIdx, 2)
                Protected dColSp = Val(dt2) : Protected dImgSp = CreateImage(#PB_Any, 16, 16)
                If StartDrawing(ImageOutput(dImgSp)) : Box(0, 0, 16, 16, dColSp) : DrawingMode(#PB_2DDrawing_Outlined) : Box(0, 0, 16, 16, $444444) : StopDrawing() : EndIf
                RemoveGadgetItem(#ListApps, dnIdx) : AddGadgetItem(#ListApps, dnIdx + 1, dt0 + Chr(10) + dt1 + Chr(10) + dt2, ImageID(dImgSp)) : SetGadgetState(#ListApps, dnIdx + 1)
              EndIf
              
            Case #BtnBrowseFile 
              Protected f.s = OpenFileRequester("Seleziona File", "", "Tutti|*.*", 0) 
              If f : SetGadgetText(#TxtCmd, f) : PostEvent(#PB_Event_Gadget, #WinSettings, #TxtCmd, #PB_EventType_Change) : EndIf
            
            Case #BtnBrowsePath
              Protected d.s = PathRequester("Seleziona Cartella", "")
              If d : SetGadgetText(#TxtCmd, d) : PostEvent(#PB_Event_Gadget, #WinSettings, #TxtCmd, #PB_EventType_Change) : EndIf

            Case #ColorPreview
              ; click sinistro sul canvas
              If EventType() = #PB_EventType_LeftClick
                Protected nC = ColorRequester(CurrentColor) 
                If nC <> -1 
                  CurrentColor = nC 
                  UpdateColorPreview()
                  
                  Protected cS = GetGadgetState(#ListApps)
                  If cS > -1 
                    SetGadgetItemText(#ListApps, cS, "$" + Hex(CurrentColor, #PB_Long), 2) 
                    Protected newImg = CreateImage(#PB_Any, 16, 16)
                    If StartDrawing(ImageOutput(newImg))
                      Box(0, 0, 16, 16, CurrentColor)
                      DrawingMode(#PB_2DDrawing_Outlined)
                      Box(0, 0, 16, 16, $444444)
                      StopDrawing()
                    EndIf
                    SetGadgetItemImage(#ListApps, cS, ImageID(newImg))
                  EndIf
                EndIf
              EndIf
            
            Case #BtnAdd 
              ;colore default (grigio $808080)
              CurrentColor = $808080 
              UpdateColorPreview()
              
              ;icona per la lista
              Protected imgNew = CreateImage(#PB_Any, 16, 16)
              If StartDrawing(ImageOutput(imgNew))
                Box(0, 0, 16, 16, CurrentColor)
                DrawingMode(#PB_2DDrawing_Outlined)
                Box(0, 0, 16, 16, $444444)
                StopDrawing()
              EndIf
              
              ;aggiunge e seleziona
              AddGadgetItem(#ListApps, -1, "Nuovo" + Chr(10) + "calc.exe" + Chr(10) + "$" + Hex(CurrentColor, #PB_Long), ImageID(imgNew))
              SetGadgetState(#ListApps, CountGadgetItems(#ListApps) - 1)             
              SetGadgetText(#TxtLabel, "Nuovo")
              SetGadgetText(#TxtCmd, "calc.exe")
              
              Case #BtnDel 
              Protected pD = GetGadgetState(#ListApps) 
              If pD > -1 
                RemoveGadgetItem(#ListApps, pD) : Protected total = CountGadgetItems(#ListApps)
                If total > 0
                  If pD >= total : pD = total - 1 : EndIf
                  SetGadgetState(#ListApps, pD) : PostEvent(#PB_Event_Gadget, #WinSettings, #ListApps, #PB_EventType_LeftClick)
                Else
                  SetGadgetText(#TxtLabel, "") : SetGadgetText(#TxtCmd, "") : CurrentColor = $808080 : UpdateColorPreview()
                EndIf
              EndIf
              
            Case #BtnDuplicate 
              Protected dI = GetGadgetState(#ListApps)  
              If dI > -1 
                Protected dCol = Val(GetGadgetItemText(#ListApps, dI, 2))
                Protected imgDup = CreateImage(#PB_Any, 16, 16)
                If StartDrawing(ImageOutput(imgDup))
                  Box(0, 0, 16, 16, dCol)
                  DrawingMode(#PB_2DDrawing_Outlined)
                  Box(0, 0, 16, 16, $444444)
                  StopDrawing()
                EndIf
                AddGadgetItem(#ListApps, -1, GetGadgetItemText(#ListApps, dI, 0) + Chr(10) + GetGadgetItemText(#ListApps, dI, 1) + Chr(10) + GetGadgetItemText(#ListApps, dI, 2), ImageID(imgDup))
                SetGadgetState(#ListApps, CountGadgetItems(#ListApps) - 1)
              EndIf

            Case #BtnSave             
              Select GetGadgetState(#ComboTrigger)
                Case 1 : TriggerKey = #VK_XBUTTON1
                Case 2 : TriggerKey = #VK_XBUTTON2
                Default : TriggerKey = #VK_MBUTTON
              EndSelect
              
              WinSize = Val(GetGadgetText(G_WinSize)) 
              RaggioBuco = Val(GetGadgetText(G_Raggio))
              PosizioneApp = ValF(GetGadgetText(G_PosApp)) 
              EffettoLoFi = ValF(GetGadgetText(G_LoFi))
              FontNome = GetGadgetText(G_FontN) 
              FontTaglia = Val(GetGadgetText(G_FontT))
              FontColore = Val(GetGadgetText(G_FontC)) 
              Trasparenza = Val(GetGadgetText(G_Trasp))
              FontBold = GetGadgetState(G_Bold)
              StartupAuto = GetGadgetState(G_Startup)

              Protected stile = #PB_Font_HighQuality
              If FontBold : stile | #PB_Font_Bold : EndIf
              If IsFont(FontID) : FreeFont(FontID) : EndIf
              FontID = LoadFont(#PB_Any, FontNome, FontTaglia, stile)
              
              SetStartup(StartupAuto)
              
              ; Salvataggio lista App
              ClearList(Slices())
              For i = 0 To CountGadgetItems(#ListApps) - 1
                AddElement(Slices())
                Slices()\label = GetGadgetItemText(#ListApps, i, 0)
                Slices()\cmd   = GetGadgetItemText(#ListApps, i, 1)
                Slices()\color = Val(GetGadgetItemText(#ListApps, i, 2))
              Next
              
              SaveSettings() 
              CreateMenuImage()
              
              ; Aggiorna la finestra del menu con i nuovi parametri
              SetWindowPos_(WindowID(#WinMenu), 0, 0, 0, WinSize, WinSize, #SWP_NOMOVE | #SWP_NOZORDER)
              SetLayeredWindowAttributes_(WindowID(#WinMenu), 0, Trasparenza, #LWA_ALPHA)
              SetWindowRgn_(WindowID(#WinMenu), CreateEllipticRgn_(0, 0, WinSize, WinSize), #True)
              
              CloseWindow(#WinSettings) : Break
          EndSelect
        Case #PB_Event_CloseWindow : CloseWindow(#WinSettings) : Break
      EndSelect
    ForEver
  EndIf
EndProcedure

; --- AVVIO APPLICAZIONE ---
LoadSettings()

If OpenWindow(#WinMenu, 0, 0, WinSize, WinSize, "PieMenu", #PB_Window_BorderLess | #PB_Window_Invisible)
  StickyWindow(#WinMenu, #True)
  
  ; ABILITA TRASPARENZA 
  SetWindowLongPtr_(WindowID(#WinMenu), #GWL_EXSTYLE, GetWindowLongPtr_(WindowID(#WinMenu), #GWL_EXSTYLE) | #WS_EX_LAYERED)
  SetLayeredWindowAttributes_(WindowID(#WinMenu), 0, Trasparenza, #LWA_ALPHA)
  
  SetWindowRgn_(WindowID(#WinMenu), CreateEllipticRgn_(0, 0, WinSize, WinSize), #True)
  CreateMenuImage()
  AddWindowTimer(#WinMenu, 123, 15) 
  
  Repeat
    Define Event = WaitWindowEvent() 
    If Event = #PB_Event_Timer And EventTimer() = 123
      If MenuVisibile And (GetAsyncKeyState_(#VK_CONTROL) & $8000) And (GetAsyncKeyState_(#VK_MENU) & $8000) And (GetAsyncKeyState_(#VK_S) & $8000)
        HideWindow(#WinMenu, #True) : MenuVisibile = #False
        If IsWindow(#WinHelp) : CloseWindow(#WinHelp) : HelpAperto = #False : EndIf
        SetClassLongPtr_(WindowID(#WinMenu), #GCLP_HCURSOR, LoadCursor_(0, #IDC_ARROW))
        OpenSettingsWin()
      EndIf

      If GetAsyncKeyState_(TriggerKey) & $8000
        If Not MenuVisibile
          GetCursorPos_(@mPos)
          LastHoveredSlice = -1
          ResizeWindow(#WinMenu, mPos\x - (WinSize/2), mPos\y - (WinSize/2), #PB_Ignore, #PB_Ignore)
          CreateMenuImage(-1)
          HideWindow(#WinMenu, #False) : MenuVisibile = #True
          If StartDrawing(WindowOutput(#WinMenu)) : DrawImage(ImageID(MenuImage), 0, 0) : StopDrawing() : EndIf
          While GetAsyncKeyState_(TriggerKey) & $8000 : Delay(1) : Wend
        Else
          HideWindow(#WinMenu, #True) : MenuVisibile = #False
          If IsWindow(#WinHelp) : CloseWindow(#WinHelp) : HelpAperto = #False : EndIf
          While GetAsyncKeyState_(TriggerKey) & $8000 : Delay(1) : Wend
        EndIf
      EndIf

      If MenuVisibile
        Define mx = WindowMouseX(#WinMenu), my = WindowMouseY(#WinMenu)
        Define dist.f = Sqr(Pow(mx-(WinSize/2), 2) + Pow(my-(WinSize/2), 2))
        ;HIGHLIGHT BASATA SU DISTANZA MINIMA
        Define CurrentHover = -1
        If dist > RaggioBuco And dist < (WinSize/2)
          Define MinD_H.f = 1000, iter = 0
          ForEach Slices()
            Define d_h.f = Sqr(Pow(mx-Slices()\targetX, 2) + Pow(my-Slices()\targetY, 2))
            If d_h < MinD_H : MinD_H = d_h : CurrentHover = iter : EndIf
            iter + 1
          Next
        EndIf

        ; Ridisegna solo se il mouse si è spostato su una fetta diversa
        If CurrentHover <> LastHoveredSlice
          LastHoveredSlice = CurrentHover
          CreateMenuImage(CurrentHover)
          If StartDrawing(WindowOutput(#WinMenu)) : DrawImage(ImageID(MenuImage), 0, 0) : StopDrawing() : EndIf
        EndIf
        ;FINE HIGHLIGHT 
        If dist <= RaggioBuco And dist >= 0
          SetClassLongPtr_(WindowID(#WinMenu), #GCLP_HCURSOR, LoadCursor_(0, #IDC_HAND))
        Else
          SetClassLongPtr_(WindowID(#WinMenu), #GCLP_HCURSOR, LoadCursor_(0, #IDC_ARROW))
        EndIf
; Gestione Click: Lancio comando tramite ShellExecute_
        If GetAsyncKeyState_(#VK_LBUTTON) & $8000
          If dist <= RaggioBuco
            GetCursorPos_(@mPos)
            ToggleSmartHelp(mPos\x, mPos\y)
          ElseIf dist < (WinSize/2)
            Define MinD.f = 1000, BestCmd.s = ""
            ForEach Slices()
              Define d.f = Sqr(Pow(mx-Slices()\targetX, 2) + Pow(my-Slices()\targetY, 2))
              If d < MinD : MinD = d : BestCmd = Slices()\cmd : EndIf
            Next
            If BestCmd <> ""
  HideWindow(#WinMenu, #True) : MenuVisibile = #False
  
  If IsWindow(#WinHelp) : CloseWindow(#WinHelp) : HelpAperto = #False : EndIf
  Delay(20)  
  Define exe.s  = LCase(StringField(BestCmd, 1, " ")) 
  Define args.s = ""
  If FindString(BestCmd, " ")
    args.s = Mid(BestCmd, Len(exe.s) + 2)
  EndIf

  If exe.s = "cmd" Or exe.s = "cmd.exe"  
    ShellExecute_(0, "open", "cmd.exe", args.s, #Null, #SW_SHOWNORMAL)
  Else   
    ShellExecute_(0, "open", BestCmd, #Null, #Null, #SW_SHOWNORMAL)
  EndIf
EndIf
          Else
            HideWindow(#WinMenu, #True) : MenuVisibile = #False
            If IsWindow(#WinHelp) : CloseWindow(#WinHelp) : HelpAperto = #False : EndIf
          EndIf
          While GetAsyncKeyState_(#VK_LBUTTON) & $8000 : Delay(1) : Wend
        EndIf
      EndIf
      If MenuVisibile = #True And GetAsyncKeyState_(#VK_ESCAPE) & $8000 : End : EndIf ;chiudi con ESC solo se menu visibile
    EndIf
  Until Event = #PB_Event_CloseWindow
EndIf
; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 12
; Folding = ---
; EnableXP
; DPIAware
; UseIcon = icon\mouselauncher1.ico
; Executable = mouselauncher.exe
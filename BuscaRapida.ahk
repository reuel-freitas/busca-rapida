#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName Busca Rápida
;@Ahk2Exe-SetDescription Busca Rápida
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetCopyright MIT License
;@Ahk2Exe-SetMainIcon icon.ico

; ================= App =================
APP_NAME    := "Busca Rápida"
APP_EXE     := "BuscaRapida.exe"
INSTALL_DIR := EnvGet("LOCALAPPDATA") "\BuscaRapida"
INSTALL_EXE := INSTALL_DIR "\" APP_EXE
STARTUP_LNK := A_Startup "\" APP_NAME ".lnk"
MENU_LNK    := A_Programs "\" APP_NAME ".lnk"

; O .exe baixado se instala sozinho na pasta do usuário (sem pedir admin)
if (A_IsCompiled && A_ScriptFullPath != INSTALL_EXE)
    Install()

; ================= Config =================
HOTKEY_OPEN := "!Space"        ; Alt+Espaço  (^Space = Ctrl+Espaço, ^!Space = Ctrl+Alt+Espaço)
MAX_RESULTS := 8
; Pastas extras para apps portáteis (busca recursiva). Ex.: "C:\Tools", "D:\Portable"
EXTRA_DIRS  := [
    ; "C:\Tools",
]
EXTRA_EXT   := "exe,lnk,bat,cmd,ps1,url"
HISTORY_FILE := A_ScriptDir "\history.ini"
WIDTH  := 680
ROW_H  := 42                   ; altura de cada linha (espaçamento entre apps)
ICON   := 24                   ; tamanho do ícone

; Cores (RRGGBB)
C_KEY    := "141416"           ; cor "transparente" (vira vidro) — não use em outro lugar
C_SEL    := "3A3A40"           ; fundo do item selecionado
C_LINE   := "3A3A3A"
C_TEXT   := "F5F5F5"
C_SUB    := "9A9A9A"
C_BORDER := 0x484848           ; 0xBBGGRR
GLASS_TINT := 0x90181818       ; 0xAABBGGRR — AA = opacidade do vidro (00 = transparente, FF = sólido)

; ================= Estado =================
Apps  := []        ; {name, target, kind, icon}
Shown := []
Hist  := Map()
IconCache := Map()
HIcons := Map()
S := A_ScreenDPI / 96
D(x) => Round(x * S)
BGR(rgb) => (n := Integer("0x" rgb), ((n & 0xFF) << 16) | (n & 0xFF00) | ((n >> 16) & 0xFF))

; ================= Janela de fundo (vidro) =================
gb := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")   ; WS_EX_NOACTIVATE
gb.BackColor := "000000"
SetAcrylic(gb.Hwnd, GLASS_TINT)
DwmSet(gb.Hwnd, 20, 1)          ; modo escuro
DwmSet(gb.Hwnd, 33, 2)          ; cantos arredondados
DwmSet(gb.Hwnd, 34, C_BORDER)   ; cor da borda

; ================= Janela de conteúdo =================
OnMessage(0x002C, WM_MEASUREITEM)   ; precisa vir antes de criar a ListView
OnMessage(0x002B, WM_DRAWITEM)

g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +Owner" gb.Hwnd, APP_NAME)
g.BackColor := C_KEY
g.MarginX := 0, g.MarginY := D(10)

; Lupa
g.SetFont("s15 q4 c" C_SUB, "Segoe MDL2 Assets")
g.SetFont(, "Segoe Fluent Icons")
g.AddText("x" D(22) " y" D(22) " w" D(26) " h" D(28) " BackgroundTrans", Chr(0xE721))

; Campo de busca
g.SetFont("s16 q4 c" C_TEXT, "Segoe UI")
search := g.AddEdit("x" D(56) " y" D(19) " w" D(WIDTH - 76) " h" D(34) " -E0x200 Background" C_KEY)
SendMessage(0x1501, 1, StrPtr("Buscar apps..."), search)       ; EM_SETCUEBANNER

; Linha divisória
g.AddText("x" D(16) " y" D(68) " w" D(WIDTH - 32) " h1 Background" C_LINE)

; Lista de resultados (desenhada à mão)
g.SetFont("s12 q4 c" C_TEXT, "Segoe UI")
lv := g.AddListView("x" D(8) " y" D(76) " w" D(WIDTH - 16) " h" D(40)
    . " -Hdr -Multi +0x8 +0x400 +LV0x10000 -E0x200 Background" C_KEY, ["App"])
lv.ModifyCol(1, D(WIDTH - 16))

; Lista de ícones do sistema (48px, reduzida ao desenhar)
IID := Buffer(16)
DllCall("ole32\CLSIDFromString", "wstr", "{46EB5926-582E-4017-9FDF-E8998DAA0950}", "ptr", IID)
DllCall("shell32\SHGetImageList", "int", 2, "ptr", IID, "ptr*", &hIL := 0)

; Rodapé com dicas
g.SetFont("s9 q4 c" C_SUB, "Segoe UI")
footer := g.AddText("x" D(22) " y" D(124) " w" D(WIDTH - 44) " h" D(18) " BackgroundTrans", "")

WinSetTransColor(C_KEY, g)

search.OnEvent("Change", (*) => Refresh())
lv.OnEvent("Click", (ctrl, row) => row && LaunchSelected())
g.OnEvent("Escape", (*) => HideUI())
OnMessage(0x0006, WM_ACTIVATE)       ; esconde ao perder o foco
OnMessage(0x0021, WM_MOUSEACTIVATE)  ; o vidro nunca rouba o foco
OnMessage(0x0201, WM_LBUTTONDOWN)    ; cliques nas áreas transparentes

LoadHistory()
LoadApps()
SetTimer(LoadApps, 5 * 60 * 1000)   ; atualiza a lista a cada 5 min

; Menu do ícone perto do relógio
OPEN_ITEM := "Abrir busca  (Alt+Espaço)"
A_IconTip := APP_NAME "  (Alt+Espaço)"
tray := A_TrayMenu
if A_IsCompiled {
    tray.Delete()
    tray.Add(OPEN_ITEM, (*) => ShowUI())
    tray.Add("Recarregar lista de apps", (*) => LoadApps())
    tray.Add()
    tray.Add("Iniciar com o Windows", ToggleStartup)
    if FileExist(STARTUP_LNK)
        tray.Check("Iniciar com o Windows")
    tray.Add("Desinstalar", Uninstall)
    tray.Add()
    tray.Add("Sair", (*) => ExitApp())
} else {
    tray.Insert("1&", OPEN_ITEM, (*) => ShowUI())
    tray.Insert("2&", "Recarregar lista de apps", (*) => LoadApps())
    tray.Insert("3&")
}
tray.Default := OPEN_ITEM
tray.ClickCount := 1

Hotkey(HOTKEY_OPEN, (*) => Toggle())

if (A_Args.Length && A_Args[1] = "/welcome")
    SetTimer(Welcome, -300)

if (A_Args.Length && A_Args[1] = "/preview") {     ; usado só para tirar print
    ShowUI(false)
    search.Value := A_Args.Length > 1 ? A_Args[2] : ""
    Refresh()
}

#HotIf WinActive("ahk_id " g.Hwnd)
Up::Move(-1)
Down::Move(1)
Tab::Move(1)
+Tab::Move(-1)
Enter::LaunchSelected()
NumpadEnter::LaunchSelected()
^Enter::LaunchSelected(true)        ; Ctrl+Enter = executar como administrador
F5::(LoadApps(), Refresh())
#HotIf

; ================= Instalação =================
Install() {
    ; fecha uma versão antiga que esteja rodando (atualização)
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE Name='" APP_EXE "'")
        if (p.ExecutablePath = INSTALL_EXE)
            ProcessClose(p.ProcessId), ProcessWaitClose(p.ProcessId, 3)
    try {
        DirCreate(INSTALL_DIR)
        FileCopy(A_ScriptFullPath, INSTALL_EXE, true)
        FileCreateShortcut(INSTALL_EXE, STARTUP_LNK, INSTALL_DIR)
        FileCreateShortcut(INSTALL_EXE, MENU_LNK, INSTALL_DIR, , "Busque e abra apps com Alt+Espaço")
    } catch as e {
        MsgBox("Não foi possível instalar o " APP_NAME ".`n`n" e.Message, APP_NAME, "Iconx")
        ExitApp
    }
    Run('"' INSTALL_EXE '" /welcome')
    ExitApp
}

Welcome() {
    MsgBox("Pronto! O " APP_NAME " está instalado.`n`n"
        . "Aperte  Alt + Espaço  em qualquer lugar para buscar e abrir seus apps.`n`n"
        . "Ele já abre sozinho quando o Windows liga. Para desinstalar, clique com o botão "
        . "direito no ícone da lupa, perto do relógio.", APP_NAME, "Iconi")
}

ToggleStartup(item, *) {
    if FileExist(STARTUP_LNK) {
        FileDelete(STARTUP_LNK)
        A_TrayMenu.Uncheck(item)
    } else {
        FileCreateShortcut(A_ScriptFullPath, STARTUP_LNK, A_ScriptDir)
        A_TrayMenu.Check(item)
    }
}

Uninstall(*) {
    if (MsgBox("Remover o " APP_NAME " deste computador?", APP_NAME, "YesNo Icon?") != "Yes")
        return
    try FileDelete(STARTUP_LNK)
    try FileDelete(MENU_LNK)
    if A_IsCompiled
        Run(A_ComSpec ' /c ping -n 3 127.0.0.1 >nul & rmdir /s /q "' INSTALL_DIR '"', , "Hide")
    MsgBox(APP_NAME " foi removido.", APP_NAME, "Iconi T3")
    ExitApp
}

; ================= Janela =================
DwmSet(hwnd, attr, val) => DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", attr, "int*", val, "int", 4)

SetAcrylic(hwnd, abgr) {
    accent := Buffer(16, 0)
    NumPut("int", 4, "int", 2, "uint", abgr, "int", 0, accent)   ; ACCENT_ENABLE_ACRYLICBLURBEHIND
    data := Buffer(A_PtrSize * 3, 0)
    NumPut("int", 19, data, 0)                                    ; WCA_ACCENT_POLICY
    NumPut("ptr", accent.Ptr, data, A_PtrSize)
    NumPut("uptr", accent.Size, data, A_PtrSize * 2)
    DllCall("user32\SetWindowCompositionAttribute", "ptr", hwnd, "ptr", data)
}

Toggle() {
    if WinActive("ahk_id " g.Hwnd)
        HideUI()
    else
        ShowUI()
}

ShowUI(activate := true) {
    search.Value := ""
    Refresh()
    g.Show("xCenter y" Round(A_ScreenHeight * 0.22) " AutoSize Hide")
    SyncBackdrop()
    g.Show(activate ? "" : "NA")
    if activate {
        WinActivate("ahk_id " g.Hwnd)
        search.Focus()
    }
}

HideUI() {
    g.Hide()
    gb.Hide()
}

SyncBackdrop() {
    g.GetPos(&x, &y, &w, &h)
    gb.Show("x" x " y" y " w" w " h" h " NA")
}

WM_ACTIVATE(wParam, lParam, msg, hwnd) {
    if (hwnd = g.Hwnd && (wParam & 0xFFFF) = 0)
        HideUI()
}

WM_MOUSEACTIVATE(wParam, lParam, msg, hwnd) {
    if (hwnd = gb.Hwnd)
        return 3                    ; MA_NOACTIVATE
}

; Pixels transparentes deixam o clique passar para o vidro: traduz para a lista
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    if (hwnd != gb.Hwnd)
        return
    x := lParam << 48 >> 48, y := lParam << 32 >> 48
    lv.GetPos(&lx, &ly, &lw, &lh)
    if (lv.Visible && x >= lx && x < lx + lw && y >= ly && y < ly + lh) {
        row := (y - ly) // D(ROW_H) + 1
        if (row <= Shown.Length) {
            lv.Modify(0, "-Select")
            lv.Modify(row, "Select Focus")
            LaunchSelected()
            return 0
        }
    }
    search.Focus()
    return 0
}

; ================= Desenho da lista =================
WM_MEASUREITEM(wParam, lParam, msg, hwnd) {
    if (NumGet(lParam, 0, "uint") = 102) {         ; ODT_LISTVIEW
        NumPut("uint", D(ROW_H), lParam, 16)
        return true
    }
}

WM_DRAWITEM(wParam, lParam, msg, hwnd) {
    if (NumGet(lParam, 0, "uint") != 102)
        return
    o    := A_PtrSize = 8 ? 24 : 20
    hdc  := NumGet(lParam, o + A_PtrSize, "ptr")
    prc  := lParam + o + 2 * A_PtrSize
    l := NumGet(prc, 0, "int"), t := NumGet(prc, 4, "int")
    r := NumGet(prc, 8, "int"), b := NumGet(prc, 12, "int")
    item := NumGet(lParam, 8, "uint") + 1

    FillRect(hdc, l, t, r, b, BGR(C_KEY))
    if (item > Shown.Length)
        return true
    a := Shown[item]

    if (item = lv.GetNext()) {
        br := DllCall("CreateSolidBrush", "uint", BGR(C_SEL), "ptr")
        ob := DllCall("SelectObject", "ptr", hdc, "ptr", br, "ptr")
        op := DllCall("SelectObject", "ptr", hdc, "ptr", DllCall("GetStockObject", "int", 8, "ptr"), "ptr")
        DllCall("RoundRect", "ptr", hdc, "int", l + D(6), "int", t + D(3), "int", r - D(6), "int", b - D(2), "int", D(10), "int", D(10))
        DllCall("SelectObject", "ptr", hdc, "ptr", ob)
        DllCall("SelectObject", "ptr", hdc, "ptr", op)
        DllCall("DeleteObject", "ptr", br)
    }

    sz := D(ICON)
    DllCall("DrawIconEx", "ptr", hdc, "int", l + D(18), "int", t + (b - t - sz) // 2, "ptr", GetHIcon(a.icon)
        , "int", sz, "int", sz, "uint", 0, "ptr", 0, "uint", 3)

    DllCall("SetBkMode", "ptr", hdc, "int", 1)
    DllCall("SetTextColor", "ptr", hdc, "uint", BGR(C_TEXT))
    of := DllCall("SelectObject", "ptr", hdc, "ptr", SendMessage(0x31, 0, 0, lv), "ptr")
    rc := Buffer(16)
    NumPut("int", l + D(18) + sz + D(14), "int", t, "int", r - D(16), "int", b, rc)
    DllCall("DrawTextW", "ptr", hdc, "wstr", a.name, "int", -1, "ptr", rc, "uint", 0x8824)
    DllCall("SelectObject", "ptr", hdc, "ptr", of)
    return true
}

FillRect(hdc, l, t, r, b, color) {
    rc := Buffer(16)
    NumPut("int", l, "int", t, "int", r, "int", b, rc)
    br := DllCall("CreateSolidBrush", "uint", color, "ptr")
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", br)
    DllCall("DeleteObject", "ptr", br)
}

GetHIcon(idx) {
    if !HIcons.Has(idx)
        HIcons[idx] := DllCall("comctl32\ImageList_GetIcon", "ptr", hIL, "int", idx, "uint", 0, "ptr")
    return HIcons[idx]
}

; ================= Dados =================
LoadApps(*) {
    global Apps
    list := []
    seen := Map()
    seen.CaseSense := false

    ; Tudo que aparece em "Todos os apps" do menu Iniciar (Win32 + Store)
    try {
        folder := ComObject("Shell.Application").NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
        for item in folder.Items() {
            name := item.Name, target := item.Path
            if (name = "" || seen.Has(name))
                continue
            seen[name] := true
            list.Push({name: name, target: target, kind: "app", icon: IconIndex(target, "app")})
        }
    }

    ; Pastas extras (apps portáteis)
    for dir in EXTRA_DIRS {
        if !DirExist(dir)
            continue
        loop files dir "\*.*", "R" {
            if !InStr("," EXTRA_EXT ",", "," A_LoopFileExt ",")
                continue
            SplitPath(A_LoopFileName, , , , &base)
            if seen.Has(base)
                continue
            seen[base] := true
            list.Push({name: base, target: A_LoopFileFullPath, kind: "file", icon: IconIndex(A_LoopFileFullPath, "file")})
        }
    }
    Apps := list
}

; Índice do ícone na lista de ícones do sistema
IconIndex(target, kind) {
    key := kind ":" target
    if IconCache.Has(key)
        return IconCache[key]
    sfi := Buffer(A_PtrSize + 688, 0)          ; SHFILEINFOW
    idx := 0
    if (kind = "app") {
        if DllCall("shell32\SHParseDisplayName", "wstr", "shell:AppsFolder\" target, "ptr", 0, "ptr*", &pidl := 0, "uint", 0, "ptr", 0) = 0 {
            if DllCall("shell32\SHGetFileInfoW", "ptr", pidl, "uint", 0, "ptr", sfi, "uint", sfi.Size, "uint", 0x4008)  ; SYSICONINDEX|PIDL
                idx := NumGet(sfi, A_PtrSize, "int")
            DllCall("ole32\CoTaskMemFree", "ptr", pidl)
        }
    } else if DllCall("shell32\SHGetFileInfoW", "wstr", target, "uint", 0, "ptr", sfi, "uint", sfi.Size, "uint", 0x4000) {
        idx := NumGet(sfi, A_PtrSize, "int")
    }
    return IconCache[key] := idx
}

; Pontuação: prefixo > início de palavra > substring > letras em sequência (fuzzy)
Score(name, q) {
    n := StrLower(name)
    if (q = "")
        return 1
    len := Min(StrLen(n), 999)
    if (SubStr(n, 1, StrLen(q)) = q)
        return 4000 - len
    if RegExMatch(n, "(^|[\s\-_.])\Q" StrReplace(q, "\E", "") "\E")
        return 3000 - len
    if (p := InStr(n, q))
        return 2000 - Min(999, p + len)
    pos := 0, gaps := 0
    loop parse q {
        if (A_LoopField = " ")
            continue
        p := InStr(n, A_LoopField, , pos + 1)
        if !p
            return 0
        gaps += p - pos - 1
        pos := p
    }
    return 1000 - Min(999, gaps * 5 + len)
}

Refresh() {
    global Shown
    q := StrLower(Trim(search.Value))
    scored := []
    for a in Apps {
        s := Score(a.name, q)
        if (s <= 0)
            continue
        s += Min(Hist.Get(a.name, 0), 25) * 40     ; apps mais usados sobem
        scored.Push({s: s, a: a})
    }

    buf := ""
    for i, x in scored
        buf .= x.s "`t" i "`n"
    buf := Sort(RTrim(buf, "`n"), "N R")

    Shown := []
    loop parse buf, "`n" {
        if (A_Index > MAX_RESULTS || A_LoopField = "")
            break
        Shown.Push(scored[Integer(StrSplit(A_LoopField, "`t")[2])].a)
    }

    lv.Opt("-Redraw")
    lv.Delete()
    for a in Shown
        lv.Add(, a.name)
    if Shown.Length
        lv.Modify(1, "Select Focus")
    lv.Opt("+Redraw")
    Layout()
}

; Ajusta a altura da lista ao número de resultados
Layout() {
    n := Shown.Length
    h := n * D(ROW_H)
    lv.Visible := n > 0
    lv.Move(, , , h)
    lv.GetPos(, &y)
    footer.Move(, n ? y + h + D(10) : y)
    footer.Text := n ? "↑↓  navegar      Enter  abrir      Ctrl+Enter  admin      Esc  fechar"
                     : "Nenhum app encontrado"
    if DllCall("IsWindowVisible", "ptr", g.Hwnd) {
        g.Show("AutoSize NA")
        SyncBackdrop()
    }
}

Move(d) {
    n := Shown.Length
    if !n
        return
    i := lv.GetNext() + d
    i := i < 1 ? n : i > n ? 1 : i
    lv.Modify(0, "-Select")
    lv.Modify(i, "Select Focus Vis")
}

LaunchSelected(admin := false) {
    i := lv.GetNext()
    if (!i || i > Shown.Length)
        return
    a := Shown[i]
    HideUI()

    Hist[a.name] := Hist.Get(a.name, 0) + 1
    try IniWrite(Hist[a.name], HISTORY_FILE, "count", a.name)

    try {
        if (a.kind = "app")
            Run((admin ? "*RunAs " : "") 'explorer.exe "shell:AppsFolder\' a.target '"')
        else
            Run((admin ? "*RunAs " : "") '"' a.target '"')
    } catch as e {
        MsgBox("Falha ao abrir " a.name "`n`n" e.Message, "Launcher", "Iconx")
    }
}

LoadHistory() {
    if !FileExist(HISTORY_FILE)
        return
    sec := IniRead(HISTORY_FILE, "count", , "")
    loop parse sec, "`n", "`r" {
        if (p := InStr(A_LoopField, "="))
            Hist[SubStr(A_LoopField, 1, p - 1)] := Integer(SubStr(A_LoopField, p + 1))
    }
}

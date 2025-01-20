#Requires AutoHotkey v2.0

#Include dependencies\RapidOcr\RapidOcr.ahk

class OcrControl {
    class Utils {
        static AssertType(value, type) {
            if not Type(value) == type {
                throw TypeError('Value must be of type ' type)
            }
        }
        static IsValidFunction(callback) => Type(callback) == 'Func' || Type(callback) == 'BoundFunc' || Type(callback) == 'Closure'
        class GDIp {
            #DllLoad 'GdiPlus'
            ;{ Startup
            static Startup() {
                if (this.HasProp("Token"))
                    return
                input := Buffer((A_PtrSize = 8) ? 24 : 16, 0)
                NumPut("UInt", 1, input)
                DllCall("gdiplus\GdiplusStartup", "UPtr*", &pToken := 0, "UPtr", input.ptr, "UPtr", 0)
                this.Token := pToken
            }
            ;}
            ;{ Shutdown
            static Shutdown() {
                if (this.HasProp("Token"))
                    DllCall("Gdiplus\GdiplusShutdown", "UPtr", this.DeleteProp("Token"))
            }
            ;}
            ;{ BitmapFromScreen
            static BitmapFromScreen(Area) {
                chdc := this.CreateCompatibleDC()
                hbm := this.CreateDIBSection(Area.W, Area.H, chdc)
                obm := this.SelectObject(chdc, hbm)
                hhdc := this.GetDC()
                this.BitBlt(chdc, 0, 0, Area.W, Area.H, hhdc, Area.X, Area.Y)
                this.ReleaseDC(hhdc)
                pBitmap := this.CreateBitmapFromHBITMAP(hbm)
                this.SelectObject(chdc, obm), this.DeleteObject(hbm), this.DeleteDC(hhdc), this.DeleteDC(chdc)
                return pBitmap
            }
            ;}
            ;{ CreateCompatibleDC
            static CreateCompatibleDC(hdc := 0) {
                return DllCall("CreateCompatibleDC", "UPtr", hdc)
            }
            ;}
            ;{ CreateDIBSection
            static CreateDIBSection(w, h, hdc := "", bpp := 32, &ppvBits := 0, Usage := 0, hSection := 0, Offset := 0) {
                hdc2 := hdc ? hdc : this.GetDC()
                bi := Buffer(40, 0)
                NumPut("UInt", 40, bi, 0)
                NumPut("UInt", w, bi, 4)
                NumPut("UInt", h, bi, 8)
                NumPut("UShort", 1, bi, 12)
                NumPut("UShort", bpp, bi, 14)
                NumPut("UInt", 0, bi, 16)

                hbm := DllCall("CreateDIBSection"
                    , "UPtr", hdc2
                    , "UPtr", bi.ptr    ; BITMAPINFO
                    , "uint", Usage
                    , "UPtr*", &ppvBits
                    , "UPtr", hSection
                    , "uint", Offset, "UPtr")

                if !hdc
                    this.ReleaseDC(hdc2)
                return hbm
            }
            ;}
            ;{ SelectObject
            static SelectObject(hdc, hgdiobj) {
                return DllCall("SelectObject", "UPtr", hdc, "UPtr", hgdiobj)
            }
            ;}
            ;{ BitBlt
            static BitBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, raster := "") {
                return DllCall("gdi32\BitBlt"
                    , "UPtr", ddc
                    , "int", dx, "int", dy
                    , "int", dw, "int", dh
                    , "UPtr", sdc
                    , "int", sx, "int", sy
                    , "uint", raster ? raster : 0x00CC0020)
            }
            ;}
            ;{ CreateBitmapFromHBITMAP
            static CreateBitmapFromHBITMAP(hBitmap, hPalette := 0) {
                DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", hPalette, "UPtr*", &pBitmap :=
                    0)
                return pBitmap
            }
            ;}
            ;{ CreateHBITMAPFromBitmap
            static CreateHBITMAPFromBitmap(pBitmap, Background := 0xffffffff) {
                DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "UPtr", pBitmap, "UPtr*", &hBitmap := 0, "int",
                    Background)
                return hBitmap
            }
            ;}
            ;{ DeleteObject
            static DeleteObject(hObject) {
                return DllCall("DeleteObject", "UPtr", hObject)
            }
            ;}
            ;{ ReleaseDC
            static ReleaseDC(hdc, hwnd := 0) {
                return DllCall("ReleaseDC", "UPtr", hwnd, "UPtr", hdc)
            }
            ;}
            ;{ DeleteDC
            static DeleteDC(hdc) {
                return DllCall("DeleteDC", "UPtr", hdc)
            }
            ;}
            ;{ DisposeImage
            static DisposeImage(pBitmap, noErr := 0) {
                if (StrLen(pBitmap) <= 2 && noErr = 1)
                    return 0

                r := DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
                if (r = 2 || r = 1) && (noErr = 1)
                    r := 0
                return r
            }
            ;}
            ;{ GetDC
            static GetDC(hwnd := 0) {
                return DllCall("GetDC", "UPtr", hwnd)
            }
            ;}
            ;{ GetDCEx
            static GetDCEx(hwnd, flags := 0, hrgnClip := 0) {
                return DllCall("GetDCEx", "UPtr", hwnd, "UPtr", hrgnClip, "int", flags)
            }
            ;}
            ;{ SaveBitmapToFile
            static SaveBitmapToFile(pBitmap, sOutput, Quality := 75, toBase64 := 0) {
                _p := 0

                SplitPath sOutput, , , &Extension
                if !RegExMatch(Extension, "^(?i:BMP|DIB|RLE|JPG|JPEG|JPE|JFIF|GIF|TIF|TIFF|PNG)$")
                    return -1

                Extension := "." Extension
                DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", &nCount := 0, "uint*", &nSize := 0)
                ci := Buffer(nSize)
                DllCall("gdiplus\GdipGetImageEncoders", "uint", nCount, "uint", nSize, "UPtr", ci.ptr)
                if !(nCount && nSize)
                    return -2

                static IsUnicode := StrLen(Chr(0xFFFF))
                if (IsUnicode) {
                    StrGet_Name := "StrGet"
                    loop nCount {
                        sString := %StrGet_Name%(NumGet(ci, (idx := (48 + 7 * A_PtrSize) * (A_Index - 1)) + 32 + 3 *
                        A_PtrSize, "UPtr"), "UTF-16")
                        if !InStr(sString, "*" Extension)
                            continue

                        pCodec := ci.ptr + idx
                        break
                    }
                } else {
                    loop nCount {
                        Location := NumGet(ci, 76 * (A_Index - 1) + 44, "UPtr")
                        nSize := DllCall("WideCharToMultiByte", "uint", 0, "uint", 0, "uint", Location, "int", -1,
                            "uint",
                            0, "int", 0, "uint", 0, "uint", 0)
                        sString := Buffer(nSize)
                        DllCall("WideCharToMultiByte", "uint", 0, "uint", 0, "uint", Location, "int", -1, "str",
                            sString,
                            "int", nSize, "uint", 0, "uint", 0)
                        if !InStr(sString, "*" Extension)
                            continue

                        pCodec := ci.ptr + 76 * (A_Index - 1)
                        break
                    }
                }

                if !pCodec
                    return -3

                if (Quality != 75) {
                    Quality := (Quality < 0) ? 0 : (Quality > 100) ? 100 : Quality
                    if (Quality > 90 && toBase64 = 1)
                        Quality := 90

                    if RegExMatch(Extension, "^\.(?i:JPG|JPEG|JPE|JFIF)$") {
                        DllCall("gdiplus\GdipGetEncoderParameterListSize", "UPtr", pBitmap, "UPtr", pCodec, "uint*", &
                            nSize
                        )
                        EncoderParameters := Buffer(nSize, 0)
                        DllCall("gdiplus\GdipGetEncoderParameterList", "UPtr", pBitmap, "UPtr", pCodec, "uint", nSize,
                            "UPtr", EncoderParameters.ptr)
                        nCount := NumGet(EncoderParameters, "UInt")
                        loop nCount {
                            elem := (24 + A_PtrSize) * (A_Index - 1) + 4 + (pad := (A_PtrSize = 8) ? 4 : 0)
                            if (NumGet(EncoderParameters, elem + 16, "UInt") = 1) && (NumGet(EncoderParameters, elem +
                                20,
                                "UInt") = 6) {
                                _p := elem + EncoderParameters.ptr - pad - 4
                                NumPut(Quality, NumGet(NumPut(4, NumPut(1, _p + 0, "UPtr") + 20, "UInt"), "UPtr"),
                                "UInt")
                                break
                            }
                        }
                    }
                }

                if (toBase64 = 1) {
                    ; part of the function extracted from ImagePut by iseahound
                    ; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=76301&sid=bfb7c648736849c3c53f08ea6b0b1309
                    DllCall("ole32\CreateStreamOnHGlobal", "UPtr", 0, "int", true, "UPtr*", &pStream := 0)
                    _E := DllCall("gdiplus\GdipSaveImageToStream", "UPtr", pBitmap, "UPtr", pStream, "UPtr", pCodec,
                        "uint",
                        _p)
                    if _E
                        return -6

                    DllCall("ole32\GetHGlobalFromStream", "UPtr", pStream, "uint*", &hData)
                    pData := DllCall("GlobalLock", "UPtr", hData, "UPtr")
                    nSize := DllCall("GlobalSize", "uint", pData)

                    bin := Buffer(nSize, 0)
                    DllCall("RtlMoveMemory", "UPtr", bin.ptr, "UPtr", pData, "uptr", nSize)
                    DllCall("GlobalUnlock", "UPtr", hData)
                    ObjRelease(pStream)
                    DllCall("GlobalFree", "UPtr", hData)

                    ; Using CryptBinaryToStringA saves about 2MB in memory.
                    DllCall("Crypt32.dll\CryptBinaryToStringA", "UPtr", bin.ptr, "uint", nSize, "uint", 0x40000001,
                        "UPtr",
                        0, "uint*", &base64Length := 0)
                    base64 := Buffer(base64Length, 0)
                    _E := DllCall("Crypt32.dll\CryptBinaryToStringA", "UPtr", bin.ptr, "uint", nSize, "uint",
                        0x40000001,
                        "UPtr", &base64, "uint*", base64Length)
                    if !_E
                        return -7

                    bin := Buffer(0)
                    return StrGet(base64, base64Length, "CP0")
                }

                _E := DllCall("gdiplus\GdipSaveImageToFile", "UPtr", pBitmap, "WStr", sOutput, "UPtr", pCodec, "uint",
                    _p)
                return _E ? -5 : 0
            }
        }
        class ScreenShooter {
            static CaptureControl(hwnd, controlId, outputFile, margin := 0) {
                if not WinExist('ahk_id ' hwnd) or not OcrControl.Utils.ControlExist(controlId, hwnd) {
                    throw Error('Invalid ControlID or window handle (hwnd).')
                }
                WinActivate(hwnd)
                try {
                    ControlGetPos(&controlX, &controlY, &controlW, &controlH, controlId, 'ahk_id ' hwnd)
                } catch Error as e {
                    throw Error('Failed to retrieve coordinates of the specified control: ' e.Message)
                }
                clientPt := Buffer(8, 0)
                NumPut('int', controlX, clientPt, 0)
                NumPut('int', controlY, clientPt, 4)
                if not OcrControl.Utils.SafeDllCall('User32\ClientToScreen', hwnd, clientPt) {
                    throw Error('Failed to convert control coordinates to screen coordinates.')
                }
                area := { x: NumGet(clientPt, 0, 'Int') - margin, y: NumGet(clientPt, 4, 'Int') - margin, w: controlW +
                    2 * margin, h: controlH + 2 * margin }
                return OcrControl.Utils.ScreenShooter.CaptureRegion(area, outputFile)
            }
            static CaptureRegion(area, outputFile) {
                area := area ?? { x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight }
                SplitPath(outputFile, , &outDir)
                if not DirExist(outDir) {
                    DirCreate(outDir)
                }
                try {
                    OcrControl.Utils.GDIp.Startup()
                    pBitmap := OcrControl.Utils.GDIp.BitmapFromScreen(area)
                    OcrControl.Utils.GDIp.SaveBitmapToFile(pBitmap, outputFile)
                    OcrControl.Utils.GDIp.DisposeImage(pBitmap)
                    return outputFile
                } catch Error as e {
                    throw Error("Failed to capture region: " e.Message)
                } finally {
                    OcrControl.Utils.GDIp.Shutdown()
                }
            }
        }
        static SafeDllCall(functionName, hwnd, buffer) {
            try {
                return DllCall(functionName, "Ptr", hwnd, "Ptr", buffer)
            } catch {
                return false
            }
        }
        static ControlExist(controlID, hwnd) {
            try {
                ControlGetPos(, , , , controlID, "ahk_id " hwnd)
                return true
            } catch {
                return false
            }
        }
        class RapidOcr {
            /************************************************************************
             * @description [RapidOcrOnnx](https://github.com/RapidAI/RapidOcrOnnx)
             * A cross platform OCR Library based on PaddleOCR & OnnxRuntime
             * @author thqby, RapidAI
             * @date 2024/08/07
             * @version 1.0.2
             * @license Apache-2.0
             ***********************************************************************/
            ptr := 0
            /**
             * @param {Map|Object} config Set det, rec, cls model location path, keys.txt path, thread number.
             * @param {String} [config.models] dir of model files
             * @param {String} [config.det] model file name of det
             * @param {String} [config.rec] model file name of rec
             * @param {String} [config.keys] keys file name
             * @param {String} [config.cls] model file name of cls
             * @param {Integer} [config.numThread] The thread number, default: 2
             * @param {String} dllpath The path of RapidOcrOnnx.dll
             * @example
             * param := RapidOcr.OcrParam()
             * param.doAngle := false ;, param.maxSideLen := 300
             * ocr := RapidOcr({ models: A_ScriptDir '\models' })
             * MsgBox ocr.ocr_from_file('1.jpg', param)
             */
            __New(config?, dllpath?) {
                static init := 0
                if (!init) {
                    init := DllCall('LoadLibrary', 'str', dllpath ?? A_LineFile '\..\dependencies\RapidOcr\' (A_PtrSize * 8) 'bit\RapidOcrOnnx.dll',
                    'ptr')
                    if (!init)
                        throw OSError()
                }
                if !IsSet(config)
                    config := { models: A_LineFile '\..\dependencies\RapidOcr\models' }
                else if !HasProp(config, 'models')
                    config.models := A_LineFile '\..\dependencies\RapidOcr\models'
                if !FileExist(config.models)
                    config.models := unset
                det_model := cls_model := rec_model := keys_dict := '', numThread := 2
                for k, v in (config is Map ? config : config.OwnProps()) {
                    switch k, false {
                        case 'det', 'cls', 'rec': %k%_model := v
                        case 'keys', 'dict': keys_dict := v
                        case 'det_model', 'cls_model', 'rec_model', 'keys_dict', 'numThread': %k% := v
                        case 'models', 'modelpath':
                            if !(v ~= '[/\\]$')
                                v .= '\'
                            if !keys_dict {
                                loop files v '*.txt'
                                    if A_LoopFileName ~= 'i)_(keys|dict)[_.]' {
                                        keys_dict := A_LoopFileFullPath
                                        break
                                    }
                            }
                            loop files v '*.onnx' {
                                if RegExMatch(A_LoopFileName, 'i)_(det|cls|rec)[_.]', &m) && !%m[1]%_model
                                    %m[1]%_model := A_LoopFileFullPath
                            } until det_model && cls_model && rec_model
                    }
                }
                for k in ['keys_dict', 'det_model', 'cls_model', 'rec_model']
                    if !%k% {
                        if k != 'cls_model'
                            throw ValueError('No value is specified: ' k)
                    } else if !FileExist(%k%)
                        throw TargetError('file "' k '" does not exist')
                this.ptr := DllCall('RapidOcrOnnx\OcrInit', 'str', det_model, 'str', cls_model, 'str', rec_model, 'str',
                    keys_dict, 'int', numThread, 'ptr')
            }
            __Delete() => this.ptr && DllCall('RapidOcrOnnx\OcrDestroy', 'ptr', this)

            static __cb(i) {
                static cbs := [{ ptr: CallbackCreate(get_text), __Delete: this => CallbackFree(this.ptr) }, { ptr: CallbackCreate(
                    get_result), __Delete: this => CallbackFree(this.ptr) },]
                return cbs[i]
                get_text(userdata, ptext, presult) => %ObjFromPtrAddRef(userdata)% := StrGet(ptext, 'utf-8')
                get_result(userdata, ptext, presult) {
                    result := %ObjFromPtrAddRef(userdata)% := RapidOcr.OcrResult(presult)
                    result.text := StrGet(ptext, 'utf-8')
                    return result
                }
            }

            ; opencv4.8.0 Mat
            ocr_from_mat(mat, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectMat', 'ptr', this,
                'ptr', mat, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res)) ? res : ''

            ; path of pic
            ocr_from_file(picpath, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectFile', 'ptr', this,
                'astr', picpath, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res)) ? res : ''

            ; Image binary data
            ocr_from_binary(data, size, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectBinary',
                'ptr', this, 'ptr', data, 'uptr', size, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr',
                ObjPtr(&res)) ? res : ''

            ; `struct BITMAP_DATA { void *bits; uint pitch; int width, height, bytespixel;};`
            ocr_from_bitmapdata(data, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectBitmapData',
                'ptr', this, 'ptr', data, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res)) ?
                res : ''

            class OcrParam extends Buffer {
                __New(param?) {
                    super.__New(42, 0)
                    p := NumPut('int', 50, 'int', 1024, 'float', 0.6, 'float', 0.3, 'float', 2.0, this)
                    if !IsSet(param)
                        return NumPut('int', 1, 'int', 1, p)
                    for k, v in (param is Map ? param : param.OwnProps())
                        if this.Base.HasOwnProp(k)
                            this.%k% := v
                }
                ; default: 50
                padding {
                    get => NumGet(this, 0, 'int')
                    set => NumPut('int', Value, this, 0)
                }
                ; default: 1024
                maxSideLen {
                    get => NumGet(this, 4, 'int')
                    set => NumPut('int', Value, this, 4)
                }
                ; default: 0.5
                boxScoreThresh {
                    get => NumGet(this, 8, 'float')
                    set => NumPut('float', Value, this, 8)
                }
                ; default: 0.3
                boxThresh {
                    get => NumGet(this, 12, 'float')
                    set => NumPut('float', Value, this, 12)
                }
                ; default: 1.6
                unClipRatio {
                    get => NumGet(this, 16, 'float')
                    set => NumPut('float', Value, this, 16)
                }
                ; default: false
                doAngle {
                    get => NumGet(this, 20, 'int')
                    set => NumPut('int', Value, this, 20)
                }
                ; default: false
                mostAngle {
                    get => NumGet(this, 24, 'int')
                    set => NumPut('int', Value, this, 24)
                }
                ; Output path of image with the boxes
                outputPath {
                    get => StrGet(NumGet(this, 24 + A_PtrSize, 'ptr') || StrPtr(''), 'cp0')
                    set => (StrPut(Value, this.__outputbuf := Buffer(StrPut(Value, 'cp0')), 'cp0'), NumPut('ptr', this.__outputbuf
                        .Ptr, this, 24 + A_PtrSize))
                }
            }

            class OcrResult extends Array {
                __New(ptr) {
                    this.dbNetTime := NumGet(ptr, 'double')
                    this.detectTime := NumGet(ptr, 8, 'double')
                    read_vector(this, &ptr += 16, read_textblock)
                    align(ptr, begin, to_align) => begin + ((ptr - begin + --to_align) & ~to_align)
                    read_textblock(&ptr, begin := ptr) => {
                        boxPoint: read_vector([], &ptr, read_point),
                        boxScore: read_float(&ptr),
                        angleIndex: read_int(&ptr),
                        angleScore: read_float(&ptr),
                        angleTime: read_double(&ptr := align(ptr, begin, 8)),
                        text: read_string(&ptr),
                        charScores: read_vector([], &ptr, read_float),
                        crnnTime: read_double(&ptr := align(ptr, begin, 8)),
                        blockTime: read_double(&ptr)
                    }
                    read_double(&ptr) => (v := NumGet(ptr, 'double'), ptr += 8, v)
                    read_float(&ptr) => (v := NumGet(ptr, 'float'), ptr += 4, v)
                    read_int(&ptr) => (v := NumGet(ptr, 'int'), ptr += 4, v)
                    read_point(&ptr) => { x: read_int(&ptr), y: read_int(&ptr) }
                    read_string(&ptr) {
                        static size := 2 * A_PtrSize + 16
                        sz := NumGet(ptr + 16, 'uptr'), p := sz < 16 ? ptr : NumGet(ptr, 'ptr'), ptr += size
                        s := StrGet(p, sz, 'utf-8')
                        return s
                    }
                    read_vector(arr, &ptr, read_element) {
                        static size := 3 * A_PtrSize
                        pend := NumGet(ptr, A_PtrSize, 'ptr'), p := NumGet(ptr, 'ptr'), ptr += size
                        while p < pend
                            arr.Push(read_element(&p))
                        return arr
                    }
                }
            }
        }
    }
    _Control := ''
    Control(control) {
        OcrControl.Utils.AssertType(control, 'string')
        this._Control := control
        return this
    }
    _WinTitle := 'A'
    WinTitle(title) {
        OcrControl.Utils.AssertType(title, 'string')
        this._WinTitle := title
        return this
    }
    _WinText := ''
    WinText(text) {
        OcrControl.Utils.AssertType(text, 'string')
        this._WinText := text
        return this
    }
    _ModifierCallback := ''
    ModifierCallback(callback) {
        OcrControl.Utils.AssertType(callback, 'Func')
        this._ModifierCallback := callback
        return this
    }
    _VerifierCallback := ''
    VerifierCallback(callback) {
        OcrControl.Utils.AssertType(callback, 'Func')
        this._VerifierCallback := callback
        return this
    }
    _MaxTries := 3
    MaxTries(tries) {
        OcrControl.Utils.AssertType(tries, 'number')
        this._MaxTries := tries
        return this
    }
    _DefaultMargin := 0
    DefaultMargin(margin) {
        OcrControl.Utils.AssertType(margin, 'number')
        this._DefaultMargin := margin
        return this
    }
    _MarginPerTry := 0
    MarginPerTry(margin) {
        OcrControl.Utils.AssertType(margin, 'number')
        this._MarginPerTry := margin
        return this
    }
    _Debug := false
    Debug(debug := true) {
        OcrControl.Utils.AssertType(debug, 'boolean')
        this._Debug := debug
        return this
    }
    _Padding := 50
    Padding(padding) {
        OcrControl.Utils.AssertType(padding, 'number')
        this._Padding := padding
        return this
    }
    _MaxSideLen := 1024
    MaxSideLen(max_side_len) {
        OcrControl.Utils.AssertType(max_side_len, 'number')
        this._MaxSideLen := max_side_len
        return this
    }
    _BoxScoreThresh := 0.5
    BoxScoreThresh(box_score_thresh) {
        OcrControl.Utils.AssertType(box_score_thresh, 'number')
        this._BoxScoreThresh := box_score_thresh
        return this
    }
    _BoxThresh := 0.3
    BoxThresh(box_thresh) {
        OcrControl.Utils.AssertType(box_thresh, 'number')
        this._BoxThresh := box_thresh
        return this
    }
    _UnClipRatio := 1.6
    UnClipRatio(un_clip_ratio) {
        OcrControl.Utils.AssertType(un_clip_ratio, 'number')
        this._UnClipRatio := un_clip_ratio
        return this
    }
    _DoAngle := false
    DoAngle(do_angle) {
        OcrControl.Utils.AssertType(do_angle, 'boolean')
        this._DoAngle := do_angle
        return this
    }
    _MostAngle := false
    MostAngle(most_angle) {
        OcrControl.Utils.AssertType(most_angle, 'boolean')
        this._MostAngle := most_angle
        return this
    }
    _OutputPath := ''
    OutputPath(output_path) {
        OcrControl.Utils.AssertType(output_path, 'string')
        this._OutputPath := output_path
        return this
    }

    GetText() {
        if not this._Control {
            throw Error('Control property is not set.')
        }
        try {
            ocr_params := OcrControl.Utils.RapidOcr.OcrParam()
            ocr_params.doAngle := this._DoAngle
            ocr_params.mostAngle := this._MostAngle
            ocr_params.padding := this._Padding
            ocr_params.maxSideLen := this._MaxSideLen
            ocr_params.boxScoreThresh := this._BoxScoreThresh
            ocr_params.boxThresh := this._BoxThresh
            ocr_params.unClipRatio := this._UnClipRatio
            ocr_params.outputPath := this._OutputPath
            printscreen_path := A_Temp '\control.bmp'
            ocr := OcrControl.Utils.RapidOcr()
            loop this._MaxTries {
                try {
                    OcrControl.Utils.ScreenShooter.CaptureControl(WinGetID(this._WinTitle), this._Control, printscreen_path, (this._MarginPerTry * A_Index) + this._DefaultMargin)
                } catch Error as e {
                    Throw Error('Failed to capture screenshot for control: ' this._Control ' - ' e.Message)
                }
                try {
                    ocr_result := ocr.ocr_from_file(printscreen_path, ocr_params)
                } catch Error as e {
                    Throw Error('Error during OCR: ' e.Message)
                }
                if this._ModifierCallback != '' and OcrControl.Utils.IsValidFunction(this._ModifierCallback) {
                    ocr_result := this._ModifierCallback(ocr_result)
                }
                if this._VerifierCallback != '' and OcrControl.Utils.IsValidFunction(this._VerifierCallback) {
                    if this._VerifierCallback(ocr_result) {
                        return ocr_result
                    }
                    continue
                }
                return ocr_result
            }
            Throw Error('Failed to validate OCR result after ' this._MaxTries ' tries. Last OCR result: ' (ocr_result ? ocr_result : "<none>"))
        } catch Error as e {
            Throw Error('Error in OCR control: ' e.Message)
        }
    }
}